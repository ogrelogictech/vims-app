import Foundation

/// Exactly what the inspection-agreement viewer shows — the VIMS agreement (filled with the company name, state
/// disclosures filtered like the viewer) or the company's edited version — as one list of blocks. The viewer, the
/// downloaded PDF (AgreementPDF) and the editor's starting text are all built from it, so they always match.
struct AgreementContent: Equatable {
    enum Block: Equatable {
        case title(String)
        /// The boxed form lines (Client name ____ …), one per line.
        case form([String])
        case paragraph(String, lead: Bool)
        case bullet(String)
        case heading(String)
        /// "State name: text" disclosure.
        case disclosure(state: String, text: String)
        /// Small gray note (e.g. "Showing Utah only. The full agreement lists 20 states.").
        case note(String)
    }

    var blocks: [Block]

    /// The VIMS agreement as the viewer shows it. `stateCode` nil = every state's disclosure (Company profile);
    /// a code = only that state's entry, or "No additional disclosures for <State>." (wizard step 1).
    static func vims(_ doc: InspectionAgreement, company: String, stateCode: String?, stateName: (String) -> String) -> AgreementContent {
        func fill(_ t: String) -> String { InspectionAgreement.fill(t, company: company) }
        func block(_ b: InspectionAgreement.Block) -> Block {
            b.isBullet ? .bullet(fill(b.text)) : .paragraph(fill(b.text), lead: b.lead ?? false)
        }
        var out: [Block] = [.title(fill(doc.title)), .form(doc.formLines.map(fill))]
        out += doc.body.map(block)
        out.append(.heading(doc.stateDisclosuresHeading))
        let all = doc.disclosureStates
        let shown = stateCode.map { code in all.filter { $0 == code } } ?? all
        if let code = stateCode, shown.isEmpty { out.append(.note("No additional disclosures for \(stateName(code)).")) }
        out += shown.map { .disclosure(state: stateName($0), text: fill(doc.stateDisclosures[$0] ?? "")) }
        if let code = stateCode, !shown.isEmpty, shown.count < all.count {
            out.append(.note("Showing \(stateName(code)) only. The full agreement lists \(all.count) states."))
        }
        out += doc.closing.map(block)
        return AgreementContent(blocks: out)
    }

    /// A company's edited agreement (plain text): one paragraph per blank-line-separated block, "• " lines become
    /// bullets, and the first block is the title when it's a single short line (as in the text the editor starts from).
    /// Line breaks inside a block are kept (the form lines). `{companyName}` is still filled if someone typed it.
    static func edited(_ text: String, company: String) -> AgreementContent {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var out: [Block] = []
        for (i, chunk) in normalized.components(separatedBy: "\n\n").enumerated() {
            let lines = chunk.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            if i == 0, out.isEmpty, lines.count == 1, lines[0].count <= 120, !lines[0].hasPrefix(bulletPrefix) {
                out.append(.title(InspectionAgreement.fill(lines[0], company: company)))
                continue
            }
            var para: [String] = []
            func flush() {
                if !para.isEmpty { out.append(.paragraph(InspectionAgreement.fill(para.joined(separator: "\n"), company: company), lead: false)) }
                para = []
            }
            for l in lines {
                if l.hasPrefix(bulletPrefix) || l.hasPrefix("\u{2022}") {
                    flush()
                    let t = l.dropFirst(l.hasPrefix(bulletPrefix) ? bulletPrefix.count : 1).trimmingCharacters(in: .whitespaces)
                    out.append(.bullet(InspectionAgreement.fill(t, company: company)))
                } else {
                    para.append(l)
                }
            }
            flush()
        }
        return AgreementContent(blocks: out)
    }

    static let bulletPrefix = "\u{2022} "

    /// Plain text for the "Edit agreement" editor: title, form lines, paragraphs separated by blank lines, bullets
    /// prefixed "• ", the disclosures heading then one "State name: text" paragraph per state, closing.
    var plainText: String {
        var chunks: [String] = []
        var bullets: [String] = []
        func flushBullets() { if !bullets.isEmpty { chunks.append(bullets.joined(separator: "\n")); bullets = [] } }
        for b in blocks {
            if case .bullet(let t) = b { bullets.append(Self.bulletPrefix + t); continue }
            flushBullets()
            switch b {
            case .title(let t), .heading(let t), .note(let t): chunks.append(t)
            case .form(let lines): chunks.append(lines.joined(separator: "\n"))
            case .paragraph(let t, _): chunks.append(t)
            case .disclosure(let state, let text): chunks.append("\(state): \(text)")
            case .bullet: break
            }
        }
        flushBullets()
        return chunks.joined(separator: "\n\n")
    }

    /// Title for file names / the PDF metadata.
    var title: String {
        for b in blocks { if case .title(let t) = b { return t } }
        return "Inspection Agreement"
    }
}

extension AgreementContent {
    /// Most an edited agreement may hold (the VIMS agreement is ~16,000 characters).
    static let maxEditedLength = 100_000

    /// "Inspection-Agreement-Vision-Property-Inspections.pdf"
    static func fileName(company: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let words = company.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let slug = String(words).split(separator: " ").joined(separator: "-")
        return "Inspection-Agreement\(slug.isEmpty ? "" : "-\(slug)").pdf"
    }
}
