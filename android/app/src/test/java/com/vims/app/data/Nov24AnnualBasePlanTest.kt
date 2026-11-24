package com.vims.app.data

import org.junit.Assert.assertEquals
import org.junit.Test

/** Nov 24 (shared v1.27.1): the Play subscription's yearly base plan ID is "annual" (as set up in Play Console). */
class Nov24AnnualBasePlanTest {
    private val config = TestData.config

    @Test fun data_version() = assertEquals("1.27.1", config.version)

    @Test fun playIds_matchPlayConsole() {
        val a = config.subscription.store.android
        assertEquals("vims_app", a.subscription)
        assertEquals("monthly", a.monthlyBasePlan)
        assertEquals("annual", a.yearlyBasePlan)
        assertEquals("vims_report_credit", a.reportCredit)
        // The built-in fallback matches, so a missing value can't bring "yearly" back.
        assertEquals("annual", AndroidStoreDef().yearlyBasePlan)
    }
}
