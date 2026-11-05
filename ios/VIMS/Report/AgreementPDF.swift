import UIKit
import CoreText

/// "Download" in the inspection-agreement viewer: the same blocks the viewer shows (AgreementContent — VIMS or the
/// company's edited version, `{companyName}` filled), laid out as a clean, paginated US Letter PDF with a page footer.
/// Text flows across pages with one NSLayoutManager and a text container per page, so long paragraphs split cleanly.
enum AgreementPDF {
    static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 54
    private static let footerHeight: CGFloat = 26

    // Report palette (ReportRenderer.Writer).
    private static let ink = UIColor(hex: 0x17222E), ink2 = UIColor(hex: 0x3F4E5E), ink3 = UIColor(hex: 0x5F6D7D)
    private static let brandDeep = UIColor(hex: 0x1E3D94), line = UIColor(hex: 0xDDE5EE)

    /// Writes the PDF to a temporary file named "Inspection-Agreement-<Company-Name>.pdf" (the name the share
    /// sheet / Files / Mail use). Nil if it couldn't be written.
    /// `fileName` (filled agreement, data v1.15): "Inspection-Agreement-<Client-Name>.pdf".
    static func write(_ content: AgreementContent, company: String, fileName: String? = nil) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName ?? AgreementContent.fileName(company: company))
        try? FileManager.default.removeItem(at: url)
        do { try render(content, company: company).pdf.write(to: url, options: .atomic); return url } catch { return nil }
    }

    static func render(_ content: AgreementContent, company: String) -> (pdf: Data, pageCount: Int) {
        let textRect = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2,
                              height: pageSize.height - margin * 2 - footerHeight)
        let storage = NSTextStorage(attributedString: attributed(content))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        // One container per page until every glyph is placed (capped, in case of a pathological layout).
        var pages: [NSTextContainer] = []
        while pages.count < 400 {
            let tc = NSTextContainer(size: textRect.size)
            tc.lineFragmentPadding = 0
            layout.addTextContainer(tc)
            let range = layout.glyphRange(for: tc)
            if range.length == 0 { layout.removeTextContainer(at: layout.textContainers.count - 1); break }
            pages.append(tc)
            if NSMaxRange(range) >= layout.numberOfGlyphs { break }
        }

        let fmt = UIGraphicsPDFRendererFormat()
        fmt.documentInfo = [
            kCGPDFContextTitle as String: "\(content.title) — \(company)",
            kCGPDFContextAuthor as String: company,
            kCGPDFContextCreator as String: "VIMS"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: fmt)
        let total = max(pages.count, 1)
        let data = renderer.pdfData { ctx in
            if pages.isEmpty { ctx.beginPage(); footer(page: 1, of: 1, company: company) }
            for (i, tc) in pages.enumerated() {
                ctx.beginPage()
                let range = layout.glyphRange(for: tc)
                layout.drawBackground(forGlyphRange: range, at: textRect.origin)
                layout.drawGlyphs(forGlyphRange: range, at: textRect.origin)
                drawBoxes(layout: layout, storage: storage, glyphs: range, origin: textRect.origin)
                footer(page: i + 1, of: total, company: company)
            }
        }
        return (data, total)
    }

    /// Client Nov 4 (`_boxDrawing`): the ☐ / ☒ characters stay in the text (invisible, so copy and search still find them) and
    /// each box is drawn as a shape over its place: outlined when empty, a solid dark square with a white X when ticked, so a
    /// tick is obvious at a glance and in a black-and-white print.
    private static func drawBoxes(layout: NSLayoutManager, storage: NSTextStorage, glyphs: NSRange, origin: CGPoint) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(boxSizeKey, in: chars) { value, range, _ in
            guard let textSize = (value as? NSNumber).map({ CGFloat($0.doubleValue) }) else { return }
            let glyph = layout.glyphIndexForCharacter(at: range.location)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let place = layout.location(forGlyphAt: glyph)
            let baseline = fragment.minY + place.y
            let side = boxSide(textSize)
            let box = CGRect(x: origin.x + fragment.minX + place.x, y: origin.y + baseline - textSize * 0.36 - side / 2, width: side, height: side)
            let ticked = (storage.string as NSString).character(at: range.location) == 0x2612
            let path = UIBezierPath(roundedRect: box, cornerRadius: side * 0.14)
            cg.saveGState()
            if ticked {
                ink.setFill()
                path.fill()
                let x = box.insetBy(dx: side * 0.24, dy: side * 0.24)
                let cross = UIBezierPath()
                cross.move(to: CGPoint(x: x.minX, y: x.minY)); cross.addLine(to: CGPoint(x: x.maxX, y: x.maxY))
                cross.move(to: CGPoint(x: x.maxX, y: x.minY)); cross.addLine(to: CGPoint(x: x.minX, y: x.maxY))
                cross.lineWidth = max(1, side * 0.15)
                cross.lineCapStyle = .round
                UIColor.white.setStroke()
                cross.stroke()
            } else {
                ink2.setStroke()
                path.lineWidth = 0.75
                path.stroke()
            }
            cg.restoreGState()
        }
    }

    private static func boxSide(_ textSize: CGFloat) -> CGFloat { textSize * 1.1 }

    /// Marks a box character in the text, with the size of the text around it.
    private static let boxSizeKey = NSAttributedString.Key("vimsBoxTextSize")

    private static func footer(page: Int, of total: Int, company: String) {
        let y = pageSize.height - margin + 4
        line.setFill()
        UIRectFill(CGRect(x: margin, y: y - 8, width: pageSize.width - margin * 2, height: 0.6))
        // "<Company> · Inspection Agreement · Page x of n" (same footer as Android).
        let s = NSAttributedString(string: "\(company) \u{00B7} Inspection Agreement \u{00B7} Page \(page) of \(total)",
                                   attributes: [.font: VFont.uUI(8.5), .foregroundColor: ink3])
        s.draw(with: CGRect(x: margin, y: y, width: pageSize.width - margin * 2, height: 14),
               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    // MARK: - Attributed text

    private static func attributed(_ content: AgreementContent) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = VFont.uUI(10.5)

        func style(before: CGFloat = 0, after: CGFloat = 7, indent: CGFloat = 0, lineSpacing: CGFloat = 2.2) -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            p.lineSpacing = lineSpacing
            p.headIndent = indent
            if indent > 0 { p.tabStops = [NSTextTab(textAlignment: .left, location: indent)]; p.defaultTabInterval = indent }
            return p
        }
        // Filled-in values (data v1.15) are bold in ink; ☐ / ☒ only hold the place of the drawn boxes (`drawBoxes`).
        func add(_ s: String, _ font: UIFont, _ color: UIColor, _ p: NSParagraphStyle, bold: UIFont? = nil) {
            let line = NSMutableAttributedString()
            for seg in AgreementFill.segments(s + "\n") {
                switch seg.kind {
                case .plain: line.append(NSAttributedString(string: seg.text, attributes: [.font: font, .foregroundColor: color]))
                case .bold: line.append(NSAttributedString(string: seg.text, attributes: [.font: bold ?? font, .foregroundColor: ink]))
                case .box:
                    // Kerned so the character's width is the drawn box plus a hair, keeping the spaces around it clear.
                    let f = BoxGlyphFont.font(for: font)
                    let width = (seg.text as NSString).size(withAttributes: [.font: f]).width
                    line.append(NSAttributedString(string: seg.text, attributes: [.font: f, .foregroundColor: UIColor.clear, .kern: boxSide(font.pointSize) + 0.5 - width,
                                                                                  boxSizeKey: NSNumber(value: Double(font.pointSize))]))
                }
            }
            line.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: line.length))
            out.append(line)
        }

        for b in content.blocks {
            switch b {
            case .title(let t):
                add(t, VFont.uDisplay(19, .heavy), ink, style(after: 12, lineSpacing: 1))
            case .form(let lines):
                // Form lines keep their own line breaks (line separators, so they stay one block).
                // Fixed line height, so lines with the (slightly larger) boxes keep the same rhythm as the others.
                let p = style(before: 2, after: 12, lineSpacing: 4.5)
                p.minimumLineHeight = ceil(VFont.uMono(8.6).lineHeight); p.maximumLineHeight = p.minimumLineHeight
                add(lines.joined(separator: "\u{2028}"), VFont.uMono(8.6), ink2, p, bold: VFont.uMono(8.6, .semibold))
            case .paragraph(let t, let lead):
                add(t.replacingOccurrences(of: "\n", with: "\u{2028}"), lead ? VFont.uUI(10.5, .semibold) : body, lead ? ink : ink2, style(),
                    bold: VFont.uUI(10.5, .bold))
            case .bullet(let t):
                add("\u{2022}\t" + t, body, ink2, style(after: 5, indent: 14), bold: VFont.uUI(10.5, .bold))
            case .heading(let t):
                add(t, VFont.uDisplay(12.5, .bold), brandDeep, style(before: 8, after: 8))
            case .disclosure(let state, let text):
                let s = NSMutableAttributedString(string: "\(state): ", attributes: [.font: VFont.uUI(10.5, .bold), .foregroundColor: ink])
                s.append(NSAttributedString(string: text + "\n", attributes: [.font: body, .foregroundColor: ink2]))
                s.addAttribute(.paragraphStyle, value: style(), range: NSRange(location: 0, length: s.length))
                out.append(s)
            case .note(let t):
                add(t, VFont.uUI(9.5), ink3, style())
            }
        }
        return out
    }
}

/// The font of the invisible ☐ / ☒ characters under the PDF's drawn boxes: one font that has both, so their width matches and
/// a character never falls back to a missing glyph: the text font itself when it has both, else the font the system
/// falls back to for ☐ when that one has ☒ too, else the first of a few system fonts that have both.
enum BoxGlyphFont {
    private static var cache: [String: UIFont] = [:]
    private static let lock = NSLock()

    /// The fallback fonts are drawn a little larger than the text (`scale`), which leaves room for the drawn box.
    static let scale: CGFloat = 1.3

    static func font(for base: UIFont) -> UIFont {
        let key = "\(base.fontName)|\(base.pointSize)"
        lock.lock(); defer { lock.unlock() }
        if let f = cache[key] { return f }
        let r = resolve(base)
        let f = r.withSize(base.pointSize * (r == base ? 1 : scale))
        cache[key] = f
        return f
    }

    /// True when `font` draws both ☐ and ☒ itself.
    static func hasBoth(_ font: UIFont) -> Bool {
        var chars: [UniChar] = [0x2610, 0x2612]
        var glyphs: [CGGlyph] = [0, 0]
        return CTFontGetGlyphsForCharacters(font as CTFont, &chars, &glyphs, 2) && glyphs.allSatisfy { $0 != 0 }
    }

    private static func resolve(_ base: UIFont) -> UIFont {
        if hasBoth(base) { return base }
        let fallback = CTFontCreateForString(base as CTFont, "\u{2610}" as CFString, CFRange(location: 0, length: 1)) as UIFont
        if hasBoth(fallback) { return fallback }
        for name in ["AppleSymbols", "Menlo-Regular", "HiraginoSans-W3", "PingFangSC-Regular", "STHeitiSC-Light"] {
            if let f = UIFont(name: name, size: base.pointSize), hasBoth(f) { return f }
        }
        return fallback
    }
}
