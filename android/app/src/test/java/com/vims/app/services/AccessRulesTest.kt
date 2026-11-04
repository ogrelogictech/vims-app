package com.vims.app.services

import com.vims.app.data.AccountState
import com.vims.app.data.ChecklistLoader
import com.vims.app.util.OwnerCode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class AccessRulesTest {
    private fun can(owner: Boolean = false, trial: Int = 0, sub: Boolean = false, credits: Int = 0) = Access.canStartNewInspection(owner, trial, sub, credits)
    private fun gate(owner: Boolean = false, trial: Int = 0, sub: Boolean = false, credits: Int = 0, generated: Boolean = false) =
        Access.reportGate(owner, trial, sub, credits, generated)

    @Test fun newInspection_needsOneOfTheFourGrants() {
        assertFalse(can())
        assertTrue(can(owner = true))
        assertTrue(can(trial = 1))
        assertTrue(can(sub = true))
        assertTrue(can(credits = 1))
        assertFalse(can(trial = 0, credits = 0))
    }

    @Test fun report_firstUsesCreditOnlyWithoutSubscriptionOrTrial() {
        assertEquals(ReportGate.FREE, gate(trial = 3, credits = 2))
        assertEquals(ReportGate.FREE, gate(sub = true, credits = 2))
        assertEquals(ReportGate.FREE, gate(owner = true))
        assertEquals(ReportGate.USES_CREDIT, gate(credits = 1))
        assertEquals(ReportGate.NEEDS_PURCHASE, gate())
    }

    @Test fun report_regeneratingIsAlwaysFree() {
        assertEquals(ReportGate.FREE, gate(generated = true))
        assertEquals(ReportGate.FREE, gate(credits = 1, generated = true))
    }

    @Test fun cache_holdsUntilExpiryPlusSevenDays() {
        val expiry = 1_000_000_000_000L
        val sub = CachedSub("t", "monthly", 0, expiry)
        assertTrue(Access.cacheHolds(sub, expiry))
        assertTrue(Access.cacheHolds(sub, expiry + Access.OFFLINE_HOLD_MS))
        assertFalse(Access.cacheHolds(sub, expiry + Access.OFFLINE_HOLD_MS + 1))
        assertFalse(Access.cacheHolds(null, 0))
    }

    @Test fun periodEnd_countsWholePeriodsFromPurchase() {
        val p = Instant.parse("2026-01-15T10:00:00Z").toEpochMilli()
        assertEquals(Instant.parse("2026-02-15T10:00:00Z").toEpochMilli(), Access.periodEnd(p, false, p))
        assertEquals(Instant.parse("2026-11-15T10:00:00Z").toEpochMilli(), Access.periodEnd(p, false, Instant.parse("2026-11-04T00:00:00Z").toEpochMilli()))
        assertEquals(Instant.parse("2027-01-15T10:00:00Z").toEpochMilli(), Access.periodEnd(p, true, Instant.parse("2026-11-04T00:00:00Z").toEpochMilli()))
    }

    @Test fun lengthLabel() {
        assertEquals("1 month", Access.lengthLabel("P1M"))
        assertEquals("1 year", Access.lengthLabel("P1Y"))
        assertEquals("3 months", Access.lengthLabel("P3M"))
    }

    @Test fun simulatedSubscriptionFromAnEarlierBuild_decodesAndCountsForNothing() {
        val old = """{"companyCode":"VIS-4827","planId":"app","billingPeriod":"yearly","active":true,"seats":3,"trialDays":30,"trialStartEpochDay":20000,
            "cardLast4":"4242","card":{"brand":"Visa","last4":"4242","expMonth":8,"expYear":2028,"squareCardId":null},"subscribedEpochDay":20100,
            "cancelled":true,"cancelledEpochDay":20200,"refundAmount":12.5,"inspectors":[]}"""
        val a = ChecklistLoader.json.decodeFromString(AccountState.serializer(), old)
        assertEquals("VIS-4827", a.companyCode)
        assertEquals(20000L, a.trialStartEpochDay)
        val encoded = ChecklistLoader.json.encodeToString(AccountState.serializer(), a)
        listOf("active", "cardLast4", "subscribedEpochDay", "refundAmount").forEach { assertFalse(it, encoded.contains("\"$it\"")) }
    }

    /** Salt, rounds and hash made with Python's hashlib.pbkdf2_hmac for the throwaway code THROWAWAY1234, like shared support.ownerCode. */
    @Test fun ownerCode_comparesNormalized() {
        val salt = "00112233445566778899aabbccddeeff"
        val hash = "8dc6786cf38a0c9deb4b38c02ea284655c8e82c563f139f452d450fb0bc88bae"
        assertTrue(OwnerCode.matches("THROWAWAY1234", salt, 200000, hash))
        assertTrue(OwnerCode.matches(" throwaway-1234 ", salt, 200000, hash))
        assertFalse(OwnerCode.matches("THROWAWAY1235", salt, 200000, hash))
        assertFalse(OwnerCode.matches("", salt, 200000, hash))
        assertFalse(OwnerCode.matches("---", salt, 200000, hash))
    }
}
