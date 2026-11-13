package com.vims.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Client Nov 13 (shared v1.24.0): Out of service area surcharge, against the real shared JSON. */
class Nov13SurchargeTest {
    private val config = TestData.config
    private val surchargeLabel = "Out of service area surcharge $"

    private fun sel(fee: String = "", surcharge: String = "", tests: List<String> = emptyList(), fees: Map<String, String> = emptyMap(), type: String = "Real Estate Sale", util: List<String> = emptyList()) =
        WizardSelections(inspType = type, tests = tests, utilOpt = util, fees = fees, inspectionFee = fee, surcharge = surcharge, state = "UT")

    private fun form(s: WizardSelections, pieces: List<AgreementPiece> = TestData.pieces): AgreementPiece.Form {
        val i = AgreementFill.input(s, "Jeremy K. Heath", config.wizard.unitMixDefault, config.wizard.areasLocked(s.inspType))
        return AgreementFill.apply(pieces, TestData.prefill, i).first { it is AgreementPiece.Form } as AgreementPiece.Form
    }
    private fun AgreementPiece.Form.line(part: String) = lines.first { part in it }

    /* ---------------------------------------------------------------- data */

    @Test fun data_version_specAndAgreementLine() {
        assertEquals("1.24.0", config.version)
        val spec = TestData.prefill.lines.single { it.label == surchargeLabel }
        assertEquals("header", spec.part)
        assertEquals(null, spec.fee)
        val form = TestData.agreement.formLines("Acme")
        val at = form.indexOf("Out of service area surcharge \$__________")
        assertTrue(form.joinToString("\n"), at >= 0)
        assertTrue(form[at + 1], form[at + 1].startsWith("Inspection Fee $"))
        // Listed before Inspection Fee in the prefill lines too.
        val labels = TestData.prefill.lines.map { it.label }
        assertTrue(labels.indexOf(surchargeLabel) < labels.indexOf("Inspection Fee $"))
    }

    /* ---------------------------------------------------------------- totals */

    @Test fun total_includesSurcharge_bundledDoesNot() {
        val t = Fees.totals(sel(fee = "400", surcharge = "75", tests = listOf("Radon"), fees = mapOf("Radon" to "150")), areasLocked = false)
        assertEquals(15_000L, t.bundled)
        assertEquals(40_000L, t.inspection)
        assertEquals(7_500L, t.surcharge)
        assertEquals(62_500L, t.total)
        assertEquals("625.00", Fees.grouped(t.total))
    }

    @Test fun surcharge_isNotLockedByAreasLockedTypes() {
        val type = config.wizard.areasLockedTypes.first()
        assertTrue(config.wizard.areasLocked(type))
        val t = Fees.totals(sel(type = type, surcharge = "50.5", util = listOf("Boiler"), fees = mapOf("Boiler" to "20")), areasLocked = true)
        assertEquals(0L, t.bundled)
        assertEquals(5_050L, t.total)
    }

    @Test fun surchargeAlone_isTheTotal() {
        val t = Fees.totals(sel(surcharge = "75"), areasLocked = false)
        assertEquals(0L, t.inspection)
        assertEquals(0L, t.bundled)
        assertEquals(7_500L, t.total)
    }

    /* ---------------------------------------------------------------- agreement */

    @Test fun fillsItsLine_andTotalAmountDueIncludesIt() {
        val f = form(sel(fee = "400", surcharge = "75", tests = listOf("Radon"), fees = mapOf("Radon" to "150")))
        assertEquals("Out of service area surcharge $75.00", f.line(surchargeLabel))
        assertEquals("Inspection Fee $400.00 Bundled Services $150.00 Total Amount Due $625.00", f.line("Inspection Fee $"))
        val k = f.lines.indexOf("Out of service area surcharge $75.00")
        assertEquals(listOf("75.00"), f.bold[k]!!.map { f.lines[k].substring(it) })
    }

    @Test fun twoDecimalsWithCommas() {
        val f = form(sel(fee = "1250", surcharge = "1250.5"))
        assertEquals("Out of service area surcharge $1,250.50", f.line(surchargeLabel))
        assertEquals("Inspection Fee $1,250.00 Bundled Services \$__________ Total Amount Due $2,500.50", f.line("Inspection Fee $"))
    }

    @Test fun blankOrZero_leavesTheLineBlank_totalUnchanged() {
        listOf("", "0", "0.00", ".").forEach { s ->
            val f = form(sel(fee = "400", surcharge = s))
            assertEquals(s, TestData.original(surchargeLabel), f.line(surchargeLabel))
            assertEquals(s, "Inspection Fee $400.00 Bundled Services \$__________ Total Amount Due $400.00", f.line("Inspection Fee $"))
        }
    }

    @Test fun surchargeOnly_fillsItsLineAndTheTotal_inspectionAndBundledStayBlank() {
        val f = form(sel(surcharge = "75"))
        assertEquals("Out of service area surcharge $75.00", f.line(surchargeLabel))
        assertEquals("Inspection Fee \$__________ Bundled Services \$__________ Total Amount Due $75.00", f.line("Inspection Fee $"))
    }

    @Test fun editedAgreement_getsTheCurrentFormBlock_andItFills() {
        val blocks = listOf(AgreementDocBlock("title", "Our agreement"), AgreementDocBlock("p", "Our words."))
        val pieces = AgreementBlocks.pieces(blocks, TestData.agreement.formLines("Acme"))
        val f = form(sel(fee = "400", surcharge = "75"), pieces)
        assertEquals("Out of service area surcharge $75.00", f.line(surchargeLabel))
        assertTrue(f.line("Total Amount Due").endsWith("Total Amount Due $475.00"))
    }

    @Test fun agreementWithoutTheLine_isSkippedSilently() {
        val pieces = listOf(AgreementPiece.Title("Our agreement"), AgreementPiece.Form(listOf("Inspection Fee \$____ Total Amount Due \$____")))
        val f = form(sel(fee = "400", surcharge = "75"), pieces)
        assertEquals(listOf("Inspection Fee $400.00 Total Amount Due $475.00"), f.lines)
    }

    /* ---------------------------------------------------------------- saved inspections */

    @Test fun legacyInspection_withoutSurcharge_readsBlank_andNothingChanges() {
        val json = ChecklistLoader.json
        // 0.36.0 stored the selections with every field, but had no surcharge.
        val stored = json.encodeToString(Inspection.serializer(), Inspection(id = "old", createdAt = 1L,
            selections = sel(fee = "400", tests = listOf("Radon"), fees = mapOf("Radon" to "150"))))
            .replace(",\"surcharge\":\"\"", "")
        assertFalse(stored, "surcharge" in stored)
        val read = json.decodeFromString(Inspection.serializer(), stored)
        assertEquals("", read.selections.surcharge)
        val t = Fees.totals(read.selections, areasLocked = false)
        assertEquals(0L, t.surcharge)
        assertEquals(55_000L, t.total)
        val f = form(read.selections)
        assertEquals(TestData.original(surchargeLabel), f.line(surchargeLabel))
        assertEquals("Inspection Fee $400.00 Bundled Services $150.00 Total Amount Due $550.00", f.line("Inspection Fee $"))
    }

    @Test fun surcharge_roundTripsInTheInspectionJson() {
        val json = ChecklistLoader.json
        val i = Inspection(id = "new", createdAt = 1L, selections = sel(fee = "400", surcharge = "75"))
        assertEquals("75", json.decodeFromString(Inspection.serializer(), json.encodeToString(Inspection.serializer(), i)).selections.surcharge)
    }

    @Test fun fees_neverReachTheReport_reportCodeDoesNotReadThem() {
        val dir = listOf("src/main/java/com/vims/app/report", "app/src/main/java/com/vims/app/report").map { java.io.File(it) }.first { it.exists() }
        dir.walk().filter { it.isFile && it.extension == "kt" }.forEach { f ->
            val t = f.readText()
            listOf(".surcharge", ".inspectionFee", "Fees.totals").forEach { assertFalse("${f.name} reads $it", it in t) }
        }
    }
}
