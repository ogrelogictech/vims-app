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
    /// Line breaks inside a block are kept. `{companyName}` is still filled if someone typed it.
    /// The form block (`form`: the VIMS agreement's form lines, company name filled) is locked — it isn't part of the
    /// editable text — and is always placed right after the title, exactly as in the VIMS agreement. Form lines left
    /// in text saved before it was locked are dropped first, so the block never shows twice.
    static func edited(_ text: String, company: String, form: [String]) -> AgreementContent {
        // Oct 13: the block editor stores JSON blocks; plain text is an edit saved by an earlier build.
        if let stored = EditedAgreement.decode(text) { return stored.content(company: company, form: form) }
        let normalized = strippingFormLines(text, formLines: form).replacingOccurrences(of: "\r\n", with: "\n")
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
        if !form.isEmpty {
            let at = out.firstIndex { if case .title = $0 { return true } else { return false } }.map { $0 + 1 } ?? 0
            out.insert(.form(form), at: at)
        }
        return AgreementContent(blocks: out)
    }

    /// Removes the form block from agreement text saved before the form was locked (the editor used to start from
    /// the whole agreement, form lines included, so a company may have saved them, possibly with field names deleted):
    /// a multi-line, non-bullet chunk that holds a form line or is mostly blanks / ☐ boxes, and any single-line chunk
    /// that is one of the form lines. The signature and date blanks in the body and closing are untouched (they're
    /// one paragraph per chunk).
    static func strippingFormLines(_ text: String, formLines: [String]) -> String {
        func norm(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "\u{2610}", with: " ")
                .replacingOccurrences(of: "$", with: " ")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let known = Set(formLines.map(norm).filter { $0.count >= 4 })
        func isBlanky(_ l: String) -> Bool { l.contains("__") || l.contains("\u{2610}") }
        let chunks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        let kept = chunks.filter { chunk in
            let lines = chunk.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return true }
            if lines.count == 1 { return !known.contains(norm(lines[0])) }
            if lines.contains(where: { $0.hasPrefix(bulletPrefix) || $0.hasPrefix("\u{2022}") }) { return true }
            let matches = lines.filter { known.contains(norm($0)) }.count
            let blanks = lines.filter(isBlanky).count
            return !(lines.count >= 3 && (matches > 0 || blanks * 2 >= lines.count))
        }
        return kept.joined(separator: "\n\n")
    }

    static let bulletPrefix = "\u{2022} "

    /// Plain text (the format "Edit agreement" saved before the Oct 13 block editor; still read): title, form lines, paragraphs separated by blank lines, bullets
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

    /// The boxed form lines, if any.
    var formLines: [String] {
        for b in blocks { if case .form(let l) = b { return l } }
        return []
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

// MARK: - Block editor (Oct 13 2026)

extension AgreementContent.Block {
    /// The text the block editor edits, nil for blocks that are never edited (form, note).
    var editableText: String? {
        switch self {
        case .title(let t), .heading(let t), .bullet(let t): return t
        case .paragraph(let t, _): return t
        case .disclosure(_, let t): return t
        case .form, .note: return nil
        }
    }

    /// The same block with new text (kind, lead and state kept).
    func withText(_ t: String) -> Self {
        switch self {
        case .title: return .title(t)
        case .heading: return .heading(t)
        case .bullet: return .bullet(t)
        case .paragraph(_, let lead): return .paragraph(t, lead: lead)
        case .disclosure(let state, _): return .disclosure(state: state, text: t)
        case .form, .note: return self
        }
    }

    /// Locked in "Edit agreement": the form block, and any block holding fill-in blanks ("___" runs) or checkboxes (☐) —
    /// "THIS AGREEMENT is entered into on ______ (Date agreement is signed) …", the agent / client name and signature
    /// lines. Their field names can't be edited away; filling them in is the deferred e-sign add-on.
    var isLocked: Bool {
        switch self {
        case .form: return true
        case .note: return true
        default:
            let t = editableText ?? ""
            return t.contains("___") || t.contains("\u{2610}")
        }
    }

    /// Small label over the block in the editor.
    var editorLabel: String {
        switch self {
        case .title: return "Title"
        case .form: return "Form fields"
        case .paragraph: return "Paragraph"
        case .bullet: return "Bullet"
        case .heading: return "Heading"
        case .disclosure(let state, _): return "\(state) disclosure"
        case .note: return "Note"
        }
    }
}

/// How an edited agreement is stored in `CompanyProfile.agreementText` since the block editor (Oct 13 2026): JSON
/// `{"format":"vims-agreement-blocks","v":1,"blocks":[{"t":"title"|"p"|"li"|"h"|"state","text":…,"state":<name, t=state only>,
/// "lead":true|false,"locked":true|false}]}` — exactly Android's format, so the server can sync one shape. The locked form block isn't stored: its lines always come from the VIMS agreement and it always sits
/// right after the title. Text saved by earlier builds (plain text, blank-line paragraphs) still loads through
/// `AgreementContent.edited`.
struct EditedAgreement: Codable, Equatable {
    static let formatID = "vims-agreement-blocks"

    struct Stored: Codable, Equatable {
        var t: String                 // title | p | li | h | state
        var text: String
        var state: String?            // state NAME, only for t = state
        var lead: Bool = false
        var locked: Bool = false      // text holds a run of 3+ underscores or ☐ (recomputed when loaded)

        init(t: String, text: String, state: String? = nil, lead: Bool = false, locked: Bool = false) {
            self.t = t; self.text = text; self.state = state; self.lead = lead; self.locked = locked
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            t = try c.decodeIfPresent(String.self, forKey: .t) ?? "p"
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            state = try c.decodeIfPresent(String.self, forKey: .state)
            lead = try c.decodeIfPresent(Bool.self, forKey: .lead) ?? false
            locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        }
    }

    var format = EditedAgreement.formatID
    var v = 1
    var blocks: [Stored]

    init(blocks: [AgreementContent.Block]) {
        self.blocks = blocks.compactMap { b -> Stored? in
            let locked = b.isLocked
            switch b {
            case .title(let t): return Stored(t: "title", text: t, locked: locked)
            case .paragraph(let t, let lead): return Stored(t: "p", text: t, lead: lead, locked: locked)
            case .bullet(let t): return Stored(t: "li", text: t, locked: locked)
            case .heading(let t): return Stored(t: "h", text: t, locked: locked)
            case .disclosure(let state, let t): return Stored(t: "state", text: t, state: state, locked: locked)
            case .form, .note: return nil
            }
        }
    }

    /// The stored blocks, or nil when `text` is a plain-text edit from an earlier build.
    static func decode(_ text: String) -> EditedAgreement? {
        // Same detection as Android: JSON when it trims to "{…" and names the format; anything else is a legacy plain-text edit.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.contains(formatID), let data = trimmed.data(using: .utf8),
              let doc = try? JSONDecoder().decode(EditedAgreement.self, from: data), doc.format == formatID else { return nil }
        return doc
    }

    var encoded: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Viewer / PDF content: `{companyName}` filled, the form block (the VIMS agreement's lines) right after the title.
    func content(company: String, form: [String]) -> AgreementContent {
        func fill(_ t: String) -> String { InspectionAgreement.fill(t, company: company) }
        var out: [AgreementContent.Block] = blocks.compactMap { b in
            switch b.t {
            case "title": return .title(fill(b.text))
            case "form": return nil
            case "li": return .bullet(fill(b.text))
            case "h": return .heading(fill(b.text))
            case "state": return .disclosure(state: b.state ?? "", text: fill(b.text))
            default: return .paragraph(fill(b.text), lead: b.lead)
            }
        }
        if !form.isEmpty, !out.contains(where: { if case .form = $0 { return true } else { return false } }) {
            let at = out.firstIndex { if case .title = $0 { return true } else { return false } }.map { $0 + 1 } ?? 0
            out.insert(.form(form), at: at)
        }
        return AgreementContent(blocks: out)
    }
}
