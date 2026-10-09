import Foundation

// Models for shared/data/vims-checklists.json — the single source of truth for
// every checklist section/item, wizard option, builder rule, finding category,
// quick comment, cover option, and plan. Loaded from the app bundle at runtime.
// Nothing in here should be hardcoded elsewhere.

struct ChecklistConfig: Decodable {
    let version: String
    let depths: [DepthDef]
    let depthRules: [String: String]
    let overallCondition: [String]
    let overallConditionDefault: String
    let sectionGroups: [SectionGroupDef]
    let sections: [SectionDef]
    let checklistBuilder: BuilderDef
    let wizard: WizardDef
    let findings: FindingsDef
    var covers: CoversDef
    let subscription: SubscriptionDef
    let support: SupportDef
    let sample: SampleDef
    let formLabels: [String: String]?
    let reportLayouts: ReportLayoutsDef?
    /// v1.3: the property State picker (50 states + DC, in display order) and per-state rules.
    let states: [StateDef]?
    let stateRules: StateRulesDef?

    /// Keys of JSON objects whose order matters but that Swift dictionaries lose.
    var unitMixOrder: [String] = []
    var coverCategoryOrder: [String] = []

    private enum CodingKeys: String, CodingKey {
        case version, depths, depthRules, overallCondition, overallConditionDefault, sectionGroups, sections,
             checklistBuilder, wizard, findings, covers, subscription, support, sample, formLabels, reportLayouts,
             states, stateRules
    }

    /// `stateRules[code]`, or nil when the state has no special rules (or no state is set).
    func stateRule(_ code: String?) -> StateRuleDef? {
        guard let code, !code.isEmpty else { return nil }
        return stateRules?.byState[code]
    }
    /// Full state name for a USPS code ("OR" -> "Oregon").
    func stateName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return states?.first { $0.code == code }?.name
    }
}

/// `states[]` entry (v1.3).
struct StateDef: Decodable, Hashable { let code: String; let name: String }

/// `stateRules[code]` (v1.3) — see the JSON `_about`:
/// type → auto-select that inspection type; note → info card under the State field;
/// summaryDisclosure → top of the Summary screen + page 1 of the PDF summary; coverNotice → PDF cover line;
/// docs → state documents given with the inspection agreement (View / Send to client + required acknowledgment).
/// agentCopyDefault (v1.4) → initial value of step 1's "Send the report to the real estate agent" (true when absent).
struct StateRuleDef: Decodable, Hashable {
    let type: String?
    let note: String?
    let summaryDisclosure: String?
    let coverNotice: String?
    let docs: [StateDocDef]?
    let agentCopyDefault: Bool?

    var requiredDocs: [StateDocDef] { docs ?? [] }
}

/// A state document; `file` is relative to shared/ (e.g. "legal/state/oregon-….pdf").
struct StateDocDef: Decodable, Hashable {
    let name: String
    let file: String

    /// The bundled PDF (shared/legal is a synchronized group, so the file is copied into the app bundle).
    var bundleURL: URL? {
        let base = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension.isEmpty ? "pdf" : (file as NSString).pathExtension
        let dir = (file as NSString).deletingLastPathComponent
        return Bundle.main.url(forResource: base, withExtension: ext)
            ?? Bundle.main.url(forResource: base, withExtension: ext, subdirectory: dir)
            ?? Bundle.main.url(forResource: base, withExtension: ext, subdirectory: (dir as NSString).lastPathComponent)
    }
}

/// `stateRules`: state code -> rule (the object also carries an "_about" string).
struct StateRulesDef: Decodable {
    let byState: [String: StateRuleDef]

    private struct Key: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var out: [String: StateRuleDef] = [:]
        for k in c.allKeys where !k.stringValue.hasPrefix("_") {
            if let v = try? c.decode(StateRuleDef.self, forKey: k) { out[k.stringValue] = v }
        }
        byState = out
    }
}

struct DepthDef: Decodable { let id: String; let label: String }

struct SectionGroupDef: Decodable { let group: String; let sections: [String] }

struct SectionDef: Codable, Hashable {
    var name: String
    var number: Int
    var icon: String?
    var photoCategories: [String]
    var photoCategoriesHigh: [String]?
    var items: [ItemDef]
    var itemsHigh: [ItemDef]?
    /// "texas" | "fourPoint": client-supplied state/insurance form (ignores checklist depth, no overall condition)
    var form: String? = nil
    /// Section with no items: opening it goes straight to its photo screen (Pictures pages)
    var photosOnly: Bool? = nil

    var isForm: Bool { form != nil }
    var isPhotosOnly: Bool { photosOnly == true }
}

struct ItemDef: Codable, Hashable {
    var q: String?
    var type: String?
    var options: [String]?
    var header: String?
    var placeholder: String?

    var isHeader: Bool { header != nil }
    var kind: ItemKind {
        if header != nil { return .header }
        switch type ?? "single" {
        case "multi": return .multi
        case "num": return .num
        case "text": return .text
        case "date": return .date
        case "time": return .time
        default: return .single
        }
    }

    static func question(_ q: String, type: String = "single", options: [String]) -> ItemDef {
        ItemDef(q: q, type: type, options: options, header: nil, placeholder: nil)
    }
}

enum ItemKind { case single, multi, num, text, date, time, header }

struct BuilderDef: Decodable {
    let phaseTypes: [String: [LayoutEntry]]
    let standardLayout: [LayoutEntry]
}

struct LayoutEntry: Decodable {
    let heading: String
    let link: String?
    let icon: String?
    let sections: [String]?
    let always: [String]?
    let optional: String?
    let order: [String]?
    let sub: SubLayout?
}

struct SubLayout: Decodable {
    let heading: String
    let always: [String]?
    let optional: String?
    let then: [String]?
}

struct WizardDef: Decodable {
    let steps: [String]
    let inspectionTypes: [String]
    let componentOptions: [String]
    let structureTypes: [String]
    let structureSideEffects: [String: [String: String]]
    let unitMixDefault: [String: Int]
    let step1: [WizardEntry]
    let step2: [WizardEntry]
    let exteriorOptions: [String]
    let roomOptions: [String]
    let utilityOptions: [String]
    let testOptions: [String]
    let roomCounts: [RoomCountDef]
    let defaults: WizardDefaults
    let typeFields: TypeFieldsDef?
}

struct TypeFieldDef: Decodable, Hashable { let label: String; let key: String; let placeholder: String? }

/// `wizard.typeFields`: inspection type -> extra step-1 fields (the object also carries an "_about" string).
struct TypeFieldsDef: Decodable {
    let byType: [String: [TypeFieldDef]]

    private struct Key: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var out: [String: [TypeFieldDef]] = [:]
        for k in c.allKeys where !k.stringValue.hasPrefix("_") {
            if let v = try? c.decode([TypeFieldDef].self, forKey: k) { out[k.stringValue] = v }
        }
        byType = out
    }
}

/// `reportLayouts`: only the type -> layout map is needed at runtime (the page lists document report.html).
struct ReportLayoutsDef: Decodable {
    let typeToLayout: [String: String]?
}

enum ReportLayout: String { case standard, texas, fourPoint }

struct WizardEntry: Decodable, Hashable {
    let kind: String          // field | chips | dynamic
    let label: String
    let type: String?         // text | tel | email | date | time | textarea
    let placeholder: String?
    let id: String?
    let single: Bool?
    let options: [String]?
    let `default`: String?
}

struct RoomCountDef: Decodable { let key: String; let label: String }

struct WizardDefaults: Decodable {
    let inspType: String
    let loan: String
    let structure: String
    let depth: String
    let bedrooms: Int
    let bathrooms: Int
    let hallways: Int
    let rooms: [String: Int]
    let exterior: [String: Int]
    let utilOpt: [String: Int]
    let tests: [String: Int]
}

struct FindingsDef: Decodable {
    let categories: [FindingCategoryDef]
    let quickComments: [String]
}

struct FindingCategoryDef: Decodable, Hashable { let id: Int; let label: String; let note: String }

/// from/to: app UI swatch gradient. light/mid/deep/solid (v1.6): the client's cover design fills —
/// page fill (Framed), Shaded gradient stops, Framed glow (deep), Solid fill.
struct CoverColorDef: Decodable, Hashable {
    let name: String
    let from: String
    let to: String
    let light: String?
    let mid: String?
    let deep: String?
    let solid: String?
}

struct CoversDef: Decodable {
    let colors: [CoverColorDef]
    let categories: [String: [String]]
    let styles: [String]
    let solidStyle: String
    let `default`: CoverDefault
    /// v1.6: the client's cover layout (inches on US Letter) and the theme artwork per image option.
    let layout: CoverLayoutDef?
    let themeArt: [String: ThemeArtDef]?

    /// The theme artwork for a cover choice (nil for the Solid category or an unknown option).
    func art(for c: CoverChoice) -> ThemeArtDef? {
        c.category == "Solid" ? nil : themeArt?[c.option]
    }
}

/// `covers.layout` — the client's "Cover - Master example". Every rect is [x, y, w, h] in inches, origin top-left.
struct CoverLayoutDef: Decodable {
    struct Box: Decodable { let rect: [Double] }
    struct Title: Decodable { let text: String; let centerY: Double; let size: Double }
    struct Fields: Decodable { let top: Double; let lineGap: Double; let left: Double; let right: Double }
    struct PhotoBox: Decodable { let rect: [Double]; let border: Double }
    struct Footer: Decodable { let centerY: Double; let size: Double; let text: String }

    var pageBox: [Double] = [0.5, 0.68, 7.48, 9.52]
    var logo = Box(rect: [0.6, 0.75, 1.6, 1.1])
    var companyInfo = Box(rect: [4.3, 0.8, 3.55, 1.1])
    var title = Title(text: "Inspection Report", centerY: 2.17, size: 20)
    var fields = Fields(top: 2.62, lineGap: 0.47, left: 1.3, right: 7.2)
    var photoBox = PhotoBox(rect: [1.2, 5.1, 6.08, 4.15], border: 1.25)
    var footer = Footer(centerY: 9.65, size: 11,
                        text: "This inspection report is the property of {companyName}.\nAny reproduction or distribution without written consent is prohibited.")

    static let fallback = CoverLayoutDef()
    init() {}
}

/// `covers.themeArt[option]` — a transparent artwork (shared/covers/*.webp) placed at `rect` (inches) on the cover.
struct ThemeArtDef: Decodable, Hashable {
    let file: String
    let rect: [Double]

    /// shared/covers is a synchronized group, so the file is copied into the app bundle.
    var bundleURL: URL? {
        let base = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension.isEmpty ? "webp" : (file as NSString).pathExtension
        return Bundle.main.url(forResource: base, withExtension: ext)
            ?? Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "covers")
    }
}

struct CoverDefault: Decodable { let color: String; let category: String; let option: String; let style: String }

struct SubscriptionDef: Decodable {
    let trialDays: Int
    let plans: [PlanDef]
    let extraInspectorMonthly: Double
}

struct PlanDef: Codable, Hashable {
    var id: String
    var name: String
    var price: Double
    var desc: String
    var unit: String?
    var perReport: Bool?
}

struct SupportDef: Decodable {
    let feedbackEmail: String
    /// v1.2: default for the platform owner's report-quality BCC.
    let reportBcc: ReportBccDef?
    /// v1.3: present → every emailed report is CC'd to the signed-in inspector's own email.
    let ccInspector: CCInspectorDef?
    /// v1.5: VIMS platform owner emails (case-insensitive) — see `PlatformOwner`. TODO(backend): server-owned.
    let platformOwners: [String]?
}

struct CCInspectorDef: Decodable {}

struct ReportBccDef: Decodable { let on: Bool; let email: String }

struct SampleDef: Decodable {
    let company: SampleCompany
    let inspectors: [SampleInspector]
    let findings: [SampleFinding]
}
struct SampleCompany: Decodable { let name: String; let code: String }
struct SampleInspector: Decodable { let name: String; let email: String; let owner: Bool? }
struct SampleFinding: Decodable { let cat: Int; let txt: String; let sec: String }

// MARK: - Loader

enum ChecklistLoader {
    enum LoadError: Error { case missing }

    static func load(bundle: Bundle = .main) throws -> ChecklistConfig {
        guard let url = bundle.url(forResource: "vims-checklists", withExtension: "json") else { throw LoadError.missing }
        let data = try Data(contentsOf: url)
        var cfg = try JSONDecoder().decode(ChecklistConfig.self, from: data)
        // Recover key order for the two objects where display order matters.
        if let root = OrderedJSON.parse(data) {
            cfg.unitMixOrder = root.keys(at: ["wizard", "unitMixDefault"]) ?? Array(cfg.wizard.unitMixDefault.keys).sorted()
            cfg.coverCategoryOrder = root.keys(at: ["covers", "categories"]) ?? Array(cfg.covers.categories.keys).sorted()
        } else {
            cfg.unitMixOrder = Array(cfg.wizard.unitMixDefault.keys).sorted()
            cfg.coverCategoryOrder = Array(cfg.covers.categories.keys).sorted()
        }
        return cfg
    }
}

/// Minimal JSON parser that keeps object key order (JSONDecoder does not).
indirect enum OrderedJSON {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case scalar

    func keys(at path: [String]) -> [String]? {
        var node = self
        for p in path {
            guard case .object(let pairs) = node, let next = pairs.first(where: { $0.0 == p })?.1 else { return nil }
            node = next
        }
        if case .object(let pairs) = node { return pairs.map { $0.0 } }
        return nil
    }

    static func parse(_ data: Data) -> OrderedJSON? {
        var p = Parser(bytes: [UInt8](data))
        return p.value()
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        mutating func ws() { while i < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[i]) { i += 1 } }

        mutating func value() -> OrderedJSON? {
            ws()
            guard i < bytes.count else { return nil }
            switch bytes[i] {
            case UInt8(ascii: "{"):
                i += 1
                var pairs: [(String, OrderedJSON)] = []
                ws()
                if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
                while i < bytes.count {
                    ws()
                    guard let k = string() else { return nil }
                    ws()
                    guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return nil }
                    i += 1
                    guard let v = value() else { return nil }
                    pairs.append((k, v))
                    ws()
                    if i < bytes.count, bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
                    return nil
                }
                return nil
            case UInt8(ascii: "["):
                i += 1
                var arr: [OrderedJSON] = []
                ws()
                if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(arr) }
                while i < bytes.count {
                    guard let v = value() else { return nil }
                    arr.append(v)
                    ws()
                    if i < bytes.count, bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(arr) }
                    return nil
                }
                return nil
            case UInt8(ascii: "\""):
                return string() == nil ? nil : .scalar
            default:
                // number / true / false / null
                while i < bytes.count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x0A, 0x0D, 0x09].contains(bytes[i]) { i += 1 }
                return .scalar
            }
        }

        mutating func string() -> String? {
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { return nil }
            let start = i
            i += 1
            while i < bytes.count {
                if bytes[i] == UInt8(ascii: "\\") { i += 2; continue }
                if bytes[i] == UInt8(ascii: "\"") { i += 1; break }
                i += 1
            }
            let slice = Data(bytes[start..<i])
            return try? JSONDecoder().decode(String.self, from: slice)
        }
    }
}
