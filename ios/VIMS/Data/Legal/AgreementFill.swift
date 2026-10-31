import Foundation

// Client Oct 30 (3), shared data v1.15.0 `agreementPrefill`: the inspection agreement fills in the client and inspection
// details already entered — label → value form lines, ☒ for the property type, inspection type, components, tests,
// utilities and "NO Report to Real Estate Agent." — and gets an "Email inspection agreement" button at the bottom.
// Everything here is pure (no store, no UI) so the filling can be checked on its own (DEBUG -oct30cStatus).

/// `agreementPrefill` in shared/data/vims-checklists.json. Read leniently: a malformed entry is skipped, never fatal.
struct AgreementPrefillDef: Decodable {
    struct Line: Hashable {
        var part: String           // "header" (the boxed form lines) | "closing"
        var label: String
        var occurrence: Int        // n-th line of that part containing the label (1 = first)
    }
    /// A box to tick: `box` is the agreement text beside it; `side` "after" = "Purchase ☐", "before" = "☐ Radon Testing",
    /// "none" = nothing to tick (Component: its components are ticked instead). `key` = the app value it stands for.
    struct Box: Hashable {
        var key: String
        var box: String
        var side: String
    }

    var lines: [Line] = []
    var propertyType: [Box] = []
    var inspectionType: [Box] = []
    var components: [Box] = []
    var tests: [Box] = []
    var utilities: [Box] = []
    var noAgentReport: Box?
    var emailLabel: String?

    private struct AnyKey: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        init(_ s: String) { stringValue = s }
    }

    init(lines: [Line] = [], propertyType: [Box] = [], inspectionType: [Box] = [], components: [Box] = [],
         tests: [Box] = [], utilities: [Box] = [], noAgentReport: Box? = nil, emailLabel: String? = nil) {
        self.lines = lines; self.propertyType = propertyType; self.inspectionType = inspectionType
        self.components = components; self.tests = tests; self.utilities = utilities
        self.noAgentReport = noAgentReport; self.emailLabel = emailLabel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        if var arr = try? c.nestedUnkeyedContainer(forKey: AnyKey("lines")) {
            while !arr.isAtEnd {
                guard let o = try? arr.nestedContainer(keyedBy: AnyKey.self) else { _ = try? arr.decode(Skip.self); continue }
                guard let label = try? o.decode(String.self, forKey: AnyKey("label")), !label.isEmpty else { continue }
                let part = (try? o.decode(String.self, forKey: AnyKey("part"))) ?? "header"
                let occ = (try? o.decode(Int.self, forKey: AnyKey("occurrence"))) ?? 1
                lines.append(Line(part: part, label: label, occurrence: max(occ, 1)))
            }
        }
        if let cb = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("checkboxes")) {
            func boxes(_ name: String, key: String) -> [Box] {
                guard var arr = try? cb.nestedUnkeyedContainer(forKey: AnyKey(name)) else { return [] }
                var out: [Box] = []
                while !arr.isAtEnd {
                    guard let o = try? arr.nestedContainer(keyedBy: AnyKey.self) else { _ = try? arr.decode(Skip.self); continue }
                    guard let k = try? o.decode(String.self, forKey: AnyKey(key)),
                          let box = try? o.decode(String.self, forKey: AnyKey("box")) else { continue }
                    out.append(Box(key: k, box: box, side: (try? o.decode(String.self, forKey: AnyKey("side"))) ?? "after"))
                }
                return out
            }
            propertyType = boxes("propertyType", key: "structure")
            inspectionType = boxes("inspectionType", key: "type")
            components = boxes("components", key: "component")
            tests = boxes("tests", key: "test")
            utilities = boxes("utilities", key: "utility")
            if let o = try? cb.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("noAgentReport")),
               let box = try? o.decode(String.self, forKey: AnyKey("box")) {
                noAgentReport = Box(key: "noAgentReport", box: box, side: (try? o.decode(String.self, forKey: AnyKey("side"))) ?? "after")
            }
        }
        if let e = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("emailButton")) {
            emailLabel = try? e.decode(String.self, forKey: AnyKey("label"))
        }
    }

    /// Swallows one array element of any shape.
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }
}

/// What the agreement is filled with — built from the wizard's current (unsaved) values or a saved inspection by
/// `make`, carried by the `.agreement` route. `lines` / `ticks` drive the text; the rest is for the email.
struct AgreementFill: Hashable {
    struct Line: Hashable {
        var part: String
        var label: String
        var occurrence: Int
        var value: String
    }
    struct Tick: Hashable {
        var box: String
        var side: String
    }

    var lines: [Line] = []
    var ticks: [Tick] = []

    var clientName = ""
    var clientEmail = ""
    /// Street line ("1428 Ridgeline Dr") for the email subject.
    var street = ""
    /// "<street>, <city>, <state> <zip>" (empty parts skipped).
    var fullAddress = ""
    /// "Nov 3, 2026 9:00 AM" (date only when no time).
    var dateTime = ""
    var stateCode = ""
    var emailLabel = "Email inspection agreement"

    /// Which app value each agreement label is filled with (the JSON's `value` describes it in words).
    enum Source { case clientName, clientPhone, clientEmail, inspectorName, license, state, dateTime, address, units, sqft, agentName, agentEmail }
    static let sources: [String: Source] = [
        "Clients Name": .clientName, "Phone #": .clientPhone, "Email": .clientEmail, "Inspectors Name": .inspectorName,
        "License/Reg #": .license, "State": .state, "Date and Time of Inspection": .dateTime,
        "Address of Property to be inspected": .address, "# Units": .units, "Total Sqft": .sqft,
        "Real Estate Agents Name": .agentName, "Agents Email": .agentEmail, "Printed Name of Client:": .clientName
    ]

    /// Builds the fill from an inspection (a saved one, or the wizard's draft with every step's current values).
    /// `inspectorName` = the signed-in inspector's full name.
    static func make(_ insp: Inspection, spec: AgreementPrefillDef?, wizard: WizardDef?, inspectorName: String) -> AgreementFill {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var f = AgreementFill()
        f.clientName = t(insp.clientName)
        f.clientEmail = t(insp.field("Client email"))
        f.street = t(insp.address.isEmpty ? "" : (insp.hasSplitAddress ? insp.address : insp.addressLine1))
        f.fullAddress = t(insp.displayAddress)
        f.dateTime = dateTime(date: insp.field("Date"), time: insp.field("Time"))
        f.stateCode = insp.stateCode
        if let l = spec?.emailLabel, !l.isEmpty { f.emailLabel = l }

        let units: String = {
            switch insp.structure {
            case "Multi-Unit":
                let n = insp.unitMix.values.reduce(0, +)
                return n > 0 ? "\(n)" : ""
            case "Duplex": return "2"
            default: return ""
            }
        }()
        func value(_ s: Source) -> String {
            switch s {
            case .clientName: return f.clientName
            case .clientPhone: return t(insp.field("Client phone"))
            case .clientEmail: return f.clientEmail
            case .inspectorName: return t(inspectorName)
            case .license: return t(insp.inspectorLicense)
            case .state: return f.stateCode
            case .dateTime: return f.dateTime
            case .address: return f.fullAddress
            case .units: return units
            case .sqft: return t(insp.field("Total sq ft"))
            case .agentName: return t(insp.field("Real estate agent name"))
            case .agentEmail: return t(insp.field("Real estate agent email"))
            }
        }
        f.lines = (spec?.lines ?? []).compactMap { l in
            guard let s = sources[l.label] else { return nil }
            return Line(part: l.part, label: l.label, occurrence: l.occurrence, value: value(s))
        }

        guard let spec else { return f }
        func tick(_ list: [AgreementPrefillDef.Box], _ picked: [String]) {
            for b in list where picked.contains(b.key) && b.side != "none" { f.ticks.append(Tick(box: b.box, side: b.side)) }
        }
        // Property type ("Mobile / Manufactured" isn't mapped: the agreement can't tell Mobile Home from Manufactured).
        tick(spec.propertyType, [insp.structure])
        // Type of inspection (Texas, Tests Only and retired types aren't mapped); Component ticks its components.
        tick(spec.inspectionType, [insp.inspType])
        if insp.inspType == "Component" { tick(spec.components, insp.components) }
        tick(spec.tests, insp.tests)
        // Utilities only count when the type uses them (data v1.10 areasLockedTypes keep the choices but ignore them).
        if !(wizard?.areasLocked(insp.inspType) ?? false) { tick(spec.utilities, insp.utilities) }
        if !insp.sendsReportToAgent, let b = spec.noAgentReport { f.ticks.append(Tick(box: b.box, side: b.side)) }
        return f
    }

    /// "Nov 3, 2026 9:00 AM" from the wizard's "yyyy-MM-dd" + "HH:mm" (date only when no time; "" when no date).
    static func dateTime(date: String, time: String) -> String {
        guard let d = Fmt.parse(date.trimmingCharacters(in: .whitespaces), "yyyy-MM-dd") else { return "" }
        let day = Fmt.date(d, "MMM d, yyyy")
        guard let tm = Fmt.parse(time.trimmingCharacters(in: .whitespaces), "HH:mm") else { return day }
        return "\(day) \(Fmt.date(tm, "h:mm a"))"
    }

    /// The PDF's file name: "Inspection-Agreement-<Client-Name>.pdf", the company's name when there is no client name.
    func fileName(company: String) -> String {
        AgreementContent.fileName(company: clientName.isEmpty ? company : clientName)
    }

    // MARK: Filling (pure)

    /// Filled values are wrapped in these private-use markers so the viewer and the PDF can draw them bold.
    static let boldOpen: Character = "\u{E000}"
    static let boldClose: Character = "\u{E001}"
    static let emptyBox: Character = "\u{2610}"     // ☐
    static let tickedBox: Character = "\u{2612}"    // ☒

    /// The content with the form lines (header) and closing lines filled and the mapped boxes ticked. The form block is
    /// the agreement's header; "closing" labels are looked up in the other text blocks (the VIMS closing, or wherever a
    /// company's edited version still has them). A label that is gone is skipped.
    func apply(to content: AgreementContent) -> AgreementContent {
        var blocks = content.blocks
        // Header labels: the n-th form line containing the label.
        if let fi = blocks.firstIndex(where: { if case .form = $0 { return true } else { return false } }),
           case .form(var form) = blocks[fi] {
            for l in lines where l.part == "header" {
                var seen = 0
                for i in form.indices where Self.contains(form[i], label: l.label) {
                    seen += 1
                    guard seen == l.occurrence else { continue }
                    if let filled = Self.fillLine(form[i], label: l.label, value: l.value) { form[i] = filled }
                    break
                }
            }
            blocks[fi] = .form(form)
        }
        // Closing labels: the n-th text block (outside the form) containing the label with a blank after it.
        for l in lines where l.part != "header" {
            var seen = 0
            for i in blocks.indices {
                guard let text = blocks[i].fillableText, Self.contains(text, label: l.label) else { continue }
                seen += 1
                guard seen == l.occurrence else { continue }
                if let filled = Self.fillLine(text, label: l.label, value: l.value) { blocks[i] = blocks[i].withFillableText(filled) }
                break
            }
        }
        // Boxes: the first matching unticked box anywhere (form lines first, then the text blocks).
        for tk in ticks {
            var done = false
            for i in blocks.indices where !done {
                if case .form(var form) = blocks[i] {
                    for j in form.indices where !done {
                        if let t = Self.tickBox(form[j], box: tk.box, side: tk.side) { form[j] = t; done = true }
                    }
                    if done { blocks[i] = .form(form) }
                } else if let text = blocks[i].fillableText, let t = Self.tickBox(text, box: tk.box, side: tk.side) {
                    blocks[i] = blocks[i].withFillableText(t); done = true
                }
            }
        }
        return AgreementContent(blocks: blocks)
    }

    /// Replaces the first run of underscores after `label` with the value (bold-marked). Nil when the label or the
    /// blank isn't there, or the value is empty (the underscores stay). A single space separates label and value:
    /// "Clients Name ____" → "Clients Name Jane Doe", "Date and Time of Inspection____" → "… Inspection Nov 3, 2026".
    /// Text already filled in (between the markers) is never searched, so a value can't be mistaken for a label.
    static func fillLine(_ line: String, label: String, value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .filter { $0 != boldOpen && $0 != boldClose }
        guard !v.isEmpty else { return nil }
        let chars = Array(line), masked = mask(chars)
        guard let at = find(Array(label), in: masked, from: 0) else { return nil }
        guard let start = masked[(at + label.count)...].firstIndex(of: "_") else { return nil }
        var end = start
        while end < masked.count, masked[end] == "_" { end += 1 }
        let lead = start > 0 && chars[start - 1].isWhitespace ? "" : " "
        return String(chars[..<start]) + lead + String(boldOpen) + v + String(boldClose) + String(chars[end...])
    }

    /// True when the line holds `label` outside any filled-in value.
    static func contains(_ line: String, label: String) -> Bool {
        find(Array(label), in: mask(Array(line)), from: 0) != nil
    }

    /// Ticks the ☐ right after ("Purchase ☐") or right before ("☐ Radon Testing") `box` (spaces between allowed).
    /// Nil when there's no such unticked box. The box text must stand on its own (not the tail / start of a longer label).
    static func tickBox(_ line: String, box: String, side: String) -> String? {
        guard side == "after" || side == "before" else { return nil }
        var chars = Array(line)
        let masked = mask(chars), b = Array(box)
        var from = 0
        while let at = find(b, in: masked, from: from) {
            from = at + 1
            let endAt = at + b.count
            if side == "after" {
                if at > 0, masked[at - 1].isLetter { continue }
                var i = endAt
                while i < masked.count, masked[i] == " " { i += 1 }
                if i < masked.count, masked[i] == emptyBox { chars[i] = tickedBox; return String(chars) }
            } else {
                if endAt < masked.count, masked[endAt].isLetter { continue }
                var i = at
                while i > 0, masked[i - 1] == " " { i -= 1 }
                if i > 0, masked[i - 1] == emptyBox { chars[i - 1] = tickedBox; return String(chars) }
            }
        }
        return nil
    }

    /// The characters with every filled-in value (markers included) blanked out, same length.
    private static func mask(_ chars: [Character]) -> [Character] {
        var inside = false
        return chars.map { c in
            if c == boldOpen { inside = true; return "\u{E002}" }
            if c == boldClose { inside = false; return "\u{E002}" }
            return inside ? "\u{E002}" : c
        }
    }

    private static func find(_ needle: [Character], in hay: [Character], from: Int) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count, from <= hay.count - needle.count else { return nil }
        for i in from...(hay.count - needle.count) where hay[i] == needle[0] {
            if Array(hay[i..<(i + needle.count)]) == needle { return i }
        }
        return nil
    }

    /// A text split for drawing: plain runs, bold (filled) runs, and single box glyphs (drawn with a font that has
    /// both ☐ and ☒).
    struct Segment: Equatable {
        enum Kind: Equatable { case plain, bold, box }
        var text: String
        var kind: Kind
    }

    static func segments(_ s: String) -> [Segment] {
        var out: [Segment] = []
        var cur = ""
        var bold = false
        func flush() { if !cur.isEmpty { out.append(Segment(text: cur, kind: bold ? .bold : .plain)); cur = "" } }
        for ch in s {
            switch ch {
            case boldOpen: flush(); bold = true
            case boldClose: flush(); bold = false
            case emptyBox, tickedBox: flush(); out.append(Segment(text: String(ch), kind: .box))
            default: cur.append(ch)
            }
        }
        flush()
        return out
    }

    /// The text without the bold markers (plain copies, accessibility).
    static func plain(_ s: String) -> String { s.filter { $0 != boldOpen && $0 != boldClose } }
}

extension AgreementContent.Block {
    /// The text a closing label / box can be filled in (paragraphs and bullets; not the title, headings, disclosures).
    var fillableText: String? {
        switch self {
        case .paragraph(let t, _), .bullet(let t): return t
        default: return nil
        }
    }

    func withFillableText(_ t: String) -> Self {
        switch self {
        case .paragraph(_, let lead): return .paragraph(t, lead: lead)
        case .bullet: return .bullet(t)
        default: return self
        }
    }
}
