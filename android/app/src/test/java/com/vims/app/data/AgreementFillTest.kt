package com.vims.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgreementFillTest {
    private fun sel(
        structure: String = "Single Family", type: String = "Real Estate Sale", tests: List<String> = emptyList(), util: List<String> = emptyList(),
        exterior: List<String> = emptyList(), fields: Map<String, String> = emptyMap(), fees: Map<String, String> = emptyMap(), fee: String = "",
        unitMix: Map<String, Int> = emptyMap(),
    ) = WizardSelections(structure = structure, inspType = type, tests = tests, utilOpt = util, exterior = exterior, fields = fields, fees = fees, inspectionFee = fee, state = "UT", unitMix = unitMix)

    private fun form(s: WizardSelections, locked: Boolean = false): List<String> {
        val i = AgreementFill.input(s, "Jeremy K. Heath", TestData.config.wizard.unitMixDefault, locked)
        return (AgreementFill.apply(TestData.pieces, TestData.prefill, i).first { it is AgreementPiece.Form } as AgreementPiece.Form).lines
    }
    private fun List<String>.line(part: String) = first { part in it }

    @Test fun licenseState_fillsState_neverTheInspectionState() {
        assertTrue(form(sel(fields = mapOf(WizardSelections.F_LICENSE_STATE to "NV", WizardSelections.F_LICENSE to "58983"))).line("Inspectors Name").endsWith("License/Reg # 58983 State NV"))
    }

    @Test fun noLicenseState_leavesStateBlank_evenWithAnInspectionState() {
        val l = form(sel()).line("Inspectors Name")
        assertTrue(l, l.endsWith("State _____"))
        assertFalse(l, " UT" in l)
    }

    @Test fun walkThrough_fillsItsBlank_afterTheInspectionTime() {
        val l = form(sel(fields = mapOf(WizardSelections.F_DATE to "2026-11-04", WizardSelections.F_TIME to "13:30", WizardSelections.F_WALK_THROUGH to "14:00"))).line("Time of walk through")
        assertEquals("Date and Time of Inspection Nov 4, 2026 1:30 PM Time of walk through 2:00 PM", l)
    }

    @Test fun walkThrough_blank_staysABlank() {
        assertTrue(form(sel()).line("Time of walk through").endsWith("Time of walk through ____________"))
    }

    @Test fun feeLines_fillEveryOption_withoutASpaceAfterTheDollar() {
        val options = TestData.config.wizard.utilityOptions + TestData.config.wizard.testOptions
        val fees = options.withIndex().associate { (n, o) -> o to "${n + 1}.5" }
        val f = form(sel(tests = TestData.config.wizard.testOptions, util = TestData.config.wizard.utilityOptions, fees = fees))
        options.withIndex().forEach { (n, o) ->
            val spec = TestData.prefill.lines.single { it.fee == o }
            assertTrue("$o: ${f.line(spec.label)}", "${spec.label}${n + 1}.50" in f.line(spec.label))
        }
        assertFalse(f.joinToString(), "$ " in f.filter { "Testing $" in it || "Chimney $" in it }.joinToString())
    }

    @Test fun totals_fillTheFeeLine_emptyWhenZero() {
        assertEquals("Inspection Fee \$__________ Bundled Services \$__________ Total Amount Due \$__________", form(sel()).line("Inspection Fee $"))
        val l = form(sel(tests = listOf("Radon"), util = listOf("Boiler"), fees = mapOf("Radon" to "150", "Boiler" to "20.25"), fee = "400")).line("Inspection Fee $")
        assertEquals("Inspection Fee $400.00 Bundled Services $170.25 Total Amount Due $570.25", l)
    }

    @Test fun selectedWithAmountZero_isTicked_amountBlank() {
        assertEquals("☒ Radon Testing \$__________ ☐ Indoor Air Quality Testing \$__________", form(sel(tests = listOf("Radon"), fees = mapOf("Radon" to "0"))).line("Radon Testing"))
    }

    @Test fun onlyInspectionFee_bundledStaysBlank() {
        assertEquals("Inspection Fee $400.00 Bundled Services \$__________ Total Amount Due $400.00", form(sel(fee = "400")).line("Inspection Fee $"))
    }

    @Test fun chimney_utility_ticksAndFillsItsFeeLine_notTheComponentLine() {
        val f = form(sel(util = listOf("Chimney"), fees = mapOf("Chimney" to "75")))
        assertEquals(TestData.original("Component Roof"), f.line("Component Roof"))
        assertEquals("☒ Chimney $75.00 ☐ Propane Tank \$__________", f.line("Propane Tank"))
    }

    @Test fun chimneySavedUnderExterior_alsoTicksItsFeeLine() {
        val f = form(sel(exterior = listOf("Chimney", "Deck")))
        assertEquals(TestData.original("Component Roof"), f.line("Component Roof"))
        assertTrue(f.line("Propane Tank").startsWith("☒ Chimney $"))
    }

    @Test fun component_ticksOnlyTheChosenComponents_chimneyBoxNeverTicked() {
        val i = AgreementFill.input(sel(type = "Component", util = listOf("Chimney")).copy(component = listOf("Roof", "HVAC")), "", emptyMap())
        val l = (AgreementFill.apply(TestData.pieces, TestData.prefill, i).first { it is AgreementPiece.Form } as AgreementPiece.Form).lines.line("Component Roof")
        assertEquals("Component Roof ☒ Chimney ☐ Electrical ☐ Plumbing ☐ HVAC ☒", l)
    }

    @Test fun newTickBoxes_eachTicksOnlyItself() {
        val f = form(sel(tests = listOf("Asbestos", "Septic"), util = listOf("Propane Tank", "Chimney")))
        assertEquals("☒ Asbestos Testing \$__________ ☒ Septic System \$__________", f.line("Asbestos Testing"))
        assertEquals("☒ Chimney \$__________ ☒ Propane Tank \$__________", f.line("Propane Tank"))
        assertEquals(TestData.original("Radon Testing"), f.line("Radon Testing"))
    }

    @Test fun lockedType_utilitiesDontTickOrCount_testsStillDo() {
        val s = sel(type = "Phase 1 Foundation", util = listOf("Chimney", "Boiler"), tests = listOf("Radon"), fees = mapOf("Chimney" to "75", "Boiler" to "50", "Radon" to "100"))
        val f = form(s, locked = true)
        assertTrue(f.line("Propane Tank"), f.line("Propane Tank").startsWith("☐ Chimney \$____"))
        assertTrue(f.line("Boiler System"), f.line("Boiler System").startsWith("☐ Boiler System \$____"))
        assertTrue(f.line("Radon Testing"), f.line("Radon Testing").startsWith("☒ Radon Testing $100.00"))
        assertEquals("Inspection Fee \$__________ Bundled Services $100.00 Total Amount Due $100.00", f.line("Inspection Fee $"))
        assertTrue(f.line("Phase 1 Foundation pre-pour ☒"), "Phase 1 Foundation pre-pour ☒" in f.line("Phase 1 Foundation"))
    }

    @Test fun duplex_ticksItsOwnBox_withTwoUnits_notMultiUnit() {
        assertEquals("Single Family ☐ Multi-Unit ☐ # Units 2 Total Sqft __________ Duplex ☒", form(sel(structure = "Duplex")).line("Single Family"))
    }

    @Test fun multiUnit_ticksItsBox_withTheUnitCountAndSqft() {
        val l = form(sel(structure = "Multi-Unit", unitMix = mapOf("Studio" to 2, "2 BR" to 3), fields = mapOf("Total sq ft" to "2400"))).line("Single Family")
        assertEquals("Single Family ☐ Multi-Unit ☒ # Units 5 Total Sqft 2400 Duplex ☐", l)
    }

    @Test fun singleFamily_totalSqft_noUnits() {
        assertEquals("Single Family ☒ Multi-Unit ☐ # Units _____ Total Sqft 1800 Duplex ☐", form(sel(fields = mapOf("Total sq ft" to "1800"))).line("Single Family"))
    }

    @Test fun mobileAndManufactured_eachTickTheirBox() {
        assertEquals("Property Type Mobile Home ☒ Manufactured Home ☐ Town House ☐ Condo ☐", form(sel(structure = "Mobile Home")).line("Property Type"))
        assertEquals("Property Type Mobile Home ☐ Manufactured Home ☒ Town House ☐ Condo ☐", form(sel(structure = "Manufactured Home")).line("Property Type"))
    }

    @Test fun legacyMobileManufactured_ticksNeither() {
        val f = form(sel(structure = WizardSelections.STRUCTURE_LEGACY_MOBILE))
        assertEquals(TestData.original("Property Type"), f.line("Property Type"))
        assertEquals(TestData.original("Single Family"), f.line("Single Family"))
    }

    @Test fun fillBold_coversTheFilledValuesOnly() {
        val i = AgreementFill.input(sel(tests = listOf("Lead"), fees = mapOf("Lead" to "12")), "", emptyMap())
        val form = AgreementFill.apply(TestData.pieces, TestData.prefill, i).first { it is AgreementPiece.Form } as AgreementPiece.Form
        val k = form.lines.indexOfFirst { "Lead Testing" in it }
        assertEquals(listOf("12.00"), form.bold[k]!!.map { form.lines[k].substring(it) })
    }

    @Test fun companyEditedAgreement_withOtherLabels_isFilledWhereItCan_andSkipsTheRest() {
        val pieces = listOf(AgreementPiece.Title("Our agreement"), AgreementPiece.Form(listOf("Clients Name ______", "☐ Radon Testing \$____", "Chimney ☐ only as a component")), AgreementPiece.Para("Plain text"))
        val i = AgreementFill.input(sel(tests = listOf("Radon"), util = listOf("Chimney"), fees = mapOf("Radon" to "10", "Chimney" to "9"), fields = mapOf(WizardSelections.F_CLIENT to "Ann Lee")), "", emptyMap())
        val form = AgreementFill.apply(pieces, TestData.prefill, i).first { it is AgreementPiece.Form } as AgreementPiece.Form
        assertEquals(listOf("Clients Name Ann Lee", "☒ Radon Testing $10.00", "Chimney ☐ only as a component"), form.lines)
    }

    @Test fun companyEditedBlocks_getTheCurrentFormBlock_andItFills() {
        val blocks = listOf(AgreementDocBlock("title", "Our agreement"), AgreementDocBlock("p", "Our words."))
        val pieces = AgreementBlocks.pieces(blocks, TestData.agreement.formLines("Acme"))
        val i = AgreementFill.input(sel(structure = "Duplex"), "", emptyMap())
        val form = AgreementFill.apply(pieces, TestData.prefill, i).first { it is AgreementPiece.Form } as AgreementPiece.Form
        assertTrue("Duplex ☒" in form.lines.line("Single Family"))
    }

    @Test fun oldPlainTextEdit_holdingTheOlderFormBlock_doesntShowItTwice() {
        // A plain-text edit from before the form was locked, holding the block as it read before the Duplex / Asbestos / Chimney lines.
        val older = TestData.agreement.formLines("Acme").filterNot { "Asbestos" in it || "Propane" in it }.map { it.replace(" Duplex ☐", "") }
        val stored = "Our agreement\n\n" + older.joinToString("\n") + "\n\nOur words."
        val pieces = AgreementText.pieces(stored, TestData.agreement.formLines("Acme"))
        assertEquals(1, pieces.count { it is AgreementPiece.Form })
        assertFalse(pieces.filterIsInstance<AgreementPiece.Para>().any { "Radon" in it.text })
    }

    @Test fun spec_everyHeaderLabelAndBox_isInTheAgreement_andFeeLabelsAreSingleUse() {
        val lines = TestData.agreement.formLines("Acme")
        TestData.prefill.lines.filter { it.part == "header" }.forEach { s -> assertTrue(s.label, lines.any { s.label in it }) }
        TestData.prefill.lines.filter { it.label.endsWith("$") }.forEach { s -> assertEquals(s.label, 1, lines.count { s.label in it }) }
        val c = TestData.prefill.checkboxes
        (c.propertyType + c.tests + c.utilities).forEach { b ->
            val hits = lines.count { l -> if (b.side == "before") "☐ ${b.box}" in l else "${b.box} ☐" in l }
            assertEquals(b.box, 1, hits)
        }
    }

    @Test fun boxes_gluedKeepTheBoxWithItsLabel_sameLength() {
        val after = "Mobile Home ☐ Town House ☐"
        assertEquals("Mobile Home ☐ Town House ☐", AgreementBoxes.glued(after))
        val before = "☐ Radon Testing \$__ ☐ Lead Testing \$__"
        assertEquals("☐ Radon Testing \$__ ☐ Lead Testing \$__", AgreementBoxes.glued(before))
        assertEquals(after.length, AgreementBoxes.glued(after).length)
        assertNotEquals(' ', AgreementBoxes.glued("NO Report to Real Estate Agent. ☐")[31])
    }
}
