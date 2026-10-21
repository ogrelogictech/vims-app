import Foundation

/// Section lookups (JSON + admin overrides) and the checklist builder
/// (mirrors `checklistBuilder` in the shared JSON / buildGroups() in the prototype).
struct ChecklistCatalog {
    let config: ChecklistConfig
    let overrides: ChecklistOverrides

    static let customGroups = ["Exterior", "Interior", "Utility", "Testing"]

    /// "Bathroom 2" -> "Bathroom"
    static func baseName(_ name: String) -> String {
        if let r = name.range(of: #"\s+\d+$"#, options: .regularExpression) { return String(name[..<r.lowerBound]) }
        return name
    }

    func section(_ name: String) -> SectionDef? {
        let base = Self.baseName(name)
        if let o = overrides.sections[base] { return o }
        if let o = overrides.sections[name] { return o }
        return config.sections.first { $0.name == base } ?? config.sections.first { $0.name == name }
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
        if s.isForm { return (s.items, false) }
        if depth == .high, let hi = s.itemsHigh, !hi.isEmpty { return (hi, true) }
        return (s.items, false)
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

    func buildGroups(for insp: Inspection) -> [ChecklistGroup] {
        let builder = config.checklistBuilder
        if let phase = builder.phaseTypes[insp.inspType] {
            return phase.map { e in
                ChecklistGroup(heading: e.heading, icon: e.icon ?? defaultIcon(e), link: e.link, sections: e.sections ?? [], sub: nil)
            }
        }
        return builder.standardLayout.map { e in
            if let link = e.link {
                return ChecklistGroup(heading: e.heading, icon: e.icon ?? defaultIcon(e), link: link, sections: [], sub: nil)
            }
            var secs: [String] = []
            secs += e.always ?? []
            if let opt = e.optional { secs += selected(optionKey: opt, insp) }
            if let order = e.order { secs += expand(order: order, insp) }
            secs += overrides.custom[customGroup(for: e)] ?? []
            var sub: ChecklistSubGroup?
            if let s = e.sub {
                var ss = s.always ?? []
                if let opt = s.optional { ss += selected(optionKey: opt, insp) }
                ss += s.then ?? []
                ss += overrides.custom["Utility"] ?? []
                sub = ChecklistSubGroup(heading: s.heading, sections: ss)
            }
            return ChecklistGroup(heading: e.heading, icon: e.icon, link: nil, sections: secs, sub: sub)
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

    private func selected(optionKey: String, _ insp: Inspection) -> [String] {
        let w = config.wizard
        switch optionKey {
        case "exteriorOptions": return w.exteriorOptions.filter { insp.exterior.contains($0) }
        case "utilityOptions": return w.utilityOptions.filter { insp.utilities.contains($0) }
        case "testOptions": return w.testOptions.filter { insp.tests.contains($0) }
        case "roomOptions": return w.roomOptions.filter { insp.rooms.contains($0) }
        default: return []
        }
    }

    /// "Garage?" -> included when selected; "Bathroom×bathrooms" -> repeated per count.
    private func expand(order: [String], _ insp: Inspection) -> [String] {
        var out: [String] = []
        for token in order {
            if token.hasSuffix("?") {
                let n = String(token.dropLast())
                if insp.rooms.contains(n) { out.append(n) }
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
