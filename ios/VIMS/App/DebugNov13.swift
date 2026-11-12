#if DEBUG
import Foundation
import PDFKit

// DEBUG only. Client Nov 13 (shared v1.24) checks:
//   -nov13Wizard                   with -screen wizard: the -nov5Wizard client details with no options picked and no amounts
//                                  (Nov13UITests types the surcharge, the fee and one test)
//   -nov13Fees                     create (once) the client's case (Inspection Fee 400, Radon 150, surcharge 75) and use it
//                                  as the chosen inspection
//   -nov13Status                   print NOV13TEST lines: the spec, the fee rules, saved inspections' fees, the JSON shape,
//                                  the agreement line and Total Amount Due (viewer content, edited agreement, PDF text), and
//                                  that the chosen inspection's report carries no fees
//   -nov13WritePDF                 write the chosen inspection's filled agreement to Documents/nov13-agreement.pdf
extension DebugLaunch {
    static let nov13Client = "Casey Faraway"

    /// The wizard draft for typing the client's case by hand: step 1 and 2 values, nothing on step 4.
    static func nov13WizardValues(_ d: inout Inspection, config: ChecklistConfig) {
        nov5Values(&d, config: config)
        d.structure = "Single Family"
        d.unitMix = [:]
        d.utilities = []
        d.tests = []
        d.fees = nil
    }

    static func nov13Values(_ d: inout Inspection, config: ChecklistConfig) {
        nov13WizardValues(&d, config: config)
        d.fields["Client name"] = nov13Client
        d.fields["Inspection address"] = "9 Far Ridge Rd"
        d.tests = ["Radon"]
        d.fees = InspectionFees(amounts: ["Radon": "150"], inspectionFee: "400", surcharge: "75")
    }

    @MainActor
    static func nov13Seed(_ store: AppStore, _ id: UUID) -> UUID {
        guard has("-nov13Fees") else { return id }
        if let found = store.inspections.first(where: { $0.clientName == nov13Client }) { return found.id }
        var d = store.newInspectionDraft()
        nov13Values(&d, config: store.config)
        return store.buildChecklist(from: d)
    }

    @MainActor
    static func nov13Status(_ store: AppStore, _ id: UUID) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        func agreementBase(_ insp: Inspection) -> AgreementContent? {
            store.editedAgreementContent ?? InspectionAgreement.bundled.map {
                AgreementContent.vims($0, company: store.company.name, stateCode: insp.state, stateName: { store.config.stateName($0) ?? $0 })
            }
        }
        if has("-nov13WritePDF"), let insp = store.inspection(id), let base = agreementBase(insp), let docs {
            let filled = store.agreementFill(insp).apply(to: base)
            try? AgreementPDF.render(filled, company: store.company.name).pdf.write(to: docs.appendingPathComponent("nov13-agreement.pdf"))
            print("NOV13TEST wrote nov13-agreement.pdf for \(insp.addressLine1)")
        }
        guard has("-nov13Status") else { return }
        let cfg = store.config, w = cfg.wizard
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print("NOV13TEST \(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " | \(detail)")")
        }
        let label = "Out of service area surcharge $"
        print("NOV13TEST data=\(cfg.version)")
        check("data 1.24.0 or later", cfg.version.compare("1.24.0", options: .numeric) != .orderedAscending, cfg.version)
        check("agreementPrefill has the surcharge header line", cfg.agreementPrefill?.lines.contains { $0.label == label && $0.part == "header" && $0.fee == nil } ?? false)
        check("the app maps the label", AgreementFill.sources[label] == .surcharge)

        // Fee rules: Total = Inspection Fee + Bundled + surcharge; Bundled unchanged; the surcharge selects and locks nothing.
        func draft(_ make: (inout Inspection) -> Void = { _ in }) -> Inspection {
            var d = store.newInspectionDraft()
            nov13Values(&d, config: cfg)
            make(&d)
            return d
        }
        let client = draft()
        check("client case: bundled 150.00", InspectionFees.text(client.bundledFees(wizard: w)) == "150.00", InspectionFees.text(client.bundledFees(wizard: w)))
        check("client case: total 625.00", InspectionFees.text(client.totalFees(wizard: w)) == "625.00", InspectionFees.text(client.totalFees(wizard: w)))
        let noSurcharge = draft { $0.fees?.surcharge = nil }
        check("without the surcharge: total 550.00 (as before)", InspectionFees.text(noSurcharge.totalFees(wizard: w)) == "550.00")
        let onlySurcharge = draft { $0.tests = []; $0.fees = nil; $0.setSurcharge("75") }
        check("surcharge alone: bundled 0, total 75.00", onlySurcharge.bundledFees(wizard: w) == 0 && InspectionFees.text(onlySurcharge.totalFees(wizard: w)) == "75.00")
        check("surcharge selects no option", onlySurcharge.tests.isEmpty && onlySurcharge.selectedUtilities.isEmpty && onlySurcharge.fees?.amounts.isEmpty == true)
        var cleared = onlySurcharge
        cleared.setSurcharge("")
        check("clearing the only amount leaves no fees", cleared.fees == nil)
        for t in w.areasLockedTypes ?? [] {
            let locked = draft { $0.inspType = t }
            check("\(t): surcharge not locked, still counted", InspectionFees.text(locked.totalFees(wizard: w)) == InspectionFees.text(locked.bundledFees(wizard: w) + 475))
        }
        let big = draft { $0.fees?.surcharge = "99,999.99"; $0.fees?.inspectionFee = "1,250.5" }
        check("commas and cents: 99,999.99 + 1,250.50 + 150", InspectionFees.text(big.totalFees(wizard: w)) == "101,400.49", InspectionFees.text(big.totalFees(wizard: w)))
        check("same limits as Inspection Fee", FieldKind.number(InspectionFees.limits).filter("1234567.891") == "12,345.89")
        check("lone dot dropped", InspectionFees(amounts: [:], inspectionFee: nil, surcharge: ".").normalized() == nil)
        check("lone dot dropped, fee kept", InspectionFees(amounts: [:], inspectionFee: "400", surcharge: ".").normalized() == InspectionFees(amounts: [:], inspectionFee: "400"))

        // JSON: fees saved by 0.36.0 have no surcharge key, decode with none, and encode back without one.
        let oldFees = #"{"amounts":{"Radon":"150"},"inspectionFee":"400"}"#
        let decoded = try? JSONDecoder().decode(InspectionFees.self, from: Data(oldFees.utf8))
        check("0.36.0 fees decode, no surcharge", decoded == InspectionFees(amounts: ["Radon": "150"], inspectionFee: "400") && decoded?.surcharge == nil)
        let reKeys = decoded.flatMap { try? JSONEncoder().encode($0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }.map { Set($0.keys) }
        check("0.36.0 fees encode back with the same keys", reKeys == ["amounts", "inspectionFee"], "\(reKeys ?? [])")
        let round = (try? JSONEncoder().encode(client)).flatMap { try? JSONDecoder().decode(Inspection.self, from: $0) }
        check("surcharge round-trips with the inspection", round?.fees?.surcharge == "75" && round?.fees == client.fees)

        // Saved inspections: fees as stored (an upgrade adds no surcharge), total = fee + bundled + surcharge.
        for i in store.inspections {
            let f = i.fees
            print("NOV13TEST saved \(i.addressLine1) client=\(i.clientName) fees=\(f == nil ? "nil" : "amounts=\(f!.amounts.count) fee=\(f!.inspectionFee ?? "nil") surcharge=\(f!.surcharge ?? "nil")") bundled=\(InspectionFees.text(i.bundledFees(wizard: w))) total=\(InspectionFees.text(i.totalFees(wizard: w)))")
            if i.clientName != nov13Client {
                check("saved \(i.addressLine1): no surcharge", f?.surcharge == nil)
                check("saved \(i.addressLine1): total = fee + bundled", i.totalFees(wizard: w) == (InspectionFees.value(f?.inspectionFee) ?? 0) + i.bundledFees(wizard: w))
            }
        }

        // The agreement: its own header line right above Inspection Fee, 2 decimals, blank at zero, in Total Amount Due.
        guard let doc = InspectionAgreement.bundled else { check("agreement bundled", false); print("NOV13TEST done failures=\(failures)"); return }
        let lines = doc.formLines
        let at = lines.firstIndex { $0.hasPrefix(label) }
        check("agreement line right above Inspection Fee", at != nil && at! + 1 < lines.count && lines[at! + 1].hasPrefix("Inspection Fee $"), at.map { lines[$0] } ?? "missing")
        let base = AgreementContent.vims(doc, company: store.company.name, stateCode: "UT", stateName: { store.config.stateName($0) ?? $0 })
        func form(_ d: Inspection, _ content: AgreementContent = base) -> [String] { store.agreementFill(d).apply(to: content).formLines.map(AgreementFill.plain) }
        func line(_ f: [String], _ prefix: String) -> String { f.first { $0.hasPrefix(prefix) } ?? "" }
        let filled = form(client)
        print("NOV13TEST line: \(line(filled, label))")
        print("NOV13TEST line: \(line(filled, "Inspection Fee"))")
        check("surcharge line 75.00", line(filled, label) == "Out of service area surcharge $ 75.00", line(filled, label))
        check("fee line: 400.00 / 150.00 / 625.00", line(filled, "Inspection Fee").hasPrefix("Inspection Fee $ 400.00 Bundled Services $ 150.00 Total Amount Due $ 625.00"), line(filled, "Inspection Fee"))
        check("printed bold", store.agreementFill(client).apply(to: base).formLines.contains { $0.contains("\(AgreementFill.boldOpen)75.00\(AgreementFill.boldClose)") })
        check("zero: underscores stay", line(form(draft { $0.fees?.surcharge = "0" }), label) == "Out of service area surcharge $__________")
        check("none: underscores stay, total without it", line(form(noSurcharge), label) == "Out of service area surcharge $__________" && line(form(noSurcharge), "Inspection Fee").contains("Total Amount Due $ 550.00"))
        check("commas: 99,999.99", line(form(big), label) == "Out of service area surcharge $ 99,999.99" && line(form(big), "Inspection Fee").contains("Total Amount Due $ 101,400.49"), line(form(big), "Inspection Fee"))
        check("the other lines fill the same with or without it", form(client).filter { !$0.hasPrefix(label) && !$0.hasPrefix("Inspection Fee") } == form(noSurcharge).filter { !$0.hasPrefix(label) && !$0.hasPrefix("Inspection Fee") })

        // A company's edited agreement keeps the locked VIMS form, so it shows the new line too.
        let edited = AgreementContent.edited(EditedAgreement(blocks: base.blocks).encoded, company: store.company.name, form: store.agreementFormLines)
        check("edited agreement shows the line, filled", line(form(client, edited), label) == "Out of service area surcharge $ 75.00")
        // An agreement without the line (an older form): skipped silently, the 75 never lands in another blank.
        let oldForm = doc.formLines.filter { !$0.hasPrefix(label) }
        let stale = form(client, AgreementContent(blocks: [.title("T"), .form(oldForm), .paragraph("Body", lead: false)]))
        check("no line: skipped, nothing else changes", stale.count == oldForm.count && !stale.contains { $0.contains("75.00") } && line(stale, "Inspection Fee").contains("Total Amount Due $ 625.00"))
        check("the label can't fill a blank that isn't right after it", AgreementFill.fillLine("Out of service area surcharge $ none Inspection Fee $____", label: label, value: "75.00") == nil)

        // The PDF: the line, filled, and the total (text extracted from the rendered file).
        if let insp = store.inspection(id) ?? Optional(client), let content = agreementBase(insp) {
            let pdf = AgreementPDF.render(store.agreementFill(insp).apply(to: content), company: store.company.name)
            let text = (PDFDocument(data: pdf.pdf)?.string ?? "").replacingOccurrences(of: "\n", with: " ")
            let surchargeOut = InspectionFees.text(insp.surchargeFee)
            let has = text.contains("Out of service area surcharge $ \(surchargeOut)") || text.contains("Out of service area surcharge $\(surchargeOut)")
            print("NOV13TEST pdf \(insp.addressLine1) pages=\(pdf.pageCount) surcharge=\(surchargeOut) total=\(InspectionFees.text(insp.totalFees(wizard: w)))")
            if insp.surchargeFee > 0 {
                check("PDF prints the surcharge line filled", has)
                check("PDF Total Amount Due includes it", text.contains("Total Amount Due $ \(InspectionFees.text(insp.totalFees(wizard: w)))"))
            } else {
                check("PDF prints the surcharge line blank", text.contains("Out of service area surcharge $__________"))
            }
        }

        // Fees never appear in the report.
        if let i = store.inspection(id), i.clientName == nov13Client, let data = store.reportData(id) {
            let report = PDFDocument(data: ReportRenderer.render(data).pdf)?.string ?? ""
            print("NOV13TEST report \(i.addressLine1) chars=\(report.count)")
            check("report: no surcharge, fee or total", !report.localizedCaseInsensitiveContains("surcharge") && !report.contains("625.00") && !report.contains("400.00")
                  && !report.contains("Inspection Fee") && !report.contains("Total Cost"))
        }
        print("NOV13TEST done failures=\(failures)")
    }
}
#endif
