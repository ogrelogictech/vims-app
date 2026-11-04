package com.vims.app.services

import android.app.Activity
import android.app.AlertDialog
import android.app.Application
import android.content.Context
import android.content.Intent
import android.util.Log
import com.vims.app.AppContainer
import com.vims.app.data.AndroidStoreDef
import com.vims.app.data.ChecklistLoader
import com.vims.app.data.OwnerCodeDef
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.util.UUID
import kotlin.coroutines.resume

/**
 * Debug builds only (this source set isn't in release). Real Google Play unless a test asks for the fake store:
 *   adb shell am start -n com.vims.app/.MainActivity --es fakeBilling on
 * Later extras, comma separated: off, reset, unavailable, available, offline, online, nextPending, nextCancel, nextFail,
 * completePending, expire, hold, unhold, failAck, failConsume, storeOk, sub:monthly[:daysAgo], sub:yearly[:daysAgo], credit.
 * --ei fakeCacheExpiryDaysAgo N rewrites the cached expiry to N days ago.
 * Owner code: --ez ownerBypass true marks the signed-in owner account verified; --es ownerCodeTest <saltHex>:<iterations>:<hashHex>
 * makes the code check use a throwaway hash for this run.
 */
object BillingFlavor {
    fun backend(app: Application, ids: AndroidStoreDef): StoreBackend = SwitchBackend(PlayBillingBackend(app, ids), FakeStoreBackend(app, ids))

    fun handleIntent(app: Application, intent: Intent?, container: AppContainer) {
        if (intent == null) return
        val scope = CoroutineScope(Dispatchers.IO)
        val fake = (container.backend as? SwitchBackend)?.fake ?: return
        intent.getStringExtra("fakeBilling")?.let { cmds ->
            cmds.split(",").forEach { fake.command(it.trim()) }
            scope.launch { container.billing.refresh(); container.billing.loadPlans() }
        }
        if (intent.hasExtra("fakeCacheExpiryDaysAgo")) {
            val days = intent.getIntExtra("fakeCacheExpiryDaysAgo", 0)
            val store = PrefsBillingStore(app)
            val s = store.read()
            s.sub?.let { store.write(s.copy(sub = it.copy(expiryMillis = System.currentTimeMillis() - days * 86_400_000L))) }
            scope.launch { container.billing.reload() }
            Log.i(FakeStoreBackend.TAG, "cached expiry set to $days days ago")
        }
        intent.getStringExtra("ownerCodeTest")?.split(":")?.takeIf { it.size == 3 }?.let { p ->
            container.ownerCodeOverride = OwnerCodeDef(p[0], p[1].toInt(), p[2])
            Log.i(FakeStoreBackend.TAG, "owner code check uses a throwaway hash")
        }
        if (intent.getBooleanExtra("ownerBypass", false)) scope.launch { container.repo.verifyOwner() }
    }
}

/** Reads the flag on every call, so a test can turn the fake on or off in a running app. */
private class SwitchBackend(private val real: StoreBackend, val fake: FakeStoreBackend) : StoreBackend {
    private val b get() = if (fake.enabled) fake else real
    override fun setListener(listener: (StoreUpdate) -> Unit) { real.setListener(listener); fake.setListener(listener) }
    override suspend fun queryPlans() = b.queryPlans()
    override suspend fun queryPurchases() = b.queryPurchases()
    override suspend fun launch(activity: Activity, kind: PlanKind, replaceToken: String?) = b.launch(activity, kind, replaceToken)
    override suspend fun acknowledge(token: String) = b.acknowledge(token)
    override suspend fun consume(token: String) = b.consume(token)
}

/**
 * A stand-in for Google Play. It keeps "the store" in its own prefs file (surviving a restart, as Play would), answers like the
 * real backend and shows a dialog instead of Play's sheet. It logs every acknowledge and consume under the tag VIMS-FakeStore.
 */
private class FakeStoreBackend(context: Context, private val ids: AndroidStoreDef) : StoreBackend {
    @Serializable
    data class P(val productId: String, val token: String, val state: String, val acknowledged: Boolean = false, val time: Long, val basePlan: String? = null,
                 val autoRenewing: Boolean = true, val suspended: Boolean = false, val created: Long = 0)
    @Serializable
    data class S(val purchases: List<P> = emptyList(), val unavailable: Boolean = false, val offline: Boolean = false, val next: String = "ok",
                 val failAck: Boolean = false, val failConsume: Boolean = false)

    private val prefs = context.applicationContext.getSharedPreferences("vims_fake_store", Context.MODE_PRIVATE)
    private var listener: (StoreUpdate) -> Unit = {}
    val enabled: Boolean get() = prefs.getBoolean("on", false)
    private fun read(): S = prefs.getString("s", null)?.let { ChecklistLoader.json.decodeFromString(S.serializer(), it) } ?: S()
    private fun write(s: S) { prefs.edit().putString("s", ChecklistLoader.json.encodeToString(S.serializer(), s)).commit() }

    fun command(c: String) {
        var s = read()
        when {
            c == "on" -> prefs.edit().putBoolean("on", true).commit()
            c == "off" -> prefs.edit().putBoolean("on", false).commit()
            c == "reset" -> s = S()
            c == "unavailable" -> s = s.copy(unavailable = true)
            c == "available" -> s = s.copy(unavailable = false)
            c == "offline" -> s = s.copy(offline = true)
            c == "online" -> s = s.copy(offline = false)
            c == "nextPending" -> s = s.copy(next = "pending")
            c == "nextCancel" -> s = s.copy(next = "cancel")
            c == "nextFail" -> s = s.copy(next = "fail")
            c == "completePending" -> s = s.copy(purchases = s.purchases.map { if (it.state == "pending") it.copy(state = "purchased") else it })
            c == "expire" -> s = s.copy(purchases = s.purchases.filterNot { it.productId == ids.subscription })
            c == "hold" -> s = s.copy(purchases = s.purchases.map { if (it.productId == ids.subscription) it.copy(suspended = true) else it })
            c == "unhold" -> s = s.copy(purchases = s.purchases.map { it.copy(suspended = false) })
            c == "failAck" -> s = s.copy(failAck = true)
            c == "failConsume" -> s = s.copy(failConsume = true)
            c == "storeOk" -> s = s.copy(failAck = false, failConsume = false)
            c == "credit" -> s = s.copy(purchases = s.purchases + purchase(ids.reportCredit, null, 0))
            c.startsWith("sub:") -> {
                val p = c.split(":")
                val days = p.getOrNull(2)?.toLongOrNull() ?: 0
                s = s.copy(purchases = s.purchases.filterNot { it.productId == ids.subscription } + purchase(ids.subscription, p[1], days))
            }
        }
        write(s)
        Log.i(TAG, "command $c: $s")
    }

    private fun purchase(id: String, basePlan: String?, daysAgo: Long, state: String = "purchased") =
        P(id, "fake-" + UUID.randomUUID(), state, time = System.currentTimeMillis() - daysAgo * 86_400_000L, basePlan = basePlan)

    private fun toStore(p: P) = StorePurchase(p.productId, p.token, if (p.state == "pending") PurchaseState.PENDING else PurchaseState.PURCHASED,
        p.acknowledged, p.autoRenewing, p.time, p.basePlan, 1, "{}", "", p.suspended)

    override fun setListener(listener: (StoreUpdate) -> Unit) { this.listener = listener }

    override suspend fun queryPlans(): List<PlanOption>? {
        val s = read()
        if (s.unavailable || s.offline) return null
        return listOf(PlanOption(PlanKind.MONTHLY, "App only", Access.lengthLabel("P1M"), "$34.95"), PlanOption(PlanKind.YEARLY, "App only", Access.lengthLabel("P1Y"), "$385.00"),
            PlanOption(PlanKind.CREDIT, "Report credit", "One report", "$5.00"))
    }

    override suspend fun queryPurchases(): List<StorePurchase>? {
        val s = read()
        if (s.unavailable || s.offline) { Log.i(TAG, "queryPurchases: can't reach the store"); return null }
        Log.i(TAG, "queryPurchases: ${s.purchases.size}")
        return s.purchases.map(::toStore)
    }

    override suspend fun launch(activity: Activity, kind: PlanKind, replaceToken: String?): Boolean {
        val s = read()
        if (s.unavailable || s.offline) return false
        val (id, plan) = when (kind) {
            PlanKind.MONTHLY -> ids.subscription to ids.monthlyBasePlan
            PlanKind.YEARLY -> ids.subscription to ids.yearlyBasePlan
            PlanKind.CREDIT -> ids.reportCredit to null
        }
        val buy = withContext(Dispatchers.Main) {
            suspendCancellableCoroutine { c ->
                AlertDialog.Builder(activity).setTitle("Fake Google Play")
                    .setMessage("Debug test store, no real payment.\n$id ${plan.orEmpty()}" + if (replaceToken != null) "\nSwitching the current plan" else "")
                    .setPositiveButton("Buy") { _, _ -> if (c.isActive) c.resume(true) }
                    .setNegativeButton("Close") { _, _ -> if (c.isActive) c.resume(false) }
                    .setOnCancelListener { if (c.isActive) c.resume(false) }.show()
            }
        }
        val next = read().next
        write(read().copy(next = "ok"))
        when {
            !buy || next == "cancel" -> listener(StoreUpdate.Cancelled)
            next == "fail" -> listener(StoreUpdate.Failed)
            else -> {
                val p = purchase(id, plan, 0, if (next == "pending") "pending" else "purchased")
                write(read().let { st -> st.copy(purchases = st.purchases.filterNot { replaceToken != null && it.token == replaceToken } + p) })
                listener(StoreUpdate.Purchases(listOf(toStore(p))))
            }
        }
        return true
    }

    override suspend fun acknowledge(token: String): Boolean {
        val s = read()
        if (s.failAck || s.unavailable || s.offline) { Log.i(TAG, "acknowledge failed"); return false }
        write(s.copy(purchases = s.purchases.map { if (it.token == token) it.copy(acknowledged = true) else it }))
        Log.i(TAG, "acknowledged")
        return true
    }

    override suspend fun consume(token: String): Boolean {
        val s = read()
        if (s.failConsume || s.unavailable || s.offline) { Log.i(TAG, "consume failed"); return false }
        write(s.copy(purchases = s.purchases.filterNot { it.token == token }))
        Log.i(TAG, "consumed")
        return true
    }

    companion object { const val TAG = "VIMS-FakeStore" }
}
