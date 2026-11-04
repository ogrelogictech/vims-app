package com.vims.app.services

import android.app.Activity
import com.vims.app.data.AndroidStoreDef
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

class BillingManagerTest {
    private val ids = AndroidStoreDef()
    private val day = 86_400_000L

    private class Mem(var s: BillingSnapshot = BillingSnapshot()) : BillingStore {
        override fun read() = s
        override fun write(s: BillingSnapshot) { this.s = s }
    }

    private class Store : StoreBackend {
        var answer: List<StorePurchase>? = emptyList()
        var ackOk = true
        var consumeOk = true
        val acked = mutableListOf<String>()
        val consumed = mutableListOf<String>()
        override fun setListener(listener: (StoreUpdate) -> Unit) {}
        override suspend fun queryPlans() = emptyList<PlanOption>()
        override suspend fun queryPurchases() = answer
        override suspend fun launch(activity: Activity, kind: PlanKind, replaceToken: String?) = true
        override suspend fun acknowledge(token: String): Boolean { if (ackOk) acked += token; return ackOk }
        override suspend fun consume(token: String): Boolean { if (consumeOk) consumed += token; return consumeOk }
    }

    private var clock = 1_800_000_000_000L
    private fun manager(store: Store, mem: Mem, key: String = "") = BillingManager(store, mem, ids, PurchaseVerifier(key), CoroutineScope(Dispatchers.Unconfined)) { clock }
    private fun sub(token: String = "s1", plan: String? = "monthly", ack: Boolean = false, state: PurchaseState = PurchaseState.PURCHASED, suspended: Boolean = false, json: String = "{}", sig: String = "") =
        StorePurchase(ids.subscription, token, state, ack, true, clock, plan, 1, json, sig, suspended)
    private fun credit(token: String = "c1", state: PurchaseState = PurchaseState.PURCHASED) =
        StorePurchase(ids.reportCredit, token, state, false, false, clock, null, 1, "{}", "")

    @Test fun subscription_isAcknowledgedAndCached() = runBlocking {
        val store = Store().apply { answer = listOf(sub()) }; val mem = Mem(); val m = manager(store, mem)
        assertTrue(m.refresh())
        assertEquals(listOf("s1"), store.acked)
        assertTrue(m.status.value.active)
        assertEquals("monthly", mem.s.sub?.basePlan)
        assertEquals(Access.periodEnd(clock, false, clock), mem.s.sub?.expiryMillis)
    }

    @Test fun acknowledgedOnce_failureRetriedOnNextRefresh() = runBlocking {
        val store = Store().apply { answer = listOf(sub()); ackOk = false }; val m = manager(store, Mem())
        m.refresh()
        assertTrue(store.acked.isEmpty())
        store.ackOk = true
        m.refresh()
        assertEquals(listOf("s1"), store.acked)
        store.answer = listOf(sub(ack = true))
        m.refresh()
        assertEquals(listOf("s1"), store.acked)
    }

    @Test fun credit_savedThenConsumed_failedConsumeNeverGrantsTwice() = runBlocking {
        val store = Store().apply { answer = listOf(credit()); consumeOk = false }; val mem = Mem(); val m = manager(store, mem)
        m.refresh()
        assertEquals(1, mem.s.credits)
        assertTrue(store.consumed.isEmpty())
        store.consumeOk = true
        m.refresh()
        assertEquals(1, mem.s.credits)
        assertEquals(listOf("c1"), store.consumed)
    }

    @Test fun spendCredit() = runBlocking {
        val mem = Mem(BillingSnapshot(credits = 1)); val m = manager(Store(), mem)
        assertTrue(m.spendCredit())
        assertEquals(0, m.status.value.credits)
        assertFalse(m.spendCredit())
    }

    @Test fun pending_grantsNothing() = runBlocking {
        val store = Store().apply { answer = listOf(sub(state = PurchaseState.PENDING), credit(state = PurchaseState.PENDING)) }; val mem = Mem(); val m = manager(store, mem)
        m.refresh()
        assertFalse(m.status.value.active)
        assertTrue(m.status.value.pendingSub)
        assertTrue(m.status.value.pendingCredit)
        assertEquals(0, mem.s.credits)
        assertTrue(store.acked.isEmpty() && store.consumed.isEmpty())
    }

    @Test fun storeThatAnswers_overridesCache() = runBlocking {
        val mem = Mem(BillingSnapshot(sub = CachedSub("s1", "yearly", clock, clock + 300 * day))); val store = Store(); val m = manager(store, mem)
        assertTrue(m.status.value.active)
        m.refresh()
        assertFalse(m.status.value.active)
        assertTrue(m.status.value.ended)
        assertNull(mem.s.sub)
    }

    @Test fun storeOutOfReach_cacheHoldsUntilExpiryPlusSeven() = runBlocking {
        val mem = Mem(BillingSnapshot(sub = CachedSub("s1", "monthly", clock, clock + 10 * day))); val store = Store().apply { answer = null }; val m = manager(store, mem)
        assertFalse(m.refresh())
        assertTrue(m.status.value.active && m.status.value.cached)
        clock += 17 * day
        m.refresh()
        assertTrue(m.status.value.active)
        clock += day
        m.refresh()
        assertFalse(m.status.value.active)
        assertNotNull(mem.s.sub)
    }

    @Test fun onHold_isNotActive() = runBlocking {
        val store = Store().apply { answer = listOf(sub(ack = true, suspended = true)) }; val mem = Mem(BillingSnapshot(sub = CachedSub("s1", "monthly", clock, clock + day))); val m = manager(store, mem)
        m.refresh()
        assertFalse(m.status.value.active)
        assertTrue(m.status.value.onHold)
    }

    @Test fun signature_checkedWhenKeySupplied_failureGrantsNothing() = runBlocking {
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val key = Base64.getEncoder().encodeToString(pair.public.encoded)
        val json = """{"productId":"vims_app"}"""
        val sig = Base64.getEncoder().encodeToString(Signature.getInstance("SHA1withRSA").run { initSign(pair.private); update(json.toByteArray()); sign() })

        val bad = Store().apply { answer = listOf(sub(json = json, sig = Base64.getEncoder().encodeToString(ByteArray(256)))) }
        val m1 = manager(bad, Mem(), key)
        m1.refresh()
        assertFalse(m1.status.value.active)
        assertTrue(bad.acked.isEmpty())

        val good = Store().apply { answer = listOf(sub(json = json, sig = sig)) }
        val m2 = manager(good, Mem(), key)
        m2.refresh()
        assertTrue(m2.status.value.active)
        assertEquals(listOf("s1"), good.acked)
    }

    @Test fun noKey_skipsTheSignatureCheck() = runBlocking {
        val m = manager(Store().apply { answer = listOf(sub(sig = "not checked")) }, Mem())
        m.refresh()
        assertTrue(m.status.value.active)
    }
}
