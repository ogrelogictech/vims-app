package com.vims.app.data

import com.vims.app.util.Filters
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Client Nov 11 (shared v1.23.0), against the real shared JSON. */
class Nov11ZeroSystemsAndCancellationFeeTest {
    private val config = TestData.config
    private val engine = ChecklistEngine(config, ChecklistEdits())
    private fun rc(key: String) = config.wizard.roomCounts.first { it.key == key }
    private fun base() = engine.defaultSelections("standard").copy(inspType = "Real Estate Sale")
    private fun sections(sel: WizardSelections) = engine.buildGroups(sel).flatMap { it.leaves }
    private fun with(vararg c: Pair<String, Int>) = base().let { it.copy(counts = it.counts + c) }
    private val systems = mapOf("hvacUnits" to "HVAC Mechanical", "waterHeaters" to "Water Heater", "electricalPanels" to "Electrical")

    /* ---------------------------------------------------------------- 0 HVAC Units / Water Heaters / Electrical Panels */

    @Test fun data_theThreeSystemSteppersGoDownToZero() {
        systems.keys.forEach { assertEquals(it, 0, rc(it).min); assertEquals(it, 0, rc(it).lowest) }
        assertEquals("1.23.0", config.version)
    }

    @Test fun stepperDownToZero_storesZero() {
        systems.keys.forEach { k -> assertEquals(k, 0, base().withRoomCount(rc(k), 0).count(k)) }
    }

    @Test fun eachSystemAtZero_leavesOnlyItsOwnSectionOut() {
        val all = sections(base())
        systems.forEach { (key, section) ->
            val s = sections(base().withRoomCount(rc(key), 0))
            assertFalse(key, s.any { it == section || baseName(it) == section })
            assertEquals(key, all - section, s)
        }
    }

    @Test fun allThreeAtZero_noSystemSections_noCoolingCopies_utilityGroupKeepsTheRest() {
        val sel = with("hvacUnits" to 0, "waterHeaters" to 0, "electricalPanels" to 0)
        val s = sections(sel)
        listOf("HVAC Mechanical", "Water Heater", "Electrical", "Cooling System").forEach { n -> assertFalse(n, s.any { baseName(it) == n }) }
        val utility = engine.buildGroups(sel).firstNotNullOf { it.sub?.takeIf { g -> g.heading == "Utility & Function" } }.sections
        assertEquals(listOf("Utility Room", "Plumbing", "Foundation / Crawl Space"), utility)
        // Outside Utilities (with its own cooling items) stays; it isn't one of the counted systems.
        assertTrue("Outside Utilities" in s)
    }

    @Test fun hvacZero_noCoolingSystemCopy_evenAfterHavingSeveral() {
        val many = with("hvacUnits" to 3)
        assertTrue(sections(many).any { it.startsWith("Cooling System #") })
        val zero = many.withRoomCount(rc("hvacUnits"), 0)
        assertFalse(sections(zero).any { it.startsWith("Cooling System") || it.startsWith("HVAC Mechanical") })
    }

    @Test fun zero_snapshotHasNoDefinitionForTheMissingSections() {
        val d = engine.snapshot(engine.buildGroups(with("hvacUnits" to 0, "waterHeaters" to 0, "electricalPanels" to 0)))
        listOf("HVAC Mechanical", "Water Heater", "Electrical", "Cooling System").forEach { assertNull(it, d[it]) }
    }

    @Test fun zero_reportOrderAndProgressSectionsLeaveThemOut() {
        val sel = with("hvacUnits" to 0, "waterHeaters" to 0, "electricalPanels" to 0)
        val g = engine.buildGroups(sel)
        val leaves = g.flatMap { it.leaves }
        val defs = engine.snapshot(g)
        val order = ChecklistEngine.reportOrder(leaves, defs, config, sel.inspType)
        assertEquals(leaves.toSet(), order.toSet())
        val b = InspectionBundle(Inspection(id = "x", createdAt = 0, selections = sel, groups = g), defs = defs)
        assertFalse(b.progressSections.any { baseName(it) in systems.values })
        assertEquals(leaves.size - 1, b.progressSections.size) // only the blank Planned Maintenance is left out of progress
    }

    @Test fun lockedLayouts_ignoreZeroToo() {
        listOf("Texas", "4 Point Inspection", "Phase 1 Foundation", "Phase 2 Pre-Dry Wall", "Tests Only").forEach { t ->
            assertEquals(t, sections(base().copy(inspType = t)), sections(with("hvacUnits" to 0, "waterHeaters" to 0, "electricalPanels" to 0).copy(inspType = t)))
        }
    }

    /* ---------------------------------------------------------------- saved inspections */

    @Test fun legacy_noStoredValue_readsOne_checklistUnchanged() {
        val legacy = base().copy(counts = mapOf("bedrooms" to 4, "bathrooms" to 3, "hallways" to 2))
        systems.keys.forEach { assertEquals(it, 1, legacy.count(it)) }
        val s = sections(legacy)
        systems.values.forEach { assertTrue(it, it in s) }
        assertEquals(sections(base()), s)
    }

    @Test fun legacy_storedOne_staysOne() {
        systems.keys.forEach { k -> assertEquals(1, base().copy(counts = mapOf(k to 1)).count(k)) }
    }

    /* ---------------------------------------------------------------- Day-of cancellation fee */

    private val about = "Cancellation on day of inspection"
    private fun para(pieces: List<AgreementPiece>) = pieces.filterIsInstance<AgreementPiece.Para>().first { about in it.text }
    private fun filled(c: CompanyProfile, pieces: List<AgreementPiece> = TestData.pieces) =
        AgreementFill.apply(pieces, TestData.prefill, AgreementFill.withCompany(AgreementFillInput(clientName = "Ann Lee"), c))

    @Test fun data_prefillHasTheClosingLine_andTheAgreementHasItsBlank() {
        val line = TestData.prefill.lines.single { it.label == "a fee totaling" }
        assertEquals("closing", line.part)
        assertTrue(para(TestData.pieces).text.contains(Regex("a fee totaling _+% of the amount")))
    }

    @Test fun fee25_fillsTheBlank_boldNumberOnly() {
        val p = para(filled(CompanyProfile(cancellationFeePercent = 25)))
        assertTrue(p.text, "a fee totaling 25% of the amount of the inspection will be charged." in p.text)
        assertFalse(p.text, "_" in p.text)
        assertEquals(listOf("25"), p.bold.map { p.text.substring(it) })
    }

    @Test fun feeZeroAndHundred_areFilled() {
        assertTrue("a fee totaling 0% of" in para(filled(CompanyProfile(cancellationFeePercent = 0))).text)
        assertTrue("a fee totaling 100% of" in para(filled(CompanyProfile(cancellationFeePercent = 100))).text)
    }

    @Test fun blank_keepsTheUnderscores() {
        val original = para(TestData.pieces)
        assertEquals(original, para(filled(CompanyProfile())))
        assertTrue("a fee totaling __________%" in para(filled(CompanyProfile())).text)
    }

    @Test fun outOfRange_isTreatedAsBlank() {
        assertEquals("", CompanyProfile(cancellationFeePercent = 101).cancellationFee)
        assertEquals("", CompanyProfile(cancellationFeePercent = -1).cancellationFee)
        assertEquals("25", CompanyProfile(cancellationFeePercent = 25).cancellationFee)
    }

    @Test fun otherClosingLinesStillFill() {
        val out = filled(CompanyProfile(cancellationFeePercent = 25))
        assertTrue(out.filterIsInstance<AgreementPiece.Para>().any { "Printed Name of Client: Ann Lee" in it.text })
    }

    @Test fun editedAgreementWithoutTheWording_isSkipped() {
        val pieces = listOf(AgreementPiece.Title("Our agreement"), AgreementPiece.Para("Cancellations are free of charge."),
            AgreementPiece.Para("A fee of ____ applies to returned checks."))
        assertEquals(pieces, AgreementFill.apply(pieces, TestData.prefill, AgreementFill.withCompany(AgreementFillInput(), CompanyProfile(cancellationFeePercent = 25))))
    }

    @Test fun editedAgreementKeepingTheWording_isFilled() {
        val blocks = listOf(AgreementDocBlock("title", "Our agreement"), AgreementDocBlock("p", "If canceled the same day a fee totaling ______% of the fee is due."))
        val pieces = AgreementBlocks.pieces(blocks, TestData.agreement.formLines("Acme"))
        val out = AgreementFill.apply(pieces, TestData.prefill, AgreementFill.withCompany(AgreementFillInput(), CompanyProfile(cancellationFeePercent = 30)))
        assertTrue(out.filterIsInstance<AgreementPiece.Para>().any { it.text == "If canceled the same day a fee totaling 30% of the fee is due." })
    }

    @Test fun noFillInput_isNeverFilled_theFeeIsNotPerInspection() {
        // The wizard / inspection values alone carry no fee: only the company profile does.
        val i = AgreementFill.input(base(), "Jeremy K. Heath", config.wizard.unitMixDefault)
        assertEquals("", i.cancellationFee)
        assertEquals(para(TestData.pieces), para(AgreementFill.apply(TestData.pieces, TestData.prefill, i)))
    }

    /* ---------------------------------------------------------------- company profile storage */

    @Test fun profileFrom035_decodesWithNoFee_andEncodesToTheSameJson() {
        val json = ChecklistLoader.json
        val old = json.encodeToString(CompanyProfile.serializer(), CompanyProfile(name = "Acme", license = "UT-1", licenseState = "UT", phone = "8015550134"))
        assertFalse(old, "cancellationFeePercent" in old)
        val read = json.decodeFromString(CompanyProfile.serializer(), old)
        assertNull(read.cancellationFeePercent)
        assertEquals(old, json.encodeToString(CompanyProfile.serializer(), read))
        val withFee = json.encodeToString(CompanyProfile.serializer(), read.copy(cancellationFeePercent = 25))
        assertEquals(25, json.decodeFromString(CompanyProfile.serializer(), withFee).cancellationFeePercent)
    }

    @Test fun percentFilter_wholeNumber0to100() {
        assertEquals("25", Filters.percent("25"))
        assertEquals("25", Filters.percent("2a5%"))
        assertEquals("100", Filters.percent("250"))
        assertEquals("100", Filters.percent("1000"))
        assertEquals("0", Filters.percent("0"))
        assertEquals("", Filters.percent(""))
    }
}
