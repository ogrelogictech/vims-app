import Foundation

/// Data v1.13 (client Oct 30) `replaces`: the v1.12 items each combined Receptacles item (`countChoice`) replaced, per
/// section / sub-header / question — generated from shared/data/vims-checklists.json v1.12.0 (commit ee2368a), 28 items
/// in 25 sections. Used only to keep the checklist an inspection was started with (`ChecklistCatalog.legacySnapshot`):
/// inspections created before 0.25.0 read the live checklist, so without this their old "GFCI" Yes/No, old single-choice
/// "Receptacles" and the Oct 29 count fields (and the answers saved on them) would disappear. Never shown on new
/// inspections. Substituting every entry into v1.13 gives back the v1.12 item lists exactly.
enum LegacyReceptacles {
    struct Entry: Decodable {
        let section: String
        let header: String?
        let q: String
        let old: [ItemDef]
    }

    static let entries: [Entry] = {
        (try? JSONDecoder().decode([Entry].self, from: Data(json.utf8))) ?? []
    }()

    /// The v1.12 items the combined item `q` under `header` in `section` replaced (nil when it isn't one of them).
    static func oldItems(section: String, header: String?, q: String) -> [ItemDef]? {
        entries.first { $0.section == section && $0.header == header && $0.q == q }?.old
    }

    private static let json = ##"""
[
{"section":"Landscaping","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Exterior Walls","header":"Lighting","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Pool House & Pool","header":"Pool House Electrical","q":"Receptacles","old":[{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Outbuilding – Shed","header":"Electrical","q":"Receptacles (outside)","old":[{"q":"Receptacles (outside)","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Outbuilding – Shed","header":"Electrical","q":"Electrical Receptacles","old":[{"q":"Electrical Receptacles","type":"single","options":["None","GFCI"]},{"q":"Electrical Receptacles GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Outbuilding – Car Port","header":null,"q":"Electrical Receptacles","old":[{"q":"Electrical Receptacles","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Deck","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Patio","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Balcony","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Detached Garage","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Mobile Home Undercarriage","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Condo","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Garage","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI","Non GFCI"]},{"q":"GFCI receptacles (count)","type":"num","integer":true,"placeholder":"e.g. 4"},{"q":"Standard receptacles (count)","type":"num","integer":true,"placeholder":"e.g. 6"},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Attic","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles","type":"single","options":["None","GFCI","Non GFCI"]},{"q":"GFCI receptacles (count)","type":"num","integer":true,"placeholder":"e.g. 4"},{"q":"Standard receptacles (count)","type":"num","integer":true,"placeholder":"e.g. 6"},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Bathroom","header":"Electrical Receptacles","q":"Receptacles","old":[{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Bedroom","header":"Electrical Receptacles","q":"Receptacles","old":[{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Hallway","header":"Electrical Receptacles","q":"Receptacles","old":[{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Living Room","header":"Electrical Receptacles","q":"Receptacles","old":[{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Den / Home Office","header":"Electrical Receptacles","q":"Receptacles","old":[{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Family Room","header":"Electrical Receptacles","q":"Receptacles","old":[{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Reception","header":"Electrical Receptacles","q":"Receptacles","old":[{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Kitchen","header":"Electrical","q":"Receptacles","old":[{"q":"GFCI receptacles (count)","type":"num","integer":true,"placeholder":"e.g. 4"},{"q":"Standard receptacles (count)","type":"num","integer":true,"placeholder":"e.g. 6"},{"q":"Receptacles GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Dining Room","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Dining Room","header":"Electrical (Fireplace)","q":"Receptacles","old":[{"q":"Receptacles GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Laundry Room","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Storage Room","header":"Electrical","q":"Receptacles","old":[{"q":"Receptacles GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Additional Living Space","header":"Electrical","q":"Receptacles (outside)","old":[{"q":"Receptacles (outside)","type":"single","options":["None","GFCI"]},{"q":"GFCI","type":"single","options":["Yes","No"]}]},
{"section":"Additional Living Space","header":"Electrical","q":"Electrical Receptacles","old":[{"q":"Electrical Receptacles GFCI","type":"single","options":["Yes","No"]}]}
]
"""##
}
