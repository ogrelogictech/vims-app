#if DEBUG
import Foundation
import UIKit

// DEBUG only. Client Nov 4 (shared v1.19) checks:
//   -nov5Wizard [-nov5Struct S]    with -screen wizard: fill the new-inspection draft with the sample values and every amount
//   -nov5Agreement [-nov5Struct S] create (once) that inspection and use it as the chosen one
//   -nov5Status                    print NOV5TEST lines: Chimney position on every saved inspection and on rebuilt copies, the
//                                  fee rules, the agreement fill, an edited agreement with labels missing, the box glyphs
//   -nov5WritePDF                  write the chosen inspection's filled agreement to Documents/nov5-agreement.pdf
extension DebugLaunch {
    static let nov5Amounts: [String: String] = [
        "Chimney": "150", "Heating Oil Tank": "75.5", "Propane Tank": "60", "Boiler": "140",
        "Radon": "175.50", "Indoor Air Quality": "225", "Lead": "95.25", "Asbestos": "300", "Meth Test": "120",
        "Thermal Audit": "200", "Sewer Scope": "180", "Wind Mitigation": "125", "Septic": "350", "Termite": "85"
    ]

    static func nov5Values(_ d: inout Inspection, config: ChecklistConfig) {
        d.fields["Client name"] = "Morgan Ellis"
        d.fields["Client phone"] = "(801) 555-0142"
        d.fields["Client email"] = "morgan.ellis@example.com"
        d.fields["Inspection address"] = "418 Cedar Ln"
        d.fields["City"] = "Ogden"
        d.fields["ZIP code"] = "84403"
        d.setState("UT", config: config)
        d.fields["Real estate agent name"] = "Kim Lopez"
        d.fields["Real estate agent email"] = "kim.lopez@example.com"
        d.fields[Inspection.licenseField] = "58983"
        d.fields[Inspection.licenseStateField] = "ID"     // on purpose not the inspection's state
        d.fields["Date"] = "2026-11-05"
        d.fields["Time"] = "13:30"
        d.fields[Inspection.walkThroughField] = "14:15"
        d.inspType = "Real Estate Sale"
        d.structure = value("-nov5Struct") ?? "Multi-Unit"
        if d.structure == "Multi-Unit" { d.unitMix = config.wizard.unitMixDefault }
        if let ext = config.wizard.structureSideEffects[d.structure]?["exterior"], !d.exterior.contains(ext) { d.exterior.append(ext) }
        d.fields["Total sq ft"] = "2,400"
        d.utilities = config.wizard.utilityOptions
        d.tests = config.wizard.testOptions
        d.fees = InspectionFees(amounts: nov5Amounts, inspectionFee: "495")
    }

    @MainActor
    static func nov5Seed(_ store: AppStore, _ id: UUID) -> UUID {
        guard has("-nov5Agreement") else { return id }
        let structure = value("-nov5Struct") ?? "Multi-Unit"
        if let found = store.inspections.first(where: { $0.clientName == "Morgan Ellis" && $0.structure == structure }) { return found.id }
        var d = store.newInspectionDraft()
        nov5Values(&d, config: store.config)
        return store.buildChecklist(from: d)
    }

    @MainActor
    static func nov5Status(_ store: AppStore, _ id: UUID) {
        if has("-nov5WritePDF"), let insp = store.inspection(id), let base = store.editedAgreementContent ?? InspectionAgreement.bundled.map({
            AgreementContent.vims($0, company: store.company.name, stateCode: insp.state, stateName: { store.config.stateName($0) ?? $0 })
        }), let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let filled = store.agreementFill(insp).apply(to: base)
            try? AgreementPDF.render(filled, company: store.company.name).pdf.write(to: docs.appendingPathComponent("nov5-agreement.pdf"))
            print("NOV5TEST wrote nov5-agreement.pdf for \(insp.addressLine1)")
        }
        guard has("-nov5Status") else { return }
        let w = store.config.wizard
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print("NOV5TEST \(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " | \(detail)")")
        }

        // Spec lists as the wizard reads them.
        print("NOV5TEST steps=\(w.steps) structures=\(w.structureTypes) exterior=\(w.exteriorOptions) utilities=\(w.utilityOptions) tests=\(w.testOptions)")
        print("NOV5TEST company license=\(store.company.license) licenseState=\(store.company.licenseState ?? "nil")")

        // Chimney on every saved inspection: stored checklist against a rebuild, no duplicates, selected under Utility.
        for i in store.inspections {
            let cat = store.catalog(for: i)
            let rebuilt = cat.buildGroups(for: i)
            let ext = { (g: [ChecklistGroup]) in g.first { $0.heading == "Property Exterior" }?.sections ?? [] }
            let leaves = i.leafSections
            let dup = Set(leaves).count != leaves.count
            let same = rebuilt.map(\.leafSections) == i.groups.map(\.leafSections)
            print("NOV5TEST saved \(i.addressLine1) type=\(i.inspType) structure=\(i.structure) chip=\(i.wizardStructure) exteriorHasChimney=\(i.exterior.contains("Chimney")) utilities=\(i.utilities) selectedUtilities=\(i.selectedUtilities) fees=\(i.fees == nil ? "nil" : "set") licenseState=\(i.licenseState) walk=\(i.walkThroughTime)")
            print("NOV5TEST   exteriorGroup=\(ext(i.groups)) chimneyCount=\(leaves.filter { $0 == "Chimney" }.count) duplicates=\(dup) rebuildSameAsStored=\(same)")
            if !same { print("NOV5TEST   stored=\(i.groups.map(\.leafSections)) rebuilt=\(rebuilt.map(\.leafSections))") }
        }

        // The same inspection with Chimney saved under exterior (before) and under utilities (after): same checklist.
        var after = store.newInspectionDraft()
        after.inspType = "Real Estate Sale"
        after.utilities = ["Chimney", "Boiler", "Propane Tank"]
        after.tests = ["Termite", "Radon", "Asbestos", "Meth Test"]
        var before = after
        before.utilities = ["Boiler", "Propane Tank"]
        before.exterior = ["Chimney"] + before.exterior
        var both = after
        both.exterior = ["Chimney"] + both.exterior
        var none = after
        none.setUtility("Chimney", selected: false)
        let cat = store.catalog
        let a = cat.buildGroups(for: after), b = cat.buildGroups(for: before), c = cat.buildGroups(for: both)
        check("chimney same checklist saved under exterior / utilities / both", a == b && a == c, "\(a.first { $0.heading == "Property Exterior" }?.sections ?? [])")
        check("chimney once", a.flatMap(\.leafSections).filter { $0 == "Chimney" }.count == 1)
        check("chimney under Property Exterior after the always sections",
              a.first { $0.heading == "Property Exterior" }?.sections.prefix(5).last == "Chimney")
        check("chimney not in Utility & Function", !(a.flatMap { $0.sub?.sections ?? [] }.contains("Chimney")))
        check("utility sections keep checklist order", a.flatMap { $0.sub?.sections ?? [] }.filter { ["Boiler", "Propane Tank", "Heating Oil Tank"].contains($0) } == ["Boiler", "Propane Tank"])
        check("test sections keep checklist order", a.first { $0.heading == "Testing" }?.sections == ["Radon", "Meth Test", "Termite", "Asbestos"], "\(a.first { $0.heading == "Testing" }?.sections ?? [])")
        var allOn = after
        allOn.utilities = w.utilityOptions
        allOn.tests = w.testOptions
        allOn.exterior = w.exteriorOptions
        let allGroups = cat.buildGroups(for: allOn)
        let order = store.config.checklistBuilder.checklistOrder
        print("NOV5TEST all-on exterior=\(allGroups.first { $0.heading == "Property Exterior" }?.sections ?? []) utilityFunction=\(allGroups.compactMap { $0.sub?.sections }.flatMap { $0 }) testing=\(allGroups.first { $0.heading == "Testing" }?.sections ?? [])")
        check("Chimney first under the exterior optional sections", allGroups.first { $0.heading == "Property Exterior" }?.sections == ["Landscaping", "Roof", "Exterior Walls", "Outside Utilities"] + order.exterior)
        check("Utility & Function optional sections Boiler, Heating Oil Tank, Propane Tank", allGroups.compactMap { $0.sub?.sections }.flatMap { $0 } == ["Utility Room", "HVAC Mechanical", "Electrical", "Water Heater", "Boiler", "Heating Oil Tank", "Propane Tank", "Plumbing", "Foundation / Crawl Space"])
        check("Testing in checklistOrder.tests", allGroups.first { $0.heading == "Testing" }?.sections == order.tests)
        var testsOnly = allOn
        testsOnly.inspType = "Tests Only"
        check("Tests Only testing in checklistOrder.tests", cat.buildGroups(for: testsOnly).first { $0.heading == "Testing" }?.sections == order.tests)
        check("wizard chip orders differ from the checklist's on purpose", w.testOptions != order.tests && w.utilityOptions != order.utility)
        let reportNames = cat.sortedForReport(allGroups.flatMap(\.leafSections).filter { order.exterior.contains($0) || order.utility.contains($0) || order.tests.contains($0) })
        print("NOV5TEST report order=\(reportNames)")
        check("chimney deselected nowhere", !cat.buildGroups(for: none).flatMap(\.leafSections).contains("Chimney"))
        var cleared = before
        cleared.setUtility("Chimney", selected: false)
        check("saved chimney clears from exterior", !cleared.hasChimney && !cat.buildGroups(for: cleared).flatMap(\.leafSections).contains("Chimney"))
        var lockedChimney = after
        lockedChimney.inspType = "Phase 1 Foundation"
        check("locked type adds no chimney", !cat.buildGroups(for: lockedChimney).flatMap(\.leafSections).contains("Chimney"))
        var fresh = store.newInspectionDraft()
        fresh.inspType = "Real Estate Sale"
        check("new draft: chimney on by default under utilities, not exterior", fresh.utilities.contains("Chimney") && !fresh.exterior.contains("Chimney"))
        check("new draft: walk-through empty, not auto-filled", fresh.fields[Inspection.walkThroughField] == nil)
        check("new draft: license state from company", fresh.licenseState == (store.company.licenseState ?? ""))
        check("new draft: no fees", fresh.fees == nil)

        // Fee rules.
        var f = fresh
        f.tests = []
        f.setFeeAmount("0", for: "Radon", in: .test)
        check("typing 0 doesn't select", !f.tests.contains("Radon"))
        f.setFeeAmount("0.10", for: "Radon", in: .test)
        check("typing above 0 selects", f.tests.contains("Radon"))
        f.setFeeAmount("0.20", for: "Lead", in: .test)
        check("exact cents: 0.10 + 0.20", InspectionFees.text(f.bundledFees(wizard: w)) == "0.30", InspectionFees.text(f.bundledFees(wizard: w)))
        f.setFeeOption("Radon", in: .test, selected: false)
        check("deselect clears the amount", f.fees?.amounts["Radon"] == nil && !f.tests.contains("Radon"))
        f.setFeeAmount("", for: "Lead", in: .test)
        check("clearing the box leaves the chip", f.tests.contains("Lead"))
        check("nothing typed leaves no fees", f.fees == nil)
        f.setFeeAmount("99,999.99", for: "Lead", in: .test)
        f.setFeeAmount("12.5", for: "Chimney", in: .utility)
        f.setInspectionFee("1,000.05")
        check("bundled = utilities + testing", InspectionFees.text(f.bundledFees(wizard: w)) == "100,012.49", InspectionFees.text(f.bundledFees(wizard: w)))
        check("total = fee + bundled", InspectionFees.text(f.totalFees(wizard: w)) == "101,012.54", InspectionFees.text(f.totalFees(wizard: w)))
        var locked = f
        locked.inspType = "4 Point Inspection"
        check("locked utility amount not counted, kept", InspectionFees.text(locked.bundledFees(wizard: w)) == "99,999.99" && locked.fees?.amounts["Chimney"] == "12.5")
        locked.inspType = "Real Estate Sale"
        check("unlocked again counts", InspectionFees.text(locked.bundledFees(wizard: w)) == "100,012.49")
        check("filter limits", FieldKind.number(InspectionFees.limits).filter("1234567.891") == "12,345.89", FieldKind.number(InspectionFees.limits).filter("1234567.891"))
        check("lone dot dropped", InspectionFees(amounts: ["Radon": "."], inspectionFee: ".").normalized() == nil)
        let round = (try? JSONDecoder().decode(Inspection.self, from: JSONEncoder().encode(f)))?.fees
        check("fees round trip", round == f.fees)
        let oldJSON = (try? JSONEncoder().encode(fresh)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check("no fees key when nil", !oldJSON.contains("\"fees\""))

        // Agreement fill.
        guard let doc = InspectionAgreement.bundled else { check("agreement bundled", false); return }
        let base = AgreementContent.vims(doc, company: store.company.name, stateCode: "UT", stateName: { store.config.stateName($0) ?? $0 })
        let plainForm = { (c: AgreementContent) in c.formLines.map(AgreementFill.plain) }
        func filled(_ make: (inout Inspection) -> Void) -> [String] {
            var d = store.newInspectionDraft()
            nov5Values(&d, config: store.config)
            make(&d)
            return plainForm(store.agreementFill(d).apply(to: base))
        }
        func line(_ form: [String], _ prefix: String) -> String { form.first { $0.contains(prefix) } ?? "" }
        let all = filled { _ in }
        for l in all where l.contains("$") || l.contains("License/Reg") || l.contains("walk through") || l.contains("Units") || l.contains("Property Type") || l.contains("Component") {
            print("NOV5TEST line: \(l)")
        }
        let tick = "\u{2612}", empty = "\u{2610}"
        check("license state, not inspection state", line(all, "License/Reg").contains("State ID") && !line(all, "License/Reg").contains("State UT"), line(all, "License/Reg"))
        check("blank license state stays blank", line(filled { $0.fields[Inspection.licenseStateField] = nil }, "License/Reg").hasSuffix("State _____"))
        check("walk-through filled", line(all, "walk through").hasSuffix("Time of walk through 2:15 PM"), line(all, "walk through"))
        check("no walk-through keeps the blank", line(filled { $0.fields[Inspection.walkThroughField] = nil }, "walk through").contains("walk through ____"))
        let expected = ["Radon Testing $ 175.50", "Indoor Air Quality Testing $ 225.00", "Lead Testing $ 95.25", "Thermal Energy Efficiency $ 200.00",
                        "Meth Testing $ 120.00", "Termite/Pest Inspection $ 85.00", "Sewer Scope $ 180.00", "Heating Oil Tank $ 75.50", "Boiler System $ 140.00",
                        "Wind Mitigation Inspection $ 125.00", "Asbestos Testing $ 300.00", "Septic System $ 350.00", "Chimney $ 150.00", "Propane Tank $ 60.00",
                        "Inspection Fee $ 495.00", "Bundled Services $ 2,281.25", "Total Amount Due $ 2,776.25"]
        for e in expected { check("fee line \(e)", all.contains { $0.contains(e) }) }
        let services = all.filter { $0.hasPrefix(tick) || $0.hasPrefix(empty) }
        check("every service box ticked", services.count == 7 && !services.joined().contains(empty), "\(services.count) lines")
        let component = line(all, "Component Roof")
        check("Component Chimney untouched by the utility", component == "Component Roof \(empty) Chimney \(empty) Electrical \(empty) Plumbing \(empty) HVAC \(empty)", component)
        // Chimney isn't a Component option (componentOptions: Roof, HVAC, Electrical, Plumbing), so nothing ticks that box.
        let compAns = filled { $0.inspType = "Component"; $0.components = ["Roof"] }
        check("Component type: Roof ticked, its Chimney box not, the Chimney $ box is", line(compAns, "Component Roof").hasPrefix("Component Roof \(tick) Chimney \(empty)") && line(compAns, "Propane Tank").hasPrefix("\(tick) Chimney $ 150.00"), line(compAns, "Component Roof"))
        let unticked = filled { $0.utilities = []; $0.tests = []; $0.fees = InspectionFees(amounts: nov5Amounts, inspectionFee: nil) }
        check("amount on an unselected option prints nothing", !unticked.joined().contains("175.50"))
        check("zero fees keep their blanks", line(filled { $0.utilities = []; $0.tests = []; $0.fees = InspectionFees(amounts: [:], inspectionFee: "0") }, "Inspection Fee").hasPrefix("Inspection Fee $__________ Bundled Services $__________ Total Amount Due $__________"))
        let zero = filled { $0.utilities = ["Boiler"]; $0.tests = []; $0.fees = InspectionFees(amounts: ["Boiler": "0"], inspectionFee: nil) }
        check("selected option at 0: ticked, amount blank", line(zero, "Boiler System").hasPrefix("\(tick) Boiler System $____"), line(zero, "Boiler System"))
        let phase1 = filled { $0.inspType = "Phase 1 Foundation"; $0.utilities = ["Chimney"]; $0.fees = nil }
        check("default Chimney doesn't tick on a Phase 1 Foundation agreement", line(phase1, "Propane Tank").hasPrefix("\(empty) Chimney $____"), line(phase1, "Propane Tank"))
        let lockedFill = filled { $0.inspType = "4 Point Inspection" }
        check("locked type: utility boxes and amounts stay empty", line(lockedFill, "Propane Tank").hasPrefix("\(empty) Chimney $____") && line(lockedFill, "Propane Tank").contains("\(empty) Propane Tank $____"), line(lockedFill, "Propane Tank"))
        check("locked type: bundled leaves utilities out", line(lockedFill, "Bundled").contains("Bundled Services $ 1,855.75"), line(lockedFill, "Bundled"))
        for (s, box, units) in [("Duplex", "Duplex", "2"), ("Mobile Home", "Mobile Home", ""), ("Manufactured Home", "Manufactured Home", ""), ("Single Family", "Single Family", ""),
                                ("Townhouse", "Town House", ""), ("Condo", "Condo", ""), ("Multi-Unit", "Multi-Unit", "8"), (Inspection.legacyMobileStructure, "", "")] {
            let form = filled { $0.structure = s; $0.unitMix = s == "Multi-Unit" ? w.unitMixDefault : [:] }
            let lines = line(form, "Property Type") + " " + line(form, "Single Family")
            let ticks = lines.filter { String($0) == tick }.count
            check("property \(s)", (box.isEmpty ? ticks == 0 : ticks == 1 && lines.contains("\(box) \(tick)")) && (units.isEmpty ? lines.contains("# Units _____") : lines.contains("# Units \(units)")) && lines.contains("Total Sqft 2,400"), lines)
        }
        var chimneyExt = store.newInspectionDraft()
        nov5Values(&chimneyExt, config: store.config)
        chimneyExt.utilities = []; chimneyExt.exterior = ["Chimney"]; chimneyExt.fees = nil
        check("saved exterior Chimney ticks the Chimney $ box", line(plainForm(store.agreementFill(chimneyExt).apply(to: base)), "Propane Tank").hasPrefix("\(tick) Chimney $"))

        // A company's edited agreement: the current form is locked in; older or edited text with labels gone is skipped.
        var sample = store.newInspectionDraft()
        nov5Values(&sample, config: store.config)
        let fill = store.agreementFill(sample)
        let edited = AgreementContent.edited(EditedAgreement(blocks: base.blocks).encoded, company: store.company.name, form: store.agreementFormLines)
        check("edited agreement fills the same", fill.apply(to: edited).formLines == fill.apply(to: base).formLines)
        let oldForm = doc.formLines.filter { !$0.contains("Asbestos") && !$0.contains("Propane") }.map { $0.replacingOccurrences(of: " Duplex \u{2610}", with: "") }
            .map { $0.hasPrefix("Inspection Fee") ? "Fee total only" : $0.replacingOccurrences(of: "Radon Testing $", with: "Radon Testing") }
        let stale = fill.apply(to: AgreementContent(blocks: [.title("T"), .form(oldForm), .paragraph("Body", lead: false)]))
        check("labels gone are skipped", stale.formLines.count == oldForm.count && !stale.formLines.joined().contains("350.00") && !stale.formLines.joined().contains("495.00"))
        let radon = stale.formLines.map(AgreementFill.plain).first { $0.contains("Radon") } ?? ""
        check("a fee label without its $ doesn't fill the next blank", radon.contains("Indoor Air Quality Testing $ 225.00") && !radon.contains("175.50"), radon)
        check("a $ label that lost its blank fills nothing", AgreementFill.fillLine("Chimney $ Propane Tank $____", label: "Chimney $", value: "9") == nil)
        check("Chimney $ never matches the Component line", AgreementFill.fillLine("Component Roof \(empty) Chimney \(empty)", label: "Chimney $", value: "9") == nil
              && AgreementFill.tickBox("Component Roof \(empty) Chimney \(empty)", box: "Chimney $", side: "before") == nil)
        check("Component Chimney never matches the fee line", AgreementFill.tickBox("\(empty) Chimney $____ \(empty) Propane Tank $____", box: "Chimney", side: "after") == nil)
        check("blank fill leaves the agreement unchanged", AgreementFill().apply(to: base) == base)
        let legacyText = base.plainText
        let legacy = AgreementContent.edited(legacyText, company: store.company.name, form: store.agreementFormLines)
        check("plain-text edit keeps one form block", legacy.blocks.filter { if case .form = $0 { return true } else { return false } }.count == 1)
        print("NOV5TEST boxFont mono8.6=\(BoxGlyphFont.font(for: VFont.uMono(8.6)).fontName) mono11.5=\(BoxGlyphFont.font(for: VFont.uMono(11.5)).fontName)")
        print("NOV5TEST done failures=\(failures)")
    }
}
#endif
