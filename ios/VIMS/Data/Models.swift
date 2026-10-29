import Foundation

// MARK: - Depth

enum Depth: String, Codable, CaseIterable, Hashable {
    case high, standard, fast

    /// Wizard/Settings chip label (from JSON `depths`).
    var label: String {
        switch self {
        case .high: return "High Detail"
        case .standard: return "Standard"
        case .fast: return "Fast Entry"
        }
    }

    init(label: String) {
        switch label {
        case "High Detail": self = .high
        case "Fast Entry": self = .fast
        default: self = .standard
        }
    }
}

enum SectionStatus: String, Codable { case todo, prog, done }

// MARK: - Checklist groups (output of the checklist builder)

struct ChecklistGroup: Codable, Hashable, Identifiable {
    var id: String { heading }
    var heading: String
    var icon: String?
    var link: String?              // "inspectionInfo" | "summary"
    var sections: [String]
    var sub: ChecklistSubGroup?

    var leafSections: [String] { sections + (sub?.sections ?? []) }
}

struct ChecklistSubGroup: Codable, Hashable {
    var heading: String
    var sections: [String]
}

// MARK: - Answers

struct SectionAnswers: Codable, Hashable {
    var choices: [String: [String]] = [:]   // item key -> selected options
    var text: [String: String] = [:]        // item key -> text/num/date/time value
    var detail: [String: String] = [:]      // item key -> "Detail / measurement" (High Detail fallback)
    var present: [String] = []              // Fast Entry "Items reviewed" (stored as `present` for saved data)
    var overall: String?
    var comments: String = ""

    var hasContent: Bool {
        choices.values.contains { !$0.isEmpty } || text.values.contains { !$0.isEmpty } ||
        detail.values.contains { !$0.isEmpty } || !present.isEmpty || !comments.isEmpty
    }

    // MARK: Indoor Air Quality readings (data v1.7 `airReading`)
    // Level measured -> text[key] (optional, non-negative number); rating "1"…"6" -> choices[key] (single).

    func airLevel(_ key: String) -> String { text[key] ?? "" }
    func airRating(_ key: String) -> String? { choices[key]?.first }

    /// Before v1.7 the IAQ readings were plain single-choice items ("Formaldehyde (HCHO)": "1 Good", "2", …) under
    /// other answer keys. Moves such a saved choice onto the matching reading's rating (by pollutant code) when that
    /// reading has none yet; answers that don't map are left alone (and simply aren't shown).
    func migratingLegacyAirRatings(_ keyed: [KeyedItem]) -> SectionAnswers {
        let readings = keyed.filter { $0.item.kind == .airReading }
        guard !readings.isEmpty else { return self }
        let current = Set(keyed.map(\.id))
        var out = self
        for r in readings where out.choices[r.id]?.isEmpty ?? true {
            guard let code = r.item.code?.lowercased(), !code.isEmpty else { continue }
            let options = r.item.options ?? []
            let legacy = out.choices.keys.sorted().first { k in
                guard !current.contains(k), !(out.choices[k]?.isEmpty ?? true) else { return false }
                return Self.legacyQuestion(k).contains(code)
            }
            guard let lk = legacy, let old = out.choices[lk]?.first,
                  let digit = old.trimmingCharacters(in: .whitespaces).first.map(String.init), options.contains(digit) else { continue }
            out.choices[r.id] = [digit]
            out.choices[lk] = nil
        }
        return out
    }

    /// "Readings (…)›HCHO (Formaldehyde)#1" -> {"hcho (formaldehyde)", "hcho", "formaldehyde"}.
    private static func legacyQuestion(_ key: String) -> Set<String> {
        var q = key.components(separatedBy: "›").last ?? key
        if let r = q.range(of: #"#\d+$"#, options: .regularExpression) { q = String(q[..<r.lowerBound]) }
        q = q.trimmingCharacters(in: .whitespaces).lowercased()
        var out: Set<String> = [q]
        if let open = q.firstIndex(of: "("), let close = q.lastIndex(of: ")"), open < close {
            out.insert(q[..<open].trimmingCharacters(in: .whitespaces))
            out.insert(q[q.index(after: open)..<close].trimmingCharacters(in: .whitespaces))
        }
        return out
    }

    /// Answers saved before the item list changed, moved onto the current items (view and report alike).
    func migratingLegacy(_ keyed: [KeyedItem]) -> SectionAnswers {
        migratingLegacyAirRatings(keyed).migratingSplitDateTime(keyed)
    }

    /// Data v1.9.1 (team QA Oct 22): Meth Test (High Detail) "Test date and time" (free text) + "AM/PM" became a
    /// "Test date" date picker and a "Test time" time picker. An old typed answer moves onto them when they're empty:
    /// a time in it ("2:30", "2:30 pm", "2pm"; AM/PM from the old chips when the text has none) → Test time, the rest
    /// → Test date when it reads as a date ("10/12/2026", "Oct 12, 2026"), else the old text is kept as Test date's
    /// answer (shown and printed as typed). The old keys are then dropped.
    func migratingSplitDateTime(_ keyed: [KeyedItem]) -> SectionAnswers {
        var out = self
        for d in keyed where d.item.kind == .date {
            guard let q = d.item.q, q.lowercased().hasSuffix(" date"), (out.text[d.id] ?? "").isEmpty else { continue }
            let prefix = d.id.components(separatedBy: "›").dropLast().joined(separator: "›")
            let path = { (question: String) in prefix.isEmpty ? "›\(question)" : "\(prefix)›\(question)" }
            let legacyKey = path("\(q) and time")
            guard let old = out.text[legacyKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !old.isEmpty else { continue }
            let timeQ = String(q.dropLast(4)) + "time"
            let timeItem = keyed.first { $0.item.kind == .time && $0.item.q?.caseInsensitiveCompare(timeQ) == .orderedSame }
            let meridiem = out.choices[path("AM/PM")]?.first
            var rest = old
            if let t = timeItem, (out.text[t.id] ?? "").isEmpty, let (hhmm, range) = Self.legacyTime(in: old, meridiem: meridiem) {
                out.text[t.id] = hhmm
                rest.removeSubrange(range)
            }
            rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,;-@").union(.whitespaces))
            if rest.lowercased().hasSuffix(" at") { rest = String(rest.dropLast(3)) }
            if let date = Fmt.answerDate(rest) ?? Self.detectedDate(rest) {
                out.text[d.id] = Fmt.date(date, Fmt.answerDateFormat)
            } else {
                out.text[d.id] = old
            }
            out.text[legacyKey] = nil
            out.choices[path("AM/PM")] = nil
        }
        return out
    }

    /// "2:30 pm" / "14:30" / "2pm" in a typed answer → ("HH:mm", its range). `meridiem` ("AM"/"PM") applies when the
    /// text has none.
    private static func legacyTime(in s: String, meridiem: String?) -> (String, Range<String.Index>)? {
        let patterns = [#"(\d{1,2}):(\d{2})\s*([ap])?\.?\s*(m\.?)?"#, #"(\d{1,2})\s*([ap])\.?\s*m\.?"#]
        for (i, p) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r = Range(m.range, in: s) else { continue }
            func group(_ n: Int) -> String? { Range(m.range(at: n), in: s).map { String(s[$0]) } }
            guard var h = Int(group(1) ?? "") else { continue }
            let min = i == 0 ? Int(group(2) ?? "") ?? 0 : 0
            let ap = (i == 0 ? group(3) : group(2))?.lowercased() ?? meridiem?.prefix(1).lowercased()
            if ap == "p", h < 12 { h += 12 }
            if ap == "a", h == 12 { h = 0 }
            guard (0...23).contains(h), (0...59).contains(min) else { continue }
            return (String(format: "%02d:%02d", h, min), r)
        }
        return nil
    }

    private static func detectedDate(_ s: String) -> Date? {
        guard !s.isEmpty, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        return det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))?.date
    }
}

// MARK: - Photos & findings

struct PhotoRef: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var file: String                 // relative path under the app data folder
    var originalFile: String?        // unmarked original, kept once markup is applied
    var flag: Int?                   // finding category 1/2/3
    var comment: String?
    var takenAt: Date = Date()
}

struct Finding: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var category: Int
    var text: String
    var section: String
    var photoID: UUID?
    var createdAt: Date = Date()
    /// The checklist item a "Concern(s)" answer was flagged on (its question), nil for a section / photo finding.
    /// Optional so findings saved before it still decode. TODO(backend): sync with the finding.
    var item: String? = nil
    /// Client Oct 16: the custom comment (a Concern's "<item>: <description>") and the quick comment, kept apart so
    /// the Summary screen and the report print "Section — custom — quick". nil on findings saved before that; they
    /// fall back to `text`, which stays the combined "custom — quick" line. TODO(backend): sync with the finding.
    var custom: String? = nil
    var quick: String? = nil

    /// The comment parts after the bold section name, empty ones dropped (prototype `findingLine`).
    var lineParts: [String] {
        let parts = (custom != nil || quick != nil) ? [custom ?? "", quick ?? ""] : [text]
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// "custom — quick" (or the stored text) — the finding without its section.
    var detail: String { lineParts.joined(separator: " — ") }

    /// The typed comment without a copy of the picked quick comment (a description that repeats it, or starts with
    /// it, e.g. a photo comment carried over as "quick — custom"), so the line never shows the quick comment twice.
    static func customPart(_ typed: String, quick: String) -> String {
        var c = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quick.isEmpty else { return c }
        if c == quick { return "" }
        if c.hasPrefix(quick) {
            c = String(c.dropFirst(quick.count))
            c = String(c.drop { $0.isWhitespace || "—–-:;,.".contains($0) })
        }
        return c
    }
}

// MARK: - Cover

/// The report cover: color, theme (category + picture; an empty `option` is "No picture") and style
/// (Shaded / Framed / Solid). Client Oct 17 (data v1.8): Solid is a style, not a category, and may carry a picture.
struct CoverChoice: Codable, Hashable {
    var color: String
    var category: String
    var option: String
    var style: String

    /// Before v1.8 "Solid" was a theme category (with no picture).
    static let legacySolidCategory = "Solid"

    init(color: String, category: String, option: String, style: String) {
        self.color = color; self.category = category; self.option = option; self.style = style
        migrateLegacySolid()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decode(String.self, forKey: .color)
        category = try c.decode(String.self, forKey: .category)
        option = try c.decodeIfPresent(String.self, forKey: .option) ?? ""
        style = try c.decode(String.self, forKey: .style)
        migrateLegacySolid()
    }

    /// A cover saved with the old "Solid" category becomes style Solid + No picture (no category chosen; the picker
    /// then lists the first category's pictures).
    private mutating func migrateLegacySolid() {
        guard category == Self.legacySolidCategory else { return }
        category = ""
        option = ""
        style = "Solid"
    }

    var hasPicture: Bool { !option.isEmpty }
    var label: String { "\(color) · \(hasPicture ? option : "No picture") · \(style)" }
    var artLabel: String { hasPicture ? option : color }
}

/// The client was given the state's required documents (stateRules[state].docs) with the inspection
/// agreement — the wizard's "Provided to the client with the inspection agreement" checkbox.
/// TODO(backend): send with the inspection as the compliance record.
struct StateDocsAck: Codable, Hashable {
    var state: String
    var docs: [String]
    var acknowledgedAt: Date
}

struct ReportInfo: Codable, Hashable {
    var generatedAt: Date
    var pageCount: Int
    var file: String
}

// MARK: - Inspection

struct Inspection: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// Values for the JSON-driven wizard fields & chips (step1/step2), keyed by label.
    var fields: [String: String] = [:]
    var inspType: String
    var components: [String] = []
    var structure: String
    var unitMix: [String: Int] = [:]
    var storiesOther: String = ""
    var depth: Depth
    /// Property state (USPS code from `states`, data v1.3), required on wizard step 1. Optional so
    /// inspections saved before v1.3 still decode.
    var state: String?
    /// Acknowledgment that the state documents were given to the client (only valid for `state`).
    var stateDocsAck: StateDocsAck?
    /// Step 1 "Send the report to the real estate agent" (data v1.4). nil (inspections saved before v1.4) = on.
    /// Reset to the state's `agentCopyDefault` whenever the state changes (off for New Hampshire).
    var sendToAgent: Bool?

    // Areas to inspect
    var exterior: [String]
    var rooms: [String]
    var utilities: [String]
    var tests: [String]
    var counts: [String: Int]

    var groups: [ChecklistGroup] = []
    /// Client Oct 28: the company's edited / custom section definitions this inspection was using when an admin restored
    /// the checklist to the VIMS original (keyed by section name). They win over the company's current checklist, so an
    /// inspection already created keeps its saved checklist. nil = none saved (uses the company checklist).
    var savedSections: [String: SectionDef]?
    var status: [String: SectionStatus] = [:]
    var answers: [String: SectionAnswers] = [:]
    var photos: [String: [String: [PhotoRef]]] = [:]
    var findings: [Finding] = []
    var cover: CoverChoice
    var report: ReportInfo?

    // Sync state (offline-first)
    var needsSync: Bool = true
    var syncedAt: Date?

    // Convenience accessors for well-known wizard fields
    func field(_ label: String) -> String { fields[label] ?? "" }

    var address: String { field("Inspection address") }
    var stateCode: String { state ?? "" }

    // Client Oct 17: the address is split — "Inspection address" (street), City, State (existing), ZIP code.
    static let streetField = "Inspection address"
    static let cityField = "City"
    static let zipField = "ZIP code"
    var city: String { field(Self.cityField).trimmingCharacters(in: .whitespaces) }
    var zip: String { field(Self.zipField).trimmingCharacters(in: .whitespaces) }
    /// Inspections created before Oct 17 (or not yet split) keep one combined "Street, City, ZIP" text.
    var hasSplitAddress: Bool { !city.isEmpty }
    /// "City, ST ZIP" — the cover's 2nd address line and the list subtitle's place.
    var cityStateZip: String {
        let stZip = [stateCode, zip].filter { !$0.isEmpty }.joined(separator: " ")
        return [city, stZip].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Splits an older combined address ("1428 Ridgeline Dr, Ogden, UT 84403", "210 Willow Park, Lot 17, Ogden 84401")
    /// into the street, City, State and ZIP code fields. Only when it reads cleanly (a street, then a city); otherwise the
    /// text stays as it is and still shows everywhere (the wizard then asks for the City on the next edit). A state
    /// already chosen in the State field wins over one written in the text. Returns true when something changed.
    @discardableResult
    mutating func splitLegacyAddress(states: [StateDef]) -> Bool {
        guard city.isEmpty else { return false }
        var parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count >= 2 else { return false }
        var street = parts.removeFirst()
        while let p = parts.first, p.range(of: #"^((Lot|Unit|Apt|Suite|Ste|Space|Bldg)\b|#)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            street += ", " + p; parts.removeFirst()
        }
        let codes = Set(states.map(\.code))
        var zip = "", st = ""
        if var toks = parts.last?.split(separator: " ").map(String.init) {
            if let t = toks.last, t.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil { zip = t; toks.removeLast() }
            if let t = toks.last, t.count == 2, t == t.uppercased(), codes.contains(t) { st = t; toks.removeLast() }
            if toks.isEmpty { parts.removeLast() } else { parts[parts.count - 1] = toks.joined(separator: " ") }
        }
        if st.isEmpty, let l = parts.last, l.count == 2, l == l.uppercased(), codes.contains(l) { st = l; parts.removeLast() }
        let cityText = parts.joined(separator: ", ")
        guard !cityText.isEmpty, !street.isEmpty else { return false }
        fields[Self.streetField] = street
        fields[Self.cityField] = cityText
        if !zip.isEmpty { fields[Self.zipField] = zip }
        if state == nil, !st.isEmpty { state = st }
        return true
    }
    /// Emailed reports include the agent (To) only when this is on.
    var sendsReportToAgent: Bool { sendToAgent ?? true }

    /// The address as shown everywhere (lists, headers, report, email): the typed "Street, City, ZIP" plus
    /// the State field — "12 Elm St, Portland, OR 97201" (state before a trailing ZIP), else "…, OR".
    /// Left alone when there is no state or the address already names it (inspections before v1.3).
    var displayAddress: String {
        if hasSplitAddress {
            return [address.trimmingCharacters(in: .whitespaces), cityStateZip].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        let a = address.trimmingCharacters(in: .whitespaces)
        let st = stateCode
        guard !st.isEmpty, !a.isEmpty else { return a }
        var parts = a.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let alreadyNamed = parts.dropFirst().contains { p in
            p.split(separator: " ").contains { $0.uppercased() == st }
        }
        if alreadyNamed { return a }
        if let last = parts.last, parts.count > 1, last.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil {
            parts[parts.count - 1] = "\(st) \(last)"
            return parts.joined(separator: ", ")
        }
        return (parts + [st]).joined(separator: ", ")
    }

    /// Picks the property state the way the wizard does (stateRules `_about`): clears the documents
    /// acknowledgment, reverts an auto-selected type when the state changes away from it, and auto-selects
    /// the state's required inspection type (TX → Texas).
    mutating func setState(_ code: String?, config: ChecklistConfig) {
        let prev = config.stateRule(state)
        let new = config.stateRule(code)
        if code != state {
            stateDocsAck = nil
            sendToAgent = new?.agentCopyDefault ?? true     // stateRules agentCopyDefault (NH → off)
        }
        state = (code?.isEmpty ?? true) ? nil : code
        if let auto = prev?.type, inspType == auto, new?.type != auto {
            inspType = config.wizard.defaults.inspType ?? ""    // v1.9.1: none preselected (the inspector picks one)
        }
        if let t = new?.type, config.wizard.inspectionTypes.contains(t), inspType != t { inspType = t }
    }

    /// A state code written into an older free-form address ("Ogden, UT 84403" -> "UT"), used to prefill
    /// the State field for inspections created before v1.3 (and the demo seed).
    static func inferState(from address: String, states: [StateDef]) -> String? {
        let codes = Set(states.map(\.code))
        let rest = address.split(separator: ",").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        for part in rest.reversed() {
            for tok in part.split(separator: " ").map(String.init) where tok.count == 2 && tok == tok.uppercased() && codes.contains(tok) {
                return tok
            }
        }
        return nil
    }

    /// The state documents still have to be acknowledged before step 1 can continue.
    func stateDocsPending(_ config: ChecklistConfig) -> Bool {
        guard let r = config.stateRule(state), !r.requiredDocs.isEmpty else { return false }
        return stateDocsAck?.state != state
    }

    /// Street line, keeping unit/lot suffixes ("210 Willow Park, Lot 17").
    private var addressSplit: (String, String) {
        if hasSplitAddress { return (address.trimmingCharacters(in: .whitespaces), cityStateZip) }
        let parts = displayAddress.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard var line = parts.first else { return ("", "") }
        var i = 1
        while i < parts.count, parts[i].range(of: #"^((Lot|Unit|Apt|Suite|Ste|Space|Bldg)\b|#)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            line += ", " + parts[i]; i += 1
        }
        return (line, parts.dropFirst(i).joined(separator: ", "))
    }
    var addressLine1: String {
        let a = addressSplit.0
        return a.isEmpty ? "New inspection" : a
    }
    var addressRest: String { addressSplit.1 }
    var cityShort: String {
        if hasSplitAddress { return [city, stateCode].filter { !$0.isEmpty }.joined(separator: ", ") }
        // "Ogden, UT 84403" -> "Ogden, UT"
        let rest = addressRest
        let comps = rest.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard comps.count >= 2 else { return rest }
        let state = comps[1].split(separator: " ").first.map(String.init) ?? comps[1]
        return "\(comps[0]), \(state)"
    }
    var clientName: String { field("Client name") }

    /// v1.9 form `prefill` values (Wind Mitigation / WDI): the inspection's client and address, the inspector's initials.
    /// `inspector` = the inspection's inspector (falls back to the signed-in user). "licenseType": VIMS inspectors are home
    /// inspectors (there's no license-type field yet; editable on the form, same as Android).
    func prefillValue(_ key: String, inspector: String) -> String {
        switch key {
        case "client": return clientName
        case "street": return hasSplitAddress ? address.trimmingCharacters(in: .whitespaces) : addressLine1
        case "city": return hasSplitAddress ? city : (cityShort.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "")
        case "zip": return hasSplitAddress ? zip : (displayAddress.range(of: #"\d{5}(-\d{4})?$"#, options: .regularExpression).map { String(displayAddress[$0]) } ?? "")
        case "clientPhone": return field("Client phone")
        case "clientEmail": return field("Client email")
        case "licenseType": return "Home Inspector"
        case "initials":
            let name = field("Inspector").isEmpty ? inspector : field("Inspector")
            return String(name.split(separator: " ").compactMap { $0.first(where: \.isLetter).map { String($0).uppercased() } }.joined().prefix(4))
        default: return ""
        }
    }

    var scheduled: Date {
        let d = field("Date"), t = field("Time")
        if let dt = Fmt.parse("\(d) \(t.isEmpty ? "09:00" : t)", "yyyy-MM-dd HH:mm") { return dt }
        return createdAt
    }

    var leafSections: [String] { groups.flatMap { $0.leafSections } }

    /// Layouts without a Summary entry (4 Point) hide "Review summary" and never route to Summary.
    var hasSummary: Bool { groups.isEmpty || groups.contains { $0.link == "summary" } }

    static let licenseField = "Inspector License #"
    var inspectorLicense: String { field(Inspection.licenseField) }

    var photoCount: Int { photos.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }

    var structureShort: String {
        switch structure {
        case "Mobile / Manufactured": return "Mobile home"
        default: return structure
        }
    }
}

// MARK: - Company, people, subscription, settings

struct Inspector: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var owner: Bool = false
    var admin: Bool = false

    var isAdmin: Bool { owner || admin }
    var roleLabel: String { owner ? "Owner · Admin" : (admin ? "Admin" : "Inspector") }
}

struct CompanyProfile: Codable, Hashable {
    var name: String
    var address: String
    var joinCode: String
    var inspectorName: String
    var license: String = ""
    var phone: String = ""
    var email: String
    var reviewURL: String = ""
    var logoFile: String?                 // relative path, nil = bundled VIMS logo
    var agreementFile: String?            // relative path
    var agreementName: String?
    /// The company's edited copy of the VIMS agreement (plain text, Company profile → Edit). Only ever this company's
    /// copy — the VIMS agreement itself never changes. nil = not edited. TODO(backend): sync to the company record.
    var agreementText: String?
    var agreementEditedAt: Date?
    var feedbackEmail: String
    var inspectors: [Inspector]
}

/// Subscription billing period (client Oct 28, data v1.11). Plans with `priceYearly` offer both; extra inspectors follow
/// the company's period.
enum BillingPeriod: String, Codable, CaseIterable, Hashable {
    case monthly, yearly
    var label: String { self == .yearly ? "Yearly" : "Monthly" }
    /// "/mo" | "/yr"
    var unit: String { self == .yearly ? "/yr" : "/mo" }
    /// "Monthly total" | "Yearly total"
    var totalLabel: String { "\(label) total" }
}

struct SubscriptionState: Codable, Hashable {
    /// The VIMS plan list. Since client Oct 28 (data v1.11) plans and prices are VIMS-wide, owned by the master admin
    /// (`PlatformSettings.pricing`): `AppStore` mirrors them in here on every session load, so a company's stored copy
    /// is never the source of truth (older builds stored a per-company copy that company admins could edit).
    var plans: [PlanDef]
    var extraInspectorMonthly: Double
    var selectedPlan: String
    var trialStart: Date
    var trialDays: Int
    var active: Bool = false
    var paymentLabel: String?
    /// QA Oct 14: the remembered card (brand / last 4 / expiry only — see `CardOnFile`), offered on the next update.
    var cardOnFile: CardOnFile?
    var startedAt: Date?
    /// Set when an owner/admin cancels: the subscription stays active until `nextBillingDate`,
    /// then stops renewing. Optional so older saved data still decodes.
    var cancelledAt: Date?
    /// True when this company was created on a device that had already used its free trial (one trial per device,
    /// `DeviceTrial`): it started with the trial used up. nil on older saved data.
    var deviceTrialUsed: Bool?
    /// v1.11: per-inspector yearly rate (mirrored like `plans`). nil on older saved data → monthly × 12.
    var extraInspectorYearly: Double?
    /// v1.11: the company's billing period ("monthly" | "yearly"). nil on older saved data = monthly.
    var billingPeriod: String?
    /// v0.23 (EULA 2026-10-28, 4.1 / 12.3 / 12.4): a cancelled YEARLY plan ends on the cancellation date (`active` goes
    /// false) with a pro-rated refund for the unused days. A cancelled monthly plan keeps `active` and runs to
    /// `nextBillingDate` as before. All optional, so older saved data still decodes.
    var endedAt: Date?
    var refundAmount: Double?
    var refundDays: Int?
    /// What the current period was charged (Start / Update subscription). nil on older data → today's total.
    var paidAmount: Double?

    /// Monthly cancellation pending: still active until `nextBillingDate`.
    var cancelled: Bool { active && cancelledAt != nil }

    /// A yearly subscription that was cancelled: access ended on `endedAt` (no new inspections until subscribing again).
    var subscriptionEnded: Bool { !active && endedAt != nil }

    /// No active subscription and no free trial left (the trial is over, or a yearly cancel ended the subscription):
    /// no new inspections (Subscribe prompt).
    var trialEnded: Bool { !active && (trialDaysLeft == 0 || endedAt != nil) }

    func plan(_ id: String) -> PlanDef? { plans.first { $0.id == id } }

    var trialDaysLeft: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: trialStart),
                                                      to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return max(0, trialDays - elapsed)
    }

    /// The company's period for its current plan (a plan without a yearly price is always monthly).
    var period: BillingPeriod {
        let p = BillingPeriod(rawValue: billingPeriod ?? "") ?? .monthly
        return plan(selectedPlan)?.hasYearly == true ? p : .monthly
    }

    /// Each additional inspector for a period.
    func extraRate(_ period: BillingPeriod) -> Double {
        period == .yearly ? (extraInspectorYearly ?? extraInspectorMonthly * 12) : extraInspectorMonthly
    }

    /// A plan's price for a period (the per-report price for Pay per report).
    static func price(_ p: PlanDef, _ period: BillingPeriod) -> Double {
        period == .yearly && p.hasYearly ? (p.priceYearly ?? p.price) : p.price
    }

    /// "$34.95/mo" · "$385.00/yr" · "$5.00/report"
    static func priceLabel(_ p: PlanDef, _ period: BillingPeriod) -> String {
        if p.isPerReport { return Fmt.money(p.price) + (p.unit ?? "/report") }
        let per: BillingPeriod = p.hasYearly ? period : .monthly
        return Fmt.money(price(p, per)) + per.unit
    }

    /// Plan + additional inspectors for a plan / period (0 for Pay per report).
    func total(plan p: PlanDef?, period: BillingPeriod, seats: Int) -> Double {
        guard let p, !p.isPerReport else { return 0 }
        let per: BillingPeriod = p.hasYearly ? period : .monthly
        return Self.price(p, per) + Double(max(0, seats - 1)) * extraRate(per)
    }

    /// "$84.85/mo" · "$935.00/yr" · "$5.00 / report"
    func totalLabel(plan p: PlanDef?, period: BillingPeriod, seats: Int) -> String {
        guard let p else { return "" }
        if p.isPerReport { return Fmt.money(p.price) + " / report" }
        let per: BillingPeriod = p.hasYearly ? period : .monthly
        return Fmt.money(total(plan: p, period: per, seats: seats)) + per.unit
    }

    /// The company's current plan + period total.
    func total(seats: Int) -> Double { total(plan: plan(selectedPlan), period: period, seats: seats) }
    func totalLabel(seats: Int) -> String { totalLabel(plan: plan(selectedPlan), period: period, seats: seats) }

    /// The billing period that contains `date`; periods roll forward from `startedAt` (auto-renew).
    func billingPeriodBounds(containing date: Date) -> (start: Date, end: Date) {
        let start = startedAt ?? date
        let cal = Calendar.current, unit: Calendar.Component = period == .yearly ? .year : .month
        var n = 0
        while n < 1200, let end = cal.date(byAdding: unit, value: n + 1, to: start) {
            if end > date { return (cal.date(byAdding: unit, value: n, to: start) ?? start, end) }
            n += 1
        }
        return (start, cal.date(byAdding: unit, value: 1, to: start) ?? start)
    }

    /// The next renewal (for a pending monthly cancellation: the end of the period it was cancelled in).
    var nextBillingDate: Date { billingPeriodBounds(containing: cancelledAt ?? Date()).end }

    /// EULA 4.1 / 12.4 — cancelling a yearly plan: price paid × days remaining ÷ days in the period, rounded to cents.
    func proratedRefund(on date: Date = Date(), seats: Int) -> (amount: Double, daysLeft: Int, daysInPeriod: Int, paid: Double) {
        let cal = Calendar.current
        let b = billingPeriodBounds(containing: date)
        let day = { (a: Date, z: Date) in cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: z)).day ?? 0 }
        let inPeriod = max(1, day(b.start, b.end))
        let left = min(inPeriod, max(0, day(date, b.end)))
        let paid = paidAmount ?? total(seats: seats)
        let amount = (paid * Double(left) / Double(inPeriod) * 100).rounded(.toNearestOrAwayFromZero) / 100
        return (amount, left, inPeriod, paid)
    }
}

/// Admin checklist edits: overridden section definitions + custom sections per group.
struct ChecklistOverrides: Codable, Hashable {
    var sections: [String: SectionDef] = [:]
    var custom: [String: [String]] = [:]     // "Exterior" | "Interior" | "Utility" | "Testing" -> section names
}

struct AppSettings: Codable, Hashable {
    var defaultDepth: Depth
    var defaultCover: CoverChoice
    var autoSync: Bool = true
}

/// VIMS platform-level settings (owned by the platform owner, not by any company).
struct PlatformSettings: Codable, Hashable {
    /// Help & feedback messages go here.
    var feedbackEmail: String
    /// Blind carbon copy of every emailed report, for report-quality review (disclosed in the VIMS EULA).
    var reportBccOn: Bool
    var reportBccEmail: String

    /// The address to BCC on an emailed report, or nil when the setting is off.
    var activeReportBcc: String? {
        let e = reportBccEmail.trimmingCharacters(in: .whitespaces)
        return reportBccOn && !e.isEmpty ? e : nil
    }
    var bccSummary: String { activeReportBcc.map { "On · \($0)" } ?? "Off" }

    /// Client Oct 28 (data v1.11): the VIMS subscription plans and prices, edited only by a master admin in Plans & pricing
    /// and used on every company's Subscribe screen. nil until a master admin saves a change = the shared JSON's plans.
    /// TODO(backend): server-owned (Square catalog).
    var plans: [PlanDef]? = nil
    var extraInspectorMonthly: Double? = nil
    var extraInspectorYearly: Double? = nil

    /// The plans and per-inspector rates in effect (stored master-admin edits, else the shared JSON).
    func pricing(_ config: ChecklistConfig) -> Pricing {
        let s = config.subscription
        let plans = (self.plans ?? []).isEmpty ? s.plans : (self.plans ?? [])
        return Pricing(plans: plans, extraMonthly: extraInspectorMonthly ?? s.extraInspectorMonthly,
                       extraYearly: extraInspectorYearly ?? s.extraInspectorYearly ?? (extraInspectorMonthly ?? s.extraInspectorMonthly) * 12)
    }

    struct Pricing: Hashable {
        var plans: [PlanDef]
        var extraMonthly: Double
        var extraYearly: Double
    }

    static func defaults(_ config: ChecklistConfig) -> PlatformSettings {
        PlatformSettings(feedbackEmail: config.support.feedbackEmail,
                         reportBccOn: config.support.reportBcc?.on ?? false,
                         reportBccEmail: config.support.reportBcc?.email ?? "")
    }

    /// v1.9.2 (client Oct 22, moved to vimsinspect.com): a stored address that still equals an old shipped default
    /// (`support.replacedDefaults`, trimmed, case-insensitive) becomes the current default; anything the owner typed
    /// in is kept. Returns the names of the fields that changed (empty = nothing to save).
    mutating func migrateReplacedDefaults(_ config: ChecklistConfig) -> [String] {
        guard let old = config.support.replacedDefaults else { return [] }
        let norm = { (e: String) in e.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let current = PlatformSettings.defaults(config)
        var changed: [String] = []
        if (old.feedbackEmail ?? []).map(norm).contains(norm(feedbackEmail)), norm(feedbackEmail) != norm(current.feedbackEmail) {
            feedbackEmail = current.feedbackEmail; changed.append("feedbackEmail")
        }
        if (old.reportBccEmail ?? []).map(norm).contains(norm(reportBccEmail)), norm(reportBccEmail) != norm(current.reportBccEmail),
           !current.reportBccEmail.isEmpty {
            reportBccEmail = current.reportBccEmail; changed.append("reportBccEmail")
        }
        return changed
    }
}

/// VIMS platform owners (system admins) — the shared JSON `support.platformOwners` list (data v1.5), several
/// allowed so the client always has at least two. Matched case-insensitively after trimming. No password is
/// stored or seeded for these accounts: the owner creates an account / signs in with the email and their own
/// password, and gets the VIMS owner settings when the email is listed.
/// TODO(backend): the server owns this list and returns an isPlatformOwner flag / role with the session.
enum PlatformOwner {
    static func normalized(_ email: String) -> String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    static func emails(_ config: ChecklistConfig) -> [String] {
        (config.support.platformOwners ?? []).map(normalized).filter { !$0.isEmpty }
    }

    static func isOwner(email: String, config: ChecklistConfig) -> Bool {
        let e = normalized(email)
        return !e.isEmpty && emails(config).contains(e)
    }
}

struct Session: Codable, Hashable {
    var name: String
    var email: String
    var inspectorID: UUID?
    var isAdmin: Bool
    /// VIMS platform owner — only this account sees platform settings (report BCC, feedback email).
    var isPlatformOwner: Bool = false
}

/// Everything that is not an inspection, persisted as one JSON document.
struct AppState: Codable {
    var session: Session?
    var company: CompanyProfile
    var subscription: SubscriptionState
    var overrides: ChecklistOverrides
    var settings: AppSettings
    var seededAt: Date?
}
