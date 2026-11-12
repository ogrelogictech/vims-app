#if DEBUG
import Foundation

// DEBUG only. Client Nov 11 (shared v1.23) checks:
//   -nov11Zero                     create (once) the -nov5 sample with HVAC Units, Water Heaters and Electrical Panels at 0
//                                  and use it as the chosen inspection (add -nov6Fill to answer it, -nov6Status for its rows)
//   -nov11Fee N|clear              set Company profile > Day-of cancellation fee (%) to N, or clear it, before the screen opens
//   -nov11Status                   print NOV11TEST lines: the 0 counts in the builder, saved inspections, the chosen
//                                  inspection's progress and report, the cancellation fee in the agreement, the field rules
extension DebugLaunch {
    static let nov11Client = "Riley Zero"

    @MainActor
    static func nov11Seed(_ store: AppStore, _ id: UUID) -> UUID {
        if let fee = value("-nov11Fee") {
            store.state.company.cancellationFeePercent = fee == "clear" ? nil : Int(fee)
            print("NOV11TEST company fee set to \(store.company.cancellationFeePercent.map(String.init) ?? "nil")")
        }
        guard has("-nov11Zero") else { return id }
        if let found = store.inspections.first(where: { $0.clientName == nov11Client }) { return found.id }
        var d = store.newInspectionDraft()
        nov5Values(&d, config: store.config)
        d.fields["Client name"] = nov11Client
        d.fields["Inspection address"] = "77 Zero Ct"
        d.structure = "Single Family"
        d.unitMix = [:]
        for k in ["hvacUnits", "waterHeaters", "electricalPanels"] { d.counts[k] = 0 }
        return store.buildChecklist(from: d)
    }

    @MainActor
    static func nov11Status(_ store: AppStore, _ id: UUID) {
        guard has("-nov11Status") else { return }
        let cfg = store.config, w = cfg.wizard, cat = store.catalog
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print("NOV11TEST \(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " | \(detail)")")
        }
        func rc(_ key: String) -> RoomCountDef { w.roomCounts.first { $0.key == key }! }
        func draft(_ type: String = "Real Estate Sale", counts: [String: Int] = [:]) -> Inspection {
            var d = store.newInspectionDraft()
            d.inspType = type
            for (k, v) in counts { d.counts[k] = v }
            return d
        }
        func leaves(_ d: Inspection) -> [String] { cat.buildGroups(for: d).flatMap(\.leafSections) }
        func copies(_ list: [String], _ base: String) -> [String] { list.filter { ChecklistCatalog.baseName($0) == base } }
        let three = ["hvacUnits", "waterHeaters", "electricalPanels"]
        let sectionOf = ["hvacUnits": "HVAC Mechanical", "waterHeaters": "Water Heater", "electricalPanels": "Electrical"]

        print("NOV11TEST data=\(cfg.version) counts=\(w.roomCounts.map { "\($0.label):\($0.range.lowerBound)-\($0.range.upperBound)" })")
        check("data 1.23.0 or later", cfg.version.compare("1.23.0", options: .numeric) != .orderedAscending, cfg.version)

        // Steppers: the three go to 0, still 12 at most, still lock with the areas; defaults stay 1.
        for k in three {
            check("\(k) stepper 0 – 12", rc(k).range == 0...12, "\(rc(k).range)")
            check("\(k) locks with the areas", rc(k).locksWithAreas)
            check("\(k) new draft starts at 1", draft().roomCount(rc(k)) == 1)
        }
        check("Kitchen unchanged 0 – 12", rc("kitchens").range == 0...12)
        check("Bedrooms unchanged 0 – 20, not locked", rc("bedrooms").range == StepperLimits.roomCount && !rc("bedrooms").locksWithAreas)

        // A saved inspection with no stored value still reads 1, so its checklist doesn't change.
        var saved = draft()
        for k in three + ["kitchens"] { saved.counts[k] = nil }
        for k in three { check("missing \(k) reads 1", saved.roomCount(rc(k)) == 1) }
        check("saved without the keys builds the defaults' checklist", leaves(saved) == leaves(draft()))

        // At 0: that section and (HVAC) every Cooling System copy left out; nothing else moves.
        let base = leaves(draft())
        for k in three {
            let s = sectionOf[k]!
            let zero = leaves(draft(counts: [k: 0]))
            check("\(k) 0: no \(s)", copies(zero, s).isEmpty, "\(copies(zero, s))")
            check("\(k) 0: everything else as at 1", zero == base.filter { $0 != s }, "\(zero.count) vs \(base.count)")
        }
        let hvacZeroFromThree = leaves(draft(counts: ["hvacUnits": 0]))
        check("HVAC 0: no Cooling System copy", !hvacZeroFromThree.contains { $0.hasPrefix("Cooling System") })
        check("HVAC 0: Outside Utilities stays", hvacZeroFromThree.contains("Outside Utilities"))
        let none = draft(counts: ["hvacUnits": 0, "waterHeaters": 0, "electricalPanels": 0])
        let noneGroups = cat.buildGroups(for: none)
        let utility = noneGroups.compactMap(\.sub).first { $0.heading == "Utility & Function" }
        print("NOV11TEST all three 0: Utility & Function=\(utility?.sections ?? [])")
        check("all three 0: Utility & Function keeps Utility Room, Plumbing, Foundation", utility.map { ["Utility Room", "Plumbing", "Foundation / Crawl Space"].allSatisfy($0.sections.contains) } ?? false)
        check("all three 0: none of the three, no Cooling System", !noneGroups.flatMap(\.leafSections).contains { ["HVAC Mechanical", "Water Heater", "Electrical", "Cooling System"].contains(ChecklistCatalog.baseName($0)) })
        check("all three 0: no empty group", noneGroups.allSatisfy { $0.link != nil || !$0.leafSections.isEmpty })
        check("HVAC 1 adds no Cooling System, 3 adds #2 #3", !leaves(draft(counts: ["hvacUnits": 1])).contains { $0.hasPrefix("Cooling System") }
              && copies(leaves(draft(counts: ["hvacUnits": 3])), "Cooling System") == ["Cooling System #2", "Cooling System #3"])

        // Phase / Texas / 4 Point / Tests Only layouts ignore the counts, 0 included.
        for t in ["Texas", "4 Point Inspection", "Phase 1 Foundation", "Phase 2 Pre-Dry Wall", "Tests Only"] {
            check("\(t): 0 changes nothing", leaves(draft(t, counts: ["hvacUnits": 0, "waterHeaters": 0, "electricalPanels": 0])) == leaves(draft(t)))
        }

        // Update checklist to 0 and back: the data stays on the inspection, the section comes back with it (as Bathroom).
        var low = draft(counts: ["electricalPanels": 2])
        low.groups = cat.buildGroups(for: low)
        low.answers["Electrical"] = SectionAnswers(comments: "main panel")
        low.answers["Electrical 2"] = SectionAnswers(comments: "sub panel")
        low.status["Electrical"] = .done
        low.counts["electricalPanels"] = 0
        low.groups = cat.buildGroups(for: low)
        check("lower to 0: both panels off the checklist", copies(low.leafSections, "Electrical").isEmpty)
        check("lower to 0: answers and status kept", low.answers["Electrical"]?.comments == "main panel" && low.answers["Electrical 2"]?.comments == "sub panel" && low.status["Electrical"] == .done)
        low.counts["electricalPanels"] = 2
        low.groups = cat.buildGroups(for: low)
        check("raise to 2: both back", copies(low.leafSections, "Electrical") == ["Electrical", "Electrical 2"])
        var noneBuilt = none
        noneBuilt.groups = noneGroups
        let noneProgress = store.progressSections(noneBuilt)
        check("progress: counts only what was built", !noneProgress.isEmpty && noneProgress.allSatisfy(noneBuilt.leafSections.contains)
              && !noneProgress.contains { ["HVAC Mechanical", "Water Heater", "Electrical"].contains($0) })

        // Report Property Information rows print the counts as read (0 prints 0, a missing value 1).
        print("NOV11TEST rows zero=\(w.roomCounts.map { "\($0.label)=\(none.roomCount($0))" }) saved=\(w.roomCounts.map { "\($0.label)=\(saved.roomCount($0))" })")

        // Every saved inspection still rebuilds exactly as stored (Update checklist changes nothing on an upgrade).
        for i in store.inspections {
            let rebuilt = store.catalog(for: i).buildGroups(for: i).map(\.leafSections)
            let same = rebuilt == i.groups.map(\.leafSections)
            print("NOV11TEST saved \(i.addressLine1) type=\(i.inspType) counts=\(i.counts.sorted { $0.key < $1.key }) sections=\(i.leafSections.count) done=\(i.status.values.filter { $0 == .done }.count) answers=\(i.answers.count) photos=\(i.photoCount) findings=\(i.findings.count)")
            check("saved rebuild identical: \(i.addressLine1)", same, same ? "" : "stored=\(i.groups.map(\.leafSections)) rebuilt=\(rebuilt)")
        }

        // The chosen inspection (-nov11Zero): checklist, progress and report without the three.
        if let i = store.inspection(id), i.clientName == nov11Client {
            let leavesI = i.leafSections
            print("NOV11TEST chosen \(i.addressLine1) counts=\(i.counts.sorted { $0.key < $1.key }) leaves=\(leavesI)")
            check("chosen: no HVAC Mechanical / Water Heater / Electrical / Cooling System", !leavesI.contains { ["HVAC Mechanical", "Water Heater", "Electrical", "Cooling System"].contains(ChecklistCatalog.baseName($0)) })
            let prog = store.progressSections(i)
            let done = prog.filter { i.status[$0] == .done }.count
            print("NOV11TEST chosen progress \(done)/\(prog.count)")
            if let data = store.reportData(id) {
                let rows = data.propertyInfo.filter { p in w.roomCounts.contains { $0.label == p.0 } }
                print("NOV11TEST chosen report rows=\(rows)")
                print("NOV11TEST chosen report sections=\(data.sections.map { "\($0.number) \($0.title)" })")
                check("chosen report rows: HVAC Units 0, Water Heaters 0, Electrical Panels 0",
                      ["HVAC Units", "Water Heaters", "Electrical Panels"].allSatisfy { l in rows.contains { $0.0 == l && $0.1 == "0" } }, "\(rows)")
                check("chosen report: none of the three sections", !data.sections.contains { ["HVAC Mechanical", "Water Heater", "Electrical", "Cooling System"].contains(ChecklistCatalog.baseName($0.title)) })
            }
        }

        // Day-of cancellation fee in the agreement.
        print("NOV11TEST company fee=\(store.company.cancellationFeePercent.map(String.init) ?? "nil")")
        check("agreementPrefill has the 'a fee totaling' closing line", cfg.agreementPrefill?.lines.contains { $0.label == "a fee totaling" && $0.part == "closing" } ?? false)
        if let doc = InspectionAgreement.bundled {
            let base = AgreementContent.vims(doc, company: store.company.name, stateCode: "UT", stateName: { store.config.stateName($0) ?? $0 })
            var sample = store.newInspectionDraft()
            nov5Values(&sample, config: store.config)
            func fill(_ fee: Int?) -> AgreementFill {
                AgreementFill.make(sample, spec: cfg.agreementPrefill, wizard: w, inspectorName: "Pat Inspector", cancellationFeePercent: fee)
            }
            func cancelLine(_ c: AgreementContent) -> String {
                c.blocks.compactMap(\.fillableText).map(AgreementFill.plain).first { $0.hasPrefix("Cancellation on day of inspection") } ?? ""
            }
            let blank = "a fee totaling __________% of the amount of the inspection will be charged."
            check("not set: underscores stay", cancelLine(fill(nil).apply(to: base)).hasSuffix(blank), cancelLine(fill(nil).apply(to: base)))
            let filled25 = cancelLine(fill(25).apply(to: base))
            print("NOV11TEST line 25=\(filled25)")
            check("25: 'a fee totaling 25% of the amount'", filled25.hasSuffix("If the inspection is canceled on the day of the inspection a fee totaling 25% of the amount of the inspection will be charged."), filled25)
            check("25: printed bold", fill(25).apply(to: base).blocks.compactMap(\.fillableText).contains { $0.contains("\(AgreementFill.boldOpen)25\(AgreementFill.boldClose)%") })
            check("0: 'a fee totaling 0%'", cancelLine(fill(0).apply(to: base)).contains("a fee totaling 0% of"))
            check("100: 'a fee totaling 100%'", cancelLine(fill(100).apply(to: base)).contains("a fee totaling 100% of"))
            check("101 never prints", cancelLine(fill(101).apply(to: base)).hasSuffix(blank))
            check("the other lines fill the same with or without the fee",
                  fill(25).lines.filter { $0.label != "a fee totaling" } == fill(nil).lines.filter { $0.label != "a fee totaling" })
            check("the store's fill uses the company fee",
                  store.agreementFill(sample).lines.first { $0.label == "a fee totaling" }?.value == (store.company.cancellationFeePercent.map(String.init) ?? ""))
            // A company's edited agreement without the wording: skipped silently, every other line still fills.
            let edited = AgreementContent(blocks: base.blocks.map { b in
                if let t = b.fillableText, t.hasPrefix("Cancellation on day of inspection") { return b.withFillableText("Cancellation on day of inspection – No fee.") }
                return b
            })
            let editedOut = fill(25).apply(to: edited)
            check("edited without the wording: skipped", cancelLine(editedOut) == "Cancellation on day of inspection – No fee.")
            check("edited without the wording: client name still filled", editedOut.blocks.contains { if case .form(let l) = $0 { return l.contains { AgreementFill.plain($0).contains("Morgan Ellis") } }; return false })
            check("fillLine: label alone, nothing typed in", AgreementFill.fillLine("a fee totaling __________% of", label: "a fee totaling", value: "") == nil)
        } else {
            check("agreement bundled", false)
        }

        // The field: whole numbers 0 – 100, blank allowed.
        let kind = FieldKind.number(.percent)
        let rule = FieldRule.opt(kind, "Day-of cancellation fee")
        check("typing: digits only, no decimals", kind.filter("2a5") == "25" && kind.filter("2.5") == "2", "\(kind.filter("2a5")) \(kind.filter("2.5"))")
        check("typing: 3 digits at most", kind.filter("1000") == "100", kind.filter("1000"))
        check("blank is fine", Validator.error(for: "", rule: rule) == nil)
        check("0, 25, 100 are fine", ["0", "25", "100"].allSatisfy { Validator.error(for: $0, rule: rule) == nil })
        check("101 is refused", Validator.error(for: "101", rule: rule) == "Enter a number up to 100", Validator.error(for: "101", rule: rule) ?? "nil")
        check("while typing 101 shows the max", Validator.overMaxError("101", kind: kind) == "Enter a number up to 100")

        // Company JSON: a 0.35.0 profile decodes with no fee and saves back without the key; a set fee round-trips.
        var old = store.company
        old.cancellationFeePercent = nil
        if let data = try? JSONEncoder().encode(old), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            check("no fee: key not written", json["cancellationFeePercent"] == nil)
            check("0.35.0 profile decodes", (try? JSONDecoder().decode(CompanyProfile.self, from: data)) == old)
        }
        var withFee = old
        withFee.cancellationFeePercent = 25
        check("fee round-trips", (try? JSONEncoder().encode(withFee)).flatMap { try? JSONDecoder().decode(CompanyProfile.self, from: $0) }?.cancellationFeePercent == 25)

        print("NOV11TEST done failures=\(failures)")
    }
}
#endif
