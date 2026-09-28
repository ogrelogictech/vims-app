import SwiftUI

// MARK: - 23 Manage checklist (admin)

struct ManageChecklistView: View {
    @Environment(AppStore.self) private var store
    @State private var newName = ""
    @State private var newGroup: String? = ChecklistCatalog.customGroups.first
    @State private var open: Set<String> = ["Exterior"]

    var body: some View {
        Screen(title: "Manage checklist", actions: [store.homeAction()]) {
            HintText(text: "Add and edit checklist sections and items yourself — changes apply to new inspections.")
                .padding(.top, 2).padding(.bottom, 12)
            DashedBox {
                SmallField(text: $newName, placeholder: "New section name (e.g. Solar Panels)")
                SingleChipGroup(options: ChecklistCatalog.customGroups, value: $newGroup, required: true)
                    .padding(.bottom, 2)
                Button {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if store.addCustomSection(name: name, group: newGroup ?? "Exterior") {
                        newName = ""
                        open.insert(newGroup ?? "Exterior")
                        store.push(.editSection(name))
                    }
                } label: { Label("Add section", systemImage: "plus") }
                    .buttonStyle(VButtonStyle(kind: .primary, minHeight: 46))
            }
            ForEach(store.catalog.adminGroups(), id: \.group) { g in
                adminGroup(g.group, g.sections)
            }
        }
    }

    private func icon(_ g: String) -> String {
        switch g {
        case "Testing": return "flask"
        case "Utility": return "bolt"
        case "Interior": return "sofa"
        case "Phase Inspections": return "layers"
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
                    Image(systemName: VIcon.symbol(icon(g))).font(.system(size: 15, weight: .medium)).foregroundStyle(VC.brand)
                        .frame(width: 30, height: 30).background(VC.paper3)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(g).font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(names.count)").font(VFont.mono(11)).foregroundStyle(VC.ink3)
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(VC.ink3)
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
                            Text(n).font(VFont.ui(14, .medium)).foregroundStyle(VC.ink).frame(maxWidth: .infinity, alignment: .leading)
                            if store.isCustomSection(n) { Pill(kind: .prog, text: "Custom", dot: false) }
                            Text("\(count) items").font(VFont.mono(10.5, .semibold)).foregroundStyle(VC.ink2)
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

    var body: some View {
        Screen(title: sectionName, subtitle: "Edit section", actions: [store.homeAction()]) {
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
                    EditItemCard(edit: $e,
                                 canUp: e.id != items.first?.id, canDown: e.id != items.last?.id,
                                 move: { move(e.id, by: $0) },
                                 delete: { items.removeAll { $0.id == e.id } })
                }
                Button {
                    items.append(EditItem(item: .question("New item", options: ["Yes", "No", "N/A"])))
                } label: { Label("Add item", systemImage: "plus") }
                    .buttonStyle(.vGhost)
                Button { save() } label: { Label("Save & done", systemImage: "checkmark") }
                    .buttonStyle(.vPrimary).padding(.top, 10)
                if store.isCustomSection(sectionName) {
                    Button(role: .destructive) { confirmRemove = true } label: {
                        Label("Remove this section", systemImage: "trash").foregroundStyle(VC.c1)
                    }
                    .buttonStyle(.vGhost).padding(.top, 10)
                }
            }
        }
        .onAppear {
            guard def == nil else { return }
            def = store.catalog.section(sectionName) ?? SectionDef(name: sectionName, number: 99, icon: nil, photoCategories: ["Overview", "Concerns"],
                                                                    photoCategoriesHigh: nil, items: [], itemsHigh: nil)
            items = (def?.items ?? []).map { EditItem(item: $0) }
        }
        .confirmationDialog("Remove “\(sectionName)”?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove section", role: .destructive) {
                store.removeCustomSection(sectionName)
                store.back()
            }
        } message: { Text("It won't appear in new inspections. Existing inspections keep their answers.") }
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
        commitTier()
        guard let def else { return }
        store.saveSectionOverride(def)
        store.back()
    }
}

struct EditItemCard: View {
    @Binding var edit: EditItem
    let canUp: Bool
    let canDown: Bool
    let move: (Int) -> Void
    let delete: () -> Void
    @State private var newOption = ""
    @FocusState private var focused: Bool

    private let types: [(String, String)] = [("single", "Pick one"), ("multi", "Pick several"), ("text", "Text"), ("num", "Number"), ("date", "Date"), ("time", "Time")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if edit.item.isHeader {
                    Text("HEADER").font(VFont.mono(9.5, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(VC.hdr).clipShape(Capsule())
                }
                TextField("", text: Binding(
                    get: { edit.item.header ?? edit.item.q ?? "" },
                    set: { if edit.item.isHeader { edit.item.header = $0 } else { edit.item.q = $0 } }),
                          prompt: Text("Question").foregroundStyle(VC.placeholder))
                    .font(VFont.ui(14.5, .semibold)).foregroundStyle(VC.ink)
                    .focused($focused)
                    .padding(.vertical, 5)
                    .overlay(alignment: .bottom) { Rectangle().fill(focused ? VC.brand : VC.line).frame(height: 1.5) }
                HStack(spacing: 6) {
                    iconButton("chevron.up", "Move up", enabled: canUp) { move(-1) }
                    iconButton("chevron.down", "Move down", enabled: canDown) { move(1) }
                    iconButton("trash", "Delete item", enabled: true, action: delete)
                }
            }
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
                        Text(types.first { $0.0 == (edit.item.type ?? "single") }?.1 ?? "Pick one").font(VFont.ui(12, .semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
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
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(VC.ink3)
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
                        SmallField(text: $newOption, placeholder: "Add option…")
                            .onSubmit(addOption)
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
        let v = newOption.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        edit.item.options = (edit.item.options ?? []) + [v]
        newOption = ""
    }

    private func iconButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(VC.ink3)
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
    @State private var extra = ""
    @State private var newName = ""
    @State private var newPrice = ""
    @State private var newDesc = ""

    var body: some View {
        Screen(title: "Plans & pricing", actions: [store.homeAction()]) {
            HintText(text: "Owner admin — edit plan prices, add a plan, or set the per-inspector rate. Changes apply to the subscribe screen.")
                .padding(.top, 2).padding(.bottom, 12)
            ForEach(store.subscription.plans, id: \.id) { p in
                priceCard(title: p.name, unit: p.unit ?? "/mo", desc: p.desc, text: Binding(get: { prices[p.id] ?? Fmt.price(p.price) }, set: { prices[p.id] = $0 })) {
                    commit(p.id)
                }
            }
            priceCard(title: "Additional inspector", unit: "/mo each", desc: nil, text: $extra) {
                if let v = Double(extra), v >= 0 {
                    store.state.subscription.extraInspectorMonthly = v
                    store.toast("Extra inspector → \(Fmt.money(v))")
                } else { extra = Fmt.price(store.subscription.extraInspectorMonthly) }
            }
            DashedBox {
                SmallField(text: $newName, placeholder: "Plan name (e.g. Team)")
                SmallField(text: $newPrice, placeholder: "Monthly price (e.g. 99.00)", keyboard: .decimalPad)
                SmallField(text: $newDesc, placeholder: "Short description")
                Button { addPlan() } label: { Label("Add plan", systemImage: "plus") }
                    .buttonStyle(VButtonStyle(kind: .primary, minHeight: 46))
            }
        }
        .onAppear { extra = Fmt.price(store.subscription.extraInspectorMonthly) }
    }

    private func priceCard(title: String, unit: String, desc: String?, text: Binding<String>, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink)
            HStack(spacing: 10) {
                Text("Price $").font(VFont.ui(13)).foregroundStyle(VC.ink2)
                TextField("", text: text)
                    .keyboardType(.decimalPad)
                    .font(VFont.ui(15)).foregroundStyle(VC.ink)
                    .padding(.horizontal, 12).frame(width: 130, height: 48)
                    .background(VC.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(VC.line, lineWidth: 1))
                    .onSubmit(commit)
                Text(unit).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                Spacer()
                Button("Save", action: commit)
                    .font(VFont.ui(13, .semibold)).foregroundStyle(VC.brandDeep)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(VC.paper3).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            if let desc { Text(desc).font(VFont.ui(12)).foregroundStyle(VC.ink3) }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 11)
    }

    private func commit(_ id: String) {
        guard let i = store.state.subscription.plans.firstIndex(where: { $0.id == id }) else { return }
        let raw = prices[id] ?? ""
        if let v = Double(raw.replacingOccurrences(of: ",", with: "")), v >= 0 {
            store.state.subscription.plans[i].price = v
            prices[id] = Fmt.price(v)
            store.toast("\(store.state.subscription.plans[i].name) → \(Fmt.money(v))")
        } else {
            prices[id] = Fmt.price(store.state.subscription.plans[i].price)
            store.toast("Enter a valid price")
        }
    }

    private func addPlan() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { store.toast("Enter a plan name"); return }
        guard let pr = Double(newPrice), pr >= 0 else { store.toast("Enter a valid price"); return }
        let id = "plan\(store.state.subscription.plans.count + 1)-\(UUID().uuidString.prefix(4))"
        store.state.subscription.plans.append(PlanDef(id: id, name: n, price: pr, desc: newDesc.isEmpty ? "Custom plan" : newDesc, unit: nil, perReport: nil))
        newName = ""; newPrice = ""; newDesc = ""
        store.toast("Added “\(n)”")
    }
}

// MARK: - 25 Inspectors

struct InspectorsView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var email = ""

    var body: some View {
        let company = store.company
        let n = company.inspectors.count
        Screen(title: "Inspectors", actions: [store.homeAction()]) {
            Text(md("Add inspector accounts under your company license. First inspector is included; each additional is **\(Fmt.money(store.subscription.extraInspectorMonthly))/mo**."))
                .font(VFont.ui(13)).foregroundStyle(VC.ink3).padding(.top, 2).padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                Text("COMPANY JOIN CODE").font(VFont.mono(10.5)).tracking(1.2).foregroundStyle(VC.ink3).padding(.bottom, 7)
                HStack {
                    Text(company.joinCode).font(VFont.mono(24, .semibold)).tracking(4.3).foregroundStyle(VC.brandDeep)
                        .accessibilityLabel("Company code \(company.joinCode.map(String.init).joined(separator: " "))")
                    Spacer()
                    Button {
                        UIPasteboard.general.string = company.joinCode
                        store.toast("Code \(company.joinCode) copied")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc").font(VFont.ui(12.5, .semibold)).foregroundStyle(VC.brandDeep)
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

            Text(md("You (the account owner) are an **admin** by default. Tap **Make admin** to grant any inspector admin access — admins can manage checklists, plans, the company profile, and settings. Nothing is hard-coded; roles are set here."))
                .font(VFont.ui(12)).foregroundStyle(VC.ink3).lineSpacing(2).padding(.horizontal, 2).padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(company.inspectors) { ins in
                HStack(spacing: 13) {
                    Avatar(name: ins.name, size: 44, radius: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ins.name) · \(ins.roleLabel)").font(VFont.ui(15, .semibold)).foregroundStyle(VC.ink)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(ins.email.isEmpty ? "no email yet" : ins.email).font(VFont.ui(12.5, .medium)).foregroundStyle(VC.ink2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if ins.owner {
                        Pill(kind: .done, text: "Admin")
                    } else {
                        VStack(alignment: .trailing, spacing: 6) {
                            Button { store.toggleAdmin(ins.id) } label: {
                                Pill(kind: ins.admin ? .prog : .new, text: ins.admin ? "Admin ✓" : "Make admin", dot: false)
                                    .frame(minHeight: 32)
                            }
                            .buttonStyle(ChipPressStyle())
                            Button { store.removeInspector(ins.id) } label: {
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
            (Text("\(n) inspector\(n == 1 ? "" : "s")").font(VFont.ui(12.5, .bold)).foregroundColor(VC.ink)
             + Text(" · monthly total \(Fmt.money(monthly))").font(VFont.ui(12.5)).foregroundColor(VC.ink3))
                .padding(.horizontal, 2).padding(.top, 4).padding(.bottom, 14)

            DashedBox {
                SmallField(text: $name, placeholder: "Inspector name")
                SmallField(text: $email, placeholder: "inspector@email.com", keyboard: .emailAddress)
                Button {
                    if store.addInspector(name: name, email: email) { name = ""; email = "" }
                } label: { Label("Add inspector", systemImage: "plus") }
                    .buttonStyle(VButtonStyle(kind: .primary, minHeight: 46))
            }
        }
    }

    private var monthly: Double {
        let s = store.subscription
        let base = s.plan(s.selectedPlan)
        if base?.perReport == true { return 0 }
        return (base?.price ?? 0) + Double(max(0, store.company.inspectors.count - 1)) * s.extraInspectorMonthly
    }
}

// MARK: - 26 Subscribe (Square)

struct SubscribeView: View {
    @Environment(AppStore.self) private var store
    @State private var card = ""
    @State private var expiry = ""
    @State private var cvc = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        let sub = store.subscription
        Screen(title: "Subscription", actions: [store.homeAction()]) {
            if !sub.active {
                Banner(symbol: "clock", tint: VC.brandDeep, background: VC.brand.opacity(0.08), border: Color(hex: 0xC9DEE6), textColor: VC.brandDeep,
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
            CounterRow(label: "Inspectors on this license", value: Binding(
                get: { store.seats() },
                set: { v in
                    let cur = store.company.inspectors.count
                    if v > cur { store.state.company.inspectors.append(Inspector(name: "Inspector \(cur + 1)", email: "")) }
                    else if v < cur, let last = store.company.inspectors.last(where: { !$0.owner }) { store.removeInspector(last.id) }
                }), range: 1...99)
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
            VTextField(label: "Card number", text: Binding(get: { card }, set: { card = formatCard($0) }), placeholder: "1234 5678 9012 3456",
                       keyboard: .numberPad, contentType: .creditCardNumber, capitalization: .never)
            HStack(alignment: .top, spacing: 10) {
                VTextField(label: "Expiry", text: Binding(get: { expiry }, set: { expiry = formatExpiry($0) }), placeholder: "MM / YY",
                           keyboard: .numberPad, contentType: .creditCardExpiration, capitalization: .never, bottom: 0)
                VTextField(label: "CVC", text: Binding(get: { cvc }, set: { cvc = String($0.filter(\.isNumber).prefix(4)) }), placeholder: "123",
                           keyboard: .numberPad, contentType: .creditCardSecurityCode, capitalization: .never, bottom: 0)
            }
            if let error {
                Text(error).font(VFont.ui(12)).foregroundStyle(VC.c1).padding(.top, 8)
            }
            HStack(spacing: 8) {
                Image(systemName: "lock").font(.system(size: 12))
                Text("Secured by Square · auto-renews monthly · cancel anytime").font(VFont.ui(12))
            }
            .foregroundStyle(VC.ink3).padding(.horizontal, 2).padding(.top, 8)
            Button { start() } label: {
                if busy { ProgressView().tint(.white) } else { Label(sub.active ? "Update subscription" : "Start subscription", systemImage: "checkmark") }
            }
            .buttonStyle(.vPrimary).padding(.top, 16)
            .disabled(busy)
        }
    }

    private func formatCard(_ s: String) -> String {
        let d = String(s.filter(\.isNumber).prefix(19))
        return stride(from: 0, to: d.count, by: 4).map { i -> String in
            let a = d.index(d.startIndex, offsetBy: i)
            let b = d.index(a, offsetBy: min(4, d.count - i))
            return String(d[a..<b])
        }.joined(separator: " ")
    }

    private func formatExpiry(_ s: String) -> String {
        let d = String(s.filter(\.isNumber).prefix(4))
        return d.count > 2 ? "\(d.prefix(2)) / \(d.dropFirst(2))" : d
    }

    private func start() {
        error = nil
        busy = true
        Task {
            do {
                try await store.startSubscription(card: CardEntry(number: card, expiry: expiry, cvc: cvc))
                card = ""; expiry = ""; cvc = ""
                store.push(.subscriptionStarted)
            } catch {
                self.error = error.localizedDescription
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
    var body: some View {
        let sub = store.subscription
        let plan = sub.plan(sub.selectedPlan)
        let seats = store.seats()
        Screen(title: "Subscription", actions: [store.homeAction()]) {
            VStack(spacing: 0) {
                row("Status") {
                    if sub.active { Pill(kind: .done, text: "Active · auto-pay") } else { Pill(kind: .queued, text: "Trial · \(sub.trialDaysLeft)d left") }
                }
                row("Plan") { Text("\(plan?.name ?? "") · \(Fmt.money(plan?.price ?? 0))\(plan?.unit ?? "/mo")").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                if plan?.perReport != true {
                    row("Inspectors") { Text("\(seats) (\(max(0, seats - 1)) × \(Fmt.money(sub.extraInspectorMonthly)))").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                }
                row(plan?.perReport == true ? "Billing" : "Monthly total") { Text(sub.totalLabel(seats: seats)).font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                row("Payment") { Text(sub.active ? (sub.paymentLabel ?? "Square") : "Not set up").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink) }
                row(sub.active ? "Next billing" : "Trial ends", last: true) {
                    Text(sub.active ? Fmt.date(sub.nextBillingDate, "MMM d, yyyy") : "in \(sub.trialDaysLeft) days").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                }
            }
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
            .padding(.bottom, 12)
            Button { store.push(.inspectors) } label: { Label("Manage inspectors", systemImage: "person.2") }
                .buttonStyle(.vGhost)
            Button(sub.active ? "Change plan / payment" : "Set up subscription") { store.push(.subscribe) }
                .buttonStyle(VButtonStyle(kind: sub.active ? .ghost : .primary))
                .padding(.top, 10)
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
