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

    var body: some View {
        Screen(title: "Manage checklist", actions: [store.homeAction()], errors: errors) {
            HintText(text: "Add and edit checklist sections and items yourself — changes apply to new inspections.")
                .padding(.top, 2).padding(.bottom, 12)
            restoreAllCard
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
        .alert("Restore the entire checklist to the original?", isPresented: $confirmRestoreAll) {
            Button("Restore entire checklist", role: .destructive) { store.restoreEntireChecklist() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ChecklistRestoreText.all(edited: store.editedSectionCount, custom: store.customSectionCount))
        }
        .onAppear {
            #if DEBUG
            // -confirmRestore SECTION|all: open the restore confirmation (review screenshots).
            if let r = DebugLaunch.value("-confirmRestore") { if r == "all" { confirmRestoreAll = true } else { restoring = r } }
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

    /// "Restore entire checklist to original" (client Oct 28): what the company changed, and the button.
    @ViewBuilder private var restoreAllCard: some View {
        let edited = store.editedSectionCount, custom = store.customSectionCount
        VStack(alignment: .leading, spacing: 10) {
            Text(store.hasChecklistEdits ? "Your checklist has changes" : "Your checklist is the VIMS original")
                .font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
            Text(store.hasChecklistEdits
                 ? ChecklistRestoreText.summary(edited: edited, custom: custom) + " Sections you changed are tagged Edited below."
                 : "Edit a section or add your own; you can restore the original at any time.")
                .font(VFont.ui(12.5)).foregroundStyle(VC.ink3).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if store.hasChecklistEdits {
                Button { confirmRestoreAll = true } label: { Text("Restore entire checklist to original") }
                    .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 46))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
        .padding(.bottom, 12)
    }

    private func icon(_ g: String) -> String {
        switch g {
        case "Testing": return "flask"
        case "Utility": return "bolt"
        case "Interior": return "sofa"
        case "Phase Inspections": return "layers"
        case "State & Insurance Forms": return "file"
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
                            if store.isCustomSection(n) { Pill(kind: .prog, text: "Custom", dot: false) }
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
                                 delete: { items.removeAll { $0.id == e.id } })
                }
                Button {
                    items.append(EditItem(item: .question("New item", options: ["Yes", "No", "N/A"])))
                } label: { IconLabel("Add item", icon: "hdr-add") }
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
    @State private var newOption = ""
    @State private var focused = false
    @State private var confirmDelete = false

    /// "“Number of kitchens” and its options will be removed from new inspections."
    private var deleteMessage: String {
        let raw = Validator.trimmed(edit.item.header ?? edit.item.q ?? "")
        let name = raw.isEmpty ? (edit.item.isHeader ? "This header" : "This item") : "\u{201C}\(raw)\u{201D}"
        let hasOptions = !edit.item.isHeader && !(edit.item.options ?? []).isEmpty && [.single, .multi].contains(edit.item.kind)
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
            if !edit.item.isHeader {
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
            if wide.isWide {
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
            Text("They'll lose access to \(store.company.name)'s checklist, plans and profile. Their own inspections stay on their device.")
        }
        .onAppear {
            if DebugFlags.validate { DebugFlags.validate = false; name = ""; email = store.company.inspectors.first?.email ?? "x@y.com"; addInspector() }
        }
    }

    private var intro: some View {
        Text(md("Add inspector accounts under your company license. First inspector is included; each additional is **\(Fmt.money(store.subscription.extraRate(store.subscription.period)))\(store.subscription.period.unit)**."))
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
        Text(md("You (the account owner) are an **admin** by default. Tap **Make admin** to grant any inspector admin access — admins can manage checklists, plans, the company profile, and settings. Nothing is hard-coded; roles are set here."))
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
                        // Admins who aren't the owner can't take ownership back (security); say so on the owner's row.
                        if ins.owner, ins.id != store.myInspectorID {
                            Text("Only the owner can transfer ownership.")
                                .font(VFont.ui(12)).foregroundStyle(VC.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if ins.owner {
                        Pill(kind: .done, text: "Owner")
                    } else if ins.id == store.myInspectorID {
                        // Your own row: no Make admin / Remove / Make owner (same as Android).
                        if ins.admin { Pill(kind: .prog, text: "Admin", dot: false) }
                    } else {
                        VStack(alignment: .trailing, spacing: 6) {
                            Button { store.toggleAdmin(ins.id) } label: {
                                Pill(kind: ins.admin ? .prog : .new, text: ins.admin ? "Admin ✓" : "Make admin", dot: false)
                                    .frame(minHeight: 32)
                            }
                            .buttonStyle(ChipPressStyle())
                            // Only the current owner can hand over ownership — to anyone on the team with an email
                            // (including the previous owner), after confirming. The new owner becomes an admin too.
                            if store.isCompanyOwner && !ins.email.isEmpty {
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

// MARK: - 26 Subscribe (Square)

struct SubscribeView: View {
    @Environment(AppStore.self) private var store
    @State private var card = ""
    @State private var expiry = ""
    @State private var cvc = ""
    @State private var holder = ""
    @State private var zip = ""
    @State private var errors = FormErrors()
    @State private var busy = false
    /// QA Oct 14: with a remembered card, "Use this card" (default) or "Use a different card" (shows the card form).
    @State private var useDifferentCard = false
    /// Client Oct 28: the plan and Monthly / Yearly period picked here; saved on Start / Update subscription.
    @State private var planID: String?
    @State private var periodChoice: BillingPeriod?

    private var chosenPlan: PlanDef? {
        let sub = store.subscription
        if let id = planID, let p = sub.plan(id), p.isSelectable { return p }
        if let p = sub.plan(sub.selectedPlan), p.isSelectable { return p }
        return sub.plans.first(where: \.isSelectable)
    }
    /// The period in effect for the chosen plan (a plan without a yearly price is monthly).
    private var period: BillingPeriod {
        guard chosenPlan?.hasYearly == true else { return .monthly }
        return periodChoice ?? BillingPeriod(rawValue: store.subscription.billingPeriod ?? "") ?? .monthly
    }

    private var brand: CardBrand { CardBrand.detect(card.filter(\.isNumber)) }
    /// The usable card on file (an expired one isn't offered).
    private var savedCard: CardOnFile? {
        guard let c = store.subscription.cardOnFile, !c.isExpired() else { return nil }
        return c
    }
    private var usingSavedCard: Bool { savedCard != nil && !useDifferentCard }

    var body: some View {
        let sub = store.subscription
        Screen(title: "Subscription", actions: [store.homeAction()], errors: errors) {
            if !sub.active {
                Banner(symbol: "free-trial-days", tint: VC.brandDeep, background: VC.brand.opacity(0.08), border: Color(hex: 0xC9DEE6), textColor: VC.brandDeep,
                       text: md(sub.trialEnded
                                ? "**Your free trial has ended.** Subscribe to start new inspections — your existing inspections and reports stay available."
                                : "**Free trial — \(sub.trialDaysLeft) days left.** Set up your subscription now so access continues automatically when the trial ends."))
                    .padding(.bottom, 14)
            }
            SectionLabel(text: "Choose your plan", top: 2)
            if sub.plans.contains(where: \.hasYearly) { periodPicker }
            ForEach(sub.plans, id: \.id) { p in planRow(p) }
            SectionLabel(text: "Inspector seats")
            // Seats never go below the current team (people with an email); − only removes open seats added with +.
            let teamSize = max(1, store.company.inspectors.filter { !$0.email.isEmpty || $0.owner }.count)
            CounterRow(label: "Inspectors on this license", value: Binding(
                get: { store.seats() },
                set: { v in
                    let cur = store.company.inspectors.count
                    if v > cur { store.state.company.inspectors.append(Inspector(name: "Inspector \(cur + 1)", email: "")) }
                    else if v < cur, let last = store.company.inspectors.last(where: { !$0.owner && $0.email.isEmpty }) { store.removeInspector(last.id) }
                }), range: min(teamSize, StepperLimits.seats.upperBound)...StepperLimits.seats.upperBound)
            Text(md(chosenPlan?.isPerReport == true
                    ? "Pay per report has no inspector fee — each report is **\(Fmt.money(chosenPlan?.price ?? 0))**."
                    : "First inspector included · each additional **\(Fmt.money(sub.extraRate(period)))\(period.unit)** (billed \(period.label.lowercased()))"))
                .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.horizontal, 2).padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(chosenPlan?.isPerReport == true ? "Billing" : period.totalLabel).font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                Spacer()
                Text(sub.totalLabel(plan: chosenPlan, period: period, seats: store.seats())).font(VFont.mono(22, .semibold)).foregroundStyle(VC.brand)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .vCard()
            .padding(.top, 14)

            SectionLabel(text: "Payment — via Square")
                .overlay(alignment: .bottomTrailing) { if !usingSavedCard { RequiredHint().fixedSize().padding(.bottom, 4) } }
            if let saved = savedCard {
                cardChoice(saved)
            }
            if !usingSavedCard {
                cardForm
            }
            HStack(spacing: 8) {
                ProtoIcon("secured-by-square", size: 14)
                Text(chosenPlan?.isPerReport == true ? "Secured by Square · billed per report · cancel anytime"
                     : "Secured by Square · auto-renews \(period.label.lowercased()) · cancel anytime").font(VFont.ui(12))
            }
            .foregroundStyle(VC.ink3).padding(.horizontal, 2).padding(.top, 8)
            Button { start() } label: {
                if busy { ProgressView().tint(.white) } else { IconLabel(sub.active ? "Update subscription" : "Start subscription", icon: "link-my-account") }
            }
            .buttonStyle(.vPrimary).padding(.top, 16)
            .disabled(busy)
        }
        .onAppear {
            #if DEBUG
            if let v = DebugLaunch.value("-period") { periodChoice = BillingPeriod(rawValue: v) }
            if let v = DebugLaunch.value("-plan") { planID = v }
            #endif
            if DebugFlags.validate { DebugFlags.validate = false; useDifferentCard = true; card = FieldKind.cardNumber.filter("4242424242424241"); expiry = "01/24"; cvc = "12"; start() }
        }
    }

    /// Monthly / Yearly (client Oct 28). Plans without a yearly price (Pay per report) are monthly / per report only.
    private var periodPicker: some View {
        let yearlyOK = chosenPlan?.hasYearly == true
        return VStack(alignment: .leading, spacing: 6) {
            Picker("Billing period", selection: Binding(get: { period }, set: { periodChoice = $0 })) {
                ForEach(BillingPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!yearlyOK)
            if !yearlyOK, let p = chosenPlan {
                Text("\(p.name) has no yearly option.").font(VFont.ui(12)).foregroundStyle(VC.ink3)
            }
        }
        .padding(.bottom, 12)
    }

    private func planRow(_ p: PlanDef) -> some View {
        let on = chosenPlan?.id == p.id
        let soon = p.isComingSoon
        return Button { planID = p.id } label: {
            HStack(spacing: 13) {
                Circle().stroke(on ? VC.brand : VC.line, lineWidth: 2).frame(width: 22, height: 22)
                    .overlay(Circle().fill(on ? VC.brand : .clear).frame(width: 11, height: 11))
                    .opacity(soon ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(p.name).font(VFont.ui(15, .bold)).foregroundStyle(soon ? VC.ink2 : VC.ink)
                        if soon { Pill(kind: .queued, text: "Coming soon", dot: false) }
                    }
                    Text(p.desc).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if soon {
                        Text("Not available yet — you can\u{2019}t choose this plan until it launches.")
                            .font(VFont.ui(11.5)).foregroundStyle(VC.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    priceText(p, p.hasYearly ? period : .monthly, big: true)
                    if p.hasYearly { Text("or \(SubscriptionState.priceLabel(p, period == .yearly ? .monthly : .yearly))").font(VFont.mono(10.5)).foregroundStyle(VC.ink3) }
                }
                .opacity(soon ? 0.6 : 1)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(soon ? VC.paper2 : VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(on ? VC.brand : VC.line, style: StrokeStyle(lineWidth: 1.5, dash: soon ? [5, 4] : [])))
            .shadow(color: on ? VC.brand.opacity(0.13) : .clear, radius: 3)
        }
        .buttonStyle(ChipPressStyle())
        .disabled(soon)
        .padding(.bottom, 10)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(soon ? "Coming soon. Not available yet." : "")
    }

    private func priceText(_ p: PlanDef, _ per: BillingPeriod, big: Bool) -> Text {
        let unit = p.isPerReport ? (p.unit ?? "/report") : per.unit
        return Text(Fmt.money(SubscriptionState.price(p, per))).font(VFont.mono(15, .semibold)).foregroundColor(VC.ink)
            + Text(unit).font(VFont.mono(11)).foregroundColor(VC.ink3)
    }

    /// "Visa •••• 4242 (exp 08/28)" with Use this card / Use a different card.
    private func cardChoice(_ saved: CardOnFile) -> some View {
        VStack(spacing: 0) {
            radioRow(title: "Use this card", detail: saved.display, on: !useDifferentCard) { useDifferentCard = false }
            Rectangle().fill(VC.line2).frame(height: 1)
            radioRow(title: "Use a different card", detail: nil, on: useDifferentCard) { useDifferentCard = true }
        }
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 13)
    }

    private func radioRow(title: String, detail: String?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Circle().stroke(on ? VC.brand : VC.line, lineWidth: 2).frame(width: 22, height: 22)
                    .overlay(Circle().fill(on ? VC.brand : .clear).frame(width: 11, height: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                    if let detail { Text(detail).font(VFont.mono(13, .medium)).foregroundStyle(VC.ink2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChipPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var cardForm: some View {
            // Placeholder card form until Square's In-App Payments SDK card entry replaces it (TODO(backend)).
            VTextField(label: "Card number", text: $card, placeholder: "1234 5678 9012 3456",
                       keyboard: .numberPad, contentType: .creditCardNumber, capitalization: .never,
                       kind: .cardNumber, fieldID: "card", errors: errors, trailing: brand.rawValue, required: true)
            HStack(alignment: .top, spacing: 10) {
                VTextField(label: "Expiry", text: $expiry, placeholder: "MM/YY",
                           keyboard: .numberPad, contentType: .creditCardExpiration, capitalization: .never, bottom: 0,
                           kind: .expiry, fieldID: "expiry", errors: errors, required: true)
                VTextField(label: "CVC", text: $cvc, placeholder: brand == .amex ? "1234" : "123",
                           keyboard: .numberPad, contentType: .creditCardSecurityCode, capitalization: .never, bottom: 0,
                           kind: .cvc(amex: brand == .amex), fieldID: "cvc", errors: errors, required: true)
            }
            .padding(.bottom, 13)
            VTextField(label: "Cardholder name", text: $holder, placeholder: "Name on card", contentType: .name, capitalization: .words,
                       kind: .personName, fieldID: "holder", errors: errors, required: true)
            // US ZIP or a Canadian / UK postal code: letters, digits, space and "-", uppercased, 3–10 characters.
            VTextField(label: "Billing ZIP / postal code", text: $zip, placeholder: "84015", keyboard: .default, contentType: .postalCode,
                       capitalization: .characters, bottom: 0, kind: .zip, fieldID: "zip", errors: errors, required: true)
    }

    private func start() {
        if usingSavedCard, let saved = savedCard {
            errors.clear()
            run(.cardOnFile(saved))
            return
        }
        let amex = brand == .amex
        let fields: [(id: String, value: String, rule: FieldRule)] = [
            ("card", card, .req(.cardNumber, "Card number")),
            ("expiry", expiry, .req(.expiry, "Expiry")),
            ("cvc", cvc, .req(.cvc(amex: amex), "CVC")),
            ("holder", holder, .req(.personName, "Cardholder name")),
            ("zip", zip, .req(.zip, "Billing ZIP / postal code"))
        ]
        guard errors.validate(fields) else { return }
        run(.newCard(CardEntry(number: card, expiry: expiry, cvc: cvc, name: holder, zip: zip)))
    }

    private func run(_ payment: SubscriptionPayment) {
        busy = true
        Task {
            do {
                guard let plan = chosenPlan else { throw ServiceError.invalid("Choose a plan") }
                try await store.startSubscription(planID: plan.id, period: period, payment: payment)
                card = ""; expiry = ""; cvc = ""; holder = ""; zip = ""
                useDifferentCard = false
                store.push(.subscriptionStarted)
            } catch {
                errors.set("card", error.localizedDescription)
            }
            busy = false
        }
    }
}

struct SubscriptionStartedView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let sub = store.subscription
        let p = sub.plan(sub.selectedPlan)
        let plan = p?.name ?? "App"
        // Client Oct 28: the confirmation shows the period chosen ("billed yearly · $935.00/yr").
        let billed = p?.isPerReport == true ? "billed per report · \(sub.totalLabel(seats: store.seats()))"
            : "billed \(sub.period.label.lowercased()) · \(sub.totalLabel(seats: store.seats()))"
        Screen(title: "Subscription active", actions: [store.homeAction()]) {
            SuccessBlock(title: "Subscription active",
                         message: AttributedString("Your \(plan) plan (\(billed)) is set up with auto-pay through Square. Access continues after your trial with no interruption.")) {
                Button("View subscription") { store.path = [.settings, .billing] }.buttonStyle(.vPrimary)
                Button("Back to inspections") { store.goHome() }.buttonStyle(.vGhost)
            }
        }
    }
}

// MARK: - 27 Plan & billing

struct BillingView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmCancel = false
    @State private var busy = false

    var body: some View {
        let sub = store.subscription
        let plan = sub.plan(sub.selectedPlan)
        let seats = store.seats()
        let periodEnd = Fmt.date(sub.nextBillingDate, "MMM d, yyyy").replacingOccurrences(of: " ", with: "\u{00A0}")  // keep the date on one line
        Screen(title: "Subscription", actions: [store.homeAction()]) {
            VStack(spacing: 0) {
                row("Status") {
                    if sub.cancelled { Pill(kind: .queued, text: "Cancelled · active until \(periodEnd)") }
                    else if sub.active { Pill(kind: .done, text: "Active · auto-pay") }
                    else if sub.trialEnded { Pill(kind: .queued, text: "Trial ended") }
                    else { Pill(kind: .queued, text: "Trial · \(sub.trialDaysLeft)d left") }
                }
                row("Plan") { Text("\(plan?.name ?? "") · \(plan.map { SubscriptionState.priceLabel($0, sub.period) } ?? "")").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                    .multilineTextAlignment(.trailing) }
                if plan?.perReport != true {
                    // Client Oct 28: monthly or yearly; extra inspectors follow the company's period.
                    row("Billing period") { Text(sub.period.label).font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                    row("Inspectors") { Text("\(seats) (\(max(0, seats - 1)) × \(Fmt.money(sub.extraRate(sub.period)))\(sub.period.unit))").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                }
                row(plan?.perReport == true ? "Billing" : sub.period.totalLabel) { Text(sub.totalLabel(seats: seats)).font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                row("Payment") { Text(sub.active ? (sub.cardOnFile?.display ?? sub.paymentLabel ?? "Square") : "Not set up").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                row(sub.cancelled ? "Active until" : sub.active ? "Next billing" : sub.trialEnded ? "Trial" : "Trial ends", last: true) {
                    Text(sub.active ? periodEnd : sub.trialEnded ? "Ended" : "in \(sub.trialDaysLeft) days").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                }
            }
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
            .padding(.bottom, 12)
            Button { store.push(.inspectors) } label: { IconLabel("Manage inspectors", icon: "manage-inspectors-h") }
                .buttonStyle(.vGhost)
            Button(sub.active ? "Change plan / payment" : "Set up subscription") { store.push(.subscribe) }
                .buttonStyle(VButtonStyle(kind: sub.active ? .ghost : .primary))
                .padding(.top, 10)

            // EULA 12.3 — cancel at the end of the billing period. Owner/admin only; not shown during the trial.
            if sub.active && store.isAdmin {
                if sub.cancelled {
                    Text("Your subscription is cancelled and stays active until \(Text(periodEnd).font(VFont.ui(13, .bold)).foregroundStyle(VC.ink)). Download anything you need within 30 days after it ends.")
                        .font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .vCard()
                        .padding(.top, 14)
                    Button { run { try await store.resumeSubscription() } } label: { busyLabel("Undo cancellation", tint: VC.ink) }
                        .buttonStyle(.vGhost)
                        .disabled(busy)
                        .padding(.top, 10)
                } else if confirmCancel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cancel your subscription?").font(VFont.ui(13, .bold)).foregroundStyle(VC.ink)
                        Text("It stays active until the end of the current billing period (\(Text(periodEnd).font(VFont.ui(13, .bold)))), then stops renewing. There are no refunds or prorated charges. Download anything you need within 30 days after it ends.")
                            .font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
                    .background(VC.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.c1, lineWidth: 1))
                    .padding(.top, 14)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { keepButton; yesCancelButton }
                        VStack(spacing: 10) { yesCancelButton; keepButton }
                    }
                    .padding(.top, 10)
                } else {
                    Button("Cancel subscription") { withAnimation(.easeOut(duration: 0.2)) { confirmCancel = true } }
                        .buttonStyle(VButtonStyle(kind: .ghost, tint: VC.c1))
                        .padding(.top, 10)
                }
            }
        }
    }

    private var keepButton: some View {
        Button("Keep subscription") { withAnimation(.easeOut(duration: 0.2)) { confirmCancel = false } }
            .buttonStyle(.vGhost)
    }

    private var yesCancelButton: some View {
        Button { run { try await store.cancelSubscription() } } label: { busyLabel("Yes, cancel", tint: .white) }
            .buttonStyle(VButtonStyle(kind: .danger))
            .disabled(busy)
    }

    @ViewBuilder
    private func busyLabel(_ title: String, tint: Color) -> some View {
        if busy { ProgressView().tint(tint) } else { Text(title) }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await op() } catch { store.toast(error.localizedDescription) }
            confirmCancel = false
            busy = false
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
