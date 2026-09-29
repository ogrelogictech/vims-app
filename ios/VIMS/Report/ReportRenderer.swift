import UIKit

// On-device PDF report following report.html: branded cover → property information →
// beginning notes → per-section data pages (checklist-number order) → photo pages →
// categorized summary. US Letter, drawn with UIGraphicsPDFRenderer.

struct ReportRow {
    enum Kind { case header(String), line(String, String) }
    let kind: Kind
}

struct ReportPhoto {
    let url: URL
    let caption: String
    let flag: Int?
    let comment: String?
}

struct ReportSection {
    let number: Int
    let name: String
    let rows: [ReportRow]
    let overall: String?
    let comments: String
    let findings: [Finding]
    let photos: [ReportPhoto]
}

struct ReportData {
    var companyName: String
    var companyAddressLines: [String]
    var companyEmail: String
    var logo: UIImage?          // nil -> initials badge
    var clientName: String
    var addressLine1: String
    var addressRest: String
    var date: String
    var agent: String
    var inspector: String
    var cover: CoverChoice
    var coverFrom: UIColor
    var coverTo: UIColor
    var coverPhoto: URL?
    var propertyInfo: [(String, String)]
    var services: [String]
    var beginning: [(String, String)]
    var concerns: String
    var hazards: String
    var sections: [ReportSection]
    var findings: [Finding]
    var categories: [FindingCategoryDef]
    var reviewURL: String

    // Texas / 4 Point additions (reportLayouts)
    var layout: ReportLayout = .standard
    var license: String = ""
    var sponsorName: String = ""
    var sponsorLicense: String = ""
    var insuredName: String = ""
    var policyNumber: String = ""
    var yearBuilt: String = ""
    var companyPhone: String = ""
    var formSections: [FormSectionData] = []
    var pictures: [ReportPhoto] = []

    static func make(_ insp: Inspection, config cfg: ChecklistConfig, overrides: ChecklistOverrides,
                     company: CompanyProfile, repo: FileStore, logo: UIImage?) -> ReportData {
        let cat = ChecklistCatalog(config: cfg, overrides: overrides)
        let colorDef = cfg.covers.colors.first { $0.name == insp.cover.color } ?? cfg.covers.colors[0]

        func v(_ label: String) -> String {
            let s = insp.field(label)
            return s.isEmpty ? "—" : s
        }

        var dateStr = "—"
        if let d = Fmt.parse(insp.field("Date"), "yyyy-MM-dd") { dateStr = Fmt.date(d, "MM/dd/yyyy") }

        var stories = v("Stories")
        if stories == "Other", !insp.storiesOther.isEmpty { stories = "Other — \(insp.storiesOther)" }
        var garage = v("Garage")
        if garage != "None", garage != "—" { garage += " · \(insp.field("Number of cars")) cars" }
        let sqft = insp.field("Total sq ft")
        let val = insp.field("Valuation ($)")
        let lot = insp.field("Lot size (acres)")
        var type = insp.inspType
        if type == "Component", !insp.components.isEmpty { type += " — " + insp.components.joined(separator: ", ") }
        var property = insp.structure
        if property == "Multi-Unit" {
            let mix = cfg.unitMixOrder.compactMap { k in (insp.unitMix[k] ?? 0) > 0 ? "\(insp.unitMix[k]!)× \(k)" : nil }
            if !mix.isEmpty { property += " (" + mix.joined(separator: ", ") + ")" }
        }

        var info: [(String, String)] = [
            ("Type of inspection", type), ("Type of loan", v("Type of loan")),
            ("Property type", property), ("Construction style", v("Construction style")),
            ("Year of construction", v("Year of construction")), ("Total square footage", sqft.isEmpty ? "—" : "\(Double(sqft.replacingOccurrences(of: ",", with: "")).map { Fmt.grouped($0) } ?? sqft) sq ft"),
            ("Valuation", val.isEmpty ? "—" : "$\(val)"), ("Lot size", lot.isEmpty ? "—" : "\(lot) acres"),
            ("Stories", stories), ("Basement", v("Basement")),
            ("Garage", garage), ("Car port", v("Car port"))
        ]
        if !cfg.checklistBuilder.phaseTypes.keys.contains(insp.inspType) {
            for rc in cfg.wizard.roomCounts { info.append((rc.label, "\(insp.counts[rc.key] ?? 0)")) }
            info.append(("Checklist depth", insp.depth.label))
        }

        let beginning: [(String, String)] = [
            ("Property status", v("Property status")), ("Weather", v("Weather & site conditions")),
            ("Temperature", insp.field("Temperature (°F)").isEmpty ? "—" : "\(insp.field("Temperature (°F)"))°F"),
            ("Power is on", v("Power is on")), ("Gas is on", v("Gas is on")), ("Water is on", v("Water is on"))
        ]

        // Sections: completed ones, in master-checklist number order.
        let done = insp.leafSections.filter { insp.status[$0] == .done }
        let ordered = cat.sortedForReport(done)
        var sections: [ReportSection] = []
        for name in ordered {
            let a = insp.answers[name] ?? SectionAnswers()
            var rows: [ReportRow] = []
            if insp.depth == .fast {
                if !a.present.isEmpty { rows.append(ReportRow(kind: .line("Items present", a.present.joined(separator: ", ")))) }
            } else {
                let items = ItemKeys.keyed(cat.items(name, depth: insp.depth).items)
                var pendingHeader: String?
                for k in items {
                    if let h = k.item.header { pendingHeader = h; continue }
                    var value = ""
                    switch k.item.kind {
                    case .single, .multi: value = (a.choices[k.id] ?? []).joined(separator: ", ")
                    case .date:
                        if let d = Fmt.parse(a.text[k.id] ?? "", "yyyy-MM-dd") { value = Fmt.date(d, "MMMM d, yyyy") }
                    case .time:
                        if let d = Fmt.parse(a.text[k.id] ?? "", "HH:mm") { value = Fmt.date(d, "h:mm a") }
                    default: value = a.text[k.id] ?? ""
                    }
                    if let det = a.detail[k.id], !det.isEmpty { value = value.isEmpty ? det : "\(value) — \(det)" }
                    guard !value.isEmpty else { continue }
                    if let h = pendingHeader { rows.append(ReportRow(kind: .header(h))); pendingHeader = nil }
                    rows.append(ReportRow(kind: .line(k.item.q ?? "", value)))
                }
            }
            var photos: [ReportPhoto] = []
            let secPhotos = insp.photos[name] ?? [:]
            let cats = cat.photoCategories(name, depth: insp.depth)
            for c in cats + secPhotos.keys.filter({ !cats.contains($0) }).sorted() {
                for p in secPhotos[c] ?? [] {
                    photos.append(ReportPhoto(url: repo.url(for: p.file), caption: c, flag: p.flag, comment: p.comment))
                }
            }
            sections.append(ReportSection(number: cat.number(name), name: name, rows: rows, overall: a.overall,
                                          comments: a.comments, findings: insp.findings.filter { $0.section == name }, photos: photos))
        }

        // Cover photo: a "Front" photo if one exists, else the first photo anywhere.
        var coverPhoto: URL?
        let preferred = ["Exterior Walls", "Landscaping"]
        outer: for s in preferred + insp.leafSections {
            for (c, arr) in (insp.photos[s] ?? [:]).sorted(by: { $0.key < $1.key }) where c.lowercased().contains("front") {
                if let p = arr.first { coverPhoto = repo.url(for: p.originalFile ?? p.file); break outer }
            }
        }
        if coverPhoto == nil {
            for s in insp.leafSections {
                if let p = (insp.photos[s] ?? [:]).values.first(where: { !$0.isEmpty })?.first { coverPhoto = repo.url(for: p.file); break }
            }
        }

        let addrParts = company.address.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let inspectorName = insp.field("Inspector").isEmpty ? company.inspectorName : insp.field("Inspector")

        var data = ReportData(
            companyName: company.name,
            companyAddressLines: addrParts,
            companyEmail: company.email,
            logo: logo,
            clientName: insp.clientName.isEmpty ? "—" : insp.clientName,
            addressLine1: insp.addressLine1,
            addressRest: insp.addressRest,
            date: dateStr,
            agent: insp.field("Real estate agent name").isEmpty ? "—" : insp.field("Real estate agent name"),
            inspector: inspectorName,
            cover: insp.cover,
            coverFrom: UIColor(hexString: colorDef.from),
            coverTo: UIColor(hexString: colorDef.to),
            coverPhoto: coverPhoto,
            propertyInfo: info,
            services: insp.tests,
            beginning: beginning,
            concerns: insp.field("Buyer's areas of concern"),
            hazards: insp.field("Apparent hazards observed before inspection"),
            sections: sections,
            findings: insp.findings,
            categories: cfg.findings.categories,
            reviewURL: company.reviewURL
        )

        // Per-type fields and form pages
        data.layout = cat.reportLayout(for: insp.inspType)
        data.license = insp.inspectorLicense
        data.sponsorName = insp.field("sponsorName")
        data.sponsorLicense = insp.field("sponsorLicense")
        data.insuredName = insp.field("insuredName")
        data.policyNumber = insp.field("policyNumber")
        data.yearBuilt = insp.field("Year of construction")
        data.companyPhone = company.phone
        if data.layout != .standard {
            let formNames = insp.leafSections.filter { cat.isForm($0) && !cat.isPhotosOnly($0) }
            data.formSections = cat.sortedForReport(formNames).map { name in
                FormSectionData.make(name: name, items: cat.items(name, depth: .standard).items, answers: insp.answers[name] ?? SectionAnswers())
            }
            // Pictures pages: the photos-only section first, then photos taken inside the form sections.
            let picSecs = insp.leafSections.filter { cat.isPhotosOnly($0) } + formNames
            for s in picSecs {
                let secPhotos = insp.photos[s] ?? [:]
                let cats = cat.photoCategories(s, depth: .standard)
                let short = FormSectionData.shortTitle(s)
                for c in cats + secPhotos.keys.filter({ !cats.contains($0) }).sorted() {
                    for p in secPhotos[c] ?? [] {
                        let cap = cat.isPhotosOnly(s) ? c : "\(short) — \(c)"
                        data.pictures.append(ReportPhoto(url: repo.url(for: p.file), caption: cap, flag: p.flag, comment: p.comment))
                    }
                }
            }
        }
        return data
    }
}

/// A state/insurance form section resolved against its answers, for the Texas and 4-Point pages.
struct FormSectionData {
    struct Row {
        let q: String
        let kind: ItemKind
        let options: [String]
        let selected: [String]
        let text: String
    }
    struct Group {
        let title: String?
        let rows: [Row]
    }
    let name: String
    let title: String
    let groups: [Group]

    static func shortTitle(_ name: String) -> String {
        for prefix in ["Texas — ", "4-Point — "] where name.hasPrefix(prefix) { return String(name.dropFirst(prefix.count)) }
        return name
    }

    static func make(name: String, items: [ItemDef], answers a: SectionAnswers) -> FormSectionData {
        var groups: [Group] = []
        var title: String?
        var rows: [Row] = []
        for k in ItemKeys.keyed(items) {
            if let h = k.item.header {
                if title != nil || !rows.isEmpty { groups.append(Group(title: title, rows: rows)) }
                title = h; rows = []
                continue
            }
            var text = a.text[k.id] ?? ""
            if k.item.kind == .date, let d = Fmt.parse(text, "yyyy-MM-dd") { text = Fmt.date(d, "MM/dd/yyyy") }
            if k.item.kind == .time, let d = Fmt.parse(text, "HH:mm") { text = Fmt.date(d, "h:mm a") }
            if let det = a.detail[k.id], !det.isEmpty { text = text.isEmpty ? det : "\(text) — \(det)" }
            rows.append(Row(q: k.item.q ?? "", kind: k.item.kind, options: k.item.options ?? [], selected: a.choices[k.id] ?? [], text: text))
        }
        if title != nil || !rows.isEmpty { groups.append(Group(title: title, rows: rows)) }
        return FormSectionData(name: name, title: shortTitle(name), groups: groups)
    }
}

enum ReportRenderer {
    static let pageSize = CGSize(width: 612, height: 792)

    static func render(_ data: ReportData) -> (pdf: Data, pageCount: Int) {
        let meta: [String: Any] = [
            kCGPDFContextTitle as String: "Inspection Report — \(data.addressLine1)",
            kCGPDFContextAuthor as String: data.companyName,
            kCGPDFContextCreator as String: "VIMS"
        ]
        let fmt = UIGraphicsPDFRendererFormat()
        fmt.documentInfo = meta
        var pages = 0
        func draw(total: Int) -> Data {
            // A fresh renderer per pass: a UIGraphicsPDFRenderer produced empty data when reused.
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: fmt)
            return renderer.pdfData { ctx in
                let w = Writer(ctx: ctx, data: data)
                w.totalPages = total
                w.cover()
                switch data.layout {
                case .standard:
                    w.propertyInformation()
                    w.beginningNotes()
                    for s in data.sections { w.section(s) }
                    for s in data.sections where !s.photos.isEmpty { w.photos(s) }
                    w.summary()
                case .texas:
                    w.trecInfoPage()
                    for f in data.formSections { w.trecChecklist(f) }
                    w.picturePages()
                    w.summary(subtitle: "Findings grouped by category")
                case .fourPoint:
                    w.fourPointForm()
                    w.picturePages()
                }
                pages = w.page
            }
        }
        var pdf = draw(total: 0)
        if data.layout != .standard { pdf = draw(total: pages) }   // second pass knows "Page X of Y"
        return (pdf, pages)
    }

    // MARK: - Writer

    final class Writer {
        let ctx: UIGraphicsPDFRendererContext
        let d: ReportData
        var page = 0
        var totalPages = 0
        /// Texas checklist/TREC pages have no running header (they reproduce the TREC form).
        var headerless = false
        var y: CGFloat = 0
        let m: CGFloat = 40
        var contentW: CGFloat { ReportRenderer.pageSize.width - m * 2 }
        var bottomLimit: CGFloat { ReportRenderer.pageSize.height - 58 }

        // palette
        let ink = UIColor(hex: 0x17222E), ink2 = UIColor(hex: 0x3F4E5E), ink3 = UIColor(hex: 0x5F6D7D)
        let line = UIColor(hex: 0xDDE5EE), line2 = UIColor(hex: 0xEEF2F7)
        let brand = UIColor(hex: 0x2F5EC9), brandDeep = UIColor(hex: 0x1E3D94), paper2 = UIColor(hex: 0xF4F7FA)

        init(ctx: UIGraphicsPDFRendererContext, data: ReportData) { self.ctx = ctx; self.d = data }

        var cg: CGContext { ctx.cgContext }

        // MARK: primitives

        @discardableResult
        func text(_ s: String, _ font: UIFont, _ color: UIColor, x: CGFloat, y: CGFloat, w: CGFloat,
                  align: NSTextAlignment = .left, lineSpacing: CGFloat = 1.5) -> CGFloat {
            let p = NSMutableParagraphStyle()
            p.alignment = align
            p.lineSpacing = lineSpacing
            p.lineBreakMode = .byWordWrapping
            let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
            let r = a.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            a.draw(with: CGRect(x: x, y: y, width: w, height: ceil(r.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            return ceil(r.height)
        }

        func measure(_ s: String, _ font: UIFont, w: CGFloat, lineSpacing: CGFloat = 1.5) -> CGFloat {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = lineSpacing
            let a = NSAttributedString(string: s, attributes: [.font: font, .paragraphStyle: p])
            return ceil(a.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        }

        func fill(_ r: CGRect, _ c: UIColor, radius: CGFloat = 0) {
            c.setFill()
            UIBezierPath(roundedRect: r, cornerRadius: radius).fill()
        }

        func stroke(_ r: CGRect, _ c: UIColor, radius: CGFloat = 0, width: CGFloat = 0.75) {
            c.setStroke()
            let p = UIBezierPath(roundedRect: r.insetBy(dx: width / 2, dy: width / 2), cornerRadius: radius)
            p.lineWidth = width
            p.stroke()
        }

        func hline(_ y: CGFloat, x: CGFloat, w: CGFloat, _ c: UIColor, width: CGFloat = 0.6) {
            fill(CGRect(x: x, y: y, width: w, height: width), c)
        }

        func gradient(_ r: CGRect, _ from: UIColor, _ to: UIColor, radius: CGFloat = 0) {
            cg.saveGState()
            UIBezierPath(roundedRect: r, cornerRadius: radius).addClip()
            let colors = [from.cgColor, to.cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
            }
            cg.restoreGState()
        }

        func image(_ img: UIImage, fill r: CGRect, radius: CGFloat = 0) {
            cg.saveGState()
            UIBezierPath(roundedRect: r, cornerRadius: radius).addClip()
            let s = img.size
            let scale = max(r.width / max(s.width, 1), r.height / max(s.height, 1))
            let sz = CGSize(width: s.width * scale, height: s.height * scale)
            img.draw(in: CGRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height))
            cg.restoreGState()
        }

        func image(_ img: UIImage, fit r: CGRect) {
            let s = img.size
            let scale = min(r.width / max(s.width, 1), r.height / max(s.height, 1))
            let sz = CGSize(width: s.width * scale, height: s.height * scale)
            img.draw(in: CGRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height))
        }

        func loadImage(_ url: URL, maxPixel: CGFloat = 1400) -> UIImage? {
            ImageTools.downsample(url, maxPixel: maxPixel)
        }

        /// Company logo, or an initials badge on the brand color when none was uploaded.
        func logoMark(_ r: CGRect) {
            if let logo = d.logo { image(logo, fit: r); return }
            gradient(r, UIColor(hex: 0x5580E6), UIColor(hex: 0x1E3D94), radius: r.width * 0.22)
            let initials = Fmt.initials(d.companyName)
            let f = VFont.uDisplay(r.height * 0.4, .bold)
            text(initials, f, .white, x: r.minX, y: r.midY - f.lineHeight / 2, w: r.width, align: .center, lineSpacing: 0)
        }

        var brandParts: (String, String) {
            let words = d.companyName.split(separator: " ").map(String.init)
            if words.count >= 2, let last = words.last, ["Inspections", "Inspection", "Services", "LLC", "Inc."].contains(last) {
                return (words.dropLast().joined(separator: " "), last)
            }
            return (d.companyName, "")
        }

        // MARK: page furniture

        func newContentPage() {
            ctx.beginPage()
            page += 1
            if headerless { y = 40 } else { runningHeader(); y = 96 }
            footer()
        }

        /// Called after an automatic page break so form pages can repeat their column headers.
        var onPageBreak: (() -> Void)?

        func ensure(_ h: CGFloat) {
            if y + h > bottomLimit { newContentPage(); onPageBreak?() }
        }

        func runningHeader() {
            let logoR = CGRect(x: m, y: 30, width: 34, height: 34)
            logoMark(logoR)
            let (b1, b2) = brandParts
            text(b1, VFont.uDisplay(12.5, .heavy), brandDeep, x: m + 42, y: 33, w: 250)
            if !b2.isEmpty { text(b2, VFont.uUI(8.5), ink3, x: m + 42, y: 49, w: 250) }
            var ay: CGFloat = 30
            ay += text(d.companyName, VFont.uUI(8.5, .semibold), ink, x: m + contentW - 240, y: ay, w: 240, align: .right, lineSpacing: 0)
            for l in d.companyAddressLines + [d.companyEmail] where !l.isEmpty {
                ay += text(l, VFont.uUI(7.8), ink2, x: m + contentW - 240, y: ay, w: 240, align: .right, lineSpacing: 0)
            }
            fill(CGRect(x: m, y: 76, width: contentW, height: 1.5), brand)
        }

        var pageOf: String { totalPages > 0 ? "Page \(page) of \(totalPages)" : "Page \(page)" }

        func footer() {
            let fy = ReportRenderer.pageSize.height - 44
            switch d.layout {
            case .texas:
                hline(fy, x: m, w: contentW, ink, width: 0.8)
                text("REI 7-6 (8/9/21)  ·  Promulgated by the Texas Real Estate Commission  ·  (512) 936-3000  ·  www.trec.texas.gov",
                     VFont.uUI(7), ink2, x: m, y: fy + 7, w: contentW - 90)
                text(pageOf, VFont.uUI(7), ink2, x: m + contentW - 90, y: fy + 7, w: 90, align: .right)
                return
            case .fourPoint:
                hline(fy, x: m, w: contentW, line)
                text("4-Point Inspection · \(d.addressLine1) · \(d.date)", VFont.uUI(7.5), ink3, x: m, y: fy + 8, w: 380)
                text(pageOf, VFont.uUI(7.5), ink3, x: m + contentW - 120, y: fy + 8, w: 120, align: .right)
                return
            case .standard:
                break
            }
            hline(fy, x: m, w: contentW, line)
            text(d.clientName, VFont.uUI(7.8, .bold), ink, x: m, y: fy + 8, w: 360)
            text("\(d.addressLine1) · \(d.date)", VFont.uUI(7.5), ink3, x: m, y: fy + 19, w: 360)
            text("Page \(page)", VFont.uUI(7.5), ink3, x: m + contentW - 120, y: fy + 8, w: 120, align: .right)
        }

        func pageTitle(_ title: String, _ sub: String) {
            text(title, VFont.uDisplay(15, .heavy), ink, x: m, y: y, w: contentW)
            y += 21
            text(sub, VFont.uUI(9), ink3, x: m, y: y, w: contentW)
            y += 22
        }

        func blockLabel(_ s: String) {
            ensure(30)
            y += 12
            text(s.uppercased(), VFont.uDisplay(9.5, .bold), brandDeep, x: m, y: y, w: contentW)
            y += 17
        }

        func note(_ s: String) {
            let h = measure(s, VFont.uUI(9), w: contentW - 20) + 16
            ensure(h)
            fill(CGRect(x: m, y: y, width: contentW, height: h), paper2, radius: 6)
            stroke(CGRect(x: m, y: y, width: contentW, height: h), line, radius: 6)
            text(s, VFont.uUI(9), ink2, x: m + 10, y: y + 8, w: contentW - 20)
            y += h
        }

        func infoGrid(_ pairs: [(String, String)]) {
            let colW = (contentW - 20) / 2
            var i = 0
            while i < pairs.count {
                let rowPairs = Array(pairs[i..<min(i + 2, pairs.count)])
                let h = rowPairs.map { max(measure($0.1, VFont.uUI(9.2, .semibold), w: colW * 0.55), 11) }.max()! + 12
                ensure(h)
                for (j, p) in rowPairs.enumerated() {
                    let x = m + CGFloat(j) * (colW + 20)
                    text(p.0, VFont.uUI(9.2), ink3, x: x, y: y + 6, w: colW * 0.45)
                    text(p.1, VFont.uUI(9.2, .semibold), ink, x: x + colW * 0.45, y: y + 6, w: colW * 0.55, align: .right)
                    hline(y + h - 0.6, x: x, w: colW, line2)
                }
                y += h
                i += 2
            }
        }

        // MARK: pages

        func cover() {
            ctx.beginPage()
            page += 1
            let W = ReportRenderer.pageSize.width, H = ReportRenderer.pageSize.height
            // top brand
            logoMark(CGRect(x: 34, y: 30, width: 48, height: 48))
            let (b1, b2) = brandParts
            text(b1, VFont.uDisplay(17, .heavy), brandDeep, x: 92, y: 34, w: 250)
            if !b2.isEmpty { text(b2, VFont.uUI(9.5, .semibold), UIColor(hex: 0x7C8A55), x: 92, y: 55, w: 250) }
            var ay: CGFloat = 32
            ay += text(d.companyName, VFont.uUI(9.2, .semibold), ink, x: W - 34 - 240, y: ay, w: 240, align: .right, lineSpacing: 1)
            for l in d.companyAddressLines + [d.companyEmail] where !l.isEmpty {
                ay += text(l, VFont.uUI(8.4), ink2, x: W - 34 - 240, y: ay, w: 240, align: .right, lineSpacing: 1)
            }
            // title
            let title = d.layout == .texas ? "Property Inspection Report" : d.layout == .fourPoint ? "4-Point Inspection Report" : "Inspection Report"
            text(title, VFont.uDisplay(19, .heavy), ink, x: 0, y: 108, w: W, align: .center)
            // fields
            var fy: CGFloat = 146
            let fx: CGFloat = 50, fw = W - 100
            let rows: [(String, String)] = d.layout == .fourPoint ? [
                ("Insured / Applicant", d.insuredName.isEmpty ? d.clientName : d.insuredName),
                ("Application / Policy #", d.policyNumber.isEmpty ? "—" : d.policyNumber),
                ("Address Inspected", d.addressLine1), ("", d.addressRest),
                ("Actual Year Built", d.yearBuilt.isEmpty ? "—" : d.yearBuilt), ("Date Inspected", d.date)
            ] : [
                ("Client Name", d.clientName), ("Address of Inspection", d.addressLine1), ("", d.addressRest),
                ("Date of Inspection", d.date), ("Real Estate Agent", d.agent)
            ]
            for (l, v) in rows {
                let lw: CGFloat = l.isEmpty ? 0 : (l as NSString).size(withAttributes: [.font: VFont.uUI(11, .bold)]).width + 9
                if !l.isEmpty { text(l, VFont.uUI(11, .bold), ink, x: fx, y: fy + 4, w: lw) }
                text(v, VFont.uUI(14), ink, x: fx + lw, y: fy, w: fw - lw)
                hline(fy + 20, x: fx + lw, w: fw - lw, UIColor(hex: 0x9FB0C2), width: 0.8)
                fy += 28
            }
            // Name of Inspector + License # (all report types)
            do {
                let lf = VFont.uUI(11, .bold)
                let nl = ("Name of Inspector" as NSString).size(withAttributes: [.font: lf]).width + 9
                let ll = ("License #" as NSString).size(withAttributes: [.font: lf]).width + 9
                let licW: CGFloat = 108
                let nameW = fw - nl - ll - licW - 10
                text("Name of Inspector", lf, ink, x: fx, y: fy + 4, w: nl)
                text(d.inspector, VFont.uUI(14), ink, x: fx + nl, y: fy, w: nameW)
                hline(fy + 20, x: fx + nl, w: nameW, UIColor(hex: 0x9FB0C2), width: 0.8)
                let lx = fx + nl + nameW + 10
                text("License #", lf, ink, x: lx, y: fy + 4, w: ll)
                text(d.license, VFont.uUI(14), ink, x: lx + ll, y: fy, w: licW)
                hline(fy + 20, x: lx + ll, w: licW, UIColor(hex: 0x9FB0C2), width: 0.8)
                fy += 28
            }
            // image area
            let bandH: CGFloat = 92
            let img = CGRect(x: 50, y: fy + 14, width: W - 100, height: H - bandH - 16 - (fy + 14))
            let photo = d.coverPhoto.flatMap { loadImage($0, maxPixel: 1800) }
            switch d.cover.style {
            case "Solid":
                gradient(img, d.coverFrom, d.coverTo, radius: 5)
                text(d.cover.artLabel, VFont.uDisplay(26, .heavy), .white, x: img.minX, y: img.midY - 18, w: img.width, align: .center)
            case "Shaded":
                if let photo { image(photo, fill: img, radius: 5) } else { gradient(img, d.coverFrom, d.coverTo, radius: 5) }
                cg.saveGState()
                UIBezierPath(roundedRect: img, cornerRadius: 5).addClip()
                gradient(img, d.coverFrom.withAlphaComponent(0.15), d.coverTo.withAlphaComponent(0.75))
                cg.restoreGState()
                text(d.cover.artLabel, VFont.uDisplay(15, .heavy), .white, x: img.minX + 16, y: img.maxY - 34, w: img.width - 32)
            default: // Framed
                gradient(img, d.coverFrom, d.coverTo, radius: 5)
                let inner = img.insetBy(dx: 12, dy: 12)
                if let photo { image(photo, fill: inner, radius: 3) } else {
                    fill(inner, UIColor.white.withAlphaComponent(0.12), radius: 3)
                    text(d.cover.artLabel, VFont.uDisplay(22, .heavy), .white, x: inner.minX, y: inner.midY - 14, w: inner.width, align: .center)
                }
                stroke(inner, UIColor.white.withAlphaComponent(0.85), radius: 3, width: 1.5)
            }
            // bottom band
            let band = CGRect(x: 0, y: H - bandH, width: W, height: bandH)
            gradient(band, d.coverFrom, d.coverTo)
            text("This inspection report is the property of \(d.companyName). Any reproduction or distribution without written consent is prohibited.",
                 VFont.uDisplay(10.5, .bold), .white, x: 40, y: band.minY + 22, w: W * 0.58, lineSpacing: 3)
            text("Cover artwork", VFont.uUI(8.5), UIColor(hex: 0xCFE0FF), x: W - 40 - 200, y: band.minY + 26, w: 200, align: .right)
            let tag = d.cover.label
            let tw = (tag as NSString).size(withAttributes: [.font: VFont.uUI(7.5)]).width + 14
            let tagR = CGRect(x: W - 40 - tw, y: band.minY + 42, width: tw, height: 15)
            fill(tagR, UIColor.white.withAlphaComponent(0.16), radius: 7.5)
            text(tag, VFont.uUI(7.5), .white, x: tagR.minX, y: tagR.minY + 2.5, w: tw, align: .center)
        }

        func propertyInformation() {
            newContentPage()
            pageTitle("Property Information", "Inspection details & property description")
            infoGrid(d.propertyInfo)
            blockLabel("Additional inspection services")
            note(d.services.isEmpty ? "None selected" : d.services.joined(separator: " · "))
        }

        func beginningNotes() {
            newContentPage()
            pageTitle("Beginning Notes", "Conditions at the time of inspection")
            infoGrid(d.beginning)
            blockLabel("Buyer’s areas of concern")
            note(d.concerns.isEmpty ? "None noted." : d.concerns)
            blockLabel("Apparent hazards observed before inspection")
            note(d.hazards.isEmpty ? "None noted." : d.hazards)
        }

        func sectionTitle(_ number: Int, _ name: String) {
            ensure(44)
            let r = CGRect(x: m, y: y, width: contentW, height: 28)
            fill(r, brand, radius: 7)
            let num = String(format: "%02d", number)
            let nw = (num as NSString).size(withAttributes: [.font: VFont.uDisplay(11, .heavy)]).width + 12
            fill(CGRect(x: m + 10, y: y + 6, width: nw, height: 16), UIColor.white.withAlphaComponent(0.2), radius: 5)
            text(num, VFont.uDisplay(11, .heavy), .white, x: m + 10, y: y + 7, w: nw, align: .center)
            text(name, VFont.uDisplay(12, .bold), .white, x: m + 18 + nw, y: y + 6.5, w: contentW - nw - 30)
            y += 38
        }

        func section(_ s: ReportSection) {
            newContentPage()
            sectionTitle(s.number, s.name)
            if s.rows.isEmpty {
                note("No line items were recorded for this section.")
            }
            for r in s.rows {
                switch r.kind {
                case .header(let h):
                    ensure(40)
                    y += 6
                    let hr = CGRect(x: m, y: y, width: contentW, height: 20)
                    fill(hr, paper2, radius: 4)
                    fill(CGRect(x: m, y: y, width: 2.5, height: 20), brand)
                    text(h, VFont.uDisplay(9.5, .bold), brandDeep, x: m + 10, y: y + 4, w: contentW - 20)
                    y += 26
                case .line(let k, let v):
                    let kw = contentW * 0.52, vw = contentW * 0.48 - 8
                    let h = max(measure(k, VFont.uUI(9.2), w: kw - 8), measure(v, VFont.uUI(9.2, .semibold), w: vw)) + 11
                    ensure(h)
                    text(k, VFont.uUI(9.2), ink2, x: m + 4, y: y + 5, w: kw - 8)
                    text(v, VFont.uUI(9.2, .semibold), ink, x: m + kw, y: y + 5, w: vw)
                    hline(y + h - 0.6, x: m, w: contentW, line2)
                    y += h
                }
            }
            if let o = s.overall {
                ensure(40)
                y += 10
                let r = CGRect(x: m, y: y, width: contentW, height: 26)
                fill(r, UIColor(hex: 0xE7F4EE), radius: 6)
                stroke(r, UIColor(hex: 0xBFE3D0), radius: 6)
                text("Overall condition", VFont.uUI(9.5), ink, x: m + 12, y: y + 7, w: 200)
                text(o, VFont.uUI(9.5, .bold), UIColor(hex: 0x1F7A52), x: m + contentW - 212, y: y + 7, w: 200, align: .right)
                y += 26
            }
            if !s.comments.isEmpty {
                blockLabel("Comments")
                note(s.comments)
            }
            if !s.findings.isEmpty {
                blockLabel("Findings")
                for f in s.findings { findingLine(f, number: nil) }
            }
        }

        func findingLine(_ f: Finding, number: Int?) {
            let lead: CGFloat = 26
            let label = number.map(String.init) ?? "Cat \(f.category)"
            let body = number == nil ? f.text : "\(f.text) (\(f.section))"
            let h = measure(body, VFont.uUI(9.2), w: contentW - lead - 20) + 12
            ensure(h)
            if number == nil {
                let c = [UIColor(hex: 0xD0584A), UIColor(hex: 0xC98A1A), UIColor(hex: 0x2F9E6B)][max(0, min(2, f.category - 1))]
                fill(CGRect(x: m + 4, y: y + 6, width: 30, height: 13), c, radius: 6.5)
                text(label, VFont.uUI(7, .bold), .white, x: m + 4, y: y + 7.5, w: 30, align: .center)
                text(body, VFont.uUI(9.2), ink2, x: m + 42, y: y + 5, w: contentW - 50)
            } else {
                text(label, VFont.uUI(9.2, .bold), ink, x: m + 12, y: y + 5, w: 20)
                let a = NSMutableAttributedString(string: f.text + " ", attributes: [.font: VFont.uUI(9.2), .foregroundColor: ink2])
                a.append(NSAttributedString(string: "(\(f.section))", attributes: [.font: VFont.uUI(9.2), .foregroundColor: ink3]))
                a.draw(with: CGRect(x: m + 12 + lead, y: y + 5, width: contentW - lead - 24, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }
            hline(y + h - 0.6, x: m, w: contentW, line2)
            y += h
        }

        func photos(_ s: ReportSection) {
            newContentPage()
            sectionTitle(s.number, "\(s.name) · Photos")
            let cols = 2
            let gap: CGFloat = 14
            let cw = (contentW - gap) / CGFloat(cols)
            let ih: CGFloat = cw * 0.62
            for (i, p) in s.photos.enumerated() {
                let capH: CGFloat = p.comment == nil ? 22 : 22 + measure(p.comment!, VFont.uUI(8), w: cw - 16) + 2
                let cardH = ih + capH
                let col = i % cols
                if col == 0 {
                    let rowH = cardH
                    if y + rowH > bottomLimit {
                        newContentPage()
                        sectionTitle(s.number, "\(s.name) · Photos")
                    }
                }
                let x = m + CGFloat(col) * (cw + gap)
                let r = CGRect(x: x, y: y, width: cw, height: cardH)
                fill(r, .white, radius: 6)
                if let img = loadImage(p.url, maxPixel: 900) {
                    cg.saveGState()
                    UIBezierPath(roundedRect: CGRect(x: x, y: y, width: cw, height: ih), byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 6, height: 6)).addClip()
                    image(img, fill: CGRect(x: x, y: y, width: cw, height: ih))
                    cg.restoreGState()
                } else {
                    fill(CGRect(x: x, y: y, width: cw, height: ih), paper2)
                }
                if let f = p.flag {
                    let c = [UIColor(hex: 0xD0584A), UIColor(hex: 0xC98A1A), UIColor(hex: 0x2F9E6B)][max(0, min(2, f - 1))]
                    fill(CGRect(x: x + 8, y: y + 8, width: 48, height: 15), UIColor(hex: 0xD0584A), radius: 7.5)
                    text("Concern", VFont.uUI(7.2, .bold), .white, x: x + 8, y: y + 10, w: 48, align: .center)
                    fill(CGRect(x: x + cw - 44, y: y + ih + 5, width: 36, height: 13), c, radius: 6.5)
                    text("Cat \(f)", VFont.uUI(7, .bold), .white, x: x + cw - 44, y: y + ih + 6.5, w: 36, align: .center)
                }
                text(p.caption, VFont.uUI(8.4), ink2, x: x + 8, y: y + ih + 5, w: cw - 60)
                if let c = p.comment { text(c, VFont.uUI(8), ink3, x: x + 8, y: y + ih + 19, w: cw - 16) }
                stroke(r, line, radius: 6)
                if col == cols - 1 || i == s.photos.count - 1 {
                    // advance by the tallest card in this row
                    let rowStart = i - col
                    let tallest = s.photos[rowStart...i].map { q -> CGFloat in
                        ih + (q.comment == nil ? 22 : 22 + measure(q.comment!, VFont.uUI(8), w: cw - 16) + 2)
                    }.max() ?? cardH
                    y += tallest + gap
                }
            }
        }

        func summary(subtitle: String = "Findings grouped by category, in the order they appear in the report") {
            headerless = false
            onPageBreak = nil
            newContentPage()
            pageTitle("Summary of Findings", subtitle)
            let order = d.sections.map(\.name)
            for c in d.categories {
                let items = d.findings.filter { $0.category == c.id }.sorted { a, b in
                    (order.firstIndex(of: a.section) ?? 999) < (order.firstIndex(of: b.section) ?? 999)
                }
                ensure(60)
                let topPage = page
                let color = [UIColor(hex: 0xD0584A), UIColor(hex: 0xC98A1A), UIColor(hex: 0x2F9E6B)][max(0, min(2, c.id - 1))]
                let bg = [UIColor(hex: 0xFBE9E6), UIColor(hex: 0xFBF1DD), UIColor(hex: 0xE7F4EE)][max(0, min(2, c.id - 1))]
                let top = y
                fill(CGRect(x: m, y: y, width: contentW, height: 42), bg, radius: 8)
                fill(CGRect(x: m + 12, y: y + 9, width: 24, height: 24), color, radius: 6)
                text("\(c.id)", VFont.uDisplay(12, .heavy), .white, x: m + 12, y: y + 13, w: 24, align: .center)
                let head = NSMutableAttributedString(string: "Category \(c.id)", attributes: [.font: VFont.uDisplay(11, .bold), .foregroundColor: ink])
                head.append(NSAttributedString(string: " · \(c.label)", attributes: [.font: VFont.uDisplay(11, .semibold), .foregroundColor: ink2]))
                head.draw(at: CGPoint(x: m + 46, y: y + 8))
                text(c.note, VFont.uUI(8.5), ink3, x: m + 46, y: y + 23, w: contentW - 100)
                text("\(items.count)", VFont.uUI(11, .bold), ink, x: m + contentW - 50, y: y + 14, w: 38, align: .right)
                y += 42
                if items.isEmpty {
                    ensure(20)
                    text("No findings in this category.", VFont.uUI(9), ink3, x: m + 12, y: y + 5, w: contentW - 24)
                    y += 20
                }
                for (i, f) in items.enumerated() { findingLine(f, number: i + 1) }
                if page == topPage, y > top { stroke(CGRect(x: m, y: top, width: contentW, height: y - top), line, radius: 8) }
                y += 12
            }
            if !d.reviewURL.isEmpty {
                blockLabel("How did we do?")
                note("We’d appreciate your feedback. Leave a review of your inspection: \(d.reviewURL)")
            }
        }
    }
}
