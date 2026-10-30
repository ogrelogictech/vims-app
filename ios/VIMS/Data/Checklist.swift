import Foundation

/// Section lookups (JSON + admin overrides) and the checklist builder
/// (mirrors `checklistBuilder` in the shared JSON / buildGroups() in the prototype).
struct ChecklistCatalog {
    let config: ChecklistConfig
    let overrides: ChecklistOverrides
    /// The inspection's wizard room counts (`Inspection.counts`) when this catalog is for one inspection
    /// (`AppStore.catalog(for:)`, the report): v1.12 `optionsFromCount` items list "1"…n from them. nil = company checklist
    /// (Manage checklist), which shows the static options.
    var counts: [String: Int]? = nil
    /// Sections in `overrides` that are an inspection's saved checklist (`Inspection.savedSections`), not the company's
    /// copy: they are used as saved — never swapped to a v1.13 `replaces` item (`AppStore.catalog(for:)`).
    var savedNames: Set<String> = []

    static let customGroups = ["Exterior", "Interior", "Utility", "Testing"]

    /// "Bathroom 2" -> "Bathroom"
    static func baseName(_ name: String) -> String {
        if let r = name.range(of: #"\s+\d+$"#, options: .regularExpression) { return String(name[..<r.lowerBound]) }
        return name
    }

    func section(_ name: String) -> SectionDef? {
        let base = Self.baseName(name)
        if let o = overrides.sections[base] {
            return withNewJSONItems(o, saved: savedNames.contains(base))
        }
        if let o = overrides.sections[name] { return withNewJSONItems(o, saved: savedNames.contains(name)) }
        return config.sections.first { $0.name == base } ?? config.sections.first { $0.name == name }
    }

    /// An admin-edited section plus the items the shared JSON added after the edit was saved (`baseItems`), each placed
    /// after the JSON item it follows. Overrides saved before data v1.10 have no `baseItems` and are used as saved
    /// (apart from the v1.12 renames / flags below).
    /// Data v1.13 `replaces`: a company copy (`saved == false`) still holding the old receptacle items gets the combined
    /// item in their place; an inspection's saved checklist (`saved`) keeps them, and `adding` never adds the combined
    /// item next to them.
    private func withNewJSONItems(_ o: SectionDef, saved: Bool = false) -> SectionDef {
        guard let json = config.sections.first(where: { $0.name == o.name }) else { return o }
        var out = o
        let jsonAll = json.items + (json.itemsHigh ?? [])
        out.items = Self.syncingJSONChanges(o.items, json: jsonAll)
        if let mh = o.itemsHigh { out.itemsHigh = Self.syncingJSONChanges(mh, json: jsonAll) }
        if !saved {
            out.items = Self.swappingReplaced(out.items, json: json.items)
            if let mh = out.itemsHigh { out.itemsHigh = Self.swappingReplaced(mh, json: json.itemsHigh ?? []) }
        }
        guard var known = o.baseItems.map(Set.init) else { return out }
        // A JSON item renamed since the edit (v1.12 `renamedFrom`) is the same item: not new, and still deleted if the
        // admin had deleted it under its old label.
        for it in jsonAll { if let old = it.previousEditKey, known.contains(old) { known.insert(it.editKey) } }
        out.items = Self.adding(json.items, to: out.items, known: known)
        if let jh = json.itemsHigh, !jh.isEmpty { out.itemsHigh = Self.adding(jh, to: out.itemsHigh ?? [], known: known) }
        return out
    }

    /// Data v1.12 on a company edit saved earlier: an item still under a label the JSON has since renamed (`renamedFrom`,
    /// e.g. Outside Utilities "Compressor size (sq ft)" → "Compressor size (home sq ft)") takes the new label and keeps
    /// the admin's other changes (its answers move with it, `SectionAnswers.migratingRenamed`); and an item matching a
    /// JSON item that gained `optionsFromCount` / `defaultFromRoomNumber` (Bathroom No. / Bedroom No.) picks those up.
    static func syncingJSONChanges(_ mine: [ItemDef], json: [ItemDef]) -> [ItemDef] {
        var out = mine
        for j in json where j.header == nil {
            if let old = j.renamedFrom, let q = j.q, !out.contains(where: { $0.editKey == j.editKey }),
               let i = out.firstIndex(where: { $0.header == nil && $0.q == old }) {
                out[i].q = q
                out[i].renamedFrom = old
            }
            if j.optionsFromCount != nil || j.defaultFromRoomNumber != nil {
                for i in out.indices where out[i].header == nil && out[i].q == j.q && out[i].kind == .single && out[i].optionsFromCount == nil {
                    out[i].optionsFromCount = j.optionsFromCount
                    out[i].defaultFromRoomNumber = out[i].defaultFromRoomNumber ?? j.defaultFromRoomNumber
                }
            }
        }
        return out
    }

    static func adding(_ json: [ItemDef], to mine: [ItemDef], known: Set<String>) -> [ItemDef] {
        var out = mine
        for (i, it) in json.enumerated() where !known.contains(it.editKey) && !out.contains(where: { $0.editKey == it.editKey }) {
            // v1.13 `replaces`: never added to a list that still has any of the items it replaces (a started
            // inspection's saved checklist), so in-progress answers are neither hidden nor duplicated.
            if Self.holdsReplaced(by: it, in: out) { continue }
            var at = i == 0 ? 0 : out.count
            for p in stride(from: i - 1, through: 0, by: -1) {
                if let j = out.lastIndex(where: { $0.editKey == json[p].editKey }) { at = j + 1; break }
            }
            out.insert(it, at: at)
        }
        return out
    }

    /// The sub-header each item sits under (nil before the first header).
    static func headers(_ list: [ItemDef]) -> [String?] {
        var h: String?
        return list.map { it in
            if let x = it.header { h = x }
            return h
        }
    }

    /// An old item `c` (a v1.13 countChoice with `replaces`) stands in for: a question item (not the combined type itself,
    /// so an old single-choice "Receptacles" with the same label is still found) whose label is in `replaces`.
    static func isReplaced(_ it: ItemDef, by c: ItemDef) -> Bool {
        it.header == nil && it.kind != .countChoice && (c.replaces ?? []).contains(it.q ?? "")
    }

    /// True when `list` still has any item `c` replaces (anywhere in the list: a saved checklist that contains a replaced
    /// label never gets `c`).
    static func holdsReplaced(by c: ItemDef, in list: [ItemDef]) -> Bool {
        guard c.kind == .countChoice, !(c.replaces ?? []).isEmpty else { return false }
        return list.contains { isReplaced($0, by: c) }
    }

    /// Data v1.13 `replaces` on a company checklist copy: under the combined item's sub-header, its old items (found by
    /// label and type, not label alone) are removed and the combined item takes the place of the first one. A copy that
    /// already has the combined item there, or none of the old items, is left as it is.
    static func swappingReplaced(_ mine: [ItemDef], json: [ItemDef]) -> [ItemDef] {
        var out = mine
        let jh = headers(json)
        for (ji, c) in json.enumerated() where c.kind == .countChoice && !(c.replaces ?? []).isEmpty {
            let h = jh[ji]
            let oh = headers(out)
            if out.indices.contains(where: { oh[$0] == h && out[$0].kind == .countChoice && out[$0].q == c.q }) { continue }
            let olds = out.indices.filter { oh[$0] == h && isReplaced(out[$0], by: c) }
            guard let first = olds.first else { continue }
            out[first] = c
            for i in olds.dropFirst().reversed() { out.remove(at: i) }
        }
        return out
    }

    /// Data v1.13: the checklist an inspection created before 0.25.0 was started with, for a section whose live checklist
    /// now has a combined Receptacles item (`replaces`). The company's copy is kept as stored (it still has the old items);
    /// otherwise the shared JSON section with each combined item put back to the v1.12 items it replaced
    /// (`LegacyReceptacles`), `baseItems` = today's JSON keys so later JSON additions still reach it. nil = the section
    /// isn't affected (nothing to keep).
    func legacySnapshot(_ name: String) -> SectionDef? {
        let base = Self.baseName(name)
        guard let json = config.sections.first(where: { $0.name == base }),
              (json.items + (json.itemsHigh ?? [])).contains(where: { $0.kind == .countChoice && !($0.replaces ?? []).isEmpty })
        else { return nil }
        if var o = overrides.sections[base] {
            o.items = Self.restoringLegacy(o.items, section: base)
            o.itemsHigh = o.itemsHigh.map { Self.restoringLegacy($0, section: base) }
            return o
        }
        var d = json
        d.items = Self.restoringLegacy(json.items, section: base)
        d.itemsHigh = json.itemsHigh.map { Self.restoringLegacy($0, section: base) }
        d.baseItems = jsonItemKeys(base)
        return d
    }

    /// Each combined item with `replaces` back to its v1.12 items (when the list doesn't already hold them).
    static func restoringLegacy(_ list: [ItemDef], section: String) -> [ItemDef] {
        var out: [ItemDef] = []
        let hs = headers(list)
        for (i, it) in list.enumerated() {
            if it.kind == .countChoice, !holdsReplaced(by: it, in: list),
               let old = LegacyReceptacles.oldItems(section: section, header: hs[i], q: it.q ?? "") {
                out += old
            } else {
                out.append(it)
            }
        }
        return out
    }

    /// The JSON item keys an admin edit is saved against (`SectionDef.baseItems`).
    func jsonItemKeys(_ name: String) -> [String]? {
        guard let s = config.sections.first(where: { $0.name == name }) else { return nil }
        return (s.items + (s.itemsHigh ?? [])).map(\.editKey)
    }

    func number(_ name: String) -> Int { section(name)?.number ?? 99 }

    /// The name shown for a section (data v1.8 `title`, e.g. key "Septic" → "Septic System", "Termite" → "Wood Destroying
    /// Organism Inspection"), keeping a numbered instance's suffix ("Bathroom 2"). The key (`name`) is what inspections,
    /// answers, photos and findings store; only lists, headers, the wizard and the report show this.
    func title(_ name: String) -> String {
        let base = Self.baseName(name)
        let t = [overrides.sections[base]?.title, overrides.sections[name]?.title,
                 config.sections.first { $0.name == base }?.title, config.sections.first { $0.name == name }?.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        guard let t else { return name }
        return config.sections.contains(where: { $0.name == name }) || base == name ? t : t + name.dropFirst(base.count)
    }

    /// v1.9 `formReport` key of a section ("oir-b1-1802", "wdi"), nil for a normal checklist section.
    func formReport(_ name: String) -> String? {
        section(name)?.formReport ?? config.sections.first { $0.name == Self.baseName(name) }?.formReport
    }

    /// Data v1.8 `reportNote`: paragraphs printed after the section's items, before Overall condition (Radon).
    func reportNote(_ name: String) -> [String] {
        (section(name)?.reportNote ?? config.sections.first { $0.name == Self.baseName(name) }?.reportNote ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func isForm(_ name: String) -> Bool { section(name)?.isForm ?? false }
    func isPhotosOnly(_ name: String) -> Bool { section(name)?.isPhotosOnly ?? false }

    /// Badge text for a form section (`formLabels[form]`).
    func formLabel(_ name: String) -> String? {
        if let r = section(name)?.formReport { return config.formReports?.byKey[r]?.title ?? r }
        guard let f = section(name)?.form else { return nil }
        return config.formLabels?[f] ?? f
    }

    /// Report page structure for an inspection type (`reportLayouts.typeToLayout`).
    func reportLayout(for inspType: String) -> ReportLayout {
        let map = config.reportLayouts?.typeToLayout ?? [:]
        let v = (map[inspType] ?? map["*"] ?? "standard").lowercased()
        if v == "texas" { return .texas }
        if v.contains("4 point") || v.contains("4point") || v.contains("fourpoint") { return .fourPoint }
        return .standard
    }

    /// Extra step-1 fields for an inspection type (`wizard.typeFields`).
    func typeFields(for inspType: String) -> [TypeFieldDef] {
        config.wizard.typeFields?.byType[inspType] ?? []
    }

    /// Items for a depth per `depthRules`: High uses itemsHigh when present, otherwise Standard.
    /// State/insurance form sections ignore depth and always use `items` (`_formNotes`).
    func items(_ name: String, depth: Depth) -> (items: [ItemDef], usingHigh: Bool) {
        guard let s = section(name) else { return ([], false) }
        if s.isForm { return (resolvingCounts(s.items), false) }
        if depth == .high, let hi = s.itemsHigh, !hi.isEmpty { return (resolvingCounts(hi), true) }
        return (resolvingCounts(s.items), false)
    }

    /// Data v1.12 `optionsFromCount`: "1"…n from this inspection's room count (minimum 1), so the Bathroom No. options
    /// follow the Bathrooms count (also after it's changed in Inspection info). No count (company checklist, or an
    /// inspection without that key) → the item's static options.
    private func resolvingCounts(_ items: [ItemDef]) -> [ItemDef] {
        guard let counts, items.contains(where: { $0.optionsFromCount != nil }) else { return items }
        return items.map { it in
            guard let key = it.optionsFromCount, it.kind == .single, let n = counts[key] else { return it }
            var r = it
            r.options = (1...max(1, n)).map(String.init)
            return r
        }
    }

    /// Data v1.12 `defaultFromRoomNumber`: the answers a numbered room section ("Bathroom 2") starts with — its Bathroom
    /// No. item pre-answered "2" — keyed like `SectionAnswers.choices`. Empty for a section without a number.
    func roomNumberDefaults(_ name: String, depth: Depth) -> [String: [String]] {
        let base = Self.baseName(name)
        guard base != name, let n = Int(name.dropFirst(base.count).trimmingCharacters(in: .whitespaces)) else { return [:] }
        let list = items(name, depth: isForm(name) ? .standard : depth).items
        guard list.contains(where: { $0.defaultFromRoomNumber == true }) else { return [:] }
        var out: [String: [String]] = [:]
        for k in ItemKeys.keyed(list) where k.item.defaultFromRoomNumber == true && k.item.kind == .single
            && (k.item.options ?? []).contains(String(n)) {
            out[k.id] = [String(n)]
        }
        return out
    }

    func photoCategories(_ name: String, depth: Depth) -> [String] {
        guard let s = section(name) else { return ["Overview", "Concerns"] }
        if s.isForm { return s.photoCategories.isEmpty ? ["Overview", "Concerns"] : s.photoCategories }
        if depth == .high, let hi = s.photoCategoriesHigh, !hi.isEmpty { return hi }
        return s.photoCategories.isEmpty ? ["Overview", "Concerns"] : s.photoCategories
    }

    /// Admin browse list: JSON groups + custom sections appended to their group.
    func adminGroups() -> [(group: String, sections: [String])] {
        config.sectionGroups.map { g in (g.group, g.sections + (overrides.custom[g.group] ?? [])) }
    }

    func sortedForReport(_ names: [String]) -> [String] {
        names.sorted { a, b in
            let na = number(a), nb = number(b)
            if na != nb { return na < nb }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    // MARK: Builder

    /// `phaseTypes[type]` when the type has its own layout (Phase 1 / Phase 2 / Texas / 4 Point / Tests Only), else
    /// `standardLayout`. Both use the same entry forms: `link`, fixed `sections`, `always`, `optional` (the options
    /// chosen in the wizard, e.g. Tests Only's `"optional": "testOptions"`), `order` tokens and `sub`. Admin custom
    /// sections are appended to their group in the standard layout, and to a phase layout's `optional` groups (Tests
    /// Only → Testing). Data v1.10 `areasLockedTypes`: the exterior / room / utility choices never add sections.
    func buildGroups(for insp: Inspection) -> [ChecklistGroup] {
        let builder = config.checklistBuilder
        let phase = builder.phaseTypes[insp.inspType]
        let locked = config.wizard.areasLocked(insp.inspType)
        return (phase ?? builder.standardLayout).map { e in
            if let link = e.link {
                return ChecklistGroup(heading: e.heading, icon: e.icon ?? defaultIcon(e), link: link, sections: [], sub: nil)
            }
            var secs: [String] = e.sections ?? []
            secs += e.always ?? []
            if let opt = e.optional { secs += selected(optionKey: opt, insp, locked: locked) }
            if let order = e.order { secs += expand(order: order, insp, locked: locked) }
            if phase == nil || e.optional != nil { secs += overrides.custom[customGroup(for: e)] ?? [] }
            var sub: ChecklistSubGroup?
            if let s = e.sub {
                var ss = s.always ?? []
                if let opt = s.optional { ss += selected(optionKey: opt, insp, locked: locked) }
                ss += s.then ?? []
                ss += overrides.custom["Utility"] ?? []
                sub = ChecklistSubGroup(heading: s.heading, sections: ss)
            }
            return ChecklistGroup(heading: e.heading, icon: phase != nil ? (e.icon ?? defaultIcon(e)) : e.icon,
                                  link: nil, sections: secs, sub: sub)
        }
    }

    private func defaultIcon(_ e: LayoutEntry) -> String {
        e.link == "summary" ? "list" : "info"
    }

    private func customGroup(for e: LayoutEntry) -> String {
        switch e.optional {
        case "exteriorOptions": return "Exterior"
        case "testOptions": return "Testing"
        case "utilityOptions": return "Utility"
        default: return e.order != nil ? "Interior" : e.heading
        }
    }

    /// The wizard options chosen for a builder `optional` key. `locked` (areasLockedTypes): exterior, room and utility
    /// choices are kept on the inspection but add nothing; tests always count.
    private func selected(optionKey: String, _ insp: Inspection, locked: Bool = false) -> [String] {
        let w = config.wizard
        if locked, optionKey != "testOptions" { return [] }
        switch optionKey {
        case "exteriorOptions": return w.exteriorOptions.filter { insp.exterior.contains($0) }
        case "utilityOptions": return w.utilityOptions.filter { insp.utilities.contains($0) }
        case "testOptions": return w.testOptions.filter { insp.tests.contains($0) }
        case "roomOptions": return w.roomOptions.filter { insp.rooms.contains($0) }
        default: return []
        }
    }

    /// "Garage?" -> included when selected; "Bathroom×bathrooms" -> repeated per count.
    private func expand(order: [String], _ insp: Inspection, locked: Bool = false) -> [String] {
        var out: [String] = []
        for token in order {
            if token.hasSuffix("?") {
                let n = String(token.dropLast())
                if !locked, insp.rooms.contains(n) { out.append(n) }
            } else if let r = token.range(of: "×") {
                let base = String(token[..<r.lowerBound])
                let key = String(token[r.upperBound...])
                let n = insp.counts[key] ?? 0
                if n > 0 { out += (1...n).map { "\(base) \($0)" } }
            } else {
                out.append(token)
            }
        }
        return out
    }
}

// MARK: - Conditional items (data v1.8 `visibleIf`)

enum ItemVisibility {
    /// The items currently shown for these answers: an item with `visibleIf` is kept only while the item it names (the
    /// first item in the same section with that question) matches — `{q, atLeast: n}` / `{q, includes: o}`.
    /// Hidden items are not shown, not validated and not printed (their saved answers are kept, so they come back if the
    /// condition matches again).
    static func visible(_ keyed: [KeyedItem], answers a: SectionAnswers) -> [KeyedItem] {
        guard keyed.contains(where: { $0.item.visibleIf != nil }) else { return keyed }
        return keyed.filter { k in
            guard let rule = k.item.visibleIf else { return true }
            guard let src = keyed.first(where: { $0.item.q == rule.q && !$0.item.isHeader }) else { return false }
            // v1.13 countChoice: matches the selected options (its counts live in `text`).
            if src.item.kind == .countChoice { return rule.matches(a.choices[src.id] ?? []) }
            return rule.matches(a.choices[src.id] ?? (a.text[src.id].map { [$0] } ?? []))
        }
    }
}

// MARK: - Item keys (stable answer keys: header path + question, deduped)

struct KeyedItem: Identifiable {
    let id: String      // answer key
    let item: ItemDef
}

enum ItemKeys {
    static func keyed(_ items: [ItemDef]) -> [KeyedItem] {
        var header = ""
        var seen: [String: Int] = [:]
        return items.enumerated().map { idx, it in
            if let h = it.header {
                header = h
                return KeyedItem(id: "#h\(idx)|\(h)", item: it)
            }
            let base = "\(header)›\(it.q ?? "")"
            let n = seen[base, default: 0]
            seen[base] = n + 1
            return KeyedItem(id: n == 0 ? base : "\(base)#\(n)", item: it)
        }
    }
}
