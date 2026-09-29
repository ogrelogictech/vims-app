import UIKit

// Texas (TREC REI 7-6) and 4-Point report pages — see report.html?type=texas and ?type=4point
// and `reportLayouts` in the shared JSON. Content comes from the inspection's form sections;
// only the promulgated/form boilerplate text lives here.

extension ReportRenderer.Writer {

    // MARK: - Texas: TREC form page 1 (inspector & property information)

    func trecInfoPage() {
        headerless = true
        onPageBreak = nil
        newContentPage()
        text("PROPERTY INSPECTION REPORT FORM", VFont.uDisplay(11.5, .heavy), ink, x: m, y: y, w: contentW, align: .center)
        y += 22

        let gap: CGFloat = 12
        let wide = (contentW - gap) * 1.6 / 2.6, narrow = contentW - gap - wide
        func cell(_ label: String, _ value: String, x: CGFloat, w: CGFloat) {
            text(label, VFont.uUI(6.8), ink3, x: x, y: y, w: w)
            text(value.isEmpty ? " " : value, VFont.uUI(8.2), ink, x: x, y: y + 9, w: w)
            hline(y + 21, x: x, w: w, ink, width: 0.6)
        }
        let rowH: CGFloat = 27
        cell("Name of Client", d.clientName, x: m, w: wide)
        cell("Date of Inspection", d.date, x: m + wide + gap, w: narrow)
        y += rowH
        cell("Address of Inspected Property", [d.addressLine1, d.addressRest].filter { !$0.isEmpty }.joined(separator: ", "), x: m, w: contentW)
        y += rowH
        cell("Name of Inspector", d.inspector, x: m, w: wide)
        cell("TREC License #", d.license, x: m + wide + gap, w: narrow)
        y += rowH
        cell("Name of Sponsor (if applicable)", d.sponsorName.isEmpty ? "N/A" : d.sponsorName, x: m, w: wide)
        cell("TREC License #", d.sponsorLicense, x: m + wide + gap, w: narrow)
        y += rowH + 6

        for p in Self.trecParagraphs { trecParagraph(p) }
    }

    struct TrecParagraph {
        var title: String? = nil
        var lead: String? = nil
        var body: String? = nil
        var bullets: [String] = []
    }

    /// Promulgated TREC REI 7-6 text, exactly as in report.html.
    static let trecParagraphs: [TrecParagraph] = [
        TrecParagraph(title: "PURPOSE OF INSPECTION",
                      body: "A real estate inspection is a visual survey of a structure and a basic performance evaluation of the systems and components of a building. It provides information regarding the general condition of a residence at the time the inspection was conducted. It is important that you carefully read ALL of this information. Ask the inspector to clarify any items or comments that are unclear."),
        TrecParagraph(title: "RESPONSIBILITY OF THE INSPECTOR",
                      body: "This inspection is governed by the Texas Real Estate Commission (TREC) Standards of Practice (SOPs), which dictates the minimum requirements for a real estate inspection."),
        TrecParagraph(body: "The inspector IS required to:",
                      bullets: ["use this Property Inspection Report form for the inspection;",
                                "inspect only those components and conditions that are present, visible, and accessible at the time of the inspection;",
                                "indicate whether each item was inspected, not inspected, or not present;",
                                "indicate an item as Deficient (D) if a condition exists that adversely and materially affects the performance of a system or component OR constitutes a hazard to life, limb or property as specified by the SOPs; and",
                                "explain the inspector’s findings in the corresponding section in the body of the report form."]),
        TrecParagraph(body: "The inspector IS NOT required to:",
                      bullets: ["identify all potential hazards;",
                                "turn on decommissioned equipment, systems, utilities, or apply an open flame or light a pilot to operate any appliance;",
                                "climb over obstacles, move furnishings or stored items;",
                                "prioritize or emphasize the importance of one deficiency over another;",
                                "provide follow-up services to verify that proper repairs have been made; or",
                                "inspect system or component listed under the optional section of the SOPs (22 TAC 535.233)."]),
        TrecParagraph(title: "RESPONSIBILITY OF THE CLIENT",
                      body: "While items identified as Deficient (D) in an inspection report DO NOT obligate any party to make repairs or take other actions, in the event that any further evaluations are needed, it is the responsibility of the client to obtain further evaluations and/or cost estimates from qualified service professionals regarding any items reported as Deficient (D). It is recommended that any further evaluations and/or cost estimates take place prior to the expiration of any contractual time limitations, such as option periods."),
        TrecParagraph(lead: "Please Note:",
                      body: "Evaluations performed by service professionals in response to items reported as Deficient (D) on the report may lead to the discovery of additional deficiencies that were not present, visible, or accessible at the time of the inspection. Any repairs made after the date of the inspection may render information contained in this report obsolete or invalid."),
        TrecParagraph(title: "REPORT LIMITATIONS",
                      body: "This report is provided for the benefit of the named client and is based on observations made by the named inspector on the date the inspection was performed (indicated above). ONLY those items specifically noted as being inspected on the report were inspected. This inspection IS NOT:",
                      bullets: ["a technically exhaustive inspection of the structure, its systems, or its components and may not reveal all deficiencies;",
                                "an inspection to verify compliance with any building codes;",
                                "an inspection to verify compliance with manufacturer’s installation instructions for any system or component and DOES NOT imply insurability or warrantability of the structure or its components."])
    ]

    private func trecParagraph(_ p: TrecParagraph) {
        let bodyFont = VFont.uUI(7.4), boldFont = VFont.uUI(7.7, .bold)
        let ps = NSMutableParagraphStyle(); ps.lineSpacing = 2.2
        let a = NSMutableAttributedString()
        if let t = p.title { a.append(NSAttributedString(string: t + "\n", attributes: [.font: boldFont, .foregroundColor: ink, .paragraphStyle: ps])) }
        if let l = p.lead { a.append(NSAttributedString(string: l + " ", attributes: [.font: boldFont, .foregroundColor: ink, .paragraphStyle: ps])) }
        if let b = p.body { a.append(NSAttributedString(string: b, attributes: [.font: bodyFont, .foregroundColor: ink, .paragraphStyle: ps])) }
        let h = ceil(a.boundingRect(with: CGSize(width: contentW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        ensure(h + 4)
        a.draw(with: CGRect(x: m, y: y, width: contentW, height: h + 2), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += h + 2
        for b in p.bullets {
            let bh = measure(b, bodyFont, w: contentW - 16, lineSpacing: 2.2)
            ensure(bh + 2)
            text("•", bodyFont, ink, x: m + 6, y: y, w: 8)
            text(b, bodyFont, ink, x: m + 16, y: y, w: contentW - 16, lineSpacing: 2.2)
            y += bh + 1.5
        }
        y += 5
    }

    // MARK: - Texas: checklist pages (I / NI / NP / D)

    private var boxW: CGFloat { 18.6 }
    private var trecGrid: UIColor { UIColor(hex: 0x9AA5B1) }

    private func trecPageTop(_ title: String) {
        let lbl = NSMutableAttributedString(string: "Report Identification: ", attributes: [.font: VFont.uUI(8, .bold), .foregroundColor: ink])
        lbl.append(NSAttributedString(string: [d.addressLine1, d.addressRest].filter { !$0.isEmpty }.joined(separator: ", "),
                                      attributes: [.font: VFont.uUI(8), .foregroundColor: ink2]))
        lbl.draw(with: CGRect(x: m, y: y, width: contentW, height: 12), options: [.usesLineFragmentOrigin], context: nil)
        y += 14
        hline(y, x: m, w: contentW, ink, width: 0.8)
        y += 5
        text("I=Inspected    NI=Not Inspected    NP=Not Present    D=Deficient", VFont.uUI(7.6, .bold), ink, x: m, y: y, w: contentW)
        y += 14
        for (i, code) in ["I", "NI", "NP", "D"].enumerated() {
            let r = CGRect(x: m + CGFloat(i) * boxW, y: y, width: boxW, height: 12)
            fill(r, paper2)
            stroke(r, trecGrid, width: 0.7)
            text(code, VFont.uUI(7, .bold), ink, x: r.minX, y: r.minY + 2, w: boxW, align: .center)
        }
        y += 18
        text(title, VFont.uDisplay(9.4, .heavy), ink, x: m, y: y, w: contentW)
        y += 14
        hline(y, x: m, w: contentW, line, width: 0.7)
        y += 4
    }

    func trecChecklist(_ f: FormSectionData) {
        headerless = true
        let sysTitle = f.title.uppercased()
        onPageBreak = nil
        newContentPage()
        trecPageTop(sysTitle)
        onPageBreak = { [unowned self] in self.trecPageTop(sysTitle + " (continued)") }

        let itemX = m + 4 * boxW
        let itemW = contentW - 4 * boxW - 8
        for g in f.groups {
            guard let title = g.title else { continue }
            var marks = [false, false, false, false]
            var fields: [(String, String)] = []
            var comments = ""
            for r in g.rows {
                if r.q == "Status" {
                    for sel in r.selected {
                        if let i = r.options.firstIndex(of: sel), i < 4 { marks[i] = true }
                    }
                } else if r.q.lowercased() == "comments" {
                    comments = r.text
                } else if !r.selected.isEmpty {
                    fields.append((r.q, r.selected.joined(separator: ", ")))
                } else {
                    fields.append((r.q, r.text))
                }
            }
            let para = NSMutableAttributedString()
            let ps = NSMutableParagraphStyle(); ps.lineSpacing = 1.6; ps.paragraphSpacing = 1.5
            para.append(NSAttributedString(string: title, attributes: [.font: VFont.uUI(8.3, .bold), .foregroundColor: ink, .paragraphStyle: ps]))
            for (k, v) in fields {
                para.append(NSAttributedString(string: "\n\(k): \(v)", attributes: [.font: VFont.uUI(7.8), .foregroundColor: ink2, .paragraphStyle: ps]))
            }
            para.append(NSAttributedString(string: "\nComments: ", attributes: [.font: VFont.uUI(7.8), .foregroundColor: ink3, .paragraphStyle: ps]))
            para.append(NSAttributedString(string: comments, attributes: [.font: VFont.uUI(7.8), .foregroundColor: ink, .paragraphStyle: ps]))
            let th = ceil(para.boundingRect(with: CGSize(width: itemW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            let rowH = max(18, th + 9)
            ensure(rowH)
            for i in 0..<4 {
                let r = CGRect(x: m + CGFloat(i) * boxW, y: y, width: boxW, height: rowH)
                stroke(r, trecGrid, width: 0.7)
                if marks[i] { text("✓", VFont.uUI(9, .bold), ink, x: r.minX, y: r.minY + 3, w: boxW, align: .center) }
            }
            para.draw(with: CGRect(x: itemX + 7, y: y + 4.5, width: itemW, height: th + 2), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            hline(y + rowH - 0.6, x: itemX, w: contentW - 4 * boxW, line2)
            y += rowH
        }
        onPageBreak = nil
    }

    // MARK: - Pictures pages (Texas + 4-Point): 3 columns, 6 per page

    func picturePages() {
        headerless = false
        onPageBreak = nil
        var first = true
        func top() {
            newContentPage()
            let r = CGRect(x: m, y: y, width: contentW, height: 28)
            fill(r, brand, radius: 7)
            fill(CGRect(x: m + 10, y: y + 6, width: 26, height: 16), UIColor.white.withAlphaComponent(0.2), radius: 5)
            text("📷", VFont.uUI(9), .white, x: m + 10, y: y + 7, w: 26, align: .center)
            text(first ? "Pictures" : "Pictures (continued)", VFont.uDisplay(12, .bold), .white, x: m + 46, y: y + 6.5, w: contentW - 60)
            y += 40
            first = false
        }
        top()
        if d.pictures.isEmpty {
            note("No pictures were added.")
            return
        }
        let cols = 3, gap: CGFloat = 12
        let cw = (contentW - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let ih = cw * 0.75
        let capH: CGFloat = 26
        for (i, p) in d.pictures.enumerated() {
            let idxOnPage = i % 6
            if i > 0 && idxOnPage == 0 { top() }
            let col = idxOnPage % cols, row = idxOnPage / cols
            let x = m + CGFloat(col) * (cw + gap)
            let yy = y + CGFloat(row) * (ih + capH + gap)
            let card = CGRect(x: x, y: yy, width: cw, height: ih + capH)
            fill(card, .white, radius: 6)
            if let img = loadImage(p.url, maxPixel: 700) {
                cg.saveGState()
                UIBezierPath(roundedRect: CGRect(x: x, y: yy, width: cw, height: ih), byRoundingCorners: [.topLeft, .topRight],
                             cornerRadii: CGSize(width: 6, height: 6)).addClip()
                image(img, fill: CGRect(x: x, y: yy, width: cw, height: ih))
                cg.restoreGState()
            } else {
                fill(CGRect(x: x, y: yy, width: cw, height: ih), paper2)
            }
            if p.flag != nil {
                fill(CGRect(x: x + 6, y: yy + 6, width: 52, height: 14), UIColor(hex: 0xD0584A), radius: 7)
                text("Deficiency", VFont.uUI(6.8, .bold), .white, x: x + 6, y: yy + 7.8, w: 52, align: .center)
            }
            text(p.caption, VFont.uUI(7.6), ink2, x: x + 7, y: yy + ih + 5, w: cw - 14)
            stroke(card, line, radius: 6)
        }
    }

    // MARK: - 4-Point form (gray-banded boxes with checkboxes + certification)

    private var fpBand: UIColor { UIColor(hex: 0xAAA5A1) }
    private var fpBorder: UIColor { UIColor(hex: 0x555555) }

    func fourPointForm() {
        headerless = false
        onPageBreak = nil
        newContentPage()
        for (i, f) in d.formSections.enumerated() {
            if i > 0 { y += 12 }
            let sub = f.title.lowercased().contains("electrical")
                ? "Separate documentation of any aluminum wiring remediation must be provided and certified by a licensed electrician." : nil
            fpSection(f, subtitle: sub)
        }
        fpCertification()
    }

    private func fpSection(_ f: FormSectionData, subtitle: String?) {
        // Pair consecutive groups with identical questions (Main/Second Panel, Predominant/Secondary Roof) side by side.
        var blocks: [(FormSectionData.Group, FormSectionData.Group?)] = []
        var i = 0
        while i < f.groups.count {
            let g = f.groups[i]
            if i + 1 < f.groups.count, g.title != nil, f.groups[i + 1].title != nil,
               g.rows.map(\.q) == f.groups[i + 1].rows.map(\.q), !g.rows.isEmpty {
                blocks.append((g, f.groups[i + 1])); i += 2
            } else {
                blocks.append((g, nil)); i += 1
            }
        }
        // band (kept with the first box)
        let bandFont = VFont.uDisplay(10.5, .heavy)
        let subH = subtitle.map { measure($0, VFont.uUI(7.2), w: contentW - 16) + 2 } ?? 0
        let bandH: CGFloat = 20 + subH
        let firstH = blocks.first.map { blockHeight($0.0, $0.1) } ?? 0
        ensure(bandH + firstH)
        func band(_ title: String, _ sub: String?, _ h: CGFloat) {
            let br = CGRect(x: m, y: y, width: contentW, height: h)
            fill(br, fpBand)
            stroke(br, fpBorder, width: 0.8)
            text(title, bandFont, UIColor(hex: 0x111111), x: m + 8, y: y + 4, w: contentW - 16)
            if let sub { text(sub, VFont.uUI(7.2), UIColor(hex: 0x111111), x: m + 8, y: y + 17, w: contentW - 16) }
            y += h
        }
        band(f.title, subtitle, bandH)
        onPageBreak = { [unowned self] in band(f.title + " (continued)", nil, 20); _ = self }
        for (a, b) in blocks { fpBlock(a, b) }
        onPageBreak = nil
    }

    private func fpParagraph(_ g: FormSectionData.Group) -> NSAttributedString {
        let s = NSMutableAttributedString()
        let ps = NSMutableParagraphStyle(); ps.lineSpacing = 2.4; ps.paragraphSpacing = 1.5
        let reg: [NSAttributedString.Key: Any] = [.font: VFont.uUI(7.8), .foregroundColor: ink, .paragraphStyle: ps]
        let bold: [NSAttributedString.Key: Any] = [.font: VFont.uUI(7.9, .bold), .foregroundColor: ink, .paragraphStyle: ps]
        let val: [NSAttributedString.Key: Any] = [.font: VFont.uUI(7.8, .semibold), .foregroundColor: ink, .paragraphStyle: ps,
                                                  .underlineStyle: NSUnderlineStyle.single.rawValue]
        var first = true
        func nl() { if !first { s.append(NSAttributedString(string: "\n", attributes: reg)) }; first = false }
        if let t = g.title { nl(); s.append(NSAttributedString(string: t, attributes: bold)) }
        for r in g.rows {
            nl()
            switch r.kind {
            case .single, .multi:
                let label = r.q.hasSuffix("?") || r.q.hasSuffix(":") ? r.q + " " : r.q + ": "
                s.append(NSAttributedString(string: label, attributes: reg))
                for (j, o) in r.options.enumerated() {
                    let on = r.selected.contains(o)
                    s.append(Self.checkbox(on, font: VFont.uUI(7.8), paragraph: ps))
                    s.append(NSAttributedString(string: "\u{00A0}", attributes: reg))
                    s.append(NSAttributedString(string: o.replacingOccurrences(of: " ", with: "\u{00A0}") + (j < r.options.count - 1 ? "   " : ""), attributes: reg))
                }
            default:
                if let t = g.title, r.q.lowercased() == t.lowercased() {
                    s.append(NSAttributedString(string: r.text.isEmpty ? " " : r.text, attributes: reg))
                } else {
                    s.append(NSAttributedString(string: r.q + ": ", attributes: reg))
                    s.append(NSAttributedString(string: r.text.isEmpty ? "\u{00A0}\u{00A0}\u{00A0}\u{00A0}\u{00A0}\u{00A0}\u{00A0}\u{00A0}\u{00A0}\u{00A0}\u{00A0}\u{00A0}"
                                                                 : "\u{00A0}\(r.text)\u{00A0}", attributes: val))
                }
            }
        }
        return s
    }

    /// Form checkbox (.ck in report.html) as an inline image — the ☐/☑ glyphs fall back to emoji.
    static func checkbox(_ on: Bool, font: UIFont, paragraph: NSParagraphStyle) -> NSAttributedString {
        let side: CGFloat = 7.6
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 4
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { ctx in
            let r = CGRect(x: 0.4, y: 0.4, width: side - 0.8, height: side - 0.8)
            UIColor(hex: 0x333333).setStroke()
            let box = UIBezierPath(rect: r); box.lineWidth = 0.7; box.stroke()
            if on {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 1.5, y: side * 0.52))
                p.addLine(to: CGPoint(x: side * 0.42, y: side - 1.6))
                p.addLine(to: CGPoint(x: side - 1.2, y: 1.4))
                p.lineWidth = 1.2; p.lineCapStyle = .round; p.lineJoinStyle = .round
                UIColor(hex: 0x17222E).setStroke(); p.stroke()
            }
        }
        let att = NSTextAttachment()
        att.image = img
        att.bounds = CGRect(x: 0, y: font.descender + 0.8, width: side, height: side)
        let a = NSMutableAttributedString(attachment: att)
        a.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: a.length))
        return a
    }

    private func paraHeight(_ a: NSAttributedString, _ w: CGFloat) -> CGFloat {
        ceil(a.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    private func blockHeight(_ a: FormSectionData.Group, _ b: FormSectionData.Group?) -> CGFloat {
        let pad: CGFloat = 7
        if let b {
            let cw = (contentW - 20 - 18) / 2
            return max(paraHeight(fpParagraph(a), cw), paraHeight(fpParagraph(b), cw)) + pad * 2
        }
        let minH: CGFloat = (a.title ?? "").lowercased().contains("comment") ? 44 : 0
        return max(minH, paraHeight(fpParagraph(a), contentW - 20) + pad * 2)
    }

    private func fpBlock(_ a: FormSectionData.Group, _ b: FormSectionData.Group?) {
        let h = blockHeight(a, b)
        ensure(h)
        let r = CGRect(x: m, y: y, width: contentW, height: h)
        if (a.title ?? "").lowercased().contains("supplemental") { fill(r, UIColor(hex: 0xECECEC)) }
        stroke(r, fpBorder, width: 0.8)
        if let b {
            let cw = (contentW - 20 - 18) / 2
            fpParagraph(a).draw(with: CGRect(x: m + 10, y: y + 7, width: cw, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            fpParagraph(b).draw(with: CGRect(x: m + 10 + cw + 18, y: y + 7, width: cw, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        } else {
            fpParagraph(a).draw(with: CGRect(x: m + 10, y: y + 7, width: contentW - 20, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        y += h
    }

    private func fpCertification() {
        let cells: [(String, String)] = [
            (d.inspector, "Inspector Signature"), ("Home Inspector", "Title"), (d.license, "License Number"), (d.date, "Date"),
            (d.companyName, "Company Name"), ("Home Inspector", "License Type"), (d.companyPhone, "Work Phone")
        ]
        let h: CGFloat = 24 + 2 * 40
        y += 12
        ensure(h)
        let r = CGRect(x: m, y: y, width: contentW, height: h)
        stroke(r, fpBorder, width: 0.8)
        text("I certify that the above statements are true and correct.",
             UIFont(descriptor: VFont.uUI(8).fontDescriptor.withSymbolicTraits(.traitItalic) ?? VFont.uUI(8).fontDescriptor, size: 8),
             ink, x: m + 10, y: y + 8, w: contentW - 20)
        let colW = (contentW - 20 - 3 * 14) / 4
        for (i, c) in cells.enumerated() {
            let col = i % 4, row = i / 4
            let x = m + 10 + CGFloat(col) * (colW + 14)
            let cy = y + 26 + CGFloat(row) * 40
            text(c.0.isEmpty ? " " : c.0, VFont.uUI(8.4, .semibold), ink, x: x, y: cy + 4, w: colW)
            hline(cy + 18, x: x, w: colW, UIColor(hex: 0x333333), width: 0.7)
            text(c.1, VFont.uUI(7.2), ink2, x: x, y: cy + 21, w: colW)
        }
        y += h
    }
}
