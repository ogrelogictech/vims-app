package com.vims.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Client Nov 6 (shared v1.20.0), against the real shared JSON. */
class Nov6MultipleSystemsTest {
    private val config = TestData.config
    private val engine = ChecklistEngine(config, ChecklistEdits())
    private val roomCounts = config.wizard.roomCounts
    private fun rc(key: String) = roomCounts.first { it.key == key }
    private fun base() = engine.defaultSelections("standard").copy(inspType = "Real Estate Sale")
    private fun sections(sel: WizardSelections) = engine.buildGroups(sel).flatMap { it.leaves }
    private fun exteriorOf(sel: WizardSelections) = engine.buildGroups(sel).first { it.heading == "Property Exterior" }.sections
    private fun interiorOf(sel: WizardSelections) = engine.buildGroups(sel).first { it.heading == "Property Interior" }.sections
    private fun utilityOf(sel: WizardSelections) = engine.buildGroups(sel).firstNotNullOf { it.sub?.takeIf { s -> s.heading == "Utility & Function" } }.sections
    private fun many(kitchens: Int = 2, hvac: Int = 3, heaters: Int = 2, panels: Int = 2) =
        base().let { it.copy(counts = it.counts + mapOf("kitchens" to kitchens, "hvacUnits" to hvac, "waterHeaters" to heaters, "electricalPanels" to panels)) }

    /** What an inspection saved by 0.31.0 stores: no new keys. */
    private fun legacy(rooms: List<String> = base().rooms) = base().copy(counts = mapOf("bedrooms" to 4, "bathrooms" to 3, "hallways" to 2), rooms = rooms)

    /* ---------------------------------------------------------------- data shape */

    @Test fun roomCounts_areInTheClientsOrder() {
        assertEquals(listOf("Bedrooms", "Bathrooms", "Hallways", "Kitchen", "HVAC Units", "Water Heaters", "Electrical Panels"), roomCounts.map { it.label })
    }

    @Test fun roomCounts_minAndSync() {
        assertEquals(0, rc("kitchens").min)
        assertEquals("Kitchen", rc("kitchens").syncsRoom)
        // Client Nov 11 (shared v1.23.0): HVAC Units, Water Heaters and Electrical Panels go down to 0 too, see Nov11ZeroSystemsAndCancellationFeeTest.
        listOf("hvacUnits", "waterHeaters", "electricalPanels").forEach { assertEquals(0, rc(it).min) }
        assertNull(rc("bedrooms").min)
    }

    @Test fun roomCounts_lockOnlyTheNewSteppers() {
        assertEquals(listOf("kitchens", "hvacUnits", "waterHeaters", "electricalPanels"), roomCounts.filter { it.locksWithAreas }.map { it.key })
    }

    @Test fun roomCounts_newStopAt12_oldKeepTheirLimit() {
        assertEquals(12, rc("hvacUnits").highest)
        assertEquals(12, rc("kitchens").highest)
        assertEquals(20, rc("bedrooms").highest)
    }

    @Test fun defaults_matchWizardDefaults() {
        val c = base()
        assertEquals(1, c.count("kitchens")); assertEquals(1, c.count("hvacUnits"))
        assertEquals(1, c.count("waterHeaters")); assertEquals(1, c.count("electricalPanels"))
        assertTrue("Kitchen" in c.rooms)
    }

    /* ---------------------------------------------------------------- tokens */

    @Test fun oneOfEach_isTheSameAsBefore_noCoolingSystem() {
        val s = sections(base())
        listOf("Kitchen", "HVAC Mechanical", "Electrical", "Water Heater").forEach { assertTrue(it, it in s) }
        assertFalse(s.any { it.startsWith("Cooling System") })
        assertFalse(s.any { it.matches(Regex("(Kitchen|HVAC Mechanical|Electrical|Water Heater) \\d+")) })
    }

    @Test fun bangToken_firstKeepsPlainName_copiesNextToEachOther() {
        assertEquals(listOf("Utility Room", "HVAC Mechanical", "HVAC Mechanical 2", "HVAC Mechanical 3", "Electrical", "Electrical 2", "Water Heater", "Water Heater 2"),
            utilityOf(many()).take(8))
    }

    @Test fun kitchens_sitInTheirInteriorPlace() {
        val i = interiorOf(many())
        val k = i.indexOf("Kitchen")
        assertEquals("Kitchen 2", i[k + 1])
        assertEquals("Family Room", i[k - 1])
        assertEquals("Dining Room", i[k + 2])
    }

    @Test fun hashToken_copies2toN_rightAfterOutsideUtilities() {
        val e = exteriorOf(many())
        val o = e.indexOf("Outside Utilities")
        assertEquals(listOf("Cooling System #2", "Cooling System #3"), e.subList(o + 1, o + 3))
        assertFalse("Cooling System" in e)
    }

    @Test fun hashToken_oneUnitAddsNothing() {
        assertFalse(exteriorOf(many(hvac = 1)).any { it.startsWith("Cooling") })
    }

    @Test fun kitchenZero_noKitchen() {
        val s = base().withRoomCount(rc("kitchens"), 0)
        assertFalse(sections(s).any { it.startsWith("Kitchen") })
    }

    @Test fun plainToken_stillNumbersFromOne() {
        assertEquals(listOf("Bathroom 1", "Bathroom 2", "Bathroom 3"), interiorOf(base()).filter { it.startsWith("Bathroom") })
    }

    /* ---------------------------------------------------------------- saved inspections */

    @Test fun legacy_missingCountsReadPerRoomCountsAbout() {
        val l = legacy()
        assertEquals(1, l.count("hvacUnits")); assertEquals(1, l.count("waterHeaters")); assertEquals(1, l.count("electricalPanels"))
        assertEquals(1, l.count("kitchens"))
        assertEquals(0, legacy(rooms = legacy().rooms - "Kitchen").count("kitchens"))
    }

    @Test fun legacy_missingReadsOne_butASavedZeroReadsZero_sinceNov11() {
        assertEquals(1, base().copy(counts = emptyMap()).count("hvacUnits"))
        assertEquals(0, base().copy(counts = mapOf("hvacUnits" to 0)).count("hvacUnits"))
    }

    @Test fun legacy_checklistIsIdenticalToWhat031Built() {
        // Literally the 0.31.0 result for the wizard's defaults.
        val expected = listOf("Landscaping", "Roof", "Exterior Walls", "Outside Utilities", "Chimney", "Deck",
            "Garage", "Attic", "Bathroom 1", "Bathroom 2", "Bathroom 3", "Bedroom 1", "Bedroom 2", "Bedroom 3", "Bedroom 4", "Hallway 1", "Hallway 2",
            "Living Room", "Den / Home Office", "Family Room", "Kitchen", "Dining Room", "Laundry Room", "Storage Room",
            "Utility Room", "HVAC Mechanical", "Electrical", "Water Heater", "Plumbing", "Foundation / Crawl Space",
            "Radon", "Thermal Audit", "Termite", "Planned Maintenance Recommendations")
        assertEquals(expected, sections(legacy()))
        assertEquals(sections(base()), sections(legacy()))
    }

    @Test fun legacy_noKitchenChip_noKitchenSection() {
        assertFalse("Kitchen" in sections(legacy(rooms = legacy().rooms - "Kitchen")))
    }

    @Test fun lockedAndFormLayouts_ignoreTheCounts() {
        listOf("Texas", "4 Point Inspection", "Phase 1 Foundation", "Phase 2 Pre-Dry Wall", "Tests Only").forEach { t ->
            val one = sections(base().copy(inspType = t))
            assertEquals(t, one, sections(many(kitchens = 4, hvac = 5, heaters = 3, panels = 3).copy(inspType = t)))
        }
    }

    @Test fun areasLockedTypes_coverOnlyTheExpectedTypes() {
        assertTrue(config.wizard.areasLocked("Phase 1 Foundation"))
        assertFalse(config.wizard.areasLocked("Real Estate Sale"))
    }

    /* ---------------------------------------------------------------- base name, defs, numbering */

    @Test fun baseName_stripsNumberAndHashNumber() {
        assertEquals("Cooling System", baseName("Cooling System #2"))
        assertEquals("Cooling System", baseName("Cooling System #12"))
        assertEquals("Electrical", baseName("Electrical 2"))
        assertEquals("Electrical", baseName("Electrical"))
        assertEquals("Den / Home Office", baseName("Den / Home Office"))
    }

    @Test fun snapshot_copiesShareOneDefinition() {
        val d = engine.snapshot(engine.buildGroups(many()))
        assertNotNull(d["Cooling System"]); assertNotNull(d["Electrical"]); assertNotNull(d["Water Heater"]); assertNotNull(d["HVAC Mechanical"]); assertNotNull(d["Kitchen"])
        assertNull(d["Electrical 2"]); assertNull(d["Cooling System #2"])
    }

    @Test fun copies_haveTheBaseSectionsNumberPhotosAndItems() {
        val d = engine.snapshot(engine.buildGroups(many()))
        assertEquals(11, ChecklistEngine.number(d, "Cooling System #2"))
        assertEquals(ChecklistEngine.number(d, "Electrical"), ChecklistEngine.number(d, "Electrical 2"))
        assertEquals(listOf("Swamp Cooler", "Compressor", "Coolant Lines", "Concerns"), ChecklistEngine.photoCategories(ChecklistEngine.savedDef(d, "Cooling System #2"), "standard"))
        assertEquals(config.section("Cooling System")!!.itemsHigh, ChecklistEngine.savedDef(d, "Cooling System #3")!!.itemsHigh)
    }

    @Test fun sectionTitle_keepsTheHashNumber() {
        assertEquals("Cooling System #2", sectionTitle("Cooling System #2"))
    }

    @Test fun savedCustomSectionEndingInHashNumber_isNotReadAsACopy() {
        val def = SectionDef(name = "Pool #2", number = 99, items = listOf(ItemDef(q = "Condition", type = "single", options = listOf("Good"))))
        val saved = mapOf("Pool #2" to def)
        assertEquals(def, ChecklistEngine.savedDef(saved, "Pool #2"))
        val custom = ChecklistEngine(config, ChecklistEdits(custom = listOf(CustomSection("Exterior", def))))
        assertEquals(def, custom.snapshot(custom.buildGroups(base()))["Pool #2"])
    }

    @Test fun roomNumber_ofAHashCopyIsNotARoomNumber() {
        assertNull(ChecklistEngine.roomNumber("Cooling System #2"))
    }

    /* ---------------------------------------------------------------- report order */

    private fun reportOrder(sel: WizardSelections) = engine.buildGroups(sel).let { g ->
        ChecklistEngine.reportOrder(g.flatMap { it.leaves }, engine.snapshot(g), config, sel.inspType)
    }

    @Test fun report_coolingCopiesFollowOutsideUtilities_copiesKeepChecklistOrder() {
        val r = reportOrder(many())
        val o = r.indexOf("Outside Utilities")
        assertEquals(listOf("Cooling System #2", "Cooling System #3"), r.subList(o + 1, o + 3))
        listOf(listOf("Electrical", "Electrical 2"), listOf("Water Heater", "Water Heater 2"), listOf("HVAC Mechanical", "HVAC Mechanical 2", "HVAC Mechanical 3"), listOf("Kitchen", "Kitchen 2")).forEach { c ->
            assertEquals(c, r.subList(r.indexOf(c[0]), r.indexOf(c[0]) + c.size))
        }
    }

    @Test fun report_copiesGoInCopyOrder_past9() {
        val r = reportOrder(many(hvac = 11, panels = 11)).filter { it.startsWith("Electrical") || it.startsWith("Cooling") || it == "Outside Utilities" }
        assertEquals(listOf("Outside Utilities") + (2..11).map { "Cooling System #$it" } + "Electrical" + (2..11).map { "Electrical $it" }, r)
    }

    /** compareBy(number, name), the sort 0.31.0 used. */
    private fun old031(sections: List<String>, defs: Map<String, SectionDef>) = sections.sortedWith(compareBy<String>({ ChecklistEngine.number(defs, it) }, { it }))

    @Test fun report_anInspectionWithoutCopies_keepsThe031Order() {
        val all = base().let { it.copy(exterior = config.wizard.exteriorOptions, rooms = config.wizard.roomOptions, utilOpt = config.wizard.utilityOptions,
            tests = config.wizard.testOptions, counts = mapOf("bedrooms" to 12, "bathrooms" to 11, "hallways" to 10)) }
        val g = engine.buildGroups(all)
        val leaves = g.flatMap { it.leaves }
        val defs = engine.snapshot(g)
        assertEquals(old031(leaves, defs), ChecklistEngine.reportOrder(leaves, defs, config, all.inspType))
        assertTrue(leaves.containsAll(listOf("Termite", "Asbestos", "Condo", "Pool House & Pool")))
    }

    @Test fun report_numberedRoomsAreNotCopies() {
        assertEquals(0, config.checklistBuilder.copyIndex("Bathroom 2"))
        assertEquals(0, config.checklistBuilder.copyIndex("Electrical"))
        assertEquals(2, config.checklistBuilder.copyIndex("Electrical 2"))
        assertEquals(3, config.checklistBuilder.copyIndex("Cooling System #3"))
    }

    @Test fun data_noOtherSectionSharesACopiedSectionsNumber() {
        // copyIndex relies on this: only Outside Utilities shares a number with a copied section.
        val copied = listOf("Kitchen", "HVAC Mechanical", "Electrical", "Water Heater", "Cooling System")
        copied.forEach { c ->
            val n = config.section(c)!!.number
            assertEquals(c, config.sections.filter { it.number == n && it.name != c }.map { it.name }.filterNot { it == "Outside Utilities" }, emptyList<String>())
        }
    }

    @Test fun findings_copiesStayTogether_nonCopiesKeepTheirTimeOrder() {
        val g = engine.buildGroups(many(panels = 11))
        val defs = engine.snapshot(g)
        fun f(section: String, at: Long) = Finding(id = "$section-$at", cat = 1, text = "x", section = section, createdAt = at)
        val fs = listOf(f("Electrical 10", 1), f("Electrical 2", 2), f("Electrical", 3), f("Cooling System #2", 4), f("Outside Utilities", 5), f("Bathroom 2", 6), f("Bathroom 1", 7), f("Electrical 9", 8))
        assertEquals(listOf("Outside Utilities", "Cooling System #2", "Bathroom 2", "Bathroom 1", "Electrical", "Electrical 2", "Electrical 9", "Electrical 10"),
            fs.sortedWith(ChecklistEngine.findingsOrder(defs, config)).map { it.section })
    }

    @Test fun report_phaseLayoutsKeepTheirOrder() {
        val g = engine.buildGroups(base().copy(inspType = "Phase 2 Pre-Dry Wall"))
        val r = ChecklistEngine.reportOrder(g.flatMap { it.leaves }, engine.snapshot(g), config, "Phase 2 Pre-Dry Wall")
        assertEquals(r.sorted(), r)
    }

    /* ---------------------------------------------------------------- Kitchen chip <-> stepper */

    @Test fun kitchenStepper_zeroTurnsChipOff_aboveZeroOn() {
        val off = base().withRoomCount(rc("kitchens"), 0)
        assertFalse("Kitchen" in off.rooms)
        assertEquals(0, off.count("kitchens"))
        val on = off.withRoomCount(rc("kitchens"), 2)
        assertTrue("Kitchen" in on.rooms)
        assertEquals(2, on.count("kitchens"))
    }

    @Test fun kitchenChip_onSetsOne_offSetsZero() {
        val b = base().withRoomCount(rc("kitchens"), 3)
        val off = b.withRoomToggled("Kitchen", roomCounts)
        assertEquals(0, off.count("kitchens")); assertFalse("Kitchen" in off.rooms)
        val on = off.withRoomToggled("Kitchen", roomCounts)
        assertEquals(1, on.count("kitchens")); assertTrue("Kitchen" in on.rooms)
    }

    @Test fun otherChips_touchNoCount() {
        val b = base()
        assertEquals(b.counts, b.withRoomToggled("Dining Room", roomCounts).counts)
    }

    @Test fun legacyKitchenChipOff_writesZero() {
        assertEquals(0, legacy().withRoomToggled("Kitchen", roomCounts).counts["kitchens"])
    }

    @Test fun steppers_respectMinAndMax() {
        assertEquals(0, base().withRoomCount(rc("hvacUnits"), 0).count("hvacUnits"))
        assertEquals(0, base().withRoomCount(rc("hvacUnits"), -1).count("hvacUnits"))
        assertEquals(12, base().withRoomCount(rc("electricalPanels"), 40).count("electricalPanels"))
    }

    /* ---------------------------------------------------------------- manage checklist */

    @Test fun manageChecklist_listsCoolingSystemAfterOutsideUtilities() {
        val ext = engine.adminGroups.first { it.first == "Exterior" }.second
        assertEquals("Cooling System", ext[ext.indexOf("Outside Utilities") + 1])
    }

    /* ---------------------------------------------------------------- agreement ticks */

    private fun form(i: AgreementFillInput) = AgreementFill.apply(TestData.pieces, TestData.prefill, i).filterIsInstance<AgreementPiece.Form>().single().lines
    private fun line(lines: List<String>, part: String) = lines.first { part in it }

    @Test fun chipOrder_nov10_doesNotMoveTheChecklist() {
        assertEquals("Detached Garage", config.wizard.exteriorOptions.first())
        assertEquals("Attic", config.wizard.roomOptions.first())
        val all = base().copy(exterior = config.wizard.exteriorOptions, rooms = config.wizard.roomOptions)
        assertEquals(config.checklistBuilder.checklistOrder.exterior.filter { it != "Chimney" }, exteriorOf(all).filter { it in config.wizard.exteriorOptions })
        val interior = interiorOf(all)
        assertTrue(interior.indexOf("Garage") < interior.indexOf("Living Room") && interior.indexOf("Kitchen") < interior.indexOf("Dining Room"))
    }

    @Test fun warranty_buildsTheRealEstateSaleChecklist_andTicksItsBox() {
        assertTrue("Warranty" in config.wizard.inspectionTypes)
        assertEquals(sections(base()), sections(base().copy(inspType = "Warranty")))
        val l = form(AgreementFillInput(inspType = "Warranty"))
        assertTrue(line(l, "Warranty").endsWith("Warranty ☒"))
        assertFalse(l.filterNot { "Warranty" in it }.any { '☒' in it })
    }

    @Test fun agreement_hasTexasTestsOnlyLine_afterThePhases() {
        val lines = TestData.agreement.formLines("Acme")
        assertEquals("Texas ☐ Tests Only ☐", lines[lines.indexOfFirst { "Phase 1 Foundation pre-pour" in it } + 1])
    }

    @Test fun texas_ticksItsOwnBoxOnly() {
        val l = form(AgreementFillInput(inspType = "Texas"))
        assertEquals("Texas ☒ Tests Only ☐", line(l, "Tests Only"))
        assertFalse(l.filterNot { "Tests Only" in it }.any { '☒' in it })
    }

    @Test fun testsOnly_ticksItsOwnBoxOnly() {
        val l = form(AgreementFillInput(inspType = "Tests Only"))
        assertEquals("Texas ☐ Tests Only ☒", line(l, "Tests Only"))
        assertFalse(l.filterNot { "Tests Only" in it }.any { '☒' in it })
    }

    @Test fun windMitigationTest_ticksBothBoxes() {
        val l = form(AgreementFillInput(tests = listOf("Wind Mitigation")))
        assertTrue(line(l, "Pre-listing").startsWith("Wind Mitigation ☒"))
        assertTrue("☒ Wind Mitigation Inspection" in line(l, "Boiler System"))
        assertEquals(2, l.sumOf { it.count { c -> c == '☒' } })
    }

    @Test fun windMitigation_afterCanNotTouchTheBeforeBox() {
        assertNull(AgreementFill.tick("☐ Boiler System \$__ ☐ Wind Mitigation Inspection \$__", "Wind Mitigation", "after"))
    }

    @Test fun texas_canOnlyMatchItsOwnBox() {
        assertEquals("Texas ☒ Tests Only ☐", AgreementFill.tick("Texas ☐ Tests Only ☐", "Texas", "after"))
        assertNull(AgreementFill.tick("Texas Real Estate Commission", "Texas", "after"))
        val all = TestData.agreement.formLines("Acme").joinToString("\n")
        assertEquals(1, Regex("Texas\\s*☐").findAll(all).count())
    }

    @Test fun ticks_noOtherType_touchesTheNewLine() {
        val l = form(AgreementFillInput(inspType = "Real Estate Sale"))
        assertEquals("Texas ☐ Tests Only ☐", line(l, "Tests Only"))
    }
}
