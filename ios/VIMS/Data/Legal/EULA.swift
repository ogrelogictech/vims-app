import Foundation

/// The client's End User License Agreement, read from shared/legal/eula.json (bundled via the
/// SharedLegal synchronized group). The text is rendered verbatim and never hardcoded in the app.
/// When the client sends a revised agreement, the JSON is replaced and its `version` bumped;
/// every user whose accepted version differs is asked to accept it again at sign-in.
struct EULADocument: Decodable, Hashable {
    struct Section: Decodable, Hashable {
        var heading: String
        var paragraphs: [String]
    }
    var title: String
    var revised: String
    var version: String
    var intro: [String]
    var sections: [Section]
    var footer: String?

    enum LoadError: Error { case missing }

    static func load(bundle: Bundle = .main) throws -> EULADocument {
        guard let url = bundle.url(forResource: "eula", withExtension: "json") else { throw LoadError.missing }
        return try JSONDecoder().decode(EULADocument.self, from: Data(contentsOf: url))
    }
}
