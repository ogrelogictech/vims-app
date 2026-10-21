import SwiftUI

// MARK: - 23 Manage checklist (admin)

struct ManageChecklistView: View {
    @Environment(AppStore.self) private var store
    @State private var newName = ""
    @State private var newGroup: String? = ChecklistCatalog.customGroups.first
    @State private var open: Set<String> = ["Exterior"]
    @State private var errors = FormErrors()

    var body: some View {
        Screen(title: "Manage checklist", actions: [store.homeAction()], errors: errors) {
            HintText(text: "Add and edit checklist sections and items yourself — changes apply to new inspections.")
                .padding(.top, 2).padding(.bottom, 12)
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
        .onAppear {
            if let g = DebugFlags.adminGroup { open = [g]; DebugFlags.adminGroup = nil }
            if DebugFlags.validate {
                DebugFlags.validate = false; newName = "Roof"
                let taken = Set(store.catalog.adminGroups().flatMap(\.sections).map { $0.lowercased() })
                errors.validate([("section", newName, .req(.sectionName, "Section name",
                    custom: { taken.contains($0.lowercased()) ? "A section with that name already exists" : nil }))])
            }
        }
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
                            Text(store.catalog.isPhotosOnly(n) ? "photos only" : "\(count) items").font(VFont.mono(10.5, .semibold)).foregroundStyle(VC.ink2)
                            Chevron()
                        }
                        .padding(.leading, 18).padding(.trailing, 15).padding(.vertical, 12).frame(minHeight: 44)
                        .overlay(alignment: .bottom) { Rectangle().fill(VC.line2).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 10)
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
    @State private var errors = FormErrors()

    var body: some View {
        Screen(title: store.catalog.title(sectionName), subtitle: "Edit section", actions: [store.homeAction()], errors: errors) {
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
                if store.isCustomSection(sectionName) {
                    Button(role: .destructive) { confirmRemove = true } label: {
                        IconLabel("Remove this section", icon: "trash").foregroundStyle(VC.c1)
                    }
                    .buttonStyle(.vGhost)
                    .confirmationDialog("Remove “\(sectionName)”?", isPresented: $confirmRemove, titleVisibility: .visible) {
                        Button("Remove section", role: .destructive) {
                            store.removeCustomSection(sectionName)
                            store.back()
                        }
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
                        .confirmationDialog("Delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
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

// MARK: - 24 Plans & pricing (admin)

struct PlansAdminView: View {
    @Environment(AppStore.self) private var store
    @State private var prices: [String: String] = [:]
    /// QA Oct 14: plan descriptions are multi-line (edited on each card, wrapped on the Subscription screen).
    @State private var descs: [String: String] = [:]
    @State private var extra = ""
    @State private var newName = ""
    @State private var newPrice = ""
    @State private var newDesc = ""
    @State private var errors = FormErrors()

    var body: some View {
        Screen(title: "Plans & pricing", actions: [store.homeAction()], errors: errors) {
            HintText(text: "Owner admin — edit plan prices, add a plan, or set the per-inspector rate. Changes apply to the subscribe screen.")
                .padding(.top, 2).padding(.bottom, 12)
            ForEach(store.subscription.plans, id: \.id) { p in
                priceCard(id: "price-\(p.id)", title: p.name, unit: p.unit ?? "/mo",
                          desc: Binding(get: { descs[p.id] ?? p.desc }, set: { descs[p.id] = $0 }),
                          text: Binding(get: { prices[p.id] ?? Fmt.price(p.price) }, set: { prices[p.id] = $0 }),
                          deletable: PlanDelete(plan: p, isLast: store.subscription.plans.count <= 1,
                                                isCurrent: store.subscription.selectedPlan == p.id)) {
                    commit(p.id)
                }
            }
            priceCard(id: "extra", title: "Additional inspector", unit: "/mo each", desc: nil, text: $extra) {
                guard errors.validate([("extra", extra, .req(.price, "Rate"))]) else { return }
                let v = Validator.number(extra) ?? 0
                store.state.subscription.extraInspectorMonthly = v
                extra = Fmt.price(v)
                store.toast("Extra inspector → \(Fmt.money(v))")
            }
            DashedBox {
                SmallField(text: $newName, placeholder: "Plan name (e.g. Team)", kind: .plain(max: 40), fieldID: "newName", errors: errors, required: true)
                SmallField(text: $newPrice, placeholder: "Monthly price (e.g. 99.00)", keyboard: .decimalPad, kind: .price, fieldID: "newPrice", errors: errors, required: true)
                DescriptionBox(text: $newDesc, placeholder: "Short description (a few lines are fine)")
                Button { addPlan() } label: { IconLabel("Add plan", icon: "hdr-add") }
                    .buttonStyle(VButtonStyle(kind: .primary, minHeight: 46))
            }
        }
        .onAppear {
            extra = Fmt.price(store.subscription.extraInspectorMonthly)
            if DebugFlags.validate { DebugFlags.validate = false; newPrice = "0"; extra = "12000"; addPlan()
                errors.validate([("extra", extra, .req(.price, "Rate")), ("newName", newName, .req(.plain(max: 40), "Plan name")),
                                 ("newPrice", newPrice, .req(.price, "Price"))]) }
        }
    }

    /// A plan card's delete control ("Additional inspector" is a rate setting, so it has none).
    struct PlanDelete { let plan: PlanDef; let isLast: Bool; let isCurrent: Bool }

    private func priceCard(id: String, title: String, unit: String, desc: Binding<String>? = nil, text: Binding<String>,
                           deletable: PlanDelete? = nil, commit: @escaping () -> Void) -> some View {
        let err = errors[id]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(title).font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let deletable { PlanDeleteButton(info: deletable) }
            }
            HStack(spacing: 10) {
                FieldLabel(text: "Price $", required: true)
                FilteredTextField(text: text, kind: .price, fieldID: id, errors: errors, keyboard: .decimalPad,
                                  accessibilityLabel: "\(title) price")
                    .padding(.horizontal, 12).frame(width: 130, height: 48)
                    .background(VC.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(err != nil ? VC.c1 : VC.line, lineWidth: err != nil ? 2 : 1))
                    .onSubmit(commit)
                Text(unit).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                Spacer()
                Button("Save", action: commit)
                    .font(VFont.ui(13, .semibold)).foregroundStyle(VC.brandDeep)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(VC.paper3).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            if let err { FieldError(text: err) }
            if let desc { DescriptionBox(text: desc, placeholder: "Short description") }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 11)
        .id(id)
    }

    private func commit(_ id: String) {
        guard let i = store.state.subscription.plans.firstIndex(where: { $0.id == id }) else { return }
        let raw = prices[id] ?? Fmt.price(store.state.subscription.plans[i].price)
        guard errors.validate([("price-\(id)", raw, .req(.price, "Price"))]) else { return }
        let v = Validator.number(raw) ?? 0
        store.state.subscription.plans[i].price = v
        prices[id] = Fmt.price(v)
        if let d = descs[id] {
            let t = d.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { store.state.subscription.plans[i].desc = t }
            descs[id] = nil
        }
        store.toast("\(store.state.subscription.plans[i].name) → \(Fmt.money(v))")
    }

    private func addPlan() {
        let names = Set(store.subscription.plans.map { $0.name.lowercased() })
        guard errors.validate([
            ("newName", newName, .req(.plain(max: 40), "Plan name", custom: { names.contains($0.lowercased()) ? "A plan with that name already exists" : nil })),
            ("newPrice", newPrice, .req(.price, "Price"))
        ]) else { return }
        let n = Validator.trimmed(newName)
        let pr = Validator.number(newPrice) ?? 0
        let id = "plan\(store.state.subscription.plans.count + 1)-\(UUID().uuidString.prefix(4))"
        let d = newDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        store.state.subscription.plans.append(PlanDef(id: id, name: n, price: pr, desc: d.isEmpty ? "Custom plan" : d, unit: nil, perReport: nil))
        newName = ""; newPrice = ""; newDesc = ""
        store.toast("Added “\(n)”")
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
        .confirmationDialog("Delete this plan?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Delete plan", role: .destructive) { store.deletePlan(info.plan.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\u{201C}\(info.plan.name)\u{201D} will no longer be offered on the Subscription screen."
                 + (info.isCurrent ? " Your company is on this plan, so it will switch to \(store.subscription.plans.first { $0.id != info.plan.id }?.name ?? "another plan")." : ""))
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
        .alert(removing.map { "Remove \($0.name)?" } ?? "Remove inspector?",
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { ins in
            Button("Remove", role: .destructive) {
                store.removeInspector(ins.id)
                store.toast("\(ins.name) removed")
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { ins in
            Text("\(ins.email.isEmpty ? ins.name : ins.email) will no longer be on \(store.company.name)'s license and can't use the company's checklist, plans or profile. Their own inspections stay on their device.")
        }
        .onAppear {
            if DebugFlags.validate { DebugFlags.validate = false; name = ""; email = store.company.inspectors.first?.email ?? "x@y.com"; addInspector() }
        }
    }

    private var intro: some View {
        Text(md("Add inspector accounts under your company license. First inspector is included; each additional is **\(Fmt.money(store.subscription.extraInspectorMonthly))/mo**."))
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
                        Text(ins.email.isEmpty ? "no email yet" : ins.email).font(VFont.ui(12.5, .medium)).foregroundStyle(VC.ink2).lineLimit(1)
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
         + Text(" · monthly total \(Fmt.money(monthly))").font(VFont.ui(12.5)).foregroundColor(VC.ink3))
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

    private var monthly: Double {
        let s = store.subscription
        let base = s.plan(s.selectedPlan)
        if base?.perReport == true { return 0 }
        return (base?.price ?? 0) + Double(max(0, store.company.inspectors.count - 1)) * s.extraInspectorMonthly
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
        .confirmationDialog("Make \(inspector.name) the owner?", isPresented: $confirm, titleVisibility: .visible) {
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
                       text: md("**Free trial — \(sub.trialDaysLeft) days left.** Set up your subscription now so access continues automatically when the trial ends."))
                    .padding(.bottom, 14)
            }
            SectionLabel(text: "Choose your plan", top: 2)
            ForEach(sub.plans, id: \.id) { p in
                let on = sub.selectedPlan == p.id
                Button { store.state.subscription.selectedPlan = p.id } label: {
                    HStack(spacing: 13) {
                        Circle().stroke(on ? VC.brand : VC.line, lineWidth: 2).frame(width: 22, height: 22)
                            .overlay(Circle().fill(on ? VC.brand : .clear).frame(width: 11, height: 11))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                            Text(p.desc).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if p.id == "portal" {
                                Text("Available when the web portal launches (Phase 2)")
                                    .font(VFont.mono(9)).foregroundStyle(VC.ink3)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(VC.paper3).clipShape(RoundedRectangle(cornerRadius: 6))
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        (Text(Fmt.money(p.price)).font(VFont.mono(15, .semibold)).foregroundColor(VC.ink)
                         + Text(p.unit ?? "/mo").font(VFont.mono(11)).foregroundColor(VC.ink3))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 15)
                    .background(VC.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? VC.brand : VC.line, lineWidth: 1.5))
                    .shadow(color: on ? VC.brand.opacity(0.13) : .clear, radius: 3)
                }
                .buttonStyle(ChipPressStyle())
                .padding(.bottom, 10)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
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
            Text(md("First inspector included · each additional **\(Fmt.money(sub.extraInspectorMonthly))/mo**"))
                .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.horizontal, 2).padding(.top, 2)
            HStack {
                Text("Monthly total").font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                Spacer()
                Text(sub.totalLabel(seats: store.seats())).font(VFont.mono(22, .semibold)).foregroundStyle(VC.brand)
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
                Text("Secured by Square · auto-renews monthly · cancel anytime").font(VFont.ui(12))
            }
            .foregroundStyle(VC.ink3).padding(.horizontal, 2).padding(.top, 8)
            Button { start() } label: {
                if busy { ProgressView().tint(.white) } else { IconLabel(sub.active ? "Update subscription" : "Start subscription", icon: "link-my-account") }
            }
            .buttonStyle(.vPrimary).padding(.top, 16)
            .disabled(busy)
        }
        .onAppear {
            if DebugFlags.validate { DebugFlags.validate = false; useDifferentCard = true; card = FieldKind.cardNumber.filter("4242424242424241"); expiry = "01/24"; cvc = "12"; start() }
        }
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
                try await store.startSubscription(payment: payment)
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
        let plan = store.subscription.plan(store.subscription.selectedPlan)?.name ?? "App"
        Screen(title: "Subscription active", actions: [store.homeAction()]) {
            SuccessBlock(title: "Subscription active",
                         message: AttributedString("Your \(plan) plan is set up with auto-pay through Square. Access continues after your trial with no interruption.")) {
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
                    else { Pill(kind: .queued, text: "Trial · \(sub.trialDaysLeft)d left") }
                }
                row("Plan") { Text("\(plan?.name ?? "") · \(Fmt.money(plan?.price ?? 0))\(plan?.unit ?? "/mo")").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                if plan?.perReport != true {
                    row("Inspectors") { Text("\(seats) (\(max(0, seats - 1)) × \(Fmt.money(sub.extraInspectorMonthly)))").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                }
                row(plan?.perReport == true ? "Billing" : "Monthly total") { Text(sub.totalLabel(seats: seats)).font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                row("Payment") { Text(sub.active ? (sub.cardOnFile?.display ?? sub.paymentLabel ?? "Square") : "Not set up").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                row(sub.cancelled ? "Active until" : sub.active ? "Next billing" : "Trial ends", last: true) {
                    Text(sub.active ? periodEnd : "in \(sub.trialDaysLeft) days").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
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
