package com.vims.app.services

import android.app.Activity
import android.content.Context
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.consumePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import com.vims.app.data.AndroidStoreDef
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * Google Play Billing Library 9.1. Any response that isn't OK (no Play Store, signed out, offline, billing unavailable, a
 * product missing in Play Console) is "the store can't be reached": null to [BillingManager], never an exception to the UI.
 */
class PlayBillingBackend(context: Context, private val ids: AndroidStoreDef) : StoreBackend, PurchasesUpdatedListener {
    private var listener: (StoreUpdate) -> Unit = {}
    private val client: BillingClient = BillingClient.newBuilder(context.applicationContext)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()
    private val connecting = Mutex()
    /** The product details of the last [queryPlans]; launch always re-queries first, so they are never stale. */
    private var subDetails: ProductDetails? = null
    private var creditDetails: ProductDetails? = null

    override fun setListener(listener: (StoreUpdate) -> Unit) { this.listener = listener }

    private suspend fun ready(): Boolean = connecting.withLock {
        if (client.isReady) return@withLock true
        withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
            suspendCancellableCoroutine { c ->
                client.startConnection(object : BillingClientStateListener {
                    override fun onBillingSetupFinished(r: BillingResult) { if (c.isActive) c.resume(r.ok) }
                    override fun onBillingServiceDisconnected() { if (c.isActive) c.resume(false) }
                })
            }
        } ?: false
    }

    private val BillingResult.ok get() = responseCode == BillingClient.BillingResponseCode.OK

    private suspend fun details(id: String, type: String): ProductDetails? {
        val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(id).setProductType(type).build())).build()
        val r = client.queryProductDetails(params)
        if (!r.billingResult.ok) Log.i(TAG, "Product $id: ${r.billingResult.responseCode}")
        return r.productDetailsList?.firstOrNull()?.takeIf { r.billingResult.ok }
    }

    /** The base plan's own offer (no offerId); a store offer is used only if the base plan has nothing else. */
    private fun offer(d: ProductDetails, basePlan: String): ProductDetails.SubscriptionOfferDetails? =
        d.subscriptionOfferDetails?.filter { it.basePlanId == basePlan }?.sortedBy { it.offerId != null }?.firstOrNull()

    private suspend fun fetch(): Boolean {
        if (!ready()) return false
        subDetails = details(ids.subscription, BillingClient.ProductType.SUBS)
        creditDetails = details(ids.reportCredit, BillingClient.ProductType.INAPP)
        return subDetails != null || creditDetails != null
    }

    override suspend fun queryPlans(): List<PlanOption>? {
        if (!fetch()) return null
        val out = mutableListOf<PlanOption>()
        subDetails?.let { d ->
            listOf(PlanKind.MONTHLY to ids.monthlyBasePlan, PlanKind.YEARLY to ids.yearlyBasePlan).forEach { (kind, plan) ->
                val phase = offer(d, plan)?.pricingPhases?.pricingPhaseList?.lastOrNull() ?: return@forEach
                out += PlanOption(kind, d.name, Access.lengthLabel(phase.billingPeriod), phase.formattedPrice)
            }
        }
        creditDetails?.let { d -> d.oneTimePurchaseOfferDetails?.let { out += PlanOption(PlanKind.CREDIT, d.name, "One report", it.formattedPrice) } }
        return out
    }

    override suspend fun queryPurchases(): List<StorePurchase>? {
        if (!ready()) return null
        val subs = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).includeSuspendedSubscriptions(true).build())
        val inapp = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build())
        if (!subs.billingResult.ok || !inapp.billingResult.ok) return null
        return (subs.purchasesList + inapp.purchasesList).mapNotNull(::map)
    }

    private fun map(p: Purchase): StorePurchase? {
        val id = p.products.firstOrNull() ?: return null
        val state = when (p.purchaseState) {
            Purchase.PurchaseState.PURCHASED -> PurchaseState.PURCHASED
            Purchase.PurchaseState.PENDING -> PurchaseState.PENDING
            else -> PurchaseState.OTHER
        }
        return StorePurchase(id, p.purchaseToken, state, p.isAcknowledged, p.isAutoRenewing, p.purchaseTime,
            p.accountIdentifiers?.obfuscatedProfileId, p.quantity, p.originalJson, p.signature, p.isSuspended)
    }

    override suspend fun launch(activity: Activity, kind: PlanKind, replaceToken: String?): Boolean {
        if (!fetch()) return false
        val builder = BillingFlowParams.newBuilder()
        val product: BillingFlowParams.ProductDetailsParams
        if (kind == PlanKind.CREDIT) {
            val d = creditDetails ?: return false
            product = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(d).build()
        } else {
            val d = subDetails ?: return false
            val plan = if (kind == PlanKind.MONTHLY) ids.monthlyBasePlan else ids.yearlyBasePlan
            val o = offer(d, plan) ?: return false
            product = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(d).setOfferToken(o.offerToken).build()
            builder.setObfuscatedProfileId(plan)
            if (replaceToken != null) builder.setSubscriptionUpdateParams(BillingFlowParams.SubscriptionUpdateParams.newBuilder()
                .setOldPurchaseToken(replaceToken)
                .setSubscriptionReplacementMode(BillingFlowParams.SubscriptionUpdateParams.ReplacementMode.WITH_TIME_PRORATION).build())
        }
        val params = builder.setProductDetailsParamsList(listOf(product)).build()
        val r = withContext(Dispatchers.Main) { client.launchBillingFlow(activity, params) }
        if (r.responseCode == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) { listener(StoreUpdate.AlreadyOwned); return true }
        return r.ok
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        listener(when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> StoreUpdate.Purchases(purchases.orEmpty().mapNotNull(::map))
            BillingClient.BillingResponseCode.USER_CANCELED -> StoreUpdate.Cancelled
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> StoreUpdate.AlreadyOwned
            else -> StoreUpdate.Failed
        })
    }

    override suspend fun acknowledge(token: String): Boolean =
        ready() && client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(token).build()).ok

    override suspend fun consume(token: String): Boolean =
        ready() && client.consumePurchase(ConsumeParams.newBuilder().setPurchaseToken(token).build()).billingResult.ok

    companion object {
        private const val TAG = "VIMS-Billing"
        private const val CONNECT_TIMEOUT_MS = 8000L
    }
}
