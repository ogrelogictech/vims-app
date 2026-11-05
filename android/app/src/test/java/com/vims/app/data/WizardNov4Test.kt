package com.vims.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WizardNov4Test {
    private val engine = ChecklistEngine(TestData.config, ChecklistEdits())
    private fun base() = engine.defaultSelections("standard").copy(inspType = "Real Estate Sale")
    private fun sections(sel: WizardSelections) = engine.buildGroups(sel).flatMap { it.leaves }
    private fun exteriorOf(sel: WizardSelections) = engine.buildGroups(sel).first { it.heading == "Property Exterior" }.sections
    private fun utilityOf(sel: WizardSelections) = engine.buildGroups(sel).firstNotNullOf { it.sub?.takeIf { s -> s.heading == "Utility & Function" } }.sections

    /** Before shared v1.19.0: Chimney first among the optional exterior sections, after the fixed ones. */
    private val expectedExterior = listOf("Landscaping", "Roof", "Exterior Walls", "Outside Utilities", "Chimney", "Deck")

    @Test fun defaults_haveChimneyUnderUtilities() {
        assertTrue("Chimney" in base().utilOpt)
        assertFalse("Chimney" in base().exterior)
    }

    @Test fun chimney_newInspection_keepsItsOldPlace_notUnderUtility() {
        assertEquals(expectedExterior, exteriorOf(base()))
        assertFalse("Chimney" in utilityOf(base()))
    }

    @Test fun chimney_savedUnderExterior_sameChecklistAsNew() {
        val saved = base().copy(utilOpt = emptyList(), exterior = listOf("Chimney", "Deck"))
        assertEquals(sections(base()), sections(saved))
    }

    @Test fun chimney_underBoth_appearsOnce() {
        val s = base().copy(exterior = base().exterior + "Chimney")
        assertEquals(1, sections(s).count { it == "Chimney" })
    }

    @Test fun chimney_notSelected_hasNoSection() {
        assertFalse("Chimney" in sections(base().copy(utilOpt = emptyList())))
    }

    @Test fun chimney_lockedType_hasNoSection_chosenOrSaved() {
        val phase = base().copy(inspType = "Tests Only")
        assertFalse("Chimney" in sections(phase))
        assertFalse("Chimney" in sections(phase.copy(utilOpt = emptyList(), exterior = listOf("Chimney"))))
    }

    @Test fun checklistOrder_notTheChipOrder_utilityAndTesting() {
        val all = base().copy(utilOpt = TestData.config.wizard.utilityOptions, tests = TestData.config.wizard.testOptions)
        assertEquals(listOf("Utility Room", "HVAC Mechanical", "Electrical", "Water Heater", "Boiler", "Heating Oil Tank", "Propane Tank", "Plumbing", "Foundation / Crawl Space"), utilityOf(all))
        val oldTests = listOf("Radon", "Meth Test", "Thermal Audit", "Termite", "Lead", "Indoor Air Quality", "Septic", "Sewer Scope", "Asbestos", "Wind Mitigation")
        assertEquals(oldTests, engine.buildGroups(all).first { it.heading == "Testing" }.sections)
        assertEquals(oldTests, engine.buildGroups(all.copy(inspType = "Tests Only")).first { it.heading == "Testing" }.sections)
    }

    @Test fun everyWizardOption_hasAPlaceInTheChecklist() {
        val w = TestData.config.wizard
        val o = TestData.config.checklistBuilder.checklistOrder
        assertEquals((w.utilityOptions + w.testOptions + w.exteriorOptions).toSet(), (o.exterior + o.utility + o.tests).toSet())
    }

    @Test fun editWizard_movesSavedChimney_checklistUnchanged_noDuplicate() {
        val saved = base().copy(utilOpt = listOf("Boiler"), exterior = listOf("Chimney", "Deck"))
        val edit = saved.chimneyMovedToUtilities()
        assertEquals(listOf("Deck"), edit.exterior)
        assertEquals(listOf("Boiler", "Chimney"), edit.utilOpt)
        assertEquals(sections(saved), sections(edit))
        assertEquals(edit, edit.chimneyMovedToUtilities())
    }

    @Test fun utilities_showsChimneySavedUnderExterior_once() {
        assertEquals(listOf("Boiler", "Chimney"), base().copy(utilOpt = listOf("Boiler"), exterior = listOf("Chimney")).utilities)
        assertEquals(listOf("Chimney"), base().copy(utilOpt = listOf("Chimney"), exterior = listOf("Chimney")).utilities)
    }

    @Test fun oldInspection_withoutTheNewFields_decodes() {
        val old = """{"fields":{"Client name":"A"},"structure":"Mobile / Manufactured","exterior":["Chimney"],"utilOpt":[],"tests":["Radon"]}"""
        val s = ChecklistLoader.json.decodeFromString(WizardSelections.serializer(), old)
        assertEquals(emptyMap<String, String>(), s.fees)
        assertEquals("", s.inspectionFee)
        assertEquals("Mobile / Manufactured", s.structure)
        assertEquals("", s.licenseState)
        val c = ChecklistLoader.json.decodeFromString(CompanyProfile.serializer(), """{"name":"Acme","license":"UT-1"}""")
        assertEquals("", c.licenseState)
    }

    @Test fun structures_bothMobileTypes_addUndercarriage() {
        val w = TestData.config.wizard
        assertEquals(listOf("Single Family", "Duplex", "Multi-Unit", "Townhouse", "Condo", "Mobile Home", "Manufactured Home"), w.structureTypes)
        listOf("Mobile Home", "Manufactured Home").forEach { assertEquals("Mobile Home Undercarriage", w.structureSideEffects[it]?.get("exterior")) }
    }

    // ---- wizard.fees

    @Test fun cents_exact_andForgiving() {
        assertEquals(15050L, Fees.cents("150.5"))
        assertEquals(10L, Fees.cents("0.1"))
        assertEquals(30L, Fees.cents("0.3"))
        assertEquals(9_999_999L, Fees.cents("99999.99"))
        assertEquals(125000L, Fees.cents("1,250"))
        assertEquals(1200L, Fees.cents("12."))
        assertEquals(50L, Fees.cents(".5"))
        listOf("", ".", "abc", "1.2.3").forEach { assertEquals(it, 0L, Fees.cents(it)) }
    }

    @Test fun format_twoDecimals() {
        assertEquals("150.00", Fees.format(15000))
        assertEquals("0.05", Fees.format(5))
        assertEquals("1,399,999.86", Fees.grouped(139_999_986))
        assertEquals("", Fees.agreementValue(0))
        assertEquals("2,281.25", Fees.agreementValue(228_125))
    }

    @Test fun totals_addUp_withoutFloatingPointDrift() {
        val s = WizardSelections(tests = listOf("Radon", "Lead"), utilOpt = listOf("Boiler"), fees = mapOf("Radon" to "0.1", "Lead" to "0.2", "Boiler" to "0.3"), inspectionFee = "100")
        val t = Fees.totals(s, areasLocked = false)
        assertEquals(60L, t.bundled)
        assertEquals(10060L, t.total)
    }

    @Test fun totals_onlySelectedOptionsCount() {
        val s = WizardSelections(tests = listOf("Radon"), fees = mapOf("Radon" to "10", "Lead" to "99"))
        assertEquals(1000L, Fees.totals(s, false).bundled)
    }

    @Test fun totals_lockedUtilitiesDontCount_untilUnlocked() {
        val s = WizardSelections(utilOpt = listOf("Boiler"), tests = listOf("Radon"), fees = mapOf("Boiler" to "50", "Radon" to "10"))
        assertEquals(1000L, Fees.totals(s, true).bundled)
        assertEquals(6000L, Fees.totals(s, false).bundled)
    }

    @Test fun totals_chimneySavedUnderExterior_counts() {
        assertEquals(700L, Fees.totals(WizardSelections(exterior = listOf("Chimney"), fees = mapOf("Chimney" to "7")), false).bundled)
    }

    @Test fun defaultChimney_notCountedOrTicked_onALockedType() {
        val phase1 = base().copy(inspType = "Phase 1 Foundation", fees = mapOf("Chimney" to "75"))
        assertEquals(0L, Fees.totals(phase1, true).bundled)
        assertEquals(emptyList<String>(), AgreementFill.input(phase1, "", emptyMap(), true).utilities)
    }

    @Test fun amount_aboveZero_selects_zeroDoesnt_clearingKeepsSelection() {
        var s = WizardSelections()
        s = s.withFeeAmount("Radon", false, "0")
        assertFalse("Radon" in s.tests)
        s = s.withFeeAmount("Radon", false, "0.")
        assertFalse("Radon" in s.tests)
        s = s.withFeeAmount("Radon", false, "0.5")
        assertTrue("Radon" in s.tests)
        s = s.withFeeAmount("Radon", false, "")
        assertTrue("Radon" in s.tests)
        assertFalse("Radon" in s.fees)
        s = s.withFeeAmount("Boiler", true, "25")
        assertEquals(listOf("Boiler"), s.utilOpt)
    }

    @Test fun deselect_clearsAmount_reselectStartsEmpty() {
        var s = WizardSelections().withFeeAmount("Radon", false, "25")
        s = s.toggleFeeOption("Radon", false)
        assertFalse("Radon" in s.tests)
        assertEquals(emptyMap<String, String>(), s.fees)
        s = s.toggleFeeOption("Radon", false)
        assertTrue("Radon" in s.tests)
        assertEquals(emptyMap<String, String>(), s.fees)
    }

    @Test fun spec_utilitiesAndTests_inTheGivenOrder_everyOptionHasAFeeLine() {
        val w = TestData.config.wizard
        assertEquals(listOf("Chimney", "Heating Oil Tank", "Propane Tank", "Boiler"), w.utilityOptions)
        assertEquals(listOf("Radon", "Indoor Air Quality", "Lead", "Asbestos", "Meth Test", "Thermal Audit", "Sewer Scope", "Wind Mitigation", "Septic", "Termite"), w.testOptions)
        val fees = TestData.prefill.lines.mapNotNull { it.fee }
        (w.utilityOptions + w.testOptions).forEach { assertTrue(it, it in fees) }
    }
}
