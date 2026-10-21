import UIKit

// v1.9 form reports (client Oct 17, item 13): sections with `formReport` print as form pages instead of the normal
// checklist page — Wind Mitigation as the Florida OIR-B1-1802 "Uniform Mitigation Verification Inspection Form"
// (4 pages, a public state form; official wording from docs/forms/oir-b1-1802.txt) and Termite as VIMS's own one-page
// "Wood Destroying Insect Inspection Report" (same data as the NPMA-33 the client uses, NOT a copy of that copyrighted
// form). Photos of these sections print after the form on a pictures page (ReportRenderer).

/// A form section's answers by question (visible items only — hidden `visibleIf` items print blank), with the `prefill`
/// values standing in for answers the inspector never opened.
struct FormReportData {
    let key: String
    let def: FormReportDef?
    /// question -> chosen options (single / multi)
    let choices: [String: [String]]
    /// question -> text (dates as MM/DD/YYYY)
    let texts: [String: String]
    /// question -> its option list (the JSON options are short labels; the form prints the official wording by index)
    let options: [String: [String]]
    /// Values from the inspection / company the form prints outside the answers.
    let inspectionDate: String
    let propertyAddress: String
    let initials: String

    func choice(_ q: String) -> [String] { choices[q] ?? [] }
    func first(_ q: String) -> String? { choices[q]?.first }
    func text(_ q: String) -> String { texts[q] ?? "" }
    /// The option at `index` of item `q` is chosen.
    func picked(_ q: String, _ index: Int) -> Bool {
        guard let opts = options[q], index < opts.count else { return false }
        return choice(q).contains(opts[index])
    }
    /// The letter of a lettered answer ("A. Built in compliance…" -> "A", "A.1" -> "A.1").
    func letter(_ q: String) -> String? {
        guard let v = first(q) else { return nil }
        if v.range(of: #"^[A-Z]\.\d$"#, options: .regularExpression) != nil || v.count == 1 { return v }
        return v.split(separator: ".").first.map(String.init)
    }

    static func make(key: String, def: FormReportDef?, items: [ItemDef], answers a: SectionAnswers, insp: Inspection,
                     inspector: String) -> FormReportData {
        var choices: [String: [String]] = [:], texts: [String: String] = [:], options: [String: [String]] = [:]
        let keyed = ItemKeys.keyed(items)
        for k in keyed { if let q = k.item.q, let o = k.item.options { options[q] = o } }
        for k in ItemVisibility.visible(keyed, answers: a) {
            guard let q = k.item.q else { continue }
            switch k.item.kind {
            case .single, .multi:
                if let c = a.choices[k.id], !c.isEmpty { choices[q] = c }
            case .date:
                let raw = a.text[k.id] ?? ""
                texts[q] = Fmt.answerDate(raw).map { Fmt.date($0, "MM/dd/yyyy") } ?? raw
            default:
                var v = (a.text[k.id] ?? "").trimmingCharacters(in: .whitespaces)
                // Never opened: the prefill values (owner name, address, initials…) still print.
                if v.isEmpty, let p = k.item.prefill, !a.hasContent {
                    v = insp.prefillValue(p, inspector: inspector)
                }
                if !v.isEmpty { texts[q] = v }
            }
        }
        let date = Fmt.parse(insp.field("Date"), "yyyy-MM-dd").map { Fmt.date($0, "MM/dd/yyyy") } ?? ""
        let initials = texts["Inspector initials"] ?? insp.prefillValue("initials", inspector: inspector)
        return FormReportData(key: key, def: def, choices: choices, texts: texts, options: options, inspectionDate: date,
                              propertyAddress: insp.displayAddress, initials: initials)
    }
}

extension ReportRenderer.Writer {
    func formReport(_ s: ReportSection, _ f: FormReportData) {
        switch f.key {
        case "oir-b1-1802": windMitigation(s, f)
        default: wdiReport(s, f)
        }
    }

    // MARK: - Shared form drawing

    /// One styled run of form text: bold lead-ins, plain text, and filled-in values (underlined; blank = underscores).
    enum FormRun {
        case b(String)
        case t(String)
        case i(String)
        /// A value printed on its line; empty prints `blank` underscores.
        case v(String, blank: Int)
    }

    func formFont(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
        let name = bold ? (italic ? "Helvetica-BoldOblique" : "Helvetica-Bold") : (italic ? "Helvetica-Oblique" : "Helvetica")
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    func formAttr(_ runs: [FormRun], size: CGFloat, align: NSTextAlignment = .left) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        p.alignment = align
        p.lineSpacing = 0.6
        let out = NSMutableAttributedString()
        let ink = UIColor.black
        for r in runs {
            switch r {
            case .b(let s): out.append(NSAttributedString(string: s, attributes: [.font: formFont(size, bold: true), .foregroundColor: ink, .paragraphStyle: p]))
            case .t(let s): out.append(NSAttributedString(string: s, attributes: [.font: formFont(size), .foregroundColor: ink, .paragraphStyle: p]))
            case .i(let s): out.append(NSAttributedString(string: s, attributes: [.font: formFont(size, italic: true), .foregroundColor: ink, .paragraphStyle: p]))
            case .v(let s, let blank):
                if s.isEmpty {
                    out.append(NSAttributedString(string: String(repeating: "_", count: blank), attributes: [.font: formFont(size), .foregroundColor: ink, .paragraphStyle: p]))
                } else {
                    out.append(NSAttributedString(string: "\u{00A0}\(s)\u{00A0}", attributes: [
                        .font: formFont(size, bold: true), .foregroundColor: UIColor(hex: 0x10275E), .paragraphStyle: p,
                        .underlineStyle: NSUnderlineStyle.single.rawValue]))
                }
            }
        }
        return out
    }

    func attrHeight(_ a: NSAttributedString, w: CGFloat) -> CGFloat {
        ceil(a.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    @discardableResult
    func drawAttr(_ a: NSAttributedString, x: CGFloat, y: CGFloat, w: CGFloat) -> CGFloat {
        let h = attrHeight(a, w: w)
        a.draw(with: CGRect(x: x, y: y, width: w, height: h + 2), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return h
    }

    /// ☐ / ☒ — a square with an X when checked.
    func formBox(x: CGFloat, y: CGFloat, size: CGFloat = 7.4, checked: Bool) {
        let r = CGRect(x: x, y: y, width: size, height: size)
        stroke(r, .black, width: 0.6)
        guard checked else { return }
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX + 1.3, y: r.minY + 1.3)); p.addLine(to: CGPoint(x: r.maxX - 1.3, y: r.maxY - 1.3))
        p.move(to: CGPoint(x: r.maxX - 1.3, y: r.minY + 1.3)); p.addLine(to: CGPoint(x: r.minX + 1.3, y: r.maxY - 1.3))
        p.lineWidth = 1.1
        UIColor.black.setStroke()
        p.stroke()
    }

    /// A checkbox answer: the box, then its wrapped text (bold lead-in + wording + filled values). Advances `y`.
    func formOption(_ checked: Bool, _ runs: [FormRun], x: CGFloat, right: CGFloat, size: CGFloat, gap: CGFloat = 2.2) {
        let a = formAttr(runs, size: size)
        let h = attrHeight(a, w: right - x - 12)
        ensure(h + gap)
        formBox(x: x, y: y + (size * 1.2 - 7.4) / 2 + 0.4, checked: checked)
        drawAttr(a, x: x + 12, y: y, w: right - x - 12)
        y += h + gap
    }

    func formPara(_ runs: [FormRun], x: CGFloat, right: CGFloat, size: CGFloat, gap: CGFloat = 3, align: NSTextAlignment = .left) {
        let a = formAttr(runs, size: size, align: align)
        let h = attrHeight(a, w: right - x)
        ensure(h + gap)
        drawAttr(a, x: x, y: y, w: right - x)
        y += h + gap
    }

    /// "Label: value" on an underline, one line (value cut with an ellipsis when long).
    func formField(_ label: String, _ value: String, x: CGFloat, w: CGFloat, y fy: CGFloat, size: CGFloat) {
        let lf = formFont(size, bold: true)
        let lw = (label as NSString).size(withAttributes: [.font: lf]).width + 4
        (label as NSString).draw(at: CGPoint(x: x, y: fy), withAttributes: [.font: lf, .foregroundColor: UIColor.black])
        hline(fy + lf.lineHeight + 0.5, x: x + lw, w: max(w - lw, 4), .black, width: 0.5)
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: CGRect(x: x + lw + 2, y: fy, width: max(w - lw - 4, 0), height: lf.lineHeight + 1),
                                 withAttributes: [.font: formFont(size), .foregroundColor: UIColor(hex: 0x10275E), .paragraphStyle: p])
    }

    // MARK: - Wind Mitigation: OIR-B1-1802 (Rev. 01/12)

    private var wmL: CGFloat { 34 }
    private var wmR: CGFloat { ReportRenderer.pageSize.width - 34 }
    private var wmBody: CGFloat { 7.7 }

    /// One form page: the form's header (title + "Maintain a copy…") and its footer (initials, property address, validity
    /// note, "OIR-B1-1802 (Rev. 01/12) Adopted by Rule 69O-170.0155  Page X of N").
    private func wmPage(_ f: FormReportData, _ formPage: inout Int) {
        ctx.beginPage()
        page += 1
        formPage += 1
        let W = ReportRenderer.pageSize.width
        let tf = formFont(12.5, bold: true)
        text("Uniform Mitigation Verification Inspection Form", tf, .black, x: 0, y: 26, w: W, align: .center, lineSpacing: 0)
        text("Maintain a copy of this form and any documentation provided with the insurance policy", formFont(8, italic: true), .black,
             x: 0, y: 43, w: W, align: .center, lineSpacing: 0)
        // footer
        let total = formTotals[f.key] ?? f.def?.pages ?? 4
        let fy = ReportRenderer.pageSize.height - 52
        let fs: CGFloat = 7.6
        let a = formAttr([.b("Inspectors Initials "), .v(f.initials, blank: 6), .b("   Property Address "), .v(f.propertyAddress, blank: 60)], size: fs)
        drawAttr(a, x: wmL, y: fy, w: wmR - wmL)
        text("*This verification form is valid for up to five (5) years provided no material changes have been made to the structure or inaccuracies found on the form.",
             formFont(6.8, italic: true), .black, x: wmL, y: fy + 13, w: wmR - wmL, lineSpacing: 0)
        text("OIR-B1-1802 (Rev. 01/12) Adopted by Rule 69O-170.0155", formFont(6.8), .black, x: wmL, y: fy + 24, w: 300, lineSpacing: 0)
        text("Page \(formPage) of \(max(total, formPage))", formFont(6.8, bold: true), .black, x: wmR - 120, y: fy + 24, w: 120, align: .right, lineSpacing: 0)
        y = 60
    }

    private var wmBottom: CGFloat { ReportRenderer.pageSize.height - 58 }

    /// Question heading: "1. Building Code: Was the structure built …" (number + bold title + question).
    private func wmQuestion(_ n: String, _ title: String, _ question: String) {
        y += 4
        formPara([.b("\(n). \(title): "), .t(question)], x: wmL, right: wmR, size: wmBody + 0.3, gap: 3)
    }

    func windMitigation(_ s: ReportSection, _ f: FormReportData) {
        var formPage = 0
        let savedStarter = pageStarter
        pageStarter = { [unowned self] in self.wmPage(f, &formPage) }
        defer { pageStarter = savedStarter; formPagesUsed[f.key] = formPage }
        let L = wmL, R = wmR, sz = wmBody
        let ind = L + 14

        // ---- Page 1: inspection date, owner information, note, Q1, Q2
        wmPage(f, &formPage)
        formField("Inspection Date:", f.inspectionDate, x: L, w: 200, y: y, size: 8.5)
        y += 16
        let oh: CGFloat = 15
        fill(CGRect(x: L, y: y, width: R - L, height: 13), UIColor(white: 0.88, alpha: 1))
        text("Owner Information", formFont(8.5, bold: true), .black, x: L + 4, y: y + 2, w: 200, lineSpacing: 0)
        y += 17
        let col = (R - L - 16) / 3
        let grid: [[(String, String)]] = [
            [("Owner Name:", f.text("Owner name")), ("Contact Person:", f.text("Contact person")), ("Home Phone:", f.text("Home phone"))],
            [("Address:", f.text("Address")), ("Work Phone:", f.text("Work phone")), ("Cell Phone:", f.text("Cell phone"))],
            [("City:", f.text("City")), ("Zip:", f.text("Zip")), ("Email:", f.text("Email"))],
            [("County:", f.text("County")), ("Insurance Company:", f.text("Insurance company")), ("Policy #:", f.text("Policy #"))],
            [("Year of Home:", f.text("Year of home")), ("# of Stories:", f.text("# of stories")), ("", "")]
        ]
        for row in grid {
            for (i, cell) in row.enumerated() where !cell.0.isEmpty {
                formField(cell.0, cell.1, x: L + CGFloat(i) * (col + 8), w: col, y: y, size: 7.8)
            }
            y += oh
        }
        y += 3
        formPara([.b("NOTE: "), .t("Any documentation used in validating the compliance or existence of each construction or mitigation attribute must accompany this form. At least one photograph must accompany this form to validate each attribute marked in questions 3 though 7. The insurer may ask additional questions regarding the mitigated feature(s) verified on this form.")],
                 x: L, right: R, size: sz, gap: 2)

        // 1. Building Code
        let q1 = f.letter("Building code")
        wmQuestion("1", "Building Code", "Was the structure built in compliance with the Florida Building Code (FBC 2001 or later) OR for homes located in the HVHZ (Miami-Dade or Broward counties), South Florida Building Code (SFBC-94)?")
        formOption(q1 == "A", [.b("A. "), .t("Built in compliance with the FBC: Year Built "), .v(f.text("Year built"), blank: 9),
                               .t(". For homes built in 2002/2003 provide a permit application with a date after 3/1/2002: Building Permit Application Date (MM/DD/YYYY) "),
                               .v(f.text("Building permit application date (FBC)"), blank: 14)], x: ind, right: R, size: sz)
        formOption(q1 == "B", [.b("B. "), .t("For the HVHZ Only: Built in compliance with the SFBC-94: Year Built "), .v(f.text("Year built (SFBC-94)"), blank: 6),
                               .t(". For homes built in 1994, 1995, and 1996 provide a permit application with a date after 9/1/1994: Building Permit Application Date (MM/DD/YYYY) "),
                               .v(f.text("Building permit application date (SFBC-94)"), blank: 14)], x: ind, right: R, size: sz)
        formOption(q1 == "C", [.b("C. "), .t("Unknown or does not meet the requirements of Answer \u{201C}A\u{201D} or \u{201C}B\u{201D}")], x: ind, right: R, size: sz)

        // 2. Roof Covering
        wmQuestion("2", "Roof Covering", "Select all roof covering types in use. Provide the permit application date OR FBC/MDC Product Approval number OR Year of Original Installation/Replacement OR indicate that no information was available to verify compliance for each roof covering identified.")
        roofCoveringTable(f, x: L + 6, right: R)
        let q2 = f.letter("Roof covering compliance")
        formOption(q2 == "A", [.b("A. "), .t("All roof coverings listed above meet the FBC with a FBC or Miami-Dade Product Approval listing current at time of installation OR have a roofing permit application date on or after 3/1/02 OR the roof is original and built in 2004 or later.")], x: ind, right: R, size: sz)
        formOption(q2 == "B", [.b("B. "), .t("All roof coverings have a Miami-Dade Product Approval listing current at time of installation OR (for the HVHZ only) a roofing permit application after 9/1/1994 and before 3/1/2002 OR the roof is original and built in 1997 or later.")], x: ind, right: R, size: sz)
        formOption(q2 == "C", [.b("C. "), .t("One or more roof coverings do not meet the requirements of Answer \u{201C}A\u{201D} or \u{201C}B\u{201D}.")], x: ind, right: R, size: sz)
        formOption(q2 == "D", [.b("D. "), .t("No roof coverings meet the requirements of Answer \u{201C}A\u{201D} or \u{201C}B\u{201D}.")], x: ind, right: R, size: sz)

        // ---- Page 2: Q3 – Q6
        wmPage(f, &formPage)
        let q3 = f.letter("Roof deck attachment")
        wmQuestion("3", "Roof Deck Attachment", "What is the weakest form of roof deck attachment?")
        formOption(q3 == "A", [.b("A. "), .t("Plywood/Oriented strand board (OSB) roof sheathing attached to the roof truss/rafter (spaced a maximum of 24\u{201D} inches o.c.) by staples or 6d nails spaced at 6\u{201D} along the edge and 12\u{201D} in the field. -OR- Batten decking supporting wood shakes or wood shingles. -OR- Any system of screws, nails, adhesives, other deck fastening system or truss/rafter spacing that has an equivalent mean uplift less than that required for Options B or C below.")], x: ind, right: R, size: sz)
        formOption(q3 == "B", [.b("B. "), .t("Plywood/OSB roof sheathing with a minimum thickness of 7/16\u{201D}inch attached to the roof truss/rafter (spaced a maximum of 24\u{201D}inches o.c.) by 8d common nails spaced a maximum of 12\u{201D} inches in the field. -OR- Any system of screws, nails, adhesives, other deck fastening system or truss/rafter spacing that is shown to have an equivalent or greater resistance 8d nails spaced a maximum of 12 inches in the field or has a mean uplift resistance of at least 103 psf.")], x: ind, right: R, size: sz)
        formOption(q3 == "C", [.b("C. "), .t("Plywood/OSB roof sheathing with a minimum thickness of 7/16\u{201D}inch attached to the roof truss/rafter (spaced a maximum of 24\u{201D}inches o.c.) by 8d common nails spaced a maximum of 6\u{201D} inches in the field. -OR- Dimensional lumber/Tongue & Groove decking with a minimum of 2 nails per board (or 1 nail per board if each board is equal to or less than 6 inches in width). -OR- Any system of screws, nails, adhesives, other deck fastening system or truss/rafter spacing that is shown to have an equivalent or greater resistance than 8d common nails spaced a maximum of 6 inches in the field or has a mean uplift resistance of at least 182 psf.")], x: ind, right: R, size: sz)
        formOption(q3 == "D", [.b("D. "), .t("Reinforced Concrete Roof Deck.")], x: ind, right: R, size: sz)
        formOption(q3 == "E", [.b("E. "), .t("Other: "), .v(f.text("Roof deck attachment \u{2014} other"), blank: 45)], x: ind, right: R, size: sz)
        formOption(q3 == "F", [.b("F. "), .t("Unknown or unidentified.")], x: ind, right: R, size: sz)
        formOption(q3 == "G", [.b("G. "), .t("No attic access.")], x: ind, right: R, size: sz)

        let q4 = f.letter("Roof to wall attachment")
        let sub = ind + 16
        func picked(_ q: String, _ i: Int) -> Bool { f.picked(q, i) }
        wmQuestion("4", "Roof to Wall Attachment", "What is the WEAKEST roof to wall connection? (Do not include attachment of hip/valley jacks within 5 feet of the inside or outside corner of the roof in determination of WEAKEST type)")
        formOption(q4 == "A", [.b("A. Toe Nails")], x: ind, right: R, size: sz)
        formOption(picked("Toe nails \u{2014} type", 0), [.t("Truss/rafter anchored to top plate of wall using nails driven at an angle through the truss/rafter and attached to the top plate of the wall, or")], x: sub, right: R, size: sz)
        formOption(picked("Toe nails \u{2014} type", 1), [.t("Metal connectors that do not meet the minimal conditions or requirements of B, C, or D")], x: sub, right: R, size: sz)
        formPara([.b("Minimal conditions to qualify for categories B, C, or D. All visible metal connectors are:")], x: ind, right: R, size: sz, gap: 2)
        let minimal = "Minimal conditions for B, C or D (all visible metal connectors are)"
        formOption(picked(minimal, 0), [.t("Secured to truss/rafter with a minimum of three (3) nails, and")], x: sub, right: R, size: sz)
        formOption(picked(minimal, 1), [.t("Attached to the wall top plate of the wall framing, or embedded in the bond beam, with less than a \u{00BD}\" gap from the blocking or truss/rafter and blocked no more than 1.5\u{201D} of the truss/rafter, and free of visible severe corrosion.")], x: sub, right: R, size: sz)
        formOption(q4 == "B", [.b("B. Clips")], x: ind, right: R, size: sz)
        formOption(picked("Clips \u{2014} type", 0), [.t("Metal connectors that do not wrap over the top of the truss/rafter, or")], x: sub, right: R, size: sz)
        formOption(picked("Clips \u{2014} type", 1), [.t("Metal connectors with a minimum of 1 strap that wraps over the top of the truss/rafter and does not meet the nail position requirements of C or D, but is secured with a minimum of 3 nails.")], x: sub, right: R, size: sz)
        formOption(q4 == "C", [.b("C. Single Wraps")], x: ind, right: R, size: sz)
        formPara([.t("Metal connectors consisting of a single strap that wraps over the top of the truss/rafter and is secured with a minimum of 2 nails on the front side and a minimum of 1 nail on the opposing side.")], x: sub + 12, right: R, size: sz, gap: 2)
        formOption(q4 == "D", [.b("D. Double Wraps")], x: ind, right: R, size: sz)
        formOption(picked("Double wraps \u{2014} type", 0), [.t("Metal Connectors consisting of 2 separate straps that are attached to the wall frame, or embedded in the bond beam, on either side of the truss/rafter where each strap wraps over the top of the truss/rafter and is secured with a minimum of 2 nails on the front side, and a minimum of 1 nail on the opposing side, or")], x: sub, right: R, size: sz)
        formOption(picked("Double wraps \u{2014} type", 1), [.t("Metal connectors consisting of a single strap that wraps over the top of the truss/rafter, is secured to the wall on both sides, and is secured to the top plate with a minimum of three nails on each side.")], x: sub, right: R, size: sz)
        formOption(q4 == "E", [.b("E. "), .t("Structural Anchor bolts structurally connected or reinforced concrete roof.")], x: ind, right: R, size: sz)
        formOption(q4 == "F", [.b("F. "), .t("Other: "), .v(f.text("Roof to wall attachment \u{2014} other"), blank: 45)], x: ind, right: R, size: sz)
        formOption(q4 == "G", [.b("G. "), .t("Unknown or unidentified")], x: ind, right: R, size: sz)
        formOption(q4 == "H", [.b("H. "), .t("No attic access")], x: ind, right: R, size: sz)

        let q5 = f.letter("Roof geometry")
        wmQuestion("5", "Roof Geometry", "What is the roof shape? (Do not consider roofs of porches or carports that are attached only to the fascia or wall of the host structure over unenclosed space in the determination of roof perimeter or roof area for roof geometry classification).")
        formOption(q5 == "A", [.b("A. Hip Roof  "), .t("Hip roof with no other roof shapes greater than 10% of the total roof system perimeter. Total length of non-hip features: "),
                               .v(f.text("Total length of non-hip features (feet)"), blank: 6), .t(" feet; Total roof system perimeter: "),
                               .v(f.text("Total roof system perimeter (feet)"), blank: 7), .t(" feet")], x: ind, right: R, size: sz)
        formOption(q5 == "B", [.b("B. Flat Roof  "), .t("Roof on a building with 5 or more units where at least 90% of the main roof area has a roof slope of less than 2:12. Roof area with slope less than 2:12 "),
                               .v(f.text("Roof area with slope less than 2:12 (sq ft)"), blank: 8), .t(" sq ft; Total roof area "),
                               .v(f.text("Total roof area (sq ft)"), blank: 10), .t(" sq ft")], x: ind, right: R, size: sz)
        formOption(q5 == "C", [.b("C. Other Roof  "), .t("Any roof that does not qualify as either (A) or (B) above.")], x: ind, right: R, size: sz)

        let q6 = f.letter("Secondary water resistance")
        wmQuestion("6", "Secondary Water Resistance (SWR)", "(standard underlayments or hot-mopped felts do not qualify as an SWR)")
        formOption(q6 == "A", [.b("A. SWR (also called Sealed Roof Deck)  "), .t("Self-adhering polymer modified-bitumen roofing underlayment applied directly to the sheathing or foam adhesive SWR barrier (not foamed-on insulation) applied as a supplemental means to protect the dwelling from water intrusion in the event of roof covering loss.")], x: ind, right: R, size: sz)
        formOption(q6 == "B", [.b("B. "), .t("No SWR.")], x: ind, right: R, size: sz)
        formOption(q6 == "C", [.b("C. "), .t("Unknown or undetermined.")], x: ind, right: R, size: sz)

        // ---- Page 3: Q7 chart + A, B, C
        wmPage(f, &formPage)
        wmQuestion("7", "Opening Protection", "What is the weakest form of wind borne debris protection installed on the structure? First, use the table to determine the weakest form of protection for each category of opening. Second, (a) check one answer below (A, B, C, N, or X) based upon the lowest protection level for ALL Glazed openings and (b) check the protection level for all Non-Glazed openings (.1, .2, or .3) as applicable.")
        openingProtectionChart(f, x: L, right: R)
        let q7 = f.first("Opening protection (weakest)") ?? ""
        let q7main = String(q7.prefix(1))
        func bullets(_ items: [String]) {
            for b in items { formPara([.t("\u{2022}  " + b)], x: sub + 6, right: R, size: sz - 0.2, gap: 0.6) }
            y += 1.6
        }
        formOption(q7main == "A", [.b("A. Exterior Openings Cyclic Pressure and 9-lb Large Missile (4.5 lb for skylights only)  "), .t("All Glazed openings are protected at a minimum, with impact resistant coverings or products listed as wind borne debris protection devices in the product approval system of the State of Florida or Miami-Dade County and meet the requirements of one of the following for \u{201C}Cyclic Pressure and Large Missile Impact\u{201D} (Level A in the table above).")], x: ind, right: R, size: sz)
        bullets(["Miami-Dade County PA 201, 202, and 203", "Florida Building Code Testing Application Standard (TAS) 201, 202, and 203",
                 "American Society for Testing and Materials (ASTM) E 1886 and ASTM E 1996", "Southern Standards Technical Document (SSTD) 12",
                 "For Skylights Only: ASTM E 1886 and ASTM E 1996", "For Garage Doors Only: ANSI/DASMA 115"])
        formOption(q7 == "A.1", [.b("A.1 "), .t("All Non-Glazed openings classified as A in the table above, or no Non-Glazed openings exist")], x: sub, right: R, size: sz)
        formOption(q7 == "A.2", [.b("A.2 "), .t("One or More Non-Glazed openings classified as Level D in the table above, and no Non-Glazed openings classified as Level B, C, N, or X in the table above")], x: sub, right: R, size: sz)
        formOption(q7 == "A.3", [.b("A.3 "), .t("One or More Non-Glazed Openings is classified as Level B, C, N, or X in the table above")], x: sub, right: R, size: sz)
        formOption(q7main == "B", [.b("B. Exterior Opening Protection- Cyclic Pressure and 4 to 8-lb Large Missile (2-4.5 lb for skylights only)  "), .t("All Glazed openings are protected, at a minimum, with impact resistant coverings or products listed as windborne debris protection devices in the product approval system of the State of Florida or Miami-Dade County and meet the requirements of one of the following for \u{201C}Cyclic Pressure and Large Missile Impact\u{201D} (Level B in the table above):")], x: ind, right: R, size: sz)
        bullets(["ASTM E 1886 and ASTM E 1996 (Large Missile \u{2013} 4.5 lb.)", "SSTD 12 (Large Missile \u{2013} 4 lb. to 8 lb.)",
                 "For Skylights Only: ASTM E 1886 and ASTM E 1996 (Large Missile - 2 to 4.5 lb.)"])
        formOption(q7 == "B.1", [.b("B.1 "), .t("All Non-Glazed openings classified as A or B in the table above, or no Non-Glazed openings exist")], x: sub, right: R, size: sz)
        formOption(q7 == "B.2", [.b("B.2 "), .t("One or More Non-Glazed openings classified as Level D in the table above, and no Non-Glazed openings classified as Level C, N, or X in the table above")], x: sub, right: R, size: sz)
        formOption(q7 == "B.3", [.b("B.3 "), .t("One or More Non-Glazed openings is classified as Level C, N, or X in the table above")], x: sub, right: R, size: sz)
        formOption(q7main == "C", [.b("C. Exterior Opening Protection- Wood Structural Panels meeting FBC 2007  "), .t("All Glazed openings are covered with plywood/OSB meeting the requirements of Table 1609.1.2 of the FBC 2007 (Level C in the table above).")], x: ind, right: R, size: sz)
        formOption(q7 == "C.1", [.b("C.1 "), .t("All Non-Glazed openings classified as A, B, or C in the table above, or no Non-Glazed openings exist")], x: sub, right: R, size: sz)
        formOption(q7 == "C.2", [.b("C.2 "), .t("One or More Non-Glazed openings classified as Level D in the table above, and no Non-Glazed openings classified as Level N or X in the table above")], x: sub, right: R, size: sz)
        formOption(q7 == "C.3", [.b("C.3 "), .t("One or More Non-Glazed openings is classified as Level N or X in the table above")], x: sub, right: R, size: sz)

        // ---- Page 4: N, X, qualified inspector, statutory text
        wmPage(f, &formPage)
        formOption(q7main == "N", [.b("N. Exterior Opening Protection (unverified shutter systems with no documentation)  "), .t("All Glazed openings are protected with protective coverings not meeting the requirements of Answer \u{201C}A\u{201D}, \u{201C}B\u{201D}, or C\u{201D} or systems that appear to meet Answer \u{201C}A\u{201D} or \u{201C}B\u{201D} with no documentation of compliance (Level N in the table above).")], x: ind, right: R, size: sz)
        formOption(q7 == "N.1", [.b("N.1 "), .t("All Non-Glazed openings classified as Level A, B, C, or N in the table above, or no Non-Glazed openings exist")], x: sub, right: R, size: sz)
        formOption(q7 == "N.2", [.b("N.2 "), .t("One or More Non-Glazed openings classified as Level D in the table above, and no Non-Glazed openings classified as Level X in the table above")], x: sub, right: R, size: sz)
        formOption(q7 == "N.3", [.b("N.3 "), .t("One or More Non-Glazed openings is classified as Level X in the table above")], x: sub, right: R, size: sz)
        formOption(q7main == "X", [.b("X. None or Some Glazed Openings  "), .t("One or more Glazed openings classified and Level X in the table above.")], x: ind, right: R, size: sz)

        y += 8
        fill(CGRect(x: L, y: y, width: R - L, height: 0.8), .black)
        y += 6
        formPara([.b("MITIGATION INSPECTIONS MUST BE CERTIFIED BY A QUALIFIED INSPECTOR.")], x: L, right: R, size: 8.4, gap: 1, align: .center)
        formPara([.t("Section 627.711(2), Florida Statutes, provides a listing of individuals who may sign this form.")], x: L, right: R, size: sz, gap: 6, align: .center)
        let third = (R - L - 16) / 3
        formField("Qualified Inspector Name:", d.inspector, x: L, w: third + 30, y: y, size: 7.8)
        formField("License Type:", f.text("License type"), x: L + third + 38, w: third - 22, y: y, size: 7.8)
        formField("License or Certificate #:", d.license, x: L + 2 * third + 24, w: third - 8, y: y, size: 7.8)
        y += 15
        formField("Inspection Company:", d.companyName, x: L, w: (R - L) * 0.62, y: y, size: 7.8)
        formField("Phone:", d.companyPhone, x: L + (R - L) * 0.62 + 12, w: (R - L) * 0.38 - 12, y: y, size: 7.8)
        y += 17
        formPara([.b("Qualified Inspector \u{2013} I hold an active license as a: "), .i("(check one)")], x: L, right: R, size: sz, gap: 2)
        let licenseText = [
            "Home inspector licensed under Section 468.8314, Florida Statutes who has completed the statutory number of hours of hurricane mitigation training approved by the Construction Industry Licensing Board and completion of a proficiency exam.",
            "Building code inspector certified under Section 468.607, Florida Statutes.",
            "General, building or residential contractor licensed under Section 489.111, Florida Statutes.",
            "Professional engineer licensed under Section 471.015, Florida Statutes.",
            "Professional architect licensed under Section 481.213, Florida Statutes.",
            "Any other individual or entity recognized by the insurer as possessing the necessary qualifications to properly complete a uniform mitigation verification form pursuant to Section 627.711(2), Florida Statutes."
        ]
        for (i, t) in licenseText.enumerated() {
            formOption(f.picked("I hold an active license as a", i), [.t(t)], x: ind, right: R, size: sz)
        }
        y += 2
        formPara([.t("Individuals other than licensed contractors licensed under Section 489.111, Florida Statutes, or professional engineer licensed under Section 471.015, Florida Statues, must inspect the structures personally and not through employees or other persons. Licensees under s.471.015 or s.489.111 may authorize a direct employee who possesses the requisite skill, knowledge, and experience to conduct a mitigation verification inspection.")],
                 x: L, right: R, size: sz, gap: 5)
        formPara([.b("I, "), .v(d.inspector, blank: 26), .t(" am a qualified inspector and I personally performed the inspection or (licensed contractors and professional engineers only) I had my employee ("),
                  .v("", blank: 22), .t(") perform the inspection and I agree to be responsible for his/her work.")], x: L, right: R, size: sz + 0.3, gap: 8)
        // Signature and date stay blank for a wet / e-signature.
        formPara([.b("Qualified Inspector Signature: "), .v("", blank: 40), .b("   Date: "), .v("", blank: 22)], x: L, right: R, size: sz + 0.3, gap: 7)
        formPara([.t("An individual or entity who knowingly or through gross negligence provides a false or fraudulent mitigation verification form is subject to investigation by the Florida Division of Insurance Fraud and may be subject to administrative action by the appropriate licensing agency or to criminal prosecution. (Section 627.711(4)-(7), Florida Statutes) The Qualified Inspector who certifies this form shall be directly liable for the misconduct of employees as if the authorized mitigation inspector personally performed the inspection.")],
                 x: L, right: R, size: sz, gap: 6)
        formPara([.b("Homeowner to complete: "), .t("I certify that the named Qualified Inspector or his or her employee did perform an inspection of the residence identified on this form and that proof of identification was provided to me or my Authorized Representative.")],
                 x: L, right: R, size: sz, gap: 5)
        formPara([.b("Signature: "), .v("", blank: 40), .b("   Date: "), .v("", blank: 22)], x: L, right: R, size: sz + 0.3, gap: 7)
        formPara([.t("An individual or entity who knowingly provides or utters a false or fraudulent mitigation verification form with the intent to obtain or receive a discount on an insurance premium to which the individual or entity is not entitled commits a misdemeanor of the first degree. (Section 627.711(7), Florida Statutes)")],
                 x: L, right: R, size: sz, gap: 5)
        formPara([.i("The definitions on this form are for inspection purposes only and cannot be used to certify any product or construction feature as offering protection from hurricanes.")],
                 x: L, right: R, size: sz, gap: 2)
    }

    /// 2.1 Roof Covering Type | Permit Application Date | FBC or MDC Product Approval # | Year of Original Installation or
    /// Replacement | No Information Provided for Compliance — one row per type, ☒ on the types in use.
    private func roofCoveringTable(_ f: FormReportData, x: CGFloat, right: CGFloat) {
        let widths: [CGFloat] = [168, 86, 120, 98]
        let noInfoW = right - x - widths.reduce(0, +)
        let heads = ["2.1 Roof Covering Type:", "Permit Application Date", "FBC or MDC Product Approval #",
                     "Year of Original Installation or Replacement", "No Information Provided for Compliance"]
        let hf = formFont(6.9, bold: true)
        let headH: CGFloat = 26
        ensure(headH + 6 * 14 + 6)
        var cx = x
        for (i, h) in heads.enumerated() {
            let w = i < widths.count ? widths[i] : noInfoW
            text(h, hf, .black, x: cx + 2, y: y + (i == 0 ? headH - 10 : 2), w: w - 4, align: i == 0 ? .left : .center, lineSpacing: 0)
            cx += w
        }
        y += headH
        let types = ["Asphalt/Fiberglass Shingle", "Concrete/Clay Tile", "Metal", "Built Up", "Membrane", "Other"]
        let inUse = f.choice("Roof covering types in use")
        let vf = formFont(7.6)
        for (n, t) in types.enumerated() {
            let used = inUse.contains(t)
            formBox(x: x + 2, y: y + 2, checked: used)
            let label = t == "Other" ? "\(n + 1). Other" : "\(n + 1). \(t)"
            text(label, formFont(7.6), .black, x: x + 13, y: y + 1, w: widths[0] - 14, lineSpacing: 0)
            if t == "Other" {
                let lw = (label as NSString).size(withAttributes: [.font: formFont(7.6)]).width + 16
                hline(y + 10.5, x: x + lw, w: widths[0] - lw - 6, .black, width: 0.5)
                oneLineForm(used ? f.text("Other roof covering type") : "", vf, x: x + lw + 1, y: y + 1, w: widths[0] - lw - 8)
            }
            var vx = x + widths[0]
            let values = used ? [f.text("\(t): permit application date"), f.text("\(t): FBC or MDC product approval #"),
                                 f.text("\(t): year of original installation or replacement")] : ["", "", ""]
            for (i, v) in values.enumerated() {
                let w = widths[i + 1]
                hline(y + 10.5, x: vx + 6, w: w - 12, .black, width: 0.5)
                oneLineForm(v, vf, x: vx + 6, y: y + 1, w: w - 12, align: .center)
                vx += w
            }
            formBox(x: vx + noInfoW / 2 - 3.7, y: y + 2, checked: used && f.first("\(t): no information provided for compliance") == "Yes")
            y += 14
        }
        y += 4
    }

    private func oneLineForm(_ s: String, _ font: UIFont, x: CGFloat, y: CGFloat, w: CGFloat, align: NSTextAlignment = .left) {
        guard !s.isEmpty else { return }
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byTruncatingTail
        (s as NSString).draw(in: CGRect(x: x, y: y, width: max(w, 0), height: font.lineHeight + 1),
                             withAttributes: [.font: font, .foregroundColor: UIColor(hex: 0x10275E), .paragraphStyle: p])
    }

    /// The Opening Protection Level Chart: rows N/A, A, B, C, D, N, X × the six opening types, an X where the inspector
    /// rated that opening type at that level (`formTable: "q7"` items, in order). D applies to non-glazed openings only.
    private func openingProtectionChart(_ f: FormReportData, x: CGFloat, right: CGFloat) {
        let colQs = ["Windows or entry doors (glazed)", "Garage doors (glazed)", "Skylights", "Glass block",
                     "Entry doors (non-glazed)", "Garage doors (non-glazed)"]
        let colHeads = ["Windows or Entry Doors", "Garage Doors", "Skylights", "Glass Block", "Entry Doors", "Garage Doors"]
        let levelW: CGFloat = 24, colW: CGFloat = 40
        let descW = right - x - levelW - colW * 6
        let rows: [(String, String)] = [
            ("N/A", "Not Applicable\u{2011} there are no openings of this type on the structure"),
            ("A", "Verified cyclic pressure & large missile (9\u{2011}lb for windows doors/4.5 lb for skylights)"),
            ("B", "Verified cyclic pressure & large missile (4\u{2011}8 lb for windows doors/2 lb for skylights)"),
            ("C", "Verified plywood/OSB meeting Table 1609.1.2 of the FBC 2007"),
            ("D", "Verified Non\u{2011}Glazed Entry or Garage doors indicating compliance with ASTM E 330, ANSI/DASMA 108, or PA/TAS 202 for wind pressure resistance"),
            ("N", "Opening Protection products that appear to be A or B but are not verified\nOther protective coverings that cannot be identified as A, B, or C"),
            ("X", "No Windborne Debris Protection")
        ]
        let df = formFont(6.8), hf = formFont(6.8, bold: true)
        let rowHs = rows.map { max(measure($0.1, df, w: descW - 6, lineSpacing: 0) + 5, 13) }
        let head1: CGFloat = 12, head2: CGFloat = 29
        ensure(head1 + head2 + rowHs.reduce(0, +) + 12)
        y += 3
        let top = y
        let gx = x + levelW + descW
        text("Opening Protection Level Chart", formFont(8, bold: true), .black, x: x, y: y + 2, w: levelW + descW, align: .center, lineSpacing: 0)
        text("Glazed Openings", hf, .black, x: gx, y: y + 2, w: colW * 4, align: .center, lineSpacing: 0)
        text("Non\u{2011}Glazed Openings", hf, .black, x: gx + colW * 4, y: y + 2, w: colW * 2, align: .center, lineSpacing: 0)
        y += head1
        text("Place an \u{201C}X\u{201D} in each row to identify all forms of protection in use for each opening type. Check only one answer below (A thru X), based on the weakest form of protection (lowest row) for any of the Glazed openings and indicate the weakest form of protection (lowest row) for Non\u{2011}Glazed openings.",
             formFont(6.2), .black, x: x + 3, y: y + 1, w: levelW + descW - 6, lineSpacing: 0)
        for (i, h) in colHeads.enumerated() {
            text(h, formFont(6.4, bold: true), .black, x: gx + CGFloat(i) * colW + 1, y: y + 2, w: colW - 2, align: .center, lineSpacing: 0)
        }
        y += head2
        let levels = colQs.map { f.first($0) }
        for (r, row) in rows.enumerated() {
            let h = rowHs[r]
            text(row.0, formFont(7.2, bold: true), .black, x: x, y: y + h / 2 - 4.5, w: levelW, align: .center, lineSpacing: 0)
            text(row.1, df, .black, x: x + levelW + 3, y: y + 2.5, w: descW - 6, lineSpacing: 0)
            for c in 0..<6 {
                let cell = CGRect(x: gx + CGFloat(c) * colW, y: y, width: colW, height: h)
                if row.0 == "D" && c < 4 { fill(cell, UIColor(white: 0.78, alpha: 1)) }
                if levels[c] == row.0 {
                    text("X", formFont(9, bold: true), UIColor(hex: 0x10275E), x: cell.minX, y: cell.midY - 5.5, w: colW, align: .center, lineSpacing: 0)
                }
            }
            hline(y, x: x, w: right - x, .black, width: 0.5)
            y += h
        }
        hline(y, x: x, w: right - x, .black, width: 0.5)
        // grid verticals + outer frame
        stroke(CGRect(x: x, y: top, width: right - x, height: y - top), .black, width: 0.7)
        fill(CGRect(x: x + levelW, y: top + head1 + head2, width: 0.5, height: y - top - head1 - head2), .black)
        for c in 0...6 {
            let vx = gx + CGFloat(c) * colW
            fill(CGRect(x: vx, y: c == 0 || c == 4 || c == 6 ? top : top + head1, width: 0.5, height: y - (c == 0 || c == 4 || c == 6 ? top : top + head1)), .black)
        }
        hline(top + head1, x: gx, w: colW * 6, .black, width: 0.5)
        y += 6
    }

    // MARK: - Wood Destroying Insect Inspection Report (VIMS's own layout, not NPMA-33)

    func wdiReport(_ s: ReportSection, _ f: FormReportData) {
        newContentPage()
        let L = m, R = m + contentW
        let sz: CGFloat = 8.6
        text(f.def?.title ?? "Wood Destroying Insect Inspection Report", VFont.uDisplay(15, .heavy), ink, x: L, y: y, w: contentW)
        y += 21
        text("\(s.title) · prepared by \(d.companyName)", VFont.uUI(9), ink3, x: L, y: y, w: contentW)
        y += 20

        func band(_ t: String) {
            ensure(34)
            y += 6
            fill(CGRect(x: L, y: y, width: contentW, height: 18), paper2, radius: 4)
            fill(CGRect(x: L, y: y, width: 2.5, height: 18), brand)
            text(t, VFont.uDisplay(9.5, .bold), brandDeep, x: L + 10, y: y + 3.5, w: contentW - 20)
            y += 24
        }
        func pair(_ a: (String, String), _ b: (String, String)?) {
            let colW = (contentW - 16) / 2
            let ha = max(measure(a.1.isEmpty ? "—" : a.1, VFont.uUI(9, .semibold), w: colW), 11)
            let hb = b.map { max(measure($0.1.isEmpty ? "—" : $0.1, VFont.uUI(9, .semibold), w: colW), 11) } ?? 0
            let h = 12 + max(ha, hb) + 6
            ensure(h)
            text(a.0.uppercased(), VFont.uUI(6.8, .bold), ink3, x: L, y: y, w: colW)
            text(a.1.isEmpty ? "—" : a.1, VFont.uUI(9, .semibold), ink, x: L, y: y + 10, w: colW)
            if let b {
                text(b.0.uppercased(), VFont.uUI(6.8, .bold), ink3, x: L + colW + 16, y: y, w: colW)
                text(b.1.isEmpty ? "—" : b.1, VFont.uUI(9, .semibold), ink, x: L + colW + 16, y: y + 10, w: colW)
            }
            y += h
            hline(y - 3, x: L, w: contentW, line2)
        }

        band("Section I. General Information")
        let companyAddress = d.companyAddressLines.joined(separator: ", ")
        pair(("Inspection company", d.companyName), ("Company address & phone", [companyAddress, d.companyPhone].filter { !$0.isEmpty }.joined(separator: " · ")))
        pair(("Inspector", d.inspector), ("Inspector license #", d.license))
        pair(("Company business license no.", f.text("Company business license no.")), ("Date of inspection", f.inspectionDate))
        pair(("Address of property inspected", f.propertyAddress), ("Structure(s) inspected", f.text("Structure(s) inspected")))

        band("Section II. Inspection Findings")
        let findings = f.first("Findings") ?? ""
        let a = "A. No visible evidence of wood destroying insects was observed."
        let b = "B. Visible evidence of wood destroying insects was observed as follows:"
        formOption(findings == a, [.b("A. "), .t("No visible evidence of wood destroying insects was observed.")], x: L, right: R, size: sz, gap: 4)
        formOption(findings == b, [.b("B. "), .t("Visible evidence of wood destroying insects was observed as follows:")], x: L, right: R, size: sz, gap: 3)
        let subs = ["1. Live insects (description and location)",
                    "2. Dead insects, insect parts, frass, shelter tubes, exit holes, or staining (description and location)",
                    "3. Visible damage from wood destroying insects (description and location)"]
        for q in subs {
            formPara([.t(q + ": "), .v(findings == b ? f.text(q) : "", blank: 24)], x: L + 24, right: R, size: sz, gap: 3)
        }
        y += 3
        let treated = f.first("Structure(s) appear to have been previously treated")
        formPara([.b("Structure(s) appear to have been previously treated:  ")], x: L, right: R, size: sz, gap: 2)
        let rowY = y
        formBox(x: L + 24, y: rowY + 1.2, checked: treated == "Yes")
        text("Yes", formFont(sz), .black, x: L + 36, y: rowY, w: 40, lineSpacing: 0)
        formBox(x: L + 76, y: rowY + 1.2, checked: treated == "No")
        text("No", formFont(sz), .black, x: L + 88, y: rowY, w: 40, lineSpacing: 0)
        y += 14
        if treated == "Yes" {
            formPara([.t("Visible evidence of possible previous treatment: "), .v(f.text("Visible evidence of possible previous treatment"), blank: 24)],
                     x: L + 24, right: R, size: sz, gap: 3)
        }

        band("Section III. Recommendations")
        let rec = f.first("Recommendation")
        formOption(rec == "No treatment recommended", [.b("No treatment recommended. "), .t("Explanation (if Section II box B is checked): "),
                                                       .v(rec == "No treatment recommended" ? f.text("Explanation (required if Section II box B is checked)") : "", blank: 20)],
                   x: L, right: R, size: sz, gap: 4)
        formOption(rec == "Recommend treatment", [.b("Recommend treatment "), .t("for the control of: "),
                                                  .v(rec == "Recommend treatment" ? f.text("Recommend treatment for the control of") : "", blank: 30)],
                   x: L, right: R, size: sz, gap: 4)

        band("Section IV. Obstructions and Inaccessible Areas")
        let areas = ["Basement", "Crawlspace", "Main level", "Attic", "Garage", "Exterior", "Porch", "Addition", "Other"]
        let rows = areas.compactMap { area -> (String, String)? in
            let v = f.text("\(area) \u{2014} obstructed or inaccessible")
            return v.isEmpty ? nil : (area, v)
        }
        if rows.isEmpty {
            formPara([.t("No obstructed or inaccessible areas were noted.")], x: L, right: R, size: sz, gap: 4)
        } else {
            let aw: CGFloat = 110
            ensure(18)
            text("AREA", VFont.uUI(6.8, .bold), ink3, x: L + 4, y: y, w: aw)
            text("OBSTRUCTION / INACCESSIBLE", VFont.uUI(6.8, .bold), ink3, x: L + aw + 8, y: y, w: contentW - aw - 12)
            y += 12
            hline(y, x: L, w: contentW, line)
            for (area, v) in rows {
                let h = max(measure(v, VFont.uUI(9), w: contentW - aw - 12), 11) + 9
                ensure(h)
                text(area, VFont.uUI(9, .semibold), ink, x: L + 4, y: y + 4.5, w: aw)
                text(v, VFont.uUI(9), ink2, x: L + aw + 8, y: y + 4.5, w: contentW - aw - 12)
                y += h
                hline(y - 0.6, x: L, w: contentW, line2)
            }
            y += 4
        }

        band("Section V. Additional Comments and Attachments")
        let comments = f.text("Additional comments"), attach = f.text("Attachments")
        formPara([.b("Comments: "), .t(comments.isEmpty ? "None." : comments)], x: L, right: R, size: sz, gap: 3)
        formPara([.b("Attachments: "), .t(attach.isEmpty ? "None." : attach)], x: L, right: R, size: sz, gap: 10)

        // Signature lines stay blank (seller / owner and buyer acknowledge receipt).
        ensure(60)
        let half = (contentW - 24) / 2
        for (i, who) in ["Signature of seller(s) or owner(s) if refinancing", "Signature of buyer(s)"].enumerated() {
            let x = L + CGFloat(i) * (half + 24)
            hline(y + 18, x: x, w: half - 70, .black, width: 0.6)
            hline(y + 18, x: x + half - 60, w: 60, .black, width: 0.6)
            text(who, VFont.uUI(7.2), ink3, x: x, y: y + 21, w: half - 70)
            text("Date", VFont.uUI(7.2), ink3, x: x + half - 60, y: y + 21, w: 60)
        }
        y += 34
        // The report's one neutral line (formReports.wdi.layout) — not NPMA's consumer text.
        let line = "This report reflects a visual inspection of readily accessible areas on the date of inspection and is not a guarantee or warranty against latent, concealed or future infestations or damage."
        ensure(measure(line, VFont.uUI(7.8), w: contentW) + 4)
        y += text(line, VFont.uUI(7.8), ink3, x: L, y: y, w: contentW)
    }
}
