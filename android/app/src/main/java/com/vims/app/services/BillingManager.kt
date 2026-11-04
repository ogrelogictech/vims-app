package com.vims.app.services

import android.app.Activity
import android.content.Context
import android.util.Log
import com.vims.app.data.AndroidStoreDef
import com.vims.app.data.ChecklistLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/** What can be bought. MONTHLY and YEARLY are the base plans of the one Play subscription; CREDIT is the consumable. */
enum class PlanKind { MONTHLY, YEARLY, CREDIT }

data class PlanOption(val kind: PlanKind, val title: String, val length: String, val price: String)

sealed interface PlansState {
    data object Loading : PlansState
    data class Loaded(val options: List<PlanOption>) : PlansState
    /** "Plans can't load right now." */
    data object Unavailable : PlansState
}

enum class PurchaseState { PURCHASED, PENDING, OTHER }

/** A store purchase, free of store types, so everything after the store call is the same code with the fake store and in tests. */
data class StorePurchase(
    val productId: String, val token: String, val state: PurchaseState, val acknowledged: Boolean, val autoRenewing: Boolean,
    val purchaseTimeMillis: Long, val basePlan: String?, val quantity: Int, val originalJson: String, val signature: String,
    /** Account hold or paused: still the user's, but not active. Play says not to grant access and to send them to its subscription page. */
    val suspended: Boolean = false,
)

sealed interface StoreUpdate {
    data class Purchases(val list: List<StorePurchase>) : StoreUpdate
    data object Cancelled : StoreUpdate
    data object AlreadyOwned : StoreUpdate
    data object Failed : StoreUpdate
}

/** The store: [PlayBillingBackend] always in release; a debug build can also ask for the fake one (src/debug). */
interface StoreBackend {
    fun setListener(listener: (StoreUpdate) -> Unit)
    /** Null when the store can't be reached. */
    suspend fun queryPlans(): List<PlanOption>?
    /** Null when the store can't be reached; an empty list is an answer. */
    suspend fun queryPurchases(): List<StorePurchase>?
    /** False when the purchase sheet couldn't open. [replaceToken] switches the current subscription to this base plan. */
    suspend fun launch(activity: Activity, kind: PlanKind, replaceToken: String?): Boolean
    suspend fun acknowledge(token: String): Boolean
    suspend fun consume(token: String): Boolean
}

interface BillingStore {
    fun read(): BillingSnapshot
    fun write(s: BillingSnapshot)
}

/**
 * On the device, outside Room and outside every account: a subscription belongs to the Google account on the phone and a credit
 * to "this device" (shared subscription.store), whichever VIMS account is signed in. Not in Auto Backup, so a restored phone
 * asks Play again instead of restoring credits that were already spent.
 */
class PrefsBillingStore(context: Context) : BillingStore {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    override fun read(): BillingSnapshot = prefs.getString(KEY, null)?.let {
        try { ChecklistLoader.json.decodeFromString(BillingSnapshot.serializer(), it) } catch (_: Exception) { null }
    } ?: BillingSnapshot()
    override fun write(s: BillingSnapshot) { prefs.edit().putString(KEY, ChecklistLoader.json.encodeToString(BillingSnapshot.serializer(), s)).commit() }
    companion object { const val PREFS = "vims_billing"; private const val KEY = "snapshot" }
}

/** Play's signature check: skipped with no key (the optional vimsPlayLicenseKey gradle property). */
class PurchaseVerifier(base64Key: String) {
    private val key = base64Key.takeIf { it.isNotBlank() }?.let {
        KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(it)))
    }
    fun verify(originalJson: String, signature: String): Boolean {
        val k = key ?: return true
        val sig = try { Base64.getDecoder().decode(signature) } catch (_: Exception) { return false }
        // Play signs with RSASSA-PKCS1-v1_5; SHA-1 in Google's samples. SHA-256 is accepted too so a change on Google's side can't refund every purchase.
        return listOf("SHA1withRSA", "SHA256withRSA").any { alg ->
            try { Signature.getInstance(alg).run { initVerify(k); update(originalJson.toByteArray()); verify(sig) } } catch (_: Exception) { false }
        }
    }
}

data class BillingStatus(
    /** Active now: the store said so, or the cached status holds with the store out of reach. */
    val active: Boolean = false,
    val basePlan: String? = null,
    val expiryMillis: Long? = null,
    val autoRenewing: Boolean = true,
    /** The token of the subscription, for a Monthly / Yearly switch. */
    val token: String? = null,
    /** True when active only from the cache, because the store couldn't be reached. */
    val cached: Boolean = false,
    /** Had a subscription that's gone. */
    val ended: Boolean = false,
    /** Account hold or paused: not active, fixed on Play's subscription page. */
    val onHold: Boolean = false,
    val pendingSub: Boolean = false,
    val pendingCredit: Boolean = false,
    val credits: Int = 0,
)

sealed interface BillingEvent {
    data object SubscriptionStarted : BillingEvent
    data object CreditAdded : BillingEvent
    data object Pending : BillingEvent
    data object AlreadyOwned : BillingEvent
    data object Failed : BillingEvent
    data class Restored(val found: Boolean) : BillingEvent
    data object RestoreFailed : BillingEvent
}

/**
 * The billing rules: everything after the store answered. Purchases are acknowledged and consumed from here, because an
 * unacknowledged purchase is refunded automatically after 3 days; anything that failed is retried by the next [refresh] (start,
 * resume, Restore Purchases, every completed purchase).
 */
class BillingManager(
    private val backend: StoreBackend, private val store: BillingStore, private val ids: AndroidStoreDef, private val verifier: PurchaseVerifier,
    private val scope: CoroutineScope, private val now: () -> Long = System::currentTimeMillis,
) {
    private val lock = Mutex()
    /** One store query at a time: a second answer read before the first was processed would acknowledge or consume twice. */
    private val querying = Mutex()
    private var pendingSub = false
    private var pendingCredit = false
    private var onHold = false
    /** The store answered the last query. Until then the status is the cache's. */
    private var live = false

    private val _status = MutableStateFlow(statusOf(store.read()))
    val status: StateFlow<BillingStatus> = _status.asStateFlow()
    private val _plans = MutableStateFlow<PlansState>(PlansState.Loading)
    val plans: StateFlow<PlansState> = _plans.asStateFlow()
    private val _events = MutableSharedFlow<BillingEvent>(extraBufferCapacity = 8)
    val events: SharedFlow<BillingEvent> = _events.asSharedFlow()

    init {
        backend.setListener { u -> scope.launch { onUpdate(u) } }
    }

    private fun statusOf(s: BillingSnapshot): BillingStatus {
        val sub = s.sub
        val active = sub != null && (live || Access.cacheHolds(sub, now()))
        return BillingStatus(active = active, basePlan = sub?.basePlan, expiryMillis = sub?.expiryMillis, autoRenewing = sub?.autoRenewing ?: true,
            token = sub?.token, cached = active && !live, ended = !active && !onHold && (s.ended || sub != null), onHold = onHold,
            pendingSub = pendingSub, pendingCredit = pendingCredit, credits = s.credits)
    }

    private fun publish(s: BillingSnapshot = store.read()) { _status.value = statusOf(s) }

    private suspend fun onUpdate(u: StoreUpdate) {
        when (u) {
            is StoreUpdate.Purchases -> { process(u.list, complete = false, announce = true); refresh() }
            StoreUpdate.Cancelled -> Unit // the user closed the sheet: no error
            StoreUpdate.AlreadyOwned -> { refresh(); _events.emit(BillingEvent.AlreadyOwned) }
            StoreUpdate.Failed -> _events.emit(BillingEvent.Failed)
        }
    }

    /** Start, resume, after a purchase: asks the store. A store that answers overrides the cache; otherwise the cache decides. */
    suspend fun refresh(): Boolean = querying.withLock {
        val list = backend.queryPurchases()
        if (list == null) {
            lock.withLock { live = false; pendingSub = false; pendingCredit = false; onHold = false; publish() }
            return@withLock false
        }
        process(list, complete = true, announce = false)
        true
    }

    fun refreshAsync() { scope.launch { refresh() } }

    /** Restore Purchases: the same query, with an answer for the user. */
    fun restore() {
        scope.launch {
            val before = store.read().credits
            if (!refresh()) { _events.emit(BillingEvent.RestoreFailed); return@launch }
            val s = _status.value
            _events.emit(BillingEvent.Restored(s.active || s.onHold || s.pendingSub || s.pendingCredit || s.credits > before))
        }
    }

    fun loadPlans() {
        scope.launch {
            _plans.value = PlansState.Loading
            val options = backend.queryPlans()
            _plans.value = if (options.isNullOrEmpty()) PlansState.Unavailable else PlansState.Loaded(options)
        }
    }

    fun purchase(activity: Activity, kind: PlanKind) {
        scope.launch {
            val s = _status.value
            val wanted = when (kind) { PlanKind.MONTHLY -> ids.monthlyBasePlan; PlanKind.YEARLY -> ids.yearlyBasePlan; PlanKind.CREDIT -> null }
            val replace = s.token?.takeIf { kind != PlanKind.CREDIT && s.active && !s.cached && s.basePlan != wanted }
            if (!backend.launch(activity, kind, replace)) _events.emit(BillingEvent.Failed)
        }
    }

    /** Generating an inspection's first report with no subscription and no trial. False when there's no credit left. */
    suspend fun spendCredit(): Boolean = lock.withLock {
        val s = store.read()
        if (s.credits < 1) return@withLock false
        val n = s.copy(credits = s.credits - 1)
        store.write(n); publish(n)
        true
    }

    /** Re-reads the cache (debug test hooks rewrite it). */
    suspend fun reload() = lock.withLock { publish() }

    private suspend fun process(list: List<StorePurchase>, complete: Boolean, announce: Boolean) = lock.withLock {
        var s = store.read()
        // A purchase that fails the check is never granted, acknowledged or consumed, so Play refunds it.
        val verified = list.filter { p -> verifier.verify(p.originalJson, p.signature).also { ok -> if (!ok) Log.w(TAG, "Purchase signature check failed: ${p.productId}") } }

        val credits = verified.filter { it.productId == ids.reportCredit }
        credits.filter { it.state == PurchaseState.PURCHASED }.forEach { p ->
            // The credit is saved first and consumed second (shared reportCredit). If the consume fails, the token stays on
            // the next query and only the consume runs again.
            if (p.token !in s.creditedTokens) {
                s = s.copy(credits = s.credits + maxOf(1, p.quantity), creditedTokens = (s.creditedTokens + p.token).takeLast(MAX_TOKENS))
                store.write(s)
                _events.emit(BillingEvent.CreditAdded)
            }
            if (!backend.consume(p.token)) Log.w(TAG, "Consume failed; retried on the next refresh")
        }

        val subs = verified.filter { it.productId == ids.subscription }
        val held = subs.filter { it.state == PurchaseState.PURCHASED && it.suspended }
        val active = subs.filter { it.state == PurchaseState.PURCHASED && !it.suspended }.maxByOrNull { it.purchaseTimeMillis }
        subs.filter { it.state == PurchaseState.PURCHASED && !it.acknowledged }.forEach { p ->
            if (!backend.acknowledge(p.token)) Log.w(TAG, "Acknowledge failed; retried on the next refresh")
        }
        val prev = s.sub
        if (active != null) {
            // Play's Purchase has no base plan, so the app sends it as obfuscatedProfileId at launch and reads it back here.
            val plan = active.basePlan ?: prev?.takeIf { it.token == active.token }?.basePlan
            val t = now()
            s = s.copy(sub = CachedSub(active.token, plan, t, Access.periodEnd(active.purchaseTimeMillis, plan == ids.yearlyBasePlan, t), active.autoRenewing), ended = false)
            if (announce && prev?.token != active.token) _events.emit(BillingEvent.SubscriptionStarted)
        } else if (complete) {
            // The store answered with no active subscription. It overrides the cache, even an expiry still in the future.
            if (prev != null) s = s.copy(sub = null, ended = true)
        }
        if (active != null || complete) { if (s != store.read()) store.write(s) }

        val newPending = list.any { it.state == PurchaseState.PENDING }
        if (announce && newPending) _events.emit(BillingEvent.Pending)
        if (complete) {
            live = true
            onHold = held.isNotEmpty() && active == null
            pendingSub = subs.any { it.state == PurchaseState.PENDING }
            pendingCredit = credits.any { it.state == PurchaseState.PENDING }
        } else {
            pendingSub = pendingSub || subs.any { it.state == PurchaseState.PENDING }
            pendingCredit = pendingCredit || credits.any { it.state == PurchaseState.PENDING }
        }
        publish(s)
    }

    companion object {
        private const val TAG = "VIMS-Billing"
        private const val MAX_TOKENS = 200
    }
}
