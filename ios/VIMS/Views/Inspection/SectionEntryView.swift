import SwiftUI

// MARK: - 11–13, 28–29 Section entry (depth-aware, rendered from JSON per depthRules)

struct SectionEntryView: View {
    @Environment(AppStore.self) private var store
    let inspectionID: UUID
    let section: String

    @State private var answers = SectionAnswers()
    @State private var loaded = false
    @State private var drawerOpen = false
    /// The finding sheet: "Flag a finding" for the section, or a concern on one checklist item.
    @State private var findingPrompt: FindingPrompt?
    @State private var errors = FormErrors()
    var wide = WideLayout()

    var body: some View {
        if let insp = store.inspection(inspectionID) {
            ZStack {
                Screen(title: store.catalog.title(section), subtitle: insp.addressLine1,
                       actions: [
                        HeaderAction(symbol: "hdr-photos", label: "Photos") { store.push(.photos(inspectionID, section)) },
                        HeaderAction(symbol: "hdr-sections", label: "Sections") { withAnimation(.easeOut(duration: 0.24)) { drawerOpen = true } },
                        store.homeAction()
                       ], errors: errors) {
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
                    // Pre-v1.7 Indoor Air Quality choices ("1 Good"…) become the matching reading's rating.
                    answers = store.prefilled(store.answers(inspectionID, section).migratingLegacyAirRatings(keyedItems(insp)),
                                              inspectionID, section)
                    loaded = true
                }
                if DebugFlags.openDrawer { DebugFlags.openDrawer = false; drawerOpen = true }
            }
            .onChange(of: answers) { _, new in
                if loaded { store.setAnswers(inspectionID, section, new) }
            }
            .sheet(item: $findingPrompt) { prompt in
                switch prompt {
                case .flag:
                    FindingSheet(section: section) { cat, custom, quick in
                        store.addFinding(inspectionID, category: cat, custom: custom, quick: quick, section: section)
                    }
                case .concern(let item):
                    // Client Oct 9: choosing "Concerns" / "Concern" on a Standard / High Detail item opens this.
                    FindingSheet(section: section, title: "Concern: \(item)",
                                 subtitle: "Describe the concern for this item and pick a category. It's added to the summary and the report automatically.") { cat, custom, quick in
                        store.addFinding(inspectionID, category: cat, custom: custom, quick: quick, section: section, item: item)
                    }
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
            // Conditional items (v1.8 `visibleIf`, e.g. Lead "Sample 2 location") have nothing to depend on here.
            let questions = (store.catalog.section(section)?.items ?? []).filter { $0.visibleIf == nil }.compactMap(\.q)
            if !questions.isEmpty {
                SectionLabel(text: "Items reviewed", top: 2)
                ChipGroup(options: questions, selection: $answers.present, single: false)
            }
        } else {
            // v1.8 `visibleIf`: conditional items appear while the item they name matches (Lead "Sample N location" for
            // "Samples taken" ≥ N, Meth "Other area tested" when "Area tested" includes Other).
            let keyed = ItemVisibility.visible(ItemKeys.keyed(resolved.items), answers: answers)
            let card = { (k: KeyedItem, fill: Bool) in
                ItemCard(item: k.item, key: k.id, answers: $answers, errors: errors,
                         showDetail: depth == .high && !resolved.usingHigh,
                         airQuality: store.catalog.section(section)?.airQuality,
                         onConcern: insp.hasSummary ? { q in findingPrompt = .concern(q) } : nil,
                         fillHeight: fill)
            }
            if wide.isWide {
                // iPad landscape: two checklist lines per row (each row as tall as its taller card); header bands and
                // Indoor Air Quality readings (level + rating side by side already) keep the full width.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ItemRow.rows(keyed)) { row in
                        switch row.kind {
                        case .header(let h, let first): HeaderBand(text: h, first: first)
                        case .full(let k): card(k, false)
                        case .pair(let a, let b):
                            HStack(alignment: .top, spacing: 12) {
                                card(a, true)
                                if let b { card(b, true) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(keyed.enumerated()), id: \.element.id) { idx, k in
                        if let h = k.item.header {
                            HeaderBand(text: h, first: idx == 0)
                        } else {
                            card(k, false)
                        }
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
            Button { findingPrompt = .flag } label: {
                IconLabel(secFindings.isEmpty ? "Flag a finding" : "Flag a finding · \(secFindings.count) flagged", icon: "flag")
            }
            .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 46))
        }

        HStack(spacing: 10) {
            Button { store.push(.photos(inspectionID, section)) } label: { IconLabel("Photos", icon: "camera") }
                .buttonStyle(.vGhost)
            Button { save() } label: { IconLabel("Save", icon: "link-my-account") }
                .buttonStyle(.vGhost)
        }
        .padding(.top, 12)
        Button { saveNext() } label: { IconLabel("Save & next section", icon: "save-return-svg") }
            .buttonStyle(.vPrimary)
            .padding(.top, 10)
    }

    /// The answer-keyed items shown for this inspection's depth (forms ignore depth).
    private func keyedItems(_ insp: Inspection) -> [KeyedItem] {
        let depth: Depth = store.catalog.isForm(section) ? .standard : insp.depth
        return ItemKeys.keyed(store.catalog.items(section, depth: depth).items)
    }

    /// `num` items: digits + one "." while typing, 0 – 99,999 when entered (counts "Number of …" 0 – 20); a value above
    /// the max shows its error while typing (docs/validation-rules.md "Number limits").
    /// `airReading` levels: same filter, optional, 0 – 99,999 (a CO reading is often 0 ppm).
    private func valid() -> Bool {
        guard let insp = store.inspection(inspectionID) else { return true }
        let isForm = store.catalog.isForm(section)
        let depth: Depth = isForm ? .standard : insp.depth
        guard depth != .fast else { return true }
        // Hidden conditional items (v1.8 `visibleIf`) are not validated.
        let keyed = ItemVisibility.visible(keyedItems(insp), answers: answers)
        let fields: [(id: String, value: String, rule: FieldRule)] = keyed.compactMap { k in
            switch k.item.kind {
            case .num: return (k.id, answers.text[k.id] ?? "", .opt(.number(.checklistItem(question: k.item.q, placeholder: k.item.placeholder)), k.item.q ?? "Value"))
            case .airReading: return (k.id, answers.text[k.id] ?? "", .opt(.number(.reading), "\(k.item.code ?? k.item.q ?? "Reading") level"))
            default: return nil
            }
        }
        return errors.validate(fields)
    }

    private func save() {
        guard valid() else { return }
        store.setAnswers(inspectionID, section, answers)
        store.markDone(inspectionID, section)
        store.toast("Section saved")
        Task {
            try? await Task.sleep(nanoseconds: 550_000_000)
            store.popToSections(inspectionID)
        }
    }

    private func saveNext() {
        guard valid() else { return }
        store.setAnswers(inspectionID, section, answers)
        store.markDone(inspectionID, section)
        if let next = store.nextSection(inspectionID, after: section) {
            store.toast("Saved — next: \(store.catalog.title(next))")
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

/// Wide checklist layout: header bands, full-width lines (air readings) and pairs of lines, in checklist order.
struct ItemRow: Identifiable {
    enum Kind {
        case header(String, first: Bool)
        case full(KeyedItem)
        case pair(KeyedItem, KeyedItem?)
    }
    let id: String
    let kind: Kind

    static func rows(_ keyed: [KeyedItem]) -> [ItemRow] {
        var out: [ItemRow] = []
        var pending: KeyedItem?
        func flush() {
            if let p = pending { out.append(ItemRow(id: "p:" + p.id, kind: .pair(p, nil))); pending = nil }
        }
        for (idx, k) in keyed.enumerated() {
            if let h = k.item.header {
                flush(); out.append(ItemRow(id: k.id, kind: .header(h, first: idx == 0)))
            } else if k.item.kind == .airReading {
                flush(); out.append(ItemRow(id: k.id, kind: .full(k)))
            } else if let p = pending {
                out.append(ItemRow(id: "p:" + p.id, kind: .pair(p, k))); pending = nil
            } else {
                pending = k
            }
        }
        flush()
        return out
    }
}

enum FindingPrompt: Identifiable, Hashable {
    case flag
    case concern(String)
    var id: String {
        switch self {
        case .flag: return "flag"
        case .concern(let q): return "concern:\(q)"
        }
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
            ProtoIcon("list", size: 17).opacity(0.9)
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
    var errors: FormErrors? = nil
    var showDetail = false
    /// The section's `airQuality` block (rating names under the 1–6 chips).
    var airQuality: AirQualityDef? = nil
    /// Called with the item's question when "Concerns" / "Concern" is newly selected (opens the concern sheet).
    var onConcern: ((String) -> Void)? = nil
    /// Wide iPad rows: the card stretches to the taller card beside it.
    var fillHeight = false

    static func isConcern(_ option: String) -> Bool {
        let o = option.trimmingCharacters(in: .whitespaces)
        return o == "Concern" || o == "Concerns"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.q ?? "")
                .font(VFont.ui(14.5, .semibold)).foregroundStyle(VC.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 11)
            switch item.kind {
            case .single, .multi:
                ChipGroup(options: item.options ?? [],
                          selection: Binding(get: { answers.choices[key] ?? [] }, set: { new in
                              let old = answers.choices[key] ?? []
                              answers.choices[key] = new.isEmpty ? nil : new
                              // Deselecting never removes a finding; Cancel in the sheet keeps the option selected.
                              if let onConcern, let q = item.q, new.contains(where: { Self.isConcern($0) && !old.contains($0) }) {
                                  onConcern(q)
                              }
                          }),
                          single: item.kind == .single)
                if showDetail {
                    VTextField(text: textBinding(\.detail), placeholder: "Detail / measurement (optional)", bottom: 0)
                        .padding(.top, 9)
                }
            case .num:
                VTextField(text: textBinding(\.text), placeholder: item.placeholder ?? "Enter a value", keyboard: .decimalPad, bottom: 0,
                           kind: .number(.checklistItem(question: item.q, placeholder: item.placeholder)), fieldID: key, errors: errors)
            case .airReading:
                AirReadingInput(item: item, key: key, level: textBinding(\.text),
                                rating: Binding(get: { answers.choices[key]?.first }, set: { answers.choices[key] = $0.map { [$0] } }),
                                ratingNames: airQuality?.ratings ?? [:], actionPrefix: airQuality?.prefix ?? AirQualityDef().prefix,
                                errors: errors)
            case .text:
                VTextField(text: textBinding(\.text), placeholder: item.placeholder ?? "Enter a value", bottom: 0, kind: .plain(max: 500))
            case .date:
                OptionalDateField(value: textBinding(\.text), components: .date, label: item.q ?? "Date")
            case .time:
                OptionalDateField(value: textBinding(\.text), components: .hourAndMinute, label: item.q ?? "Time")
            case .header:
                EmptyView()
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
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

/// Indoor Air Quality reading (data v1.7 `airReading`): optional "Level (unit)" on the decimal keypad + a 1–6 rating
/// (tap again to deselect), then the client's reference levels and corrective action in small secondary text.
/// iPhone stacks the level over the rating row; iPad puts them side by side (prototype `.li.air`).
struct AirReadingInput: View {
    let item: ItemDef
    let key: String
    @Binding var level: String
    @Binding var rating: String?
    var ratingNames: [String: String] = [:]
    var actionPrefix = "Corrective action if needed — "
    var errors: FormErrors? = nil

    private var unit: String { item.unit ?? "" }
    private var options: [String] { item.options ?? ["1", "2", "3", "4", "5", "6"] }
    var wide = WideLayout()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if Device.isPad {
                HStack(alignment: .bottom, spacing: 14) {
                    levelField.frame(width: wide.isWide ? 300 : 250)
                    VStack(alignment: .leading, spacing: 6) {
                        ratingCaption
                        ratingRow.frame(maxWidth: wide.isWide ? 540 : 380)
                    }
                    .padding(.bottom, 2)
                    Spacer(minLength: 0)
                }
            } else {
                levelField
                ratingCaption.padding(.top, 11).padding(.bottom, 6)
                ratingRow
            }
            VStack(alignment: .leading, spacing: 3) {
                if let r = item.reference, !r.isEmpty { Text(r) }
                if let a = item.action, !a.isEmpty { Text(actionPrefix + a) }
            }
            .font(VFont.ui(11.5)).foregroundStyle(VC.ink3)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        }
    }

    private var levelField: some View {
        VTextField(text: $level, placeholder: unit.isEmpty ? "Level measured" : "Level (\(unit))", keyboard: .decimalPad, bottom: 0,
                   kind: .number(.reading), fieldID: key, errors: errors, trailing: unit.isEmpty ? nil : unit)
    }

    private var ratingCaption: some View {
        HStack(spacing: 6) {
            Text("Air quality rating").font(VFont.ui(12, .semibold)).foregroundStyle(VC.ink2)
            if let r = rating, let name = ratingNames[r] {
                Text("· \(r) \(name)").font(VFont.ui(12, .semibold)).foregroundStyle(VC.brandDeep)
            }
        }
    }

    private var ratingRow: some View {
        HStack(spacing: 7) {
            ForEach(options, id: \.self) { o in
                let on = rating == o
                Button { rating = on ? nil : o } label: {
                    Text(o)
                        .font(VFont.ui(15, .semibold))
                        .foregroundStyle(on ? .white : VC.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? VC.brand : VC.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(on ? VC.brand : VC.line, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(ChipPressStyle())
                .accessibilityLabel("Rating \(o)\(ratingNames[o].map { ", \($0)" } ?? "")")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A checklist `date` / `time` answer (data v1.7.1: IAQ Date / Time, Termite and Wind Mitigation inspection date).
/// Looks like the wizard's Date / Time fields (the value in a gray pill inside the field box) and behaves like them:
/// one tap anywhere on the field opens the calendar (or the time wheels) right away, no keyboard. An empty answer
/// shows "Select date" / "Select time"; opening the picker fills in today / now (like the wizard), × clears it.
/// Stored as "yyyy-MM-dd" / "HH:mm" like the wizard; older typed answers are read when possible, else shown as typed.
struct OptionalDateField: View {
    @Binding var value: String
    let components: DatePickerComponents
    let label: String
    @State private var open = false

    private var isDate: Bool { components == .date }
    private var format: String { isDate ? Fmt.answerDateFormat : Fmt.answerTimeFormat }
    private var parsed: Date? { isDate ? Fmt.answerDate(value) : Fmt.answerTime(value) }
    /// What the pill shows: "Oct 12, 2026" / "10:15 AM" like the system compact picker in the wizard.
    private var display: String? {
        guard !value.isEmpty else { return nil }
        return parsed.map { Fmt.date($0, isDate ? "MMM d, yyyy" : "h:mm a") } ?? value
    }

    var body: some View {
        FieldBox(focused: open) {
            HStack(spacing: 8) {
                Button { openPicker() } label: {
                    HStack {
                        if let display {
                            Text(display)
                                .font(.system(size: 17)).foregroundStyle(open ? VC.brand : Color(.label))
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .padding(.vertical, -6)
                        } else {
                            IconLabel(isDate ? "Select date" : "Select time", icon: isDate ? "calendar" : "free-trial-days", iconSize: 18)
                                .font(VFont.ui(15)).foregroundStyle(VC.brand)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityValue(display ?? "Not set")
                .accessibilityHint(isDate ? "Opens the calendar" : "Opens the time picker")
                .popover(isPresented: $open, arrowEdge: .top) {
                    picker.presentationCompactAdaptation(.popover)
                }
                if display != nil {
                    Button { value = "" } label: {
                        ProtoIcon("close", size: 16).foregroundStyle(VC.ink3).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -10)
                    .accessibilityLabel("Clear \(label)")
                }
            }
        }
    }

    private func openPicker() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        // Like the wizard's picker, which always holds a date: opening it chooses today / now until changed.
        if parsed == nil { value = Fmt.date(Date(), format) }
        open = true
    }

    private var picker: some View {
        let selection = Binding(get: { parsed ?? Date() }, set: { value = Fmt.date($0, format) })
        return Group {
            if isDate {
                DatePicker(label, selection: selection, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .frame(width: 320)
            } else {
                DatePicker(label, selection: selection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .frame(width: 280)
            }
        }
        .labelsHidden()
        .tint(VC.brand)
        .environment(\.locale, Fmt.locale)
        .padding(12)
    }
}

// MARK: - 16 Flag a finding (bottom sheet)

struct FindingSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let section: String
    var title = "Flag a finding"
    var subtitle = "Pick a category and add a note. It's added to the summary and the report automatically."
    /// (category, custom comment = the Description, quick comment) — stored apart (client Oct 16).
    let onAdd: (Int, String, String?) -> Void

    @State private var category = 2
    @State private var text: String
    @State private var quick: String?
    @State private var missingDescription = false

    init(section: String, initialText: String = "", initialQuick: String? = nil, title: String? = nil, subtitle: String? = nil,
         onAdd: @escaping (Int, String, String?) -> Void) {
        self.section = section
        if let title { self.title = title }
        if let subtitle { self.subtitle = subtitle }
        self.onAdd = onAdd
        _text = State(initialValue: initialText)
        _quick = State(initialValue: initialQuick)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(VFont.display(18, .bold)).foregroundStyle(VC.ink).padding(.bottom, 4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
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
                // The pick stays in its own field (it's the finding's quick comment); the Description is the custom comment.
                QuickCommentMenu(placeholder: "Pick a quick comment…", selection: $quick, dark: false, noneLabel: "No quick comment") { _ in
                    missingDescription = false
                }
                    .padding(.bottom, 13)
                // Required only when no quick comment is picked (matches Android, Oct 16).
                VTextArea(label: "Description", text: $text, placeholder: "Describe the concern…",
                          error: missingDescription ? "Describe the finding or pick a quick comment." : nil)
                    .onChange(of: text) { _, t in if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missingDescription = false } }
                HStack(spacing: 10) {
                    Button("Cancel") { dismiss() }.buttonStyle(.vGhost)
                    Button("Add finding") {
                        guard quick != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            missingDescription = true
                            return
                        }
                        onAdd(category, text, quick)
                        dismiss()
                    }
                    .buttonStyle(.vPrimary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 26)
        }
        .background(VC.paper)
        // iPhone: the approved bottom sheet (large / medium). iPad: one full-height form sheet so nothing is cut off.
        .presentationDetents(Device.isPad ? [.large] : [.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
    }
}

/// Styled "select" for the 8 canned quick comments (JSON findings.quickComments). Every comment shows in full,
/// wrapped, with a checkmark on the current one (the system menu cut the long ones off on iPhone).
/// iPhone: a sheet listing them. iPad: a popover list with its arrow on the field.
struct QuickCommentMenu: View {
    @Environment(AppStore.self) private var store
    let placeholder: String
    @Binding var selection: String?
    var dark = false
    /// When set, the list starts with this row, which clears the selection (Flag a finding: "No quick comment").
    var noneLabel: String? = nil
    let onPick: (String?) -> Void
    @State private var showList = false
    @State private var fieldWidth: CGFloat = 320

    var body: some View {
        Button { showList = true } label: { field }
            .buttonStyle(.plain)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { fieldWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in fieldWidth = w }
            })
            .modifier(QuickCommentPresentation(isPresented: $showList, padList: { padList }, phoneSheet: { phoneSheet }))
            .task {
                guard DebugFlags.openCommentList, dark || !Device.isPad else { return }
                DebugFlags.openCommentList = false
                try? await Task.sleep(nanoseconds: 900_000_000)
                showList = true
            }
            .accessibilityLabel(placeholder)
            .accessibilityValue(selection ?? "None")
            .accessibilityHint("Shows the quick comments")
    }

    private func pick(_ c: String?) {
        selection = c
        onPick(c)
        showList = false
    }

    private var rows: some View {
        let comments = store.config.findings.quickComments
        return VStack(spacing: 0) {
            if let noneLabel {
                Button { pick(nil) } label: {
                    HStack(spacing: 10) {
                        Text(noneLabel).font(VFont.ui(15)).foregroundStyle(VC.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if selection == nil { ProtoIcon("check", size: 16, lineWidth: 2.4).foregroundStyle(VC.brand) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .overlay(alignment: .bottom) { Rectangle().fill(VC.line2).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selection == nil ? .isSelected : [])
            }
            ForEach(Array(comments.enumerated()), id: \.offset) { i, c in
                Button { pick(c) } label: {
                    HStack(spacing: 10) {
                        Text(c).font(VFont.ui(15)).foregroundStyle(VC.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if c == selection { ProtoIcon("check", size: 16, lineWidth: 2.4).foregroundStyle(VC.brand) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .overlay(alignment: .bottom) { if i < comments.count - 1 { Rectangle().fill(VC.line2).frame(height: 1) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(c == selection ? .isSelected : [])
            }
        }
    }

    /// iPhone: titled sheet tall enough for all eight wrapped comments (drag up for full height).
    private var phoneSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Quick comment").font(VFont.display(17, .bold)).foregroundStyle(VC.ink)
                Spacer()
                Button("Cancel") { showList = false }
                    .font(VFont.ui(16)).foregroundStyle(VC.brand)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
            Rectangle().fill(VC.line).frame(height: 1)
            ScrollView { rows }
        }
        .background(VC.paper)
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
        .environment(\.colorScheme, .light)
    }

    private var padList: some View {
        let comments = store.config.findings.quickComments
        return ScrollView { rows }
            .frame(width: max(fieldWidth, 320))
            .frame(minHeight: 200, idealHeight: min(CGFloat(comments.count + (noneLabel == nil ? 0 : 1)) * 49 + 4, 520), maxHeight: 520)
            .background(VC.paper)
            .presentationCompactAdaptation(.popover)
    }

    private var field: some View {
            HStack {
                Text(selection ?? placeholder)
                    .font(VFont.ui(dark ? 13 : 15))
                    .foregroundStyle(dark ? .white : (selection == nil ? VC.ink3 : VC.ink))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProtoIcon("chevron-down", size: 16)
                    .foregroundStyle(dark ? .white.opacity(0.8) : VC.ink3)
            }
            .padding(.horizontal, dark ? 11 : 14)
            .padding(.vertical, 8)
            .frame(minHeight: dark ? 44 : 48)
            .background(dark ? Color.white.opacity(0.1) : VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: dark ? 9 : 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: dark ? 9 : 11, style: .continuous).stroke(dark ? Color.white.opacity(0.18) : VC.line, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

private struct QuickCommentPresentation<PadList: View, PhoneSheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let padList: () -> PadList
    let phoneSheet: () -> PhoneSheet

    func body(content: Content) -> some View {
        if Device.isPad {
            content.popover(isPresented: $isPresented, arrowEdge: .bottom, content: padList)
        } else {
            content.sheet(isPresented: $isPresented, content: phoneSheet)
        }
    }
}
