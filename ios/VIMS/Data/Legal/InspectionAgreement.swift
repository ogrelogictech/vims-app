import Foundation

/// The client's VIMS default Home Inspection Agreement, read from shared/legal/inspection-agreement.json
/// (bundled via the SharedLegal synchronized group, shared v1.4). Every company uses it unless they upload
/// their own (Company profile). The text is rendered verbatim; `{companyName}` is replaced with the signed-in
/// company's name at display time. `stateDisclosures` is keyed by state code: all states from Company profile,
/// only the inspection's state from the wizard. No in-app e-signature in Phase 1.
struct InspectionAgreement: Decodable, Hashable {
    struct Block: Decodable, Hashable {
        var t: String            // "p" paragraph | "li" bullet
        var text: String
        var lead: Bool?
        var isBullet: Bool { t == "li" }
    }
    var title: String
    var version: String
    var status: String?
    var header: [String]
    var body: [Block]
    var stateDisclosuresHeading: String
    var stateDisclosures: [String: String]
    var closing: [Block]

    /// The form lines shown in the boxed block (the first two header lines — "Company Name Company Logo" and
    /// the title — are the letterhead, which the viewer draws as the title instead; same as the prototype).
    var formLines: [String] { Array(header.dropFirst(2)) }

    /// State codes with a disclosure, in the JSON's order.
    var disclosureStates: [String] { orderedKeys }
    private var orderedKeys: [String] = []

    private enum CodingKeys: String, CodingKey {
        case title, version, status, header, body, stateDisclosuresHeading, stateDisclosures, closing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        version = try c.decode(String.self, forKey: .version)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        header = try c.decode([String].self, forKey: .header)
        body = try c.decode([Block].self, forKey: .body)
        stateDisclosuresHeading = try c.decode(String.self, forKey: .stateDisclosuresHeading)
        stateDisclosures = try c.decode([String: String].self, forKey: .stateDisclosures)
        closing = try c.decode([Block].self, forKey: .closing)
        orderedKeys = Array(stateDisclosures.keys).sorted()
    }

    /// Fills `{companyName}`.
    static func fill(_ text: String, company: String) -> String {
        text.replacingOccurrences(of: "{companyName}", with: company)
    }

    enum LoadError: Error { case missing }

    static func load(bundle: Bundle = .main) throws -> InspectionAgreement {
        guard let url = bundle.url(forResource: "inspection-agreement", withExtension: "json") else { throw LoadError.missing }
        var doc = try JSONDecoder().decode(InspectionAgreement.self, from: Data(contentsOf: url))
        // Keep the JSON's key order (it isn't alphabetical: …IN, IA, KS…), which JSONDecoder's dictionary loses.
        if let raw = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
           let text = try? String(contentsOf: url, encoding: .utf8),
           let sd = raw["stateDisclosures"] as? [String: Any],
           let start = text.range(of: "\"stateDisclosures\"") {
            let tail = text[start.upperBound...]
            doc.orderedKeys = sd.keys.sorted { a, b in
                (tail.range(of: "\"\(a)\":")?.lowerBound ?? tail.endIndex) < (tail.range(of: "\"\(b)\":")?.lowerBound ?? tail.endIndex)
            }
        }
        return doc
    }

    /// Loaded once; nil only if the bundled file is missing or malformed (the UI then says so).
    static let bundled: InspectionAgreement? = try? load()
}
