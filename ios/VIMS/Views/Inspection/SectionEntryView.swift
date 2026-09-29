import SwiftUI

// MARK: - 11–13, 28–29 Section entry (depth-aware, rendered from JSON per depthRules)

struct SectionEntryView: View {
    @Environment(AppStore.self) private var store
    let inspectionID: UUID
    let section: String

    @State private var answers = SectionAnswers()
    @State private var loaded = false
    @State private var drawerOpen = false
    @State private var showFinding = false

    var body: some View {
        if let insp = store.inspection(inspectionID) {
            ZStack {
                Screen(title: section, subtitle: insp.addressLine1,
                       actions: [
                        HeaderAction(symbol: "camera", label: "Photos") { store.push(.photos(inspectionID, section)) },
                        HeaderAction(symbol: "list.bullet", label: "Sections") { withAnimation(.easeOut(duration: 0.24)) { drawerOpen = true } },
                        store.homeAction()
                       ]) {
                    content(insp)
                }
                if drawerOpen {
                    SectionsDrawer(insp: insp, current: section, isOpen: $drawerOpen) { next in
                        replaceSection(next)
                    }
                    .zIndex(5)
                }
            }
            .onAppear {
                if !loaded {
                    answers = store.answers(inspectionID, section)
                    loaded = true
                }
                if DebugFlags.openDrawer { DebugFlags.openDrawer = false; drawerOpen = true }
            }
            .onChange(of: answers) { _, new in
                if loaded { store.setAnswers(inspectionID, section, new) }
            }
            .sheet(isPresented: $showFinding) {
                FindingSheet(section: section) { cat, text in
                    store.addFinding(inspectionID, category: cat, text: text, section: section)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ insp: Inspection) -> some View {
        let isForm = store.catalog.isForm(section)
        // State/insurance forms ignore the checklist depth (always `items`, no detail box, no Fast Entry chips).
        let depth: Depth = isForm ? .standard : insp.depth
        let resolved = store.catalog.items(section, depth: depth)
        if isForm {
            ModeTile(depth: .high, customLabel: store.catalog.formLabel(section),
                     customHint: store.catalog.section(section)?.form == "texas"
                        ? "Mark each item I / NI / NP / D and add comments. Same on every checklist depth."
                        : "Complete every line of the form. Same on every checklist depth.")
        } else {
            ModeTile(depth: depth)
        }

        if depth == .fast {
            let questions = (store.catalog.section(section)?.items ?? []).compactMap(\.q)
            if !questions.isEmpty {
                SectionLabel(text: "Items present", top: 2)
                ChipGroup(options: questions, selection: $answers.present, single: false)
            }
        } else {
            let keyed = ItemKeys.keyed(resolved.items)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(keyed.enumerated()), id: \.element.id) { idx, k in
                    if let h = k.item.header {
                        HeaderBand(text: h, first: idx == 0)
                    } else {
                        ItemCard(item: k.item, key: k.id, answers: $answers,
                                 showDetail: depth == .high && !resolved.usingHigh)
                    }
                }
            }
            if keyed.isEmpty {
                Text("This section has no checklist items yet. Add some in Settings → Manage checklist.")
                    .font(VFont.ui(13)).foregroundStyle(VC.ink3).padding(.vertical, 8)
            }
        }

        if !isForm {
            SectionLabel(text: "Overall condition")
            SegGrid(options: store.config.overallCondition, value: $answers.overall)
        }
        SectionLabel(text: "Comments")
        VTextArea(text: $answers.comments, placeholder: "Notes for this section…")

        let secFindings = insp.findings.filter { $0.section == section }
        if insp.hasSummary {
            Button { showFinding = true } label: {
                Label(secFindings.isEmpty ? "Flag a finding" : "Flag a finding · \(secFindings.count) flagged", systemImage: "flag")
            }
            .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 46))
        }

        HStack(spacing: 10) {
            Button { store.push(.photos(inspectionID, section)) } label: { Label("Photos", systemImage: "camera") }
                .buttonStyle(.vGhost)
            Button { save() } label: { Label("Save", systemImage: "checkmark") }
                .buttonStyle(.vGhost)
        }
        .padding(.top, 12)
        Button { saveNext() } label: { Label("Save & next section", systemImage: "arrow.right") }
            .buttonStyle(.vPrimary)
            .padding(.top, 10)
    }

    private func save() {
        store.setAnswers(inspectionID, section, answers)
        store.markDone(inspectionID, section)
        store.toast("Section saved")
        Task {
            try? await Task.sleep(nanoseconds: 550_000_000)
            store.popToSections(inspectionID)
        }
    }

    private func saveNext() {
        store.setAnswers(inspectionID, section, answers)
        store.markDone(inspectionID, section)
        if let next = store.nextSection(inspectionID, after: section) {
            store.toast("Saved — next: \(next)")
            replaceSection(next)
        } else {
            store.toast("Saved — last section")
            store.popToSections(inspectionID)
            store.push(store.inspection(inspectionID)?.hasSummary == false ? .report(inspectionID) : .summary(inspectionID))
        }
    }

    private func replaceSection(_ next: String) {
        if case .section = store.path.last { store.path.removeLast() }
        store.path.append(store.sectionRoute(inspectionID, next))
    }
}

/// .modetile — one badge per depth + hint.
struct ModeTile: View {
    let depth: Depth
    var customLabel: String? = nil
    var customHint: String? = nil
    var body: some View {
        let (bg, hint): (Color, String) = {
            switch depth {
            case .high: return (VC.brand, "Tap what applies, scroll to the next line — saves in one go.")
            case .standard: return (VC.ink3, "Tap what applies, scroll to the next line — saves in one go.")
            case .fast: return (VC.signalDeep, "Overall condition and notes — no line-by-line. Change depth in Settings.")
            }
        }()
        HStack(spacing: 8) {
            Text(customLabel ?? "\(depth.label) checklist")
                .font(VFont.ui(12, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(bg).clipShape(Capsule())
                .fixedSize()
            Text(customHint ?? hint).font(VFont.ui(11.5)).foregroundStyle(VC.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 14)
    }
}

/// .lihead — sub-section header band inside a section.
struct HeaderBand: View {
    let text: String
    var first = false
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "list.bullet").font(.system(size: 13, weight: .semibold)).opacity(0.9)
            Text(text).font(VFont.display(14, .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(VC.hdr)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: VC.brand.opacity(0.45), radius: 8, y: 6)
        .padding(.top, first ? 2 : 9)
        .padding(.bottom, 11)
        .accessibilityAddTraits(.isHeader)
    }
}

/// .li — one checklist line.
struct ItemCard: View {
    let item: ItemDef
    let key: String
    @Binding var answers: SectionAnswers
    var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.q ?? "")
                .font(VFont.ui(14.5, .semibold)).foregroundStyle(VC.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 11)
            switch item.kind {
            case .single, .multi:
                ChipGroup(options: item.options ?? [],
                          selection: Binding(get: { answers.choices[key] ?? [] }, set: { answers.choices[key] = $0.isEmpty ? nil : $0 }),
                          single: item.kind == .single)
                if showDetail {
                    VTextField(text: textBinding(\.detail), placeholder: "Detail / measurement (optional)", bottom: 0)
                        .padding(.top, 9)
                }
            case .num:
                VTextField(text: textBinding(\.text), placeholder: item.placeholder ?? "Enter a value", keyboard: .decimalPad, bottom: 0)
            case .text:
                VTextField(text: textBinding(\.text), placeholder: item.placeholder ?? "Enter a value", bottom: 0)
            case .date:
                OptionalDateField(value: textBinding(\.text), format: "yyyy-MM-dd", components: .date, prompt: "Select date")
            case .time:
                OptionalDateField(value: textBinding(\.text), format: "HH:mm", components: .hourAndMinute, prompt: "Select time")
            case .header:
                EmptyView()
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 11)
    }

    private func textBinding(_ kp: WritableKeyPath<SectionAnswers, [String: String]>) -> Binding<String> {
        Binding(get: { answers[keyPath: kp][key] ?? "" },
                set: { answers[keyPath: kp][key] = $0.isEmpty ? nil : $0 })
    }
}

/// A date/time answer that starts empty ("Select date") and can be cleared.
struct OptionalDateField: View {
    @Binding var value: String
    let format: String
    let components: DatePickerComponents
    let prompt: String

    var body: some View {
        FieldBox(focused: false) {
            if value.isEmpty {
                Button {
                    value = Fmt.date(Date(), format)
                } label: {
                    Label(prompt, systemImage: components == .date ? "calendar" : "clock")
                        .font(VFont.ui(15)).foregroundStyle(VC.brand)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    DatePicker(prompt, selection: Binding(get: { Fmt.parse(value, format) ?? Date() }, set: { value = Fmt.date($0, format) }),
                               displayedComponents: components)
                        .labelsHidden()
                        .environment(\.locale, Fmt.locale)
                    Spacer()
                    Button { value = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(VC.ink3).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -10)
                    .accessibilityLabel("Clear")
                }
            }
        }
    }
}

// MARK: - 16 Flag a finding (bottom sheet)

struct FindingSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let section: String
    let onAdd: (Int, String) -> Void

    @State private var category = 2
    @State private var text: String
    @State private var quick: String?

    init(section: String, initialText: String = "", onAdd: @escaping (Int, String) -> Void) {
        self.section = section
        self.onAdd = onAdd
        _text = State(initialValue: initialText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Flag a finding").font(VFont.display(18, .bold)).foregroundStyle(VC.ink).padding(.bottom, 4)
                Text("Pick a category and add a note. It's added to the summary and the report automatically.")
                    .font(VFont.ui(13)).foregroundStyle(VC.ink3).padding(.bottom, 16)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    ForEach(store.config.findings.categories, id: \.id) { c in
                        let on = category == c.id
                        Button { category = c.id } label: {
                            VStack(spacing: 5) {
                                Text("\(c.id)").font(VFont.display(20, .heavy)).foregroundStyle(on ? VC.category(c.id) : VC.ink)
                                Text(c.label).font(VFont.ui(10.5)).foregroundStyle(VC.ink3).multilineTextAlignment(.center)
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 74)
                            .background(on ? VC.categoryBg(c.id) : VC.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(on ? VC.category(c.id) : VC.line, lineWidth: 1.5))
                        }
                        .buttonStyle(ChipPressStyle())
                        .accessibilityLabel("Category \(c.id), \(c.label)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.bottom, 14)

                FieldLabel(text: "Quick comment").padding(.bottom, 7)
                QuickCommentMenu(placeholder: "Pick a quick comment…", selection: $quick, dark: false) { text = $0 }
                    .padding(.bottom, 13)
                VTextArea(label: "Description", text: $text, placeholder: "Describe the concern…")
                HStack(spacing: 10) {
                    Button("Cancel") { dismiss() }.buttonStyle(.vGhost)
                    Button("Add finding") {
                        onAdd(category, text)
                        dismiss()
                    }
                    .buttonStyle(.vPrimary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 26)
        }
        .background(VC.paper)
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
    }
}

/// Styled "select" for the 8 canned quick comments (JSON findings.quickComments).
struct QuickCommentMenu: View {
    @Environment(AppStore.self) private var store
    let placeholder: String
    @Binding var selection: String?
    var dark = false
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(store.config.findings.quickComments, id: \.self) { c in
                Button(c) { selection = c; onPick(c) }
            }
        } label: {
            HStack {
                Text(selection ?? placeholder)
                    .font(VFont.ui(dark ? 13 : 15))
                    .foregroundStyle(dark ? .white : (selection == nil ? VC.ink3 : VC.ink))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(dark ? .white.opacity(0.8) : VC.ink3)
            }
            .padding(.horizontal, dark ? 11 : 14)
            .frame(minHeight: dark ? 44 : 48)
            .background(dark ? Color.white.opacity(0.1) : VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: dark ? 9 : 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: dark ? 9 : 11, style: .continuous).stroke(dark ? Color.white.opacity(0.18) : VC.line, lineWidth: 1))
        }
        .accessibilityLabel(placeholder)
    }
}
