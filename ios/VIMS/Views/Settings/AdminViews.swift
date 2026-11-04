import StoreKit
import SwiftUI

// MARK: - 23 Manage checklist (admin)

struct ManageChecklistView: View {
    @Environment(AppStore.self) private var store
    @State private var newName = ""
    @State private var newGroup: String? = ChecklistCatalog.customGroups.first
    @State private var open: Set<String> = ["Exterior"]
    @State private var errors = FormErrors()
    /// Client Oct 28: "Restore original" asks first (one section / the entire checklist).
    @State private var restoring: String?
    @State private var confirmRestoreAll = false
    /// Client Oct 28 (2nd email): "Restore selected checklists" picker, then one confirm naming the picked sections.
    @State private var pickingRestore = false
    @State private var confirmPicked: [AppStore.RestorableSection] = []

    var body: some View {
        Screen(title: "Manage checklist", actions: [store.homeAction()], errors: errors) {
            HintText(text: "Add and edit checklist sections and items yourself — changes apply to new inspections.")
                .padding(.top, 2).padding(.bottom, 12)
            restoreTopCard
            DashedBox {
                SmallField(text: $newName, placeholder: "New section name (e.g. Solar Panels)", kind: .sectionName, fieldID: "section", errors: errors, required: true)
                SingleChipGroup(options: ChecklistCatalog.customGroups, value: $newGroup, required: true)
                    .padding(.bottom, 2)
                Button {
                    let name = Validator.trimmed(newName)
                    let taken = Set(store.catalog.adminGroups().flatMap(\.sections).map { $0.lowercased() })
                    guard errors.validate([("section", newName, .req(.sectionName, "Section name",
                        custom: { taken.contains($0.lowercased()) ? "A section with that name already exists" : nil }))]) else { return }
                    if store.addCustomSection(name: name, group: newGroup ?? "Exterior") {
                        newName = ""
                        open.insert(newGroup ?? "Exterior")
                        store.push(.editSection(name))
                    }
                } label: { IconLabel("Add section", icon: "hdr-add") }
                    .buttonStyle(VButtonStyle(kind: .primary, minHeight: 46))
            }
            ForEach(store.catalog.adminGroups(), id: \.group) { g in
                adminGroup(g.group, g.sections)
            }
        }
        .alert(restoring.map { "Restore \u{201C}\(store.catalog.title($0))\u{201D} to the original?" } ?? "Restore this section?",
               isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), presenting: restoring) { name in
            Button("Restore original", role: .destructive) { store.restoreSection(name); restoring = nil }
            Button("Cancel", role: .cancel) { restoring = nil }
        } message: { _ in
            Text(ChecklistRestoreText.section)
        }
        .alert("Restore all checklists to the original?", isPresented: $confirmRestoreAll) {
            Button("Restore all checklists", role: .destructive) { store.restoreEntireChecklist() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ChecklistRestoreText.all(edited: store.editedSectionCount, custom: store.customSectionCount))
        }
        .alert(ChecklistRestoreText.pickedTitle(confirmPicked),
               isPresented: Binding(get: { !confirmPicked.isEmpty }, set: { if !$0 { confirmPicked = [] } })) {
            Button(confirmPicked.count == 1 ? "Restore checklist" : "Restore \(confirmPicked.count) checklists", role: .destructive) {
                store.restoreSections(confirmPicked.map(\.name)); confirmPicked = []
            }
            Button("Cancel", role: .cancel) { confirmPicked = [] }
        } message: {
            Text(ChecklistRestoreText.picked(confirmPicked))
        }
        .sheet(isPresented: $pickingRestore) {
            RestorePickerSheet(sections: store.restorableSections) { picked in
                pickingRestore = false
                // Let the sheet finish closing before the alert presents.
                Task { try? await Task.sleep(nanoseconds: 450_000_000); confirmPicked = picked }
            }
            .padFormSheet()
        }
        .onAppear {
            #if DEBUG
            // -confirmRestore SECTION|all|picked|"A,B": open the restore confirmation (review screenshots);
            // -pickRestore: open the Restore selected checklists picker.
            if let r = DebugLaunch.value("-confirmRestore") {
                let all = store.restorableSections
                if r == "all" { confirmRestoreAll = true }
                else if r == "picked" { confirmPicked = all }
                else if r.contains(",") { let n = r.split(separator: ",").map(String.init); confirmPicked = all.filter { n.contains($0.name) } }
                else { restoring = r }
            }
            if DebugLaunch.has("-pickRestore") { pickingRestore = true }
            #endif
            if let g = DebugFlags.adminGroup { open = [g]; DebugFlags.adminGroup = nil }
            if DebugFlags.validate {
                DebugFlags.validate = false; newName = "Roof"
                let taken = Set(store.catalog.adminGroups().flatMap(\.sections).map { $0.lowercased() })
                errors.validate([("section", newName, .req(.sectionName, "Section name",
                    custom: { taken.contains($0.lowercased()) ? "A section with that name already exists" : nil }))])
            }
        }
    }

    /// Client Oct 28 (2nd email): the Restore block at the top of Manage checklist, in the client's words — "Restore all
    /// checklists" (the whole checklist) and "Restore selected checklists" (each section is one checklist). Both are
    /// disabled when nothing differs from the VIMS original.
    @ViewBuilder private var restoreTopCard: some View {
        let edited = store.editedSectionCount, added = store.customSectionCount, any = store.hasChecklistEdits
        VStack(alignment: .leading, spacing: 10) {
            Text("Restore checklists").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                .accessibilityAddTraits(.isHeader)
            Text(any ? ChecklistRestoreText.topSummary(edited: edited, added: added)
                     : "Your checklist matches the VIMS original, so there is nothing to restore.")
                .font(VFont.ui(12.5)).foregroundStyle(VC.ink3).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { restoreAllButton; restoreSelectedButton }
                VStack(spacing: 10) { restoreAllButton; restoreSelectedButton }
            }
            .disabled(!any)
            .opacity(any ? 1 : 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
        .padding(.bottom, 12)
    }

    private var restoreAllButton: some View {
        Button { confirmRestoreAll = true } label: { Text("Restore all checklists").lineLimit(1) }
            .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 46))
            .accessibilityHint(store.hasChecklistEdits ? "Restores every section to the VIMS original" : "Nothing to restore")
    }

    private var restoreSelectedButton: some View {
        Button { pickingRestore = true } label: { Text("Restore selected checklists").lineLimit(1) }
            .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 46))
            .accessibilityHint(store.hasChecklistEdits ? "Choose edited or added sections to restore" : "Nothing to restore")
    }

    private func icon(_ g: String) -> String {
        switch g {
        case "Testing": return "flask"
        case "Utility": return "bolt"
        case "Interior": return "sofa"
        case "Phase Inspections": return "layers"
        case "State & Insurance Forms": return "file"
        case "Planned Maintenance": return "file"
        default: return "tree"
        }
    }

    private func adminGroup(_ g: String, _ names: [String]) -> some View {
        let isOpen = open.contains(g)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { if isOpen { open.remove(g) } else { open.insert(g) } }
            } label: {
                HStack(spacing: 11) {
                    ProtoIcon(icon(g), size: 17).foregroundStyle(VC.brand)
                        .frame(width: 30, height: 30).background(VC.paper3)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(g).font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink).frame(maxWidth: .infinity, alignment: .leading)
                    let edited = names.filter { store.isEditedSection($0) || store.isCustomSection($0) }.count
                    if edited > 0 { Text("\(edited) changed").font(VFont.mono(10.5, .semibold)).foregroundStyle(VC.signalDeep) }
                    Text("\(names.count)").font(VFont.mono(11)).foregroundStyle(VC.ink3)
                    ProtoIcon("chevron-down", size: 18).foregroundStyle(VC.ink3)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 15).padding(.vertical, 13).frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            if isOpen {
                Rectangle().fill(VC.line2).frame(height: 1)
                ForEach(names, id: \.self) { n in
                    let count = store.catalog.section(n)?.items.filter { !$0.isHeader }.count ?? 0
                    Button { store.push(.editSection(n)) } label: {
                        HStack(spacing: 12) {
                            Text(store.catalog.title(n)).font(VFont.ui(14, .medium)).foregroundStyle(VC.ink).frame(maxWidth: .infinity, alignment: .leading)
                            if store.isCustomSection(n) { Pill(kind: .prog, text: "Added", dot: false) }
                            else if store.isEditedSection(n) { Pill(kind: .queued, text: "Edited", dot: false) }
                            Text(store.catalog.isPhotosOnly(n) ? "photos only" : "\(count) items").font(VFont.mono(10.5, .semibold)).foregroundStyle(VC.ink2)
                            Chevron()
                        }
                        .padding(.leading, 18).padding(.trailing, 15).padding(.vertical, 12).frame(minHeight: 44)
                        .overlay(alignment: .bottom) { if !store.isEditedSection(n) { Rectangle().fill(VC.line2).frame(height: 1) } }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityHint(store.isEditedSection(n) ? "Edited by your company" : "")
                    if store.isEditedSection(n) {
                        // Client Oct 28: per-section "Restore original" right under the edited section.
                        HStack(spacing: 10) {
                            Text("Your company changed this section.").font(VFont.ui(12)).foregroundStyle(VC.ink3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Restore original") { restoring = n }
                                .font(VFont.ui(12.5, .semibold)).foregroundStyle(VC.brandDeep)
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(VC.paper)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(VC.line, lineWidth: 1))
                                .accessibilityLabel("Restore \(store.catalog.title(n)) to the original")
                        }
                        .padding(.leading, 18).padding(.trailing, 15).padding(.top, 2).padding(.bottom, 10)
                        .background(VC.paper2)
                        .overlay(alignment: .bottom) { Rectangle().fill(VC.line2).frame(height: 1) }
                    }
                }
            }
        }
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 10)
    }
}

/// Restore-to-original wording (client Oct 28), shared by Manage checklist and Edit section.
enum ChecklistRestoreText {
    static let section = "This removes your company\u{2019}s changes to this section (renamed, added and removed items) and brings back the VIMS original for new inspections. Inspections already started keep their saved checklist."

    static func all(edited: Int, custom: Int) -> String {
        "This removes all of your company\u{2019}s checklist changes — \(summary(edited: edited, custom: custom, sentence: false)) — and brings back the VIMS original for new inspections. Inspections already started keep their saved checklist."
    }

    /// "2 edited sections and 1 custom section."
    static func summary(edited: Int, custom: Int, sentence: Bool = true) -> String {
        var parts: [String] = []
        if edited > 0 { parts.append("\(edited) edited section\(edited == 1 ? "" : "s")") }
        if custom > 0 { parts.append("\(custom) custom section\(custom == 1 ? "" : "s") you added") }
        let t = parts.isEmpty ? "no changes" : parts.joined(separator: " and ")
        return sentence ? t.prefix(1).uppercased() + t.dropFirst() + "." : t
    }

    /// The top Restore block: "2 edited and 1 added checklist. Restore all of them, or pick …".
    static func topSummary(edited: Int, added: Int) -> String {
        var parts: [String] = []
        if edited > 0 { parts.append("\(edited) edited") }
        if added > 0 { parts.append("\(added) added") }
        let n = edited + added
        return parts.joined(separator: " and ") + " checklist\(n == 1 ? "" : "s"). "
            + (n == 1 ? "Restore it to the VIMS original" : "Restore all of them, or pick the ones to restore")
            + (added > 0 ? "; added sections are removed." : ".") + " Inspections already started keep their saved checklist."
    }

    /// "Restore 3 checklists?" · "Restore \u{201C}Roof\u{201D}?"
    static func pickedTitle(_ picked: [AppStore.RestorableSection]) -> String {
        picked.count == 1 ? "Restore \u{201C}\(picked[0].title)\u{201D}?" : "Restore \(picked.count) checklists?"
    }

    /// Names every picked section: edited ones go back to the VIMS original, added ones are removed.
    static func picked(_ picked: [AppStore.RestorableSection]) -> String {
        let edited = picked.filter { !$0.added }.map(\.title), added = picked.filter(\.added).map(\.title)
        var t = ""
        if !edited.isEmpty { t += list(edited) + (edited.count == 1 ? " goes" : " go") + " back to the VIMS original. " }
        if !added.isEmpty { t += list(added) + (added.count == 1 ? " was added by your company and is removed. " : " were added by your company and are removed. ") }
        return t + "Inspections already started keep their saved checklist."
    }

    /// \u{201C}A\u{201D}, \u{201C}B\u{201D} and \u{201C}C\u{201D}
    static func list(_ names: [String]) -> String {
        let q = names.map { "\u{201C}\($0)\u{201D}" }
        return q.count < 3 ? q.joined(separator: " and ") : q.dropLast().joined(separator: ", ") + " and " + q[q.count - 1]
    }
}

/// Client Oct 28 (2nd email) — "Restore selected checklists": only the Edited / Added sections, each with a checkmark
/// toggle (44 pt+ rows) and Select all; Restore hands the pick to Manage checklist for one confirm.
struct RestorePickerSheet: View {
    let sections: [AppStore.RestorableSection]
    let onRestore: ([AppStore.RestorableSection]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

    var body: some View {
        let allOn = !sections.isEmpty && picked.count == sections.count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Each section is one checklist. Only sections you edited or added are listed. Added sections are removed when restored.")
                        .font(VFont.ui(13)).foregroundStyle(VC.ink3).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                    VStack(spacing: 0) {
                        row(title: "Select all", detail: nil, tag: nil, on: allOn, bold: true) {
                            picked = allOn ? [] : Set(sections.map(\.name))
                        }
                        .accessibilityValue(allOn ? "All selected" : "\(picked.count) of \(sections.count) selected")
                        ForEach(sections) { s in
                            row(title: s.title, detail: s.group.isEmpty ? nil : s.group, tag: s.added ? "Added" : "Edited",
                                on: picked.contains(s.name), bold: false) {
                                if picked.contains(s.name) { picked.remove(s.name) } else { picked.insert(s.name) }
                            }
                        }
                    }
                    .background(VC.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
                }
                .padding(16)
            }
            .background(VC.paper2)
            .safeAreaInset(edge: .bottom) {
                Button {
                    onRestore(sections.filter { picked.contains($0.name) })
                } label: { Text(picked.isEmpty ? "Restore selected" : "Restore \(picked.count) selected") }
                    .buttonStyle(VButtonStyle(kind: .primary, minHeight: 50))
                    .disabled(picked.isEmpty)
                    .opacity(picked.isEmpty ? 0.5 : 1)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                    .background(VC.paper.ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) { Rectangle().fill(VC.line).frame(height: 1) }
            }
            .navigationTitle("Restore selected checklists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(VC.brand) }
            }
            .toolbarBackground(VC.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
        .onAppear {
            #if DEBUG
            // -pickRestore with -pickAll: every listed section starts ticked (review screenshots).
            if DebugLaunch.has("-pickAll") { picked = Set(sections.map(\.name)) }
            #endif
        }
    }

    private func row(title: String, detail: String?, tag: String?, on: Bool, bold: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(on ? VC.brand : VC.ink3)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(VFont.ui(14, bold ? .bold : .medium)).foregroundStyle(VC.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail { Text(detail).font(VFont.ui(12)).foregroundStyle(VC.ink3) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let tag { Pill(kind: tag == "Added" ? .prog : .queued, text: tag, dot: false) }
            }
            .padding(.horizontal, 15).padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(VC.line2).frame(height: 1) }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityLabel(tag.map { "\(title), \($0)" } ?? title)
    }
}

// MARK: Edit a section

struct EditItem: Identifiable, Equatable {
    let id = UUID()
    var item: ItemDef
}

struct EditSectionView: View {
    @Environment(AppStore.self) private var store
    let sectionName: String
    @State private var def: SectionDef?
    @State private var tier: Depth = .standard
    @State private var items: [EditItem] = []
    @State private var confirmRemove = false
    @State private var confirmRestore = false
    @State private var errors = FormErrors()

    var body: some View {
        Screen(title: store.catalog.title(sectionName), subtitle: store.isEditedSection(sectionName) ? "Edit section · Edited" : "Edit section", actions: [store.homeAction()], errors: errors) {
            if let def {
                if def.itemsHigh?.isEmpty == false {
                    Picker("Checklist tier", selection: Binding(get: { tier }, set: { switchTier($0) })) {
                        Text("Standard items").tag(Depth.standard)
                        Text("High Detail items").tag(Depth.high)
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 4)
                }
                SectionLabel(text: "Checklist items · \(sectionName)", top: 10)
                ForEach($items) { $e in
                    EditItemCard(edit: $e, errors: errors,
                                 canUp: e.id != items.first?.id, canDown: e.id != items.last?.id,
                                 move: { move(e.id, by: $0) },
                                 delete: { items.removeAll { $0.id == e.id } },
                                 notesLine: def.isNotes)
                }
                Button {
                    items.append(EditItem(item: def.isNotes ? newNotesLine() : .question("New item", options: ["Yes", "No", "N/A"])))
                } label: { IconLabel(def.isNotes ? "Add line" : "Add item", icon: "hdr-add") }
                    .buttonStyle(.vGhost)
                Button { save() } label: { IconLabel("Save & done", icon: "link-my-account") }
                    .buttonStyle(.vPrimary).padding(.top, 10)
                if store.isEditedSection(sectionName) {
                    // Client Oct 28: drop this company's changes to the section (asks first).
                    Button("Restore original") { confirmRestore = true }
                        .buttonStyle(.vGhost)
                        .padding(.top, 10)
                        .alert("Restore \u{201C}\(store.catalog.title(sectionName))\u{201D} to the original?", isPresented: $confirmRestore) {
                            Button("Restore original", role: .destructive) {
                                store.restoreSection(sectionName)
                                store.back()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: { Text(ChecklistRestoreText.section) }
                }
                if store.isCustomSection(sectionName) {
                    Button(role: .destructive) { confirmRemove = true } label: {
                        IconLabel("Remove this section", icon: "trash").foregroundStyle(VC.c1)
                    }
                    .buttonStyle(.vGhost)
                    .alert("Remove the “\(sectionName)” section?", isPresented: $confirmRemove) {
                        Button("Remove", role: .destructive) {
                            store.removeCustomSection(sectionName)
                            store.back()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: { Text("It won't appear in new inspections. Existing inspections keep their answers.") }
                    .padding(.top, 10)
                }
            }
        }
        .onAppear {
            guard def == nil else { return }
            def = store.catalog.section(sectionName) ?? SectionDef(name: sectionName, number: 99, icon: nil, photoCategories: ["Overview", "Concerns"],
                                                                    photoCategoriesHigh: nil, items: [], itemsHigh: nil)
            items = (def?.items ?? []).map { EditItem(item: $0) }
            if DebugFlags.validate, !items.isEmpty { DebugFlags.validate = false; items[0].item.q = ""; save() }
        }
    }

    /// Data v1.14 notes section (Planned Maintenance): a new line is an optional text line like the shipped ones
    /// ("Recommendation 11", up to 300 characters, the next free number).
    private func newNotesLine() -> ItemDef {
        let taken = Set(items.compactMap { $0.item.q?.lowercased() })
        let base = items.first { !$0.item.isHeader }?.item.q.map { $0.replacingOccurrences(of: #"\s*\d+$"#, with: "", options: .regularExpression) }
        let stem = (base?.isEmpty == false ? base! : "Recommendation")
        var n = items.filter { !$0.item.isHeader }.count + 1
        while taken.contains("\(stem) \(n)".lowercased()) { n += 1 }
        let max = items.compactMap(\.item.maxLength).max() ?? NotesLineCard.defaultMax
        return ItemDef(q: "\(stem) \(n)", type: "text", options: nil, header: nil, placeholder: nil, maxLength: max)
    }

    private func commitTier() {
        let list = items.map(\.item)
        if tier == .high { def?.itemsHigh = list } else { def?.items = list }
    }

    private func switchTier(_ t: Depth) {
        commitTier()
        tier = t
        items = ((t == .high ? def?.itemsHigh : def?.items) ?? []).map { EditItem(item: $0) }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard items.indices.contains(j) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { items.swapAt(i, j) }
    }

    private func save() {
        // Every question needs text (max 120); headers too.
        let fields: [(id: String, value: String, rule: FieldRule)] = items.map { e in
            ("q-\(e.id)", e.item.header ?? e.item.q ?? "", .req(.question, e.item.isHeader ? "Header" : "Question"))
        }
        guard errors.validate(fields) else { return }
        for i in items.indices {
            if items[i].item.isHeader { items[i].item.header = Validator.trimmed(items[i].item.header ?? "") }
            else { items[i].item.q = Validator.trimmed(items[i].item.q ?? "") }
        }
        commitTier()
        guard let def else { return }
        store.saveSectionOverride(def)
        store.back()
    }
}

struct EditItemCard: View {
    @Binding var edit: EditItem
    let errors: FormErrors
    let canUp: Bool
    let canDown: Bool
    let move: (Int) -> Void
    let delete: () -> Void
    /// Data v1.14 notes section (Planned Maintenance): every line is a free-text line; its type is fixed here.
    var notesLine = false
    @State private var newOption = ""
    @State private var focused = false
    @State private var confirmDelete = false

    /// "“Number of kitchens” and its options will be removed from new inspections."
    private var deleteMessage: String {
        let raw = Validator.trimmed(edit.item.header ?? edit.item.q ?? "")
        let name = raw.isEmpty ? (edit.item.isHeader ? "This header" : "This item") : "\u{201C}\(raw)\u{201D}"
        let hasOptions = !edit.item.isHeader && !(edit.item.options ?? []).isEmpty && [.single, .multi, .countChoice].contains(edit.item.kind)
        return "\(name)\(hasOptions ? " and its options" : "") will be removed from new inspections."
    }

    private let types: [(String, String)] = [("single", "Pick one"), ("multi", "Pick several"), ("text", "Text"), ("num", "Number"), ("date", "Date"), ("time", "Time")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if edit.item.isHeader {
                    Text("HEADER").font(VFont.mono(9.5, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(VC.hdr).clipShape(Capsule())
                }
                FilteredTextField(text: Binding(
                    get: { edit.item.header ?? edit.item.q ?? "" },
                    set: { if edit.item.isHeader { edit.item.header = $0 } else { edit.item.q = $0 } }),
                              kind: .question, fieldID: "q-\(edit.id)", errors: errors, placeholder: "Question",
                              font: VFont.uUI(14.5, .semibold), onFocus: { focused = $0 })
                    .padding(.vertical, 5)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(errors["q-\(edit.id)"] != nil ? VC.c1 : (focused ? VC.brand : VC.line)).frame(height: 1.5)
                    }
                HStack(spacing: 6) {
                    iconButton("chevron-up", "Move up", enabled: canUp) { move(-1) }
                    iconButton("chevron-down", "Move down", enabled: canDown) { move(1) }
                    // Deleting asks first (Oct 13 QA); on iPad the dialog points at this trash button.
                    iconButton("trash", "Delete item", enabled: true) { confirmDelete = true }
                        .alert(edit.item.isHeader ? "Delete this header?" : "Delete this item?", isPresented: $confirmDelete) {
                            Button("Delete", role: .destructive, action: delete)
                            Button("Cancel", role: .cancel) {}
                        } message: { Text(deleteMessage) }
                }
            }
            if let e = errors["q-\(edit.id)"] { FieldError(text: e) }
            if edit.item.kind == .countChoice {
                countChoiceSummary
            } else if notesLine, !edit.item.isHeader {
                Text("Text line · optional · up to \(edit.item.maxLength ?? NotesLineCard.defaultMax) characters")
                    .font(VFont.ui(12, .semibold)).foregroundStyle(VC.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(VC.paper3).clipShape(Capsule())
                    .fixedSize(horizontal: false, vertical: true)
            } else if !edit.item.isHeader {
                Menu {
                    ForEach(types, id: \.0) { t in
                        Button(t.1) {
                            edit.item.type = t.0
                            if ["single", "multi"].contains(t.0), (edit.item.options ?? []).isEmpty { edit.item.options = ["Yes", "No", "N/A"] }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(edit.item.kind == .airReading ? "Air reading" : types.first { $0.0 == (edit.item.type ?? "single") }?.1 ?? "Pick one").font(VFont.ui(12, .semibold))
                        ProtoIcon("chevron-down", size: 12)
                    }
                    .foregroundStyle(VC.brandDeep)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(VC.brand.opacity(0.1)).clipShape(Capsule())
                }
                if edit.item.kind == .single || edit.item.kind == .multi {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(Array((edit.item.options ?? []).enumerated()), id: \.offset) { i, op in
                            HStack(spacing: 7) {
                                Text(op).font(VFont.ui(12.5)).foregroundStyle(VC.ink2)
                                Button { edit.item.options?.remove(at: i) } label: {
                                    Text("×").font(.system(size: 16)).foregroundStyle(VC.ink3)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove option \(op)")
                            }
                            .padding(.leading, 12).padding(.trailing, 5).padding(.vertical, 3)
                            .background(VC.paper3).clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 7) {
                        SmallField(text: $newOption, placeholder: "Add option…", kind: .option, fieldID: "opt-\(edit.id)", errors: errors,
                                   onSubmit: addOption)
                        Button("Add", action: addOption)
                            .font(VFont.ui(14, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 15).frame(minHeight: 44)
                            .background(VC.brand).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 11)
    }

    /// Data v1.13 `countChoice` (client Oct 30, Receptacles): the question can be renamed, moved and deleted like any item;
    /// its type and buttons are fixed (read-only here), since the report and the count fields depend on them.
    private var countChoiceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buttons + counts")
                .font(VFont.ui(12, .semibold)).foregroundStyle(VC.ink2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(VC.paper3).clipShape(Capsule())
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(edit.item.options ?? [], id: \.self) { op in
                    let counted = (edit.item.countOptions ?? []).contains(op)
                    Text(counted ? "\(op) + \(edit.item.countPlaceholder ?? "count")" : op)
                        .font(VFont.ui(12.5)).foregroundStyle(VC.ink2)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(VC.paper3).clipShape(Capsule())
                }
            }
            Text("These buttons are fixed. You can rename, move or delete the item.")
                .font(VFont.ui(12)).foregroundStyle(VC.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func addOption() {
        let existing = Set((edit.item.options ?? []).map { $0.lowercased() })
        guard errors.validate([("opt-\(edit.id)", newOption, .req(.option, "Option",
            custom: { existing.contains($0.lowercased()) ? "That option is already in this question" : nil }))]) else { return }
        let v = Validator.trimmed(newOption)
        edit.item.options = (edit.item.options ?? []) + [v]
        newOption = ""
    }

    private func iconButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ProtoIcon(symbol, size: 15).foregroundStyle(VC.ink3)
                .frame(width: 36, height: 36)
                .background(VC.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(VC.line, lineWidth: 1))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

// MARK: - 24 Plans & pricing (VIMS master admin only, client Oct 28)

struct PlansAdminView: View {
    @Environment(AppStore.self) private var store
    /// Typed values by field id ("price-<plan>", "yearly-<plan>", "extra", "extraYearly"); nil = the saved value.
    @State private var texts: [String: String] = [:]
    /// QA Oct 14: plan descriptions are multi-line (edited on each card, wrapped on the Subscription screen).
    @State private var descs: [String: String] = [:]
    @State private var newName = ""
    @State private var newPrice = ""
    @State private var newYearly = ""
    @State private var newDesc = ""
    @State private var errors = FormErrors()

    var body: some View {
        // Data v1.18 `features.planEditing` is false in Phase 1: the stores set the prices. The editor stays for Phase 2.
        if store.config.planEditingEnabled { editor } else { StorePricesView() }
    }

    @ViewBuilder private var editor: some View {
        let pricing = store.pricing
        Screen(title: "Plans & pricing", subtitle: "Master admin", actions: [store.homeAction()], errors: errors) {
            Text(md("**Master admin (VIMS owner only)** — edit monthly and yearly plan prices, add a plan, or set the per-inspector rates. Changes apply to every company\u{2019}s Subscribe screen. Company admins can\u{2019}t see or change these."))
                .font(VFont.ui(13)).foregroundStyle(VC.ink3).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2).padding(.bottom, 12)
            ForEach(pricing.plans, id: \.id) { p in
                planCard(p, isLast: pricing.plans.count <= 1)
            }
            extraCard(pricing)
            DashedBox {
                SmallField(text: $newName, placeholder: "Plan name (e.g. Team)", kind: .plain(max: 40), fieldID: "newName", errors: errors, required: true)
                SmallField(text: $newPrice, placeholder: "Monthly price (e.g. 99.00)", keyboard: .decimalPad, kind: .price, fieldID: "newPrice", errors: errors, required: true)
                SmallField(text: $newYearly, placeholder: "Yearly price (optional, e.g. 990.00)", keyboard: .decimalPad, kind: .price, fieldID: "newYearly", errors: errors)
                DescriptionBox(text: $newDesc, placeholder: "Short description (a few lines are fine)")
                Button { addPlan() } label: { IconLabel("Add plan", icon: "hdr-add") }
                    .buttonStyle(VButtonStyle(kind: .primary, minHeight: 46))
            }
        }
        .onAppear {
            if DebugFlags.validate { DebugFlags.validate = false; newPrice = "0"; texts["extra"] = "12000"; texts["extraYearly"] = "0"; addPlan(); saveExtra() }
        }
    }

    /// A plan card's delete control ("Additional inspector" is a rate setting, so it has none).
    struct PlanDelete { let plan: PlanDef; let isLast: Bool; let isCurrent: Bool }

    private func text(_ id: String, _ saved: Double?) -> Binding<String> {
        Binding(get: { texts[id] ?? saved.map(Fmt.price) ?? "" }, set: { texts[id] = $0 })
    }

    private func planCard(_ p: PlanDef, isLast: Bool) -> some View {
        card(id: "price-\(p.id)") {
            HStack(alignment: .center, spacing: 8) {
                Text(p.name).font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink)
                if p.isComingSoon { Pill(kind: .queued, text: "Coming soon", dot: false) }
                Spacer(minLength: 4)
                PlanDeleteButton(info: PlanDelete(plan: p, isLast: isLast, isCurrent: store.subscription.selectedPlan == p.id))
            }
            if p.isPerReport {
                priceRow(id: "price-\(p.id)", label: "Per report $", unit: p.unit ?? "/report", text: text("price-\(p.id)", p.price), a11y: "\(p.name) price per report")
            } else {
                priceRow(id: "price-\(p.id)", label: "Monthly $", unit: "/mo", text: text("price-\(p.id)", p.price), a11y: "\(p.name) monthly price")
                priceRow(id: "yearly-\(p.id)", label: "Yearly $", unit: "/yr", text: text("yearly-\(p.id)", p.priceYearly), required: false,
                         a11y: "\(p.name) yearly price")
                Text("Leave Yearly blank to offer this plan monthly only.").font(VFont.ui(11.5)).foregroundStyle(VC.ink3)
            }
            DescriptionBox(text: Binding(get: { descs[p.id] ?? p.desc }, set: { descs[p.id] = $0 }), placeholder: "Short description")
            Button("Save \(p.name)") { commit(p.id) }
                .font(VFont.ui(13.5, .semibold)).foregroundStyle(VC.brandDeep)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(VC.paper3).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.top, 13)
        }
    }

    private func extraCard(_ pricing: PlatformSettings.Pricing) -> some View {
        card(id: "extra") {
            Text("Additional inspector").font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink)
            Text("Each inspector after the first. Billed on the company\u{2019}s period (monthly or yearly).")
                .font(VFont.ui(12)).foregroundStyle(VC.ink3).fixedSize(horizontal: false, vertical: true)
            // Client Oct 28 (shared v1.11.1): a rate on every plan, not a plan, so it intentionally has no Delete.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(VC.ink3)
                    .accessibilityHidden(true)
                Text("Applies to every plan, so it can\u{2019}t be deleted.")
                    .font(VFont.ui(12, .semibold)).foregroundStyle(VC.ink2).fixedSize(horizontal: false, vertical: true)
            }
            priceRow(id: "extra", label: "Monthly $", unit: "/mo each", text: text("extra", pricing.extraMonthly), a11y: "Additional inspector monthly rate")
            priceRow(id: "extraYearly", label: "Yearly $", unit: "/yr each", text: text("extraYearly", pricing.extraYearly), a11y: "Additional inspector yearly rate")
            Button("Save rates") { saveExtra() }
                .font(VFont.ui(13.5, .semibold)).foregroundStyle(VC.brandDeep)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(VC.paper3).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.top, 3)
        }
    }

    private func card<C: View>(id: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(VC.line, lineWidth: 1))
            .padding(.bottom, 11)
            .id(id)
    }

    @ViewBuilder
    private func priceRow(id: String, label: String, unit: String, text: Binding<String>, required: Bool = true, a11y: String) -> some View {
        let err = errors[id]
        HStack(spacing: 10) {
            FieldLabel(text: label, required: required)
                .frame(width: 92, alignment: .leading)
            FilteredTextField(text: text, kind: .price, fieldID: id, errors: errors, keyboard: .decimalPad, accessibilityLabel: a11y)
                .padding(.horizontal, 12).frame(width: 120, height: 48)
                .background(VC.paper)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(err != nil ? VC.c1 : VC.line, lineWidth: err != nil ? 2 : 1))
            Text(unit).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
            Spacer(minLength: 0)
        }
        .id(id)
        if let err { FieldError(text: err) }
    }

    private func commit(_ id: String) {
        var pricing = store.pricing
        guard let i = pricing.plans.firstIndex(where: { $0.id == id }) else { return }
        let plan = pricing.plans[i]
        let monthly = texts["price-\(id)"] ?? Fmt.price(plan.price)
        let yearly = texts["yearly-\(id)"] ?? plan.priceYearly.map(Fmt.price) ?? ""
        var fields: [(id: String, value: String, rule: FieldRule)] = [("price-\(id)", monthly, .req(.price, "Price"))]
        if !plan.isPerReport { fields.append(("yearly-\(id)", yearly, .opt(.price, "Yearly price"))) }
        guard errors.validate(fields) else { return }
        pricing.plans[i].price = Validator.number(monthly) ?? plan.price
        if !plan.isPerReport { pricing.plans[i].priceYearly = Validator.trimmed(yearly).isEmpty ? nil : Validator.number(yearly) }
        if let d = descs[id] {
            let t = d.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { pricing.plans[i].desc = t }
        }
        store.savePricing(pricing)
        texts["price-\(id)"] = nil; texts["yearly-\(id)"] = nil; descs[id] = nil
        let p = pricing.plans[i]
        store.toast("\(p.name) → \(SubscriptionState.priceLabel(p, .monthly))\(p.hasYearly ? " · " + SubscriptionState.priceLabel(p, .yearly) : "")")
    }

    private func saveExtra() {
        var pricing = store.pricing
        let m = texts["extra"] ?? Fmt.price(pricing.extraMonthly)
        let y = texts["extraYearly"] ?? Fmt.price(pricing.extraYearly)
        guard errors.validate([("extra", m, .req(.price, "Monthly rate")), ("extraYearly", y, .req(.price, "Yearly rate"))]) else { return }
        pricing.extraMonthly = Validator.number(m) ?? pricing.extraMonthly
        pricing.extraYearly = Validator.number(y) ?? pricing.extraYearly
        store.savePricing(pricing)
        texts["extra"] = nil; texts["extraYearly"] = nil
        store.toast("Additional inspector → \(Fmt.money(pricing.extraMonthly))/mo · \(Fmt.money(pricing.extraYearly))/yr")
    }

    private func addPlan() {
        var pricing = store.pricing
        let names = Set(pricing.plans.map { $0.name.lowercased() })
        guard errors.validate([
            ("newName", newName, .req(.plain(max: 40), "Plan name", custom: { names.contains($0.lowercased()) ? "A plan with that name already exists" : nil })),
            ("newPrice", newPrice, .req(.price, "Price")),
            ("newYearly", newYearly, .opt(.price, "Yearly price"))
        ]) else { return }
        let n = Validator.trimmed(newName)
        let id = "plan\(pricing.plans.count + 1)-\(UUID().uuidString.prefix(4))"
        let d = newDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        pricing.plans.append(PlanDef(id: id, name: n, price: Validator.number(newPrice) ?? 0, desc: d.isEmpty ? "Custom plan" : d,
                                     unit: nil, perReport: nil,
                                     priceYearly: Validator.trimmed(newYearly).isEmpty ? nil : Validator.number(newYearly)))
        store.savePricing(pricing)
        newName = ""; newPrice = ""; newYearly = ""; newDesc = ""
        store.toast("Added \u{201C}\(n)\u{201D}")
    }
}

/// Multi-line plan description (QA Oct 14): the app's multi-line text box (wraps while typing, line breaks kept), 200 max.
private struct DescriptionBox: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VTextArea(text: $text, placeholder: placeholder, minHeight: 64, maxLength: 200)
            .padding(.bottom, -13)
            .accessibilityLabel(placeholder)
    }
}

/// Trash on a plan card → "Delete this plan?" (anchored to the button on iPad). The last plan can't be deleted.
private struct PlanDeleteButton: View {
    @Environment(AppStore.self) private var store
    let info: PlansAdminView.PlanDelete
    @State private var confirm = false

    var body: some View {
        Button {
            if info.isLast { store.toast("Keep at least one plan") } else { confirm = true }
        } label: {
            ProtoIcon("trash", size: 15).foregroundStyle(info.isLast ? VC.ink3.opacity(0.5) : VC.c1)
                .frame(width: 36, height: 36)
                .background(VC.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(VC.line, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -6)
        .accessibilityLabel("Delete \(info.plan.name) plan")
        .accessibilityHint(info.isLast ? "The only plan can't be deleted" : "")
        // Team QA Oct 22: centered alert, short title + message, explicit Delete / Cancel.
        .alert("Delete the \u{201C}\(info.plan.name)\u{201D} plan?", isPresented: $confirm) {
            Button("Delete", role: .destructive) { store.deletePlan(info.plan.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will no longer be offered on any company\u{2019}s Subscribe screen. Companies on it move to "
                 + "\(store.pricing.plans.first { $0.id != info.plan.id && $0.isSelectable }?.name ?? "another plan").")
        }
    }
}

// MARK: - 25 Inspectors

struct InspectorsView: View {
    @Environment(AppStore.self) private var store
    /// QA Oct 14: Remove asks first.
    @State private var removing: Inspector?
    @State private var name = ""
    @State private var email = ""
    @State private var errors = FormErrors()
    var wide = WideLayout()

    var body: some View {
        Screen(title: "Inspectors", actions: [store.homeAction()], errors: errors) {
            if !joinEnabled {
                // Data v1.18 `features.companyJoin` is false in Phase 1: no server, so nobody can be added from another
                // device. What's left is the people already on this device: their roles, ownership and the list itself.
                intro
                if store.isAdmin && store.otherCompanyUsers.count > 0 { roles }
                team
            } else if wide.isWide {
                // iPad landscape: the join code and the add form on the left, the team beside them.
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 0) { intro; joinCode; addForm }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 0) { roles; team; total }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                intro; joinCode; roles; team; total; addForm
            }
        }
        .alert(removing.map { "Remove \($0.name)?" } ?? "Remove this inspector?",
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { ins in
            Button("Remove", role: .destructive) {
                store.removeInspector(ins.id)
                store.toast("\(ins.name) removed")
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { ins in
            Text(joinEnabled ? "They'll lose access to \(store.company.name)'s checklist, plans and profile. Their own inspections stay on their device."
                 : store.repo.user(id: ins.id) != nil ? "They come off \(store.company.name)'s team and lose admin access. Their account and inspections stay on this device."
                 : "They come off \(store.company.name)'s team list.")
        }
        .onAppear {
            if DebugFlags.validate { DebugFlags.validate = false; name = ""; email = store.company.inspectors.first?.email ?? "x@y.com"; addInspector() }
        }
    }

    private var joinEnabled: Bool { store.config.companyJoinEnabled }

    private var intro: some View {
        Text(md(joinEnabled
                ? "Add inspector accounts under your company license. First inspector is included; each additional is **\(Fmt.money(store.subscription.extraRate(store.subscription.period)))\(store.subscription.period.unit)**."
                : "Inspector accounts on this device. An inspector on another phone or tablet creates an account and subscribes there."))
            .font(VFont.ui(13)).foregroundStyle(VC.ink3).padding(.top, 2).padding(.bottom, 12)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var joinCode: some View {
        let company = store.company
        return VStack(alignment: .leading, spacing: 0) {
            Text("COMPANY JOIN CODE").font(VFont.mono(10.5)).tracking(1.2).foregroundStyle(VC.ink3).padding(.bottom, 7)
            HStack {
                Text(company.joinCode).font(VFont.mono(24, .semibold)).tracking(4.3).foregroundStyle(VC.brandDeep)
                    .accessibilityLabel("Company code \(company.joinCode.map(String.init).joined(separator: " "))")
                Spacer()
                Button {
                    UIPasteboard.general.string = company.joinCode
                    store.toast("Code \(company.joinCode) copied")
                } label: {
                    IconLabel("Copy", icon: "copy").font(VFont.ui(12.5, .semibold)).foregroundStyle(VC.brandDeep)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(VC.paper3).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(ChipPressStyle())
            }
            Text(md("Share this code with an inspector. They download VIMS, tap **Join a company with a code**, and their account links to your license & billing."))
                .font(VFont.ui(12)).foregroundStyle(VC.ink3).lineSpacing(2).padding(.top, 9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(VC.brand, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.bottom, 14)
    }

    private var roles: some View {
        Text(md(joinEnabled
                ? "You (the account owner) are an **admin** by default. Tap **Make admin** to grant any inspector admin access — admins can manage checklists, plans, the company profile, and settings. Nothing is hard-coded; roles are set here."
                : "You (the account owner) are an **admin** by default. Tap **Make admin** to grant any inspector here admin access — admins can manage checklists, the company profile, and settings."))
            .font(VFont.ui(12)).foregroundStyle(VC.ink3).lineSpacing(2).padding(.horizontal, 2).padding(.bottom, 12)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var team: some View {
        let company = store.company
        return VStack(spacing: 0) {
            ForEach(company.inspectors) { ins in
                HStack(spacing: 13) {
                    UserAvatar(userID: ins.id, name: ins.name, size: 44, radius: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ins.name) · \(ins.roleLabel)").font(VFont.ui(15, .semibold)).foregroundStyle(VC.ink)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(ins.email.isEmpty ? "no email yet" : ins.email).font(VFont.ui(12.5, .medium)).foregroundStyle(VC.ink2).lineLimit(1).minimumScaleFactor(0.75)  // long emails shrink, not cut (QA Oct 22)
                        if !joinEnabled, ins.id != store.myInspectorID, store.repo.user(id: ins.id) == nil {
                            Text("No account on this device").font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.top, 3)
                        }
                        // Admins who aren't the owner can't take ownership back (security); say so on the owner's row.
                        if ins.owner, ins.id != store.myInspectorID {
                            Text("Only the owner can transfer ownership.")
                                .font(VFont.ui(12)).foregroundStyle(VC.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // With join off, an old invite (no account on this device) can never turn into an account: it can
                    // only be removed, and can't be given a role or the company.
                    let actionable = joinEnabled || store.repo.user(id: ins.id) != nil
                    if ins.owner {
                        Pill(kind: .done, text: "Owner")
                    } else if ins.id == store.myInspectorID {
                        // Your own row: no Make admin / Remove / Make owner (same as Android).
                        if ins.admin { Pill(kind: .prog, text: "Admin", dot: false) }
                    } else if joinEnabled || store.isAdmin {
                        VStack(alignment: .trailing, spacing: 6) {
                            if actionable {
                                Button { store.toggleAdmin(ins.id) } label: {
                                    Pill(kind: ins.admin ? .prog : .new, text: ins.admin ? "Admin ✓" : "Make admin", dot: false)
                                        .frame(minHeight: 32)
                                }
                                .buttonStyle(ChipPressStyle())
                            }
                            // Only the current owner can hand over ownership — to anyone on the team with an email
                            // (including the previous owner), after confirming. The new owner becomes an admin too.
                            if actionable && store.isCompanyOwner && !ins.email.isEmpty {
                                MakeOwnerButton(inspector: ins)
                            }
                            Button { removing = ins } label: {
                                Pill(kind: .queued, text: "Remove", dot: false).frame(minHeight: 32)
                            }
                            .buttonStyle(ChipPressStyle())
                            .accessibilityLabel("Remove \(ins.name)")
                        }
                    }
                }
                .padding(.horizontal, 15).padding(.vertical, 14)
                .background(VC.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
                .padding(.bottom, 10)
            }
        }
    }

    private var total: some View {
        let n = store.company.inspectors.count
        return (Text("\(n) inspector\(n == 1 ? "" : "s")").font(VFont.ui(12.5, .bold)).foregroundColor(VC.ink)
         + Text(" · \(store.subscription.period.totalLabel.lowercased()) \(Fmt.money(store.subscription.total(seats: n)))").font(VFont.ui(12.5)).foregroundColor(VC.ink3))
            .padding(.horizontal, 2).padding(.top, 4).padding(.bottom, 14)
    }

    private var addForm: some View {
        DashedBox {
            SmallField(text: $name, placeholder: "Inspector name", kind: .personName, fieldID: "name", errors: errors, required: true)
            SmallField(text: $email, placeholder: "inspector@email.com", keyboard: .emailAddress, kind: .email, fieldID: "email", errors: errors, required: true)
            Button {
                addInspector()
            } label: { IconLabel("Add inspector", icon: "hdr-add") }
                .buttonStyle(VButtonStyle(kind: .primary, minHeight: 46))
        }
    }

    private func addInspector() {
        let team = Set(store.company.inspectors.map { $0.email.lowercased() })
        guard errors.validate([
            ("name", name, .req(.personName, "Inspector name")),
            ("email", email, .req(.email, "Email", custom: { team.contains($0.lowercased()) ? "That email is already on the team" : nil }))
        ]) else { return }
        if store.addInspector(name: Validator.trimmed(name), email: Validator.trimmed(email).lowercased()) { name = ""; email = "" }
    }
}

/// "Make owner" on an inspector row → "Make <name> the owner?" (anchored to the pill on iPad).
private struct MakeOwnerButton: View {
    @Environment(AppStore.self) private var store
    let inspector: Inspector
    @State private var confirm = false

    var body: some View {
        Button { confirm = true } label: {
            Pill(kind: .new, text: "Make owner", dot: false).frame(minHeight: 32)
        }
        .buttonStyle(ChipPressStyle())
        .accessibilityLabel("Make \(inspector.name) the owner")
        .alert("Make \(inspector.name) the owner?", isPresented: $confirm) {
            Button("Make owner") { store.makeOwner(inspector.id) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You\u{2019}ll stay an admin. Only the new owner can transfer ownership again.") }
    }
}

// MARK: - 26 Plans (App Store in-app purchases, shared v1.18.0 `subscription.store.plansScreen`)

/// One purchasable option on the plans screen.
enum StorePlanOption: Hashable, CaseIterable {
    case monthly, yearly, credit

    @MainActor func product(_ p: StoreKitSubscriptionService) -> Product? {
        switch self {
        case .monthly: return p.monthly
        case .yearly: return p.yearly
        case .credit: return p.reportCredit
        }
    }
    var fallbackTitle: String {
        switch self {
        case .monthly: return "App only, monthly"
        case .yearly: return "App only, yearly"
        case .credit: return "Report credit"
        }
    }
    var length: String {
        switch self {
        case .monthly: return "1 month · renews automatically"
        case .yearly: return "1 year · renews automatically"
        case .credit: return "One inspection report · no subscription"
        }
    }
    var unit: String {
        switch self {
        case .monthly: return "/mo"
        case .yearly: return "/yr"
        case .credit: return "/report"
        }
    }
    /// The store's price: "$34.99/mo".
    @MainActor func priceLabel(_ p: StoreKitSubscriptionService) -> String? { product(p).map { $0.displayPrice + unit } }
}

struct SubscribeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var choice: StorePlanOption?
    @State private var busy = false
    @State private var restoring = false
    /// A pending purchase: not an error.
    @State private var notice: String?
    @State private var failure: String?

    private var purchases: StoreKitSubscriptionService { store.purchases }
    private var currentOption: StorePlanOption? {
        guard store.hasStoreSubscription else { return nil }
        return purchases.status.productID == purchases.ids?.yearly ? .yearly : .monthly
    }
    /// Defaults to the first option that isn't the current plan.
    private var chosen: StorePlanOption? {
        if let choice, choice.product(purchases) != nil, choice != currentOption { return choice }
        return StorePlanOption.allCases.first { $0 != currentOption && $0.product(purchases) != nil }
    }

    var body: some View {
        Screen(title: "Subscription", actions: [store.homeAction()]) {
            statusBanner
            switch purchases.productsState {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading plans…").font(VFont.ui(13.5)).foregroundStyle(VC.ink3)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            case .unavailable:
                loadFailed
            case .loaded:
                plans
            }
            portal
            footer
        }
        .task {
            await purchases.loadProducts()
            await purchases.refresh()
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if let text = PlanStatusText.banner(store) {
            Banner(symbol: "free-trial-days", tint: VC.brandDeep, background: VC.brand.opacity(0.08), border: Color(hex: 0xC9DEE6), textColor: VC.brandDeep,
                   text: md(text))
                .padding(.bottom, 14)
        }
    }

    private var loadFailed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plans can\u{2019}t load right now. Check your connection and try again.")
                .font(VFont.ui(14)).foregroundStyle(VC.ink2).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { Task { await purchases.loadProducts(); await purchases.refresh() } }
                .buttonStyle(.vPrimary)
        }
        .vCard()
    }

    @ViewBuilder private var plans: some View {
        let hasSub = StorePlanOption.monthly.product(purchases) != nil || StorePlanOption.yearly.product(purchases) != nil
        if hasSub {
            SectionLabel(text: planName("app", "App only"), top: 2)
            ForEach([StorePlanOption.monthly, .yearly].filter { $0.product(purchases) != nil }, id: \.self) { optionRow($0) }
        }
        if purchases.reportCredit != nil {
            SectionLabel(text: planName("payg", "Pay per report"), top: hasSub ? 10 : 2)
            optionRow(.credit)
        }
        if let chosen {
            Text(disclosure).font(VFont.ui(12)).foregroundStyle(VC.ink3).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2).padding(.top, 4)
            if let failure { FieldError(text: failure).padding(.top, 10) }
            if let notice {
                Text(notice).font(VFont.ui(12.5)).foregroundStyle(VC.brandDeep)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
            Button { buy(chosen) } label: {
                if busy { ProgressView().tint(.white) } else { IconLabel(ctaTitle(chosen), icon: "link-my-account") }
            }
            .buttonStyle(.vPrimary)
            .disabled(busy)
            .padding(.top, 14)
        }
    }

    /// Spec text, Apple Account on iOS.
    private var disclosure: String {
        "Payment is charged to your Apple Account. Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel in your account settings."
    }

    private func planName(_ id: String, _ fallback: String) -> String {
        store.config.subscription.plans.first { $0.id == id }?.name ?? fallback
    }

    private func ctaTitle(_ option: StorePlanOption) -> String {
        switch option {
        case .credit: return "Buy report credit"
        case .monthly: return currentOption == nil ? "Subscribe" : "Switch to monthly"
        case .yearly: return currentOption == nil ? "Subscribe" : "Switch to yearly"
        }
    }

    private func optionRow(_ option: StorePlanOption) -> some View {
        let isCurrent = option == currentOption
        let on = chosen == option
        return Button { choice = option; failure = nil; notice = nil } label: {
            HStack(spacing: 13) {
                Circle().stroke(on ? VC.brand : VC.line, lineWidth: 2).frame(width: 22, height: 22)
                    .overlay(Circle().fill(on ? VC.brand : .clear).frame(width: 11, height: 11))
                    .opacity(isCurrent ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.product(purchases)?.displayName ?? option.fallbackTitle).font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(option.length).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if isCurrent { Pill(kind: .done, text: "Current plan").padding(.top, 3) }
                    if option == .credit, purchases.credits > 0 {
                        Text(creditsLine).font(VFont.ui(12.5, .semibold)).foregroundStyle(VC.brandDeep).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(option.priceLabel(purchases) ?? "").font(VFont.mono(15, .semibold)).foregroundStyle(VC.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? VC.brand : VC.line, lineWidth: 1.5))
            .shadow(color: on ? VC.brand.opacity(0.13) : .clear, radius: 3)
        }
        .buttonStyle(ChipPressStyle())
        .disabled(isCurrent)
        .padding(.bottom, 10)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var creditsLine: String {
        "You have \(purchases.credits) report credit\(purchases.credits == 1 ? "" : "s") on this device."
    }

    /// Portal + App stays Coming soon and can't be bought.
    @ViewBuilder private var portal: some View {
        if let p = store.config.subscription.plans.first(where: \.isComingSoon) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(p.name).font(VFont.ui(15, .bold)).foregroundStyle(VC.ink2)
                    Pill(kind: .queued, text: "Coming soon", dot: false)
                }
                Text(p.desc).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Not available yet \u{2014} you can\u{2019}t choose this plan until it launches.")
                    .font(VFont.ui(11.5)).foregroundStyle(VC.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(VC.paper2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .padding(.top, 16)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button { restore() } label: {
                if restoring { ProgressView() } else { Text("Restore Purchases") }
            }
            .buttonStyle(.vGhost)
            .disabled(restoring)
            Button("Manage subscription") { Task { await purchases.showManageSubscriptions() } }
                .buttonStyle(.vGhost)
            StoreLegalLinks()
        }
        .padding(.top, 16)
    }

    private func buy(_ option: StorePlanOption) {
        guard let product = option.product(purchases) else { return }
        busy = true; failure = nil; notice = nil
        Task {
            let outcome = await purchases.purchase(product)
            busy = false
            switch outcome {
            case .purchased:
                if option == .credit {
                    store.toast("Report credit added")
                    choice = nil
                } else {
                    store.push(.subscriptionStarted)
                }
            case .pending:
                notice = "Waiting for approval. It\u{2019}s added as soon as it\u{2019}s approved."
            case .cancelled:
                break
            case .failed(let message):
                failure = message
            }
        }
    }

    private func restore() {
        restoring = true; failure = nil; notice = nil
        Task {
            switch await purchases.restore() {
            case .restored: store.toast("Your subscription is restored")
            case .nothingFound: store.toast("No subscription to restore on this Apple Account")
            case .cancelled: break
            case .failed(let message): failure = message
            }
            restoring = false
        }
    }
}

/// License agreement (in-app) and Privacy Policy, required next to a subscription purchase.
struct StoreLegalLinks: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { eula; privacy }
            VStack(spacing: 0) { eula; privacy }
        }
        .frame(maxWidth: .infinity)
    }

    private var eula: some View {
        Button { store.push(.eula) } label: { linkText("License agreement") }.buttonStyle(.plain)
    }

    private var privacy: some View {
        Button {
            if let url = URL(string: "https://vimsinspect.com/privacy.html") { openURL(url) }
        } label: { linkText("Privacy Policy") }
        .buttonStyle(.plain)
    }

    private func linkText(_ t: String) -> some View {
        Text(t).font(VFont.ui(13, .medium)).foregroundStyle(VC.brandDeep).underline()
            .frame(minHeight: 44).contentShape(Rectangle())
    }
}

/// Wording shared by the plans screen, Plan & billing, Settings and the trial prompts.
@MainActor
enum PlanStatusText {
    static func optionName(_ store: AppStore, _ productID: String?) -> String {
        let p = store.purchases
        if productID == p.ids?.yearly { return "Yearly" }
        if productID == p.ids?.monthly { return "Monthly" }
        return ""
    }

    static func day(_ date: Date?) -> String {
        date.map { Fmt.date($0, "MMM d, yyyy").replacingOccurrences(of: " ", with: "\u{00A0}") } ?? ""
    }

    /// The plans screen's lead line.
    static func banner(_ store: AppStore) -> String? {
        let p = store.purchases, sub = store.subscription
        if store.hasStoreSubscription {
            if p.status.hasBillingIssue { return billingIssue }
            if p.isOfflineHold { return offlineHold }
            return nil
        }
        if store.isSubscriptionExempt {
            return "**\(AppStore.exemptLine).** VIMS master admin accounts don\u{2019}t need a free trial or a subscription."
        }
        if !sub.trialEnded {
            return "**Free trial \u{2014} \(sub.trialDaysLeft) days left.** Set up your subscription any time. Billing starts when you subscribe."
        }
        if p.status.lapsed {
            return "**Your subscription ended on \(day(p.status.expiresAt)).** Subscribe or buy a report credit to start new inspections \u{2014} your existing inspections and reports stay available."
        }
        return "**Your free trial has ended.** Subscribe or buy a report credit to start new inspections \u{2014} your existing inspections and reports stay available."
    }

    static let billingIssue = "**Apple couldn\u{2019}t renew your subscription.** Update your payment method in your account settings to keep it. Access continues for now."
    static let offlineHold = "**Can\u{2019}t reach the App Store right now.** Using your last known subscription status."
}

struct SubscriptionStartedView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let name = store.config.subscription.plans.first { $0.id == "app" }?.name ?? "App"
        Screen(title: "Subscription active", actions: [store.homeAction()]) {
            SuccessBlock(title: "Subscription active",
                         message: AttributedString("Your \(name) plan is active. It renews automatically through your Apple Account.")) {
                Button("View subscription") { store.path = [.settings, .billing] }.buttonStyle(.vPrimary)
                Button("Back to inspections") { store.goHome() }.buttonStyle(.vGhost)
            }
        }
    }
}

// MARK: - 27 Plan & billing

struct BillingView: View {
    @Environment(AppStore.self) private var store
    @State private var restoring = false
    @State private var failure: String?

    private var purchases: StoreKitSubscriptionService { store.purchases }

    var body: some View {
        let sub = store.subscription
        let status = purchases.status
        let subscribed = store.hasStoreSubscription
        Screen(title: "Subscription", actions: [store.homeAction()]) {
            if store.isSubscriptionExempt && !subscribed {
                // Client Oct 28: master admins have no trial or plan to show.
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStore.exemptLine).font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                    Text("VIMS master admin accounts don\u{2019}t need a free trial or a subscription, and can always start new inspections.")
                        .font(VFont.ui(13)).foregroundStyle(VC.ink3).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .vCard()
                .padding(.bottom, 12)
                if store.isAdmin { manageInspectors }
            } else {
                if subscribed, let text = PlanStatusText.banner(store) {
                    Banner(text: md(text)).padding(.bottom, 12)
                }
                VStack(spacing: 0) {
                    row("Status") { statusPill(subscribed: subscribed, sub: sub) }
                    if subscribed {
                        row("Plan") { boldText(planLine(status.productID)) }
                        row("Payment") { boldText("Apple Account") }
                        // Billing retry has no date to promise: the store retries until it gives up.
                        if status.state != .billingRetry {
                            row(status.state == .gracePeriod ? "Grace period until" : status.willAutoRenew ? "Renews" : "Active until") { boldText(PlanStatusText.day(status.expiresAt)) }
                        }
                        if let pending = status.pendingProductID, !PlanStatusText.optionName(store, pending).isEmpty {
                            row("Next plan") { boldText("\(PlanStatusText.optionName(store, pending)) on \(PlanStatusText.day(status.expiresAt))") }
                        }
                    } else if status.lapsed {
                        row(status.state == .revoked ? "Refunded" : "Ended") { boldText(PlanStatusText.day(status.expiresAt)) }
                    } else {
                        row(sub.trialEnded ? "Trial" : "Trial ends") { boldText(sub.trialEnded ? "Ended" : "in \(sub.trialDaysLeft) days") }
                    }
                    row("Report credits", last: true) { boldText("\(purchases.credits)") }
                }
                .background(VC.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
                .padding(.bottom, 12)
                if store.isAdmin { manageInspectors }
                Button(subscribed ? "Change plan" : "Set up subscription") { store.push(.subscribe) }
                    .buttonStyle(VButtonStyle(kind: subscribed ? .ghost : .primary))
                    .padding(.top, 10)
                Button("Manage subscription") { Task { await purchases.showManageSubscriptions() } }
                    .buttonStyle(.vGhost)
                    .padding(.top, 10)
                Button { restore() } label: {
                    if restoring { ProgressView() } else { Text("Restore Purchases") }
                }
                .buttonStyle(.vGhost)
                .disabled(restoring)
                .padding(.top, 10)
                if let failure { FieldError(text: failure).padding(.top, 8) }
                Text("Cancel in your Apple Account settings. Refunds follow Apple\u{2019}s rules.")
                    .font(VFont.ui(12)).foregroundStyle(VC.ink3).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2).padding(.top, 10)
            }
        }
        .task {
            await purchases.loadProducts()
            await purchases.refresh()
        }
    }

    private var manageInspectors: some View {
        Button { store.push(.inspectors) } label: { IconLabel("Manage inspectors", icon: "manage-inspectors-h") }
            .buttonStyle(.vGhost)
    }

    @ViewBuilder
    private func statusPill(subscribed: Bool, sub: SubscriptionState) -> some View {
        let status = purchases.status
        if subscribed {
            if status.hasBillingIssue { Pill(kind: .queued, text: "Payment issue") }
            else if status.willAutoRenew { Pill(kind: .done, text: "Active · renews automatically") }
            else { Pill(kind: .queued, text: "Canceled · active until \(PlanStatusText.day(status.expiresAt))") }
        } else if status.state == .revoked {
            Pill(kind: .queued, text: "Refunded")
        } else if status.lapsed {
            Pill(kind: .queued, text: "Ended")
        } else if sub.trialEnded {
            Pill(kind: .queued, text: "Trial ended")
        } else {
            Pill(kind: .queued, text: "Trial · \(sub.trialDaysLeft)d left")
        }
    }

    /// "App only · Monthly · $34.99/mo"; the price only when the store has answered.
    private func planLine(_ productID: String?) -> String {
        let name = store.config.subscription.plans.first { $0.id == "app" }?.name ?? "App only"
        let option: StorePlanOption = productID == purchases.ids?.yearly ? .yearly : .monthly
        return [name, PlanStatusText.optionName(store, productID), option.priceLabel(purchases)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func boldText(_ t: String) -> some View {
        Text(t).font(VFont.ui(14, .bold)).foregroundStyle(VC.ink).multilineTextAlignment(.trailing)
    }

    private func restore() {
        restoring = true; failure = nil
        Task {
            switch await purchases.restore() {
            case .restored: store.toast("Your subscription is restored")
            case .nothingFound: store.toast("No subscription to restore on this Apple Account")
            case .cancelled: break
            case .failed(let message): failure = message
            }
            restoring = false
        }
    }

    private func row<V: View>(_ label: String, last: Bool = false, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label).font(VFont.ui(14)).foregroundStyle(VC.ink2)
            Spacer()
            value()
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(VC.line2).frame(height: 1) } }
    }
}

// MARK: - Master admin code (shared v1.18 `support.ownerCode`)

struct OwnerCodeView: View {
    @Environment(AppStore.self) private var store
    @State private var code = ""
    @State private var errors = FormErrors()
    @State private var busy = false

    var body: some View {
        Screen(title: "Master admin code", actions: [store.homeAction()], errors: errors) {
            HintText(text: "Enter the master admin code once on this device to turn on the VIMS master admin screens and free access for this account.")
                .padding(.top, 2).padding(.bottom, 14)
            VTextField(label: "Master admin code", text: $code, capitalization: .characters, mono: true,
                       fieldID: "ownerCode", errors: errors, required: true)
            Button { submit() } label: {
                if busy { ProgressView().tint(.white) } else { IconLabel("Confirm code", icon: "link-my-account") }
            }
            .buttonStyle(.vPrimary)
            .disabled(busy)
        }
    }

    private func submit() {
        guard !busy else { return }
        guard !OwnerCode.normalized(code).isEmpty else { errors.set("ownerCode", "That code isn\u{2019}t right."); return }
        busy = true
        errors.clear()
        Task {
            switch await store.verifyOwnerCode(code) {
            case .verified:
                code = ""
                store.back()
                store.toast("Master admin access is on")
            case .wrong:
                errors.set("ownerCode", "That code isn\u{2019}t right.")
            case .notSaved:
                errors.set("ownerCode", "That code is right, but it couldn\u{2019}t be saved on this device. Try again.")
            }
            busy = false
        }
    }
}

/// Plans & pricing with `features.planEditing` off: read-only, at store prices.
private struct StorePricesView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Screen(title: "Plans & pricing", subtitle: "Master admin", actions: [store.homeAction()]) {
            Text("Prices are set in App Store Connect and Google Play Console.")
                .font(VFont.ui(13)).foregroundStyle(VC.ink3).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2).padding(.bottom, 12)
            ForEach(store.config.subscription.plans, id: \.id) { p in planCard(p) }
        }
        .task { await store.purchases.loadProducts() }
    }

    private func planCard(_ p: PlanDef) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(p.name).font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink)
                if p.isComingSoon { Pill(kind: .queued, text: "Coming soon", dot: false) }
            }
            if !p.isComingSoon {
                if p.isPerReport {
                    priceRow("Per report", .credit, reference: SubscriptionState.priceLabel(p, .monthly))
                } else {
                    priceRow("Monthly", .monthly, reference: SubscriptionState.priceLabel(p, .monthly))
                    priceRow("Yearly", .yearly, reference: SubscriptionState.priceLabel(p, .yearly))
                }
            }
        }
        .vCard(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14), radius: 13)
        .padding(.bottom, 11)
    }

    /// The store price; the JSON's reference price, labeled, only while no store price is available.
    private func priceRow(_ label: String, _ option: StorePlanOption, reference: String) -> some View {
        HStack {
            Text(label).font(VFont.ui(13.5)).foregroundStyle(VC.ink2)
            Spacer()
            if let live = option.priceLabel(store.purchases) {
                Text(live).font(VFont.mono(14, .semibold)).foregroundStyle(VC.ink)
            } else {
                Text("\(reference) (reference)").font(VFont.mono(12.5)).foregroundStyle(VC.ink3)
            }
        }
    }
}
