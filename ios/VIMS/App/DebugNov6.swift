#if DEBUG
import Foundation
import UIKit

// DEBUG only. Client Nov 6 (shared v1.20) checks:
//   -nov6Wizard                    with -screen wizard: the -nov5Wizard sample with one Chimney, Radon and Wind Mitigation
//   -nov6Agreement TYPE            create (once) a TYPE inspection with the Wind Mitigation test and use it as the chosen one
//   -nov6Fill                      the chosen inspection: every section answered, a comment, a photo and a finding of its own, done
//   -nov6Status                    print NOV6TEST lines: base names, the builder tokens, saved inspections, sort order, chip / stepper
//                                  sync, Manage checklist, agreement boxes, and how each copy of the chosen inspection is stored
extension DebugLaunch {
    static func nov6Values(_ d: inout Inspection) {
        d.structure = "Single Family"
        d.unitMix = [:]
        d.utilities = ["Chimney"]
        d.tests = ["Radon", "Wind Mitigation"]
        d.fees = InspectionFees(amounts: ["Chimney": "150", "Radon": "175.50", "Wind Mitigation": "125"], inspectionFee: "495")
    }

    @MainActor
    static func nov6Seed(_ store: AppStore, _ id: UUID) -> UUID {
        guard let type = value("-nov6Agreement") else { return id }
        if let found = store.inspections.first(where: { $0.clientName == "Morgan Ellis" && $0.inspType == type }) { return found.id }
        var d = store.newInspectionDraft()
        nov5Values(&d, config: store.config)
        nov6Values(&d)
        d.inspType = type
        return store.buildChecklist(from: d)
    }

    private static func sample(_ text: String) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).image { c in
            UIColor.systemTeal.setFill()
            c.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            (text as NSString).draw(at: CGPoint(x: 30, y: 200), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 44), .foregroundColor: UIColor.black])
        }
    }

    /// Sections already answered through the UI keep their answers.
    @MainActor
    static func nov6Fill(_ store: AppStore, _ id: UUID) {
        guard has("-nov6Fill"), let insp = store.inspection(id) else { return }
        let cat = store.catalog(for: insp)
        for s in insp.leafSections where !cat.isNotes(s) && !cat.isPhotosOnly(s) {
            var a = insp.answers[s] ?? store.defaultAnswers(s, catalog: cat)
            for k in ItemKeys.keyed(cat.items(s, depth: cat.isForm(s) ? .standard : insp.depth).items) where !k.item.isHeader {
                switch k.item.kind {
                case .single, .multi: if a.choices[k.id] == nil, let o = k.item.options?.first { a.choices[k.id] = [o] }
                case .text: if a.text[k.id] == nil { a.text[k.id] = "Note in \(s)" }
                default: break
                }
            }
            if a.comments.isEmpty { a.comments = "Comment for \(s)." }
            store.setAnswers(id, s, a)
            store.update(id) { $0.status[s] = .done }
            if store.inspection(id)?.photos[s] == nil, let c = cat.photoCategories(s, depth: insp.depth).first {
                _ = store.addPhoto(id, section: s, category: c, image: sample(s))
            }
            if !(store.inspection(id)?.findings.contains { $0.section == s } ?? true) {
                store.addFinding(id, category: 2, custom: "Finding in \(s)", section: s)
            }
        }
        store.flushNow()
    }

    @MainActor
    static func nov6Status(_ store: AppStore, _ id: UUID) {
        guard has("-nov6Status") else { return }
        let cfg = store.config, w = cfg.wizard, cat = store.catalog
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print("NOV6TEST \(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " | \(detail)")")
        }
        func rc(_ key: String) -> RoomCountDef { w.roomCounts.first { $0.key == key }! }
        func draft(_ type: String = "Real Estate Sale", counts: [String: Int] = [:]) -> Inspection {
            var d = store.newInspectionDraft()
            d.inspType = type
            for (k, v) in counts { d.counts[k] = v }
            return d
        }
        func leaves(_ d: Inspection) -> [String] { cat.buildGroups(for: d).flatMap(\.leafSections) }
        func followed(_ list: [String], _ a: [String]) -> Bool {
            guard let i = list.firstIndex(of: a[0]), i + a.count <= list.count else { return false }
            return Array(list[i..<(i + a.count)]) == a
        }
        let four = ["hvacUnits", "waterHeaters", "electricalPanels", "kitchens"]

        print("NOV6TEST data=\(cfg.version) counts=\(w.roomCounts.map { "\($0.label):\($0.range.lowerBound)-\($0.range.upperBound)" })")

        // Base-name rule.
        for (n, b) in [("Bathroom 2", "Bathroom"), ("Bedroom 10", "Bedroom"), ("Cooling System #2", "Cooling System"), ("Cooling System #12", "Cooling System"),
                       ("Electrical 2", "Electrical"), ("Electrical", "Electrical"), ("HVAC Mechanical 3", "HVAC Mechanical")] {
            check("base \(n)", ChecklistCatalog.baseName(n) == b, ChecklistCatalog.baseName(n))
        }

        // The tokens.
        let one = leaves(draft())
        var saved = draft()            // an inspection saved before the new keys
        for k in four { saved.counts[k] = nil }
        check("saved without the new keys builds the same as a new draft at the defaults", leaves(saved) == one, "\(one)")
        check("one of each: no copies, no Cooling System", !one.contains { $0.contains("Cooling") || $0.hasSuffix(" 2") && !$0.hasPrefix("Bathroom") && !$0.hasPrefix("Bedroom") && !$0.hasPrefix("Hallway") })
        for k in four where k != "kitchens" { check("missing \(k) reads 1", saved.roomCount(rc(k)) == 1) }
        check("missing kitchens with the chip reads 1", saved.roomCount(rc("kitchens")) == 1)
        var noKitchen = saved
        noKitchen.rooms.removeAll { $0 == "Kitchen" }
        check("missing kitchens without the chip reads 0, no Kitchen", noKitchen.roomCount(rc("kitchens")) == 0 && !leaves(noKitchen).contains("Kitchen"))
        for k in four where k != "kitchens" {
            var zero = saved
            zero.counts[k] = 0
            check("stored 0 for \(k) still reads 1", zero.roomCount(rc(k)) == 1)
        }
        let many = leaves(draft(counts: ["hvacUnits": 3, "waterHeaters": 2, "electricalPanels": 2, "kitchens": 2]))
        print("NOV6TEST many=\(many)")
        check("Cooling System #2, #3 right after Outside Utilities", followed(many, ["Outside Utilities", "Cooling System #2", "Cooling System #3"]))
        check("plain Cooling System never listed", !many.contains("Cooling System"))
        check("HVAC copies together", followed(many, ["HVAC Mechanical", "HVAC Mechanical 2", "HVAC Mechanical 3"]))
        check("Electrical copies together", followed(many, ["Electrical", "Electrical 2"]))
        check("Water Heater copies together", followed(many, ["Water Heater", "Water Heater 2"]))
        check("Kitchen copies together", followed(many, ["Kitchen", "Kitchen 2"]))
        check("no duplicates", Set(many).count == many.count)
        check("copies at 12", leaves(draft(counts: ["electricalPanels": 12])).filter { ChecklistCatalog.baseName($0) == "Electrical" }.count == 12)

        // Standard layout only.
        for t in ["Texas", "4 Point Inspection", "Phase 1 Foundation", "Phase 2 Pre-Dry Wall", "Tests Only"] {
            var kept = draft(t)
            for k in four { kept.counts[k] = nil }
            check("\(t): counts change nothing", leaves(draft(t, counts: ["hvacUnits": 3, "waterHeaters": 2, "electricalPanels": 2, "kitchens": 2])) == leaves(kept), "\(leaves(kept).count) sections")
        }
        check("locked types are the disabled ones", w.areasLockedTypes == ["Phase 1 Foundation", "Phase 2 Pre-Dry Wall", "Tests Only", "4 Point Inspection"])
        check("only the new counts lock", w.roomCounts.filter(\.locksWithAreas).map(\.key) == ["kitchens", "hvacUnits", "waterHeaters", "electricalPanels"])

        // Everything that reads through the base name.
        let oc = cat.section("Outside Utilities"), cool = cat.section("Cooling System")
        check("Cooling System #2 is the Cooling System section", cat.section("Cooling System #2") == cool && cool != nil)
        check("Cooling System number 11", cat.number("Cooling System #2") == 11 && oc?.number == 11)
        check("titles", cat.title("Cooling System #2") == "Cooling System #2" && cat.title("Electrical 2") == "Electrical 2" && cat.title("Kitchen") == "Kitchen", cat.title("Cooling System #2"))
        check("Cooling System #2 photo categories", cat.photoCategories("Cooling System #2", depth: .standard) == ["Swamp Cooler", "Compressor", "Coolant Lines", "Concerns"])
        check("High photo categories", cat.photoCategories("Cooling System #3", depth: .high) == cool?.photoCategoriesHigh)
        check("Water Heater 2 photos like Water Heater", cat.photoCategories("Water Heater 2", depth: .high) == cat.photoCategories("Water Heater", depth: .high))
        check("copies' numbers", cat.number("Electrical 2") == cat.number("Electrical") && cat.number("Kitchen 2") == 23 && cat.number("HVAC Mechanical 3") == 28)
        check("no room-number pre-answers on a '#' copy", cat.roomNumberDefaults("Cooling System #2", depth: .high).isEmpty)
        check("not forms or notes", !cat.isForm("Cooling System #2") && !cat.isNotes("Electrical 2") && cat.formReport("Water Heater 2") == nil)
        check("items same at High", cat.items("Cooling System #2", depth: .high).items == cool?.itemsHigh && cat.items("Cooling System #2", depth: .high).usingHigh)
        var edit = ChecklistOverrides()
        var edited = cool!
        edited.items.append(ItemDef.question("Added by the admin", options: ["Yes", "No"]))
        edit.sections["Cooling System"] = edited
        let editedCat = ChecklistCatalog(config: cfg, overrides: edit)
        check("a Manage checklist edit reaches Cooling System #2", editedCat.items("Cooling System #2", depth: .standard).items.contains { $0.q == "Added by the admin" })

        // A custom section that happens to be named like a copy is listed once.
        var custom = ChecklistOverrides()
        custom.custom["Utility"] = ["Electrical 2"]
        custom.sections["Electrical 2"] = SectionDef(name: "Electrical 2", number: 99, icon: nil, photoCategories: [], items: [])
        let customCat = ChecklistCatalog(config: cfg, overrides: custom)
        let customLeaves = customCat.buildGroups(for: draft(counts: ["electricalPanels": 2])).flatMap(\.leafSections)
        check("custom 'Electrical 2' + 2 panels: one row", customLeaves.filter { $0 == "Electrical 2" }.count == 1)

        // Report order.
        let sorted = cat.sortedForReport(many)
        print("NOV6TEST report=\(sorted)")
        check("report: Cooling System right after Outside Utilities", followed(sorted, ["Outside Utilities", "Cooling System #2", "Cooling System #3"]))
        check("report: copies together", followed(sorted, ["Electrical", "Electrical 2"]) && followed(sorted, ["HVAC Mechanical", "HVAC Mechanical 2", "HVAC Mechanical 3"])
              && followed(sorted, ["Water Heater", "Water Heater 2"]) && followed(sorted, ["Kitchen", "Kitchen 2"]))
        let twelve = (0..<12).map { $0 == 0 ? "Electrical" : "Electrical \($0 + 1)" }
        check("report: copies stay in number order", cat.sortedForReport(twelve.reversed()) == twelve)
        check("report: other ties stay by name, as before", cat.sortedForReport(["Termite", "Asbestos"]) == cat.sortedForReport(["Asbestos", "Termite"]))
        check("report: by number first", cat.sortedForReport(["Kitchen 2", "Landscaping"]) == ["Landscaping", "Kitchen 2"])

        // Lowering a count leaves the copy's data on the inspection and off the checklist (as Bathroom).
        var low = draft(counts: ["electricalPanels": 2, "bathrooms": 2])
        low.answers["Electrical 2"] = SectionAnswers(comments: "panel two")
        low.answers["Bathroom 2"] = SectionAnswers(comments: "bath two")
        low.counts["electricalPanels"] = 1; low.counts["bathrooms"] = 1
        check("lower: both off the checklist", !leaves(low).contains("Electrical 2") && !leaves(low).contains("Bathroom 2"))
        check("lower: both keep their answers", low.answers["Electrical 2"]?.comments == "panel two" && low.answers["Bathroom 2"]?.comments == "bath two")

        // Kitchen chip / stepper.
        var sync = draft()
        let k = rc("kitchens")
        sync.setRoomCount(2, for: k)
        check("sync: stepper 2, chip on", sync.counts["kitchens"] == 2 && sync.rooms.contains("Kitchen"))
        sync.setRoomCount(0, for: k)
        check("sync: stepper 0, chip off", !sync.rooms.contains("Kitchen") && sync.roomCount(k) == 0)
        sync.setRoomCount(1, for: k)
        check("sync: stepper 1, chip on", sync.rooms.contains("Kitchen"))
        sync.setRoomCount(3, for: k)
        sync.setRooms(sync.rooms.filter { $0 != "Kitchen" }, wizard: w)
        check("sync: chip off, 0", sync.counts["kitchens"] == 0 && sync.roomCount(k) == 0)
        sync.setRooms(sync.rooms + ["Kitchen"], wizard: w)
        check("sync: chip on, 1", sync.counts["kitchens"] == 1 && sync.roomCount(k) == 1)
        sync.setRooms(sync.rooms.filter { $0 != "Garage" }, wizard: w)
        check("sync: another chip leaves the count", sync.counts["kitchens"] == 1)
        var hvac = draft()
        hvac.setRoomCount(4, for: rc("hvacUnits"))
        check("sync: hvac changes no chip", hvac.rooms == draft().rooms)

        // Manage checklist.
        let exterior = cat.adminGroups().first { $0.group == "Exterior" }?.sections ?? []
        check("Manage checklist: Cooling System after Outside Utilities", followed(exterior, ["Outside Utilities", "Cooling System"]), "\(exterior)")

        // Agreement boxes.
        guard let doc = InspectionAgreement.bundled else { check("agreement bundled", false); return }
        let tick = "\u{2612}", empty = "\u{2610}"
        for st in ["UT", "TX", "OR"] {
            let base = AgreementContent.vims(doc, company: store.company.name, stateCode: st, stateName: { store.config.stateName($0) ?? $0 })
            func filled(_ make: (inout Inspection) -> Void) -> [String] {
                var d = store.newInspectionDraft()
                nov5Values(&d, config: store.config)
                d.utilities = []; d.tests = []; d.fees = nil; d.sendToAgent = true
                make(&d)
                return store.agreementFill(d).apply(to: base).blocks.flatMap { b -> [String] in
                    if case .form(let l) = b { return l.map(AgreementFill.plain) }
                    return [b.fillableText].compactMap { $0 }.map(AgreementFill.plain)
                }
            }
            func line(_ all: [String], _ p: String) -> String { all.first { $0.contains(p) } ?? "" }
            let none = filled { _ in }
            let count = { (a: [String]) in a.joined().filter { String($0) == tick }.count }
            let bb = count(none)
            check("\(st) new line in the form", line(none, "Tests Only") == "Texas \(empty) Tests Only \(empty)", line(none, "Tests Only"))
            check("\(st) Warranty ticks its box", line(filled { $0.inspType = "Warranty" }, "Warranty").hasSuffix("Warranty \(tick)"), line(filled { $0.inspType = "Warranty" }, "Warranty"))
            let tx = filled { $0.inspType = "Texas" }
            check("\(st) Texas ticks one box, its own", line(tx, "Tests Only") == "Texas \(tick) Tests Only \(empty)" && count(tx) == bb)
            let to = filled { $0.inspType = "Tests Only" }
            check("\(st) Tests Only ticks one box, its own", line(to, "Tests Only") == "Texas \(empty) Tests Only \(tick)" && count(to) == bb)
            let wind = filled { $0.tests = ["Wind Mitigation"] }
            check("\(st) Wind Mitigation ticks both its boxes", line(wind, "Pre-listing").hasPrefix("Wind Mitigation \(tick) Pre-listing") && line(wind, "Wind Mitigation Inspection").contains("\(tick) Wind Mitigation Inspection") && count(wind) == bb + 2, line(wind, "Pre-listing"))
            let noWind = filled { $0.tests = ["Radon"] }
            check("\(st) no Wind Mitigation test leaves both", line(noWind, "Pre-listing").hasPrefix("Wind Mitigation \(empty)") && line(noWind, "Wind Mitigation Inspection").contains("\(empty) Wind Mitigation Inspection"))
        }
        let services = "\(empty) Boiler System $__________ \(empty) Wind Mitigation Inspection $__________"
        check("'Wind Mitigation' after can't touch '\(empty) Wind Mitigation Inspection'", AgreementFill.tickBox(services, box: "Wind Mitigation", side: "after") == nil)
        check("'Wind Mitigation Inspection' before can't touch 'Wind Mitigation \(empty)'", AgreementFill.tickBox("Wind Mitigation \(empty) Pre-listing/Maintenance \(empty)", box: "Wind Mitigation Inspection", side: "before") == nil)

        // Every saved inspection against a rebuild (the same catalog the wizard's Update checklist uses).
        for i in store.inspections {
            let c = store.catalog(for: i)
            let rebuilt = c.buildGroups(for: i)
            let same = rebuilt.map(\.leafSections) == i.groups.map(\.leafSections)
            print("NOV6TEST saved \(i.addressLine1) type=\(i.inspType) counts=\(i.counts.sorted { $0.key < $1.key }) sections=\(i.leafSections.count) status=\(i.status.values.filter { $0 == .done }.count) answers=\(i.answers.count) photos=\(i.photoCount) findings=\(i.findings.count) version=\(i.checklistVersion ?? "nil")")
            check("saved rebuild identical: \(i.addressLine1)", same, same ? "" : "stored=\(i.groups.map(\.leafSections)) rebuilt=\(rebuilt.map(\.leafSections))")
        }

        // The chosen inspection's copies.
        if let i = store.inspection(id) {
            print("NOV6TEST chosen \(i.addressLine1) counts=\(i.counts.sorted { $0.key < $1.key }) leaves=\(i.leafSections)")
            for s in i.leafSections where ChecklistCatalog.baseName(s) != s || ["Electrical", "Water Heater", "HVAC Mechanical", "Kitchen", "Outside Utilities"].contains(s) {
                print("NOV6TEST copy \(s) status=\(i.status[s]?.rawValue ?? "nil") comment=\(i.answers[s]?.comments ?? "nil") answers=\((i.answers[s]?.choices.count ?? 0)) photos=\(i.photos[s]?.mapValues(\.count) ?? [:]) findings=\(i.findings.filter { $0.section == s }.map(\.text))")
            }
            if let data = store.reportData(id) {
                print("NOV6TEST report rows=\(data.propertyInfo.filter { p in w.roomCounts.contains { $0.label == p.0 } })")
                print("NOV6TEST report sections=\(data.sections.map { "\($0.number) \($0.title)" })")
            }
        }
        print("NOV6TEST done failures=\(failures)")
    }
}
#endif
