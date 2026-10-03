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
    var present: [String] = []              // Fast Entry "Items present"
    var overall: String?
    var comments: String = ""

    var hasContent: Bool {
        choices.values.contains { !$0.isEmpty } || text.values.contains { !$0.isEmpty } ||
        detail.values.contains { !$0.isEmpty } || !present.isEmpty || !comments.isEmpty
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
}

// MARK: - Cover

struct CoverChoice: Codable, Hashable {
    var color: String
    var category: String
    var option: String
    var style: String

    var label: String { "\(color) · \(category == "Solid" ? "Solid" : option) · \(style)" }
    var artLabel: String { category == "Solid" ? color : option }
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

    // Areas to inspect
    var exterior: [String]
    var rooms: [String]
    var utilities: [String]
    var tests: [String]
    var counts: [String: Int]

    var groups: [ChecklistGroup] = []
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

    /// The address as shown everywhere (lists, headers, report, email): the typed "Street, City, ZIP" plus
    /// the State field — "12 Elm St, Portland, OR 97201" (state before a trailing ZIP), else "…, OR".
    /// Left alone when there is no state or the address already names it (inspections before v1.3).
    var displayAddress: String {
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
        if code != state { stateDocsAck = nil }
        state = (code?.isEmpty ?? true) ? nil : code
        if let auto = prev?.type, inspType == auto, new?.type != auto {
            inspType = config.wizard.defaults.inspType          // "Real Estate Sale"
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
        // "Ogden, UT 84403" -> "Ogden, UT"
        let rest = addressRest
        let comps = rest.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard comps.count >= 2 else { return rest }
        let state = comps[1].split(separator: " ").first.map(String.init) ?? comps[1]
        return "\(comps[0]), \(state)"
    }
    var clientName: String { field("Client name") }

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
    var feedbackEmail: String
    var inspectors: [Inspector]
}

struct SubscriptionState: Codable, Hashable {
    var plans: [PlanDef]
    var extraInspectorMonthly: Double
    var selectedPlan: String
    var trialStart: Date
    var trialDays: Int
    var active: Bool = false
    var paymentLabel: String?
    var startedAt: Date?
    /// Set when an owner/admin cancels: the subscription stays active until `nextBillingDate`,
    /// then stops renewing. Optional so older saved data still decodes.
    var cancelledAt: Date?

    var cancelled: Bool { active && cancelledAt != nil }

    func plan(_ id: String) -> PlanDef? { plans.first { $0.id == id } }

    var trialDaysLeft: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: trialStart),
                                                      to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return max(0, trialDays - elapsed)
    }

    func monthlyTotal(seats: Int) -> Double {
        guard let p = plan(selectedPlan) else { return 0 }
        if p.perReport == true { return 0 }
        return p.price + Double(max(0, seats - 1)) * extraInspectorMonthly
    }

    func totalLabel(seats: Int) -> String {
        guard let p = plan(selectedPlan) else { return "" }
        if p.perReport == true { return Fmt.money(p.price) + " / report" }
        return Fmt.money(monthlyTotal(seats: seats)) + "/mo"
    }

    var nextBillingDate: Date {
        let start = startedAt ?? Date()
        return Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
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

    static func defaults(_ config: ChecklistConfig) -> PlatformSettings {
        PlatformSettings(feedbackEmail: config.support.feedbackEmail,
                         reportBccOn: config.support.reportBcc?.on ?? false,
                         reportBccEmail: config.support.reportBcc?.email ?? "")
    }
}

/// Who owns the VIMS platform (Jeremy). TODO(backend): the server returns an isPlatformOwner flag / role.
enum PlatformOwner {
    static let email = "jeremy@visionpropertyinspections.com"
    static func isOwner(email: String) -> Bool { email.caseInsensitiveCompare(Self.email) == .orderedSame }
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
