import SwiftUI

// MARK: - 06–09 New-inspection wizard (rendered from JSON `wizard`)

struct WizardView: View {
    @Environment(AppStore.self) private var store
    let editingID: UUID?
    @State private var draft: Inspection?
    @State private var step = 1
    @State private var errors = FormErrors()
    /// Earliest selectable inspection date: today, or the saved date when editing an older inspection.
    @State private var minDate = Calendar.current.startOfDay(for: Date())

    var body: some View {
        let w = store.config.wizard
        Screen(title: editingID == nil ? "New inspection" : "Inspection info",
               subtitle: editingID == nil ? nil : draft?.addressLine1,
               actions: [store.homeAction()],
               scroll: false) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 16).id("top")
                        StepsBar(count: w.steps.count, current: step)
                        if draft != nil {
                            switch step {
                            case 1: EntryList(entries: w.step1, draft: draftBinding, errors: errors, pairText: false, minDate: minDate)
                            case 2: EntryList(entries: w.step2, draft: draftBinding, errors: errors, pairText: true, minDate: minDate)
                            case 3: areas
                            default: tests
                            }
                        }
                        HStack(spacing: 10) {
                            Button("Back") { go(step - 1, proxy) }
                                .buttonStyle(.vGhost)
                                .opacity(step == 1 ? 0 : 1)
                                .disabled(step == 1)
                            Button { next(proxy) } label: {
                                if step == w.steps.count {
                                    IconLabel(editingID == nil ? "Build checklist" : "Update checklist", icon: "build-checklist-next")
                                } else {
                                    Text("Next")
                                }
                            }
                            .buttonStyle(.vPrimary)
                        }
                        .padding(.top, 22)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 34)
                    .readableColumn()
                }
                .scrollDismissesKeyboard(.interactively)
                #if DEBUG
                .task {
                    // -wizScroll ID: scroll step 1 to a block (e.g. sendToAgent, agreementLine) for review screenshots.
                    guard let target = DebugLaunch.value("-wizScroll") else { return }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    proxy.scrollTo(target, anchor: .center)
                }
                #endif
            }
        }
        .onAppear {
            guard draft == nil else { return }
            if let id = editingID, var existing = store.inspection(id) {
                // Inspections from before v1.3: prefill State from a code written into the address.
                if existing.state == nil, let st = Inspection.inferState(from: existing.address, states: store.config.states ?? []) {
                    existing.state = st
                }
                draft = existing
                if let saved = Fmt.parse(existing.field("Date"), "yyyy-MM-dd") { minDate = min(minDate, Calendar.current.startOfDay(for: saved)) }
            } else { draft = store.newInspectionDraft() }
            if let s = DebugFlags.wizardStep { step = max(1, min(4, s)); DebugFlags.wizardStep = nil }
            #if DEBUG
            // -wizState TX[,UT…]: pick those states in order through the same setter as the picker.
            if let seq = DebugFlags.wizardStates {
                DebugFlags.wizardStates = nil
                for code in seq {
                    draft?.setState(code, config: store.config)
                    print("STATETEST picked \(code) -> type=\(draft?.inspType ?? "") state=\(draft?.state ?? "none") docsPending=\(draft?.stateDocsPending(store.config) ?? false) sendToAgent=\(draft?.sendsReportToAgent ?? true)")
                }
                if DebugLaunch.has("-ackStateDocs"), let st = draft?.state, let r = store.config.stateRule(st) {
                    draft?.stateDocsAck = StateDocsAck(state: st, docs: r.requiredDocs.map(\.name), acknowledgedAt: Date())
                }
            }
            #endif
            if DebugFlags.validate {
                DebugFlags.validate = false
                draft?.fields["Client phone"] = "(801) 555"
                draft?.fields["Client email"] = "client@mail"
                draft?.fields["Temperature (°F)"] = "150"
                draft?.fields["Year of construction"] = "1700"
                errors.validate(stepFields(step, draft!))
                if step == 1 { applyStateErrors(draft!) }
            }
        }
    }

    private var draftBinding: Binding<Inspection> {
        Binding(get: { draft ?? store.newInspectionDraft() }, set: { draft = $0 })
    }

    // Step 3 — areas to inspect
    @ViewBuilder private var areas: some View {
        let w = store.config.wizard
        HintText(text: "Choose every area to inspect — add or remove anything. This builds the checklist.")
            .padding(.top, 2).padding(.bottom, 2)
        SectionLabel(text: "Exterior areas")
        ChipGroup(options: w.exteriorOptions, selection: draftBinding.exterior, single: false)
        SectionLabel(text: "Room counts")
        ForEach(w.roomCounts, id: \.key) { rc in
            CounterRow(label: rc.label, value: Binding(
                get: { draft?.counts[rc.key] ?? 0 },
                set: { draft?.counts[rc.key] = $0 }), range: 0...12)
        }
        SectionLabel(text: "Interior rooms", top: 11)
        ChipGroup(options: w.roomOptions, selection: draftBinding.rooms, single: false)
        SectionLabel(text: "Utility & systems")
        ChipGroup(options: w.utilityOptions, selection: draftBinding.utilities, single: false)
    }

    // Step 4 — secondary testing
    @ViewBuilder private var tests: some View {
        HintText(text: "Add any secondary testing for this inspection.").padding(.top, 2).padding(.bottom, 12)
        ChipGroup(options: store.config.wizard.testOptions, selection: draftBinding.tests, single: false)
    }

    private func go(_ s: Int, _ proxy: ScrollViewProxy) {
        step = max(1, min(store.config.wizard.steps.count, s))
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("top", anchor: .top) }
    }

    /// docs/validation-rules.md checks for the fields on a wizard step (typeFields ride along with step 1).
    private func stepFields(_ step: Int, _ d: Inspection) -> [(id: String, value: String, rule: FieldRule)] {
        let w = store.config.wizard
        let entries = step == 1 ? w.step1 : step == 2 ? w.step2 : []
        var out: [(id: String, value: String, rule: FieldRule)] = []
        for e in entries where e.kind == "field" {
            if let r = WizardRules.rule(for: e.label, type: e.type) { out.append((e.label, d.field(e.label), r)) }
        }
        if step == 1 {
            for f in store.catalog.typeFields(for: d.inspType) {
                if let r = WizardRules.rule(for: f.key, type: nil) { out.append((f.key, d.field(f.key), r)) }
            }
        }
        return out
    }

    private func next(_ proxy: ScrollViewProxy) {
        guard var d = draft else { return }
        // Validate the current step; on the last step re-check step 1 (the required fields live there).
        let fields = stepFields(step, d)
        let fieldsOK = errors.validate(fields)
        let stateOK = step == 1 ? applyStateErrors(d) : true
        guard fieldsOK, stateOK else { scrollToError(proxy); return }
        if let date = Fmt.parse(d.field("Date"), "yyyy-MM-dd"), date < minDate, fields.contains(where: { $0.id == "Date" }) {
            errors.set("Date", "Choose today or a later date")
            scrollToError(proxy)
            return
        }
        if step == store.config.wizard.steps.count, !(errors.validate(stepFields(1, d)) && applyStateErrors(d)) {
            step = 1
            scrollToError(proxy)
            return
        }
        for (id, value, _) in fields { d.fields[id] = Validator.trimmed(value) }
        draft = d
        if step < store.config.wizard.steps.count { go(step + 1, proxy); return }
        if d.field("Inspector").isEmpty { d.fields["Inspector"] = store.session?.name ?? store.company.inspectorName }
        let id = store.buildChecklist(from: d)
        if editingID != nil {
            store.toast("Checklist updated")
            store.popToSections(id)
        } else {
            store.toast("Checklist built — \(d.structure)")
            store.path = [.sections(id)]
        }
    }

    /// Adds the State / state-documents errors after the field validation (which resets the map) and
    /// scrolls to the first error in screen order (State sits right after Inspection address).
    @discardableResult
    private func applyStateErrors(_ d: Inspection) -> Bool {
        let errs = WizardRules.stateErrors(d, store.config)
        guard let first = errs.first else { return true }
        let fieldScroll = errors.scrollTarget
        for (id, msg) in errs { errors.map[id] = msg }
        let step1 = store.config.wizard.step1.map(\.label)
        let before = Set(step1.prefix { $0 != "Inspection address" } + ["Inspection address"])
        if fieldScroll == nil || !before.contains(fieldScroll!) { errors.scrollTarget = first.0 }
        return false
    }

    private func scrollToError(_ proxy: ScrollViewProxy) {
        guard let t = errors.scrollTarget else { return }
        errors.scrollTarget = nil
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation { proxy.scrollTo(t, anchor: .center) }
        }
    }
}

/// Field rules for the JSON-driven wizard fields, keyed by label / typeFields key.
enum WizardRules {
    /// Data v1.3 has a `states` list → the wizard shows the required State field on step 1.
    static func hasStateField(_ cfg: ChecklistConfig) -> Bool { !(cfg.states ?? []).isEmpty }

    /// Step-1 State checks (docs/validation-rules.md: State required) + the stateRules documents
    /// acknowledgment, as (field id, message) in screen order.
    static func stateErrors(_ d: Inspection, _ cfg: ChecklistConfig) -> [(String, String)] {
        guard hasStateField(cfg) else { return [] }
        guard let st = d.state, cfg.stateName(st) != nil else { return [(StateFieldIDs.state, StateFieldIDs.stateError)] }
        return d.stateDocsPending(cfg) ? [(StateFieldIDs.docsAck, StateFieldIDs.docsAckError)] : []
    }

    static func rule(for key: String, type: String?) -> FieldRule? {
        switch key {
        case "Client name": return .req(.personName, "Client name")
        case "Client phone": return .opt(.phone, "Client phone")
        case "Client email": return .opt(.email, "Client email")
        case "Inspection address": return .req(.address, "Inspection address")
        case "Real estate agent name": return .opt(.personName, "Agent name")
        case "Real estate agent email": return .opt(.email, "Agent email")
        case Inspection.licenseField: return .opt(.license, "License #")
        case "Date": return .req(.plain(max: nil), "Date")
        case "Temperature (°F)": return .opt(.temperature, "Temperature")
        case "Year of construction": return .opt(.year, "Year of construction")
        case "Total sq ft": return .opt(.decimal, "Total sq ft")
        case "Valuation ($)": return .opt(.decimal, "Valuation")
        case "Lot size (acres)": return .opt(.decimal, "Lot size")
        case "sponsorName", "insuredName": return .opt(.personName, "Name")
        case "sponsorLicense": return .opt(.license, "Sponsor TREC License #")
        case "policyNumber": return .opt(.policy, "Application / Policy #")
        default: return nil
        }
    }

    static func kind(for key: String, type: String?) -> FieldKind? {
        if let r = rule(for: key, type: type), r.kind != .plain(max: nil) { return r.kind }
        return type == "email" ? .email : type == "tel" ? .phone : nil
    }
}

struct StepsBar: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(i == current ? VC.brand : (i < current ? VC.brandBright : VC.paper3))
                    .frame(height: 5)
            }
        }
        .padding(.top, 4).padding(.bottom, 16)
        .accessibilityElement()
        .accessibilityLabel("Step \(current) of \(count)")
    }
}

/// Renders a JSON wizard step (`step1` / `step2`) in order.
private struct EntryList: View {
    @Environment(AppStore.self) private var store
    let entries: [WizardEntry]
    @Binding var draft: Inspection
    let errors: FormErrors
    let pairText: Bool
    var minDate: Date? = nil

    var body: some View {
        let groups = grouped()
        VStack(alignment: .leading, spacing: 0) {
            if !pairText {
                SectionLabel(text: store.config.wizard.steps.first ?? "Client & inspection", top: 2)
                    .overlay(alignment: .bottomTrailing) { RequiredHint().fixedSize().padding(.bottom, 4) }
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                render(g)
            }
        }
    }

    private enum Block {
        case single(WizardEntry)
        case pair(WizardEntry, WizardEntry)
        case labelThenField(String, WizardEntry)   // e.g. "Weather & site conditions" label before Temperature
    }

    private func grouped() -> [Block] {
        var out: [Block] = []
        var i = 0
        while i < entries.count {
            let e = entries[i]
            let next = i + 1 < entries.count ? entries[i + 1] : nil
            if e.kind == "field", e.type == "date", let n = next, n.type == "time" {
                out.append(.pair(e, n)); i += 2; continue
            }
            if pairText, e.kind == "field", (e.type ?? "text") == "text", let n = next, n.kind == "field", (n.type ?? "text") == "text" {
                out.append(.pair(e, n)); i += 2; continue
            }
            if e.kind == "field", e.label.hasPrefix("Temperature"), let n = next, n.kind == "chips" {
                out.append(.labelThenField(n.label, e)); i += 1; continue
            }
            out.append(.single(e)); i += 1
        }
        return out
    }

    @ViewBuilder
    private func render(_ b: Block) -> some View {
        switch b {
        case .pair(let a, let c):
            if pairText, a.label == entries.first(where: { $0.kind == "field" })?.label {
                SectionLabel(text: "Property details")
            }
            HStack(alignment: .top, spacing: 10) {
                field(a, bottom: 0)
                field(c, bottom: 0)
            }
            .padding(.bottom, 11)
        case .labelThenField(let lbl, let e):
            SectionLabel(text: lbl)
            field(e, bottom: 11).frame(maxWidth: 140, alignment: .leading)
        case .single(let e):
            switch e.kind {
            case "field":
                field(e, bottom: 13)
                // v1.3: required State right after Inspection address (list + rules from the shared JSON).
                if e.label == "Inspection address", WizardRules.hasStateField(store.config) {
                    StateFieldBlock(draft: $draft, errors: errors)
                }
            case "dynamic": dynamic(e)
            default: chips(e)
            }
        }
    }

    // MARK: fields

    private func text(_ label: String) -> Binding<String> {
        Binding(get: { draft.fields[label] ?? "" }, set: { draft.fields[label] = $0 })
    }

    @ViewBuilder
    private func field(_ e: WizardEntry, bottom: CGFloat) -> some View {
        switch e.type ?? "text" {
        case "date":
            DateFieldBox(label: e.label, value: text(e.label), format: "yyyy-MM-dd", components: .date, error: errors[e.label], minimumDate: minDate,
                         required: WizardRules.rule(for: e.label, type: e.type)?.required ?? false).padding(.bottom, bottom)
                .id(e.label)
        case "time":
            DateFieldBox(label: e.label, value: text(e.label), format: "HH:mm", components: .hourAndMinute).padding(.bottom, bottom)
        case "textarea":
            VTextArea(label: e.label, text: text(e.label), placeholder: e.placeholder ?? "")
        default:
            let kind = WizardRules.kind(for: e.label, type: e.type)
            let kb: UIKeyboardType = e.type == "email" ? .emailAddress : e.type == "tel" ? .phonePad :
                e.label.hasPrefix("Temperature") ? .numbersAndPunctuation :
                (["Year of construction", "Total sq ft", "Lot size (acres)", "Valuation ($)"].contains(e.label) ? .decimalPad : .default)
            let isAddress = e.label == "Inspection address"
            // The state now has its own field, so the address asks for "Street, City, ZIP" (prototype ca5ab5a;
            // vims-checklists.json v1.3 still carries the older "Street, City, State" placeholder).
            let placeholder = isAddress && WizardRules.hasStateField(store.config) ? "Street, City, ZIP" : (e.placeholder ?? "")
            VTextField(label: e.label, text: text(e.label), placeholder: placeholder, keyboard: kb,
                       contentType: e.type == "email" ? .emailAddress : e.type == "tel" ? .telephoneNumber : (isAddress ? .fullStreetAddress : nil),
                       capitalization: e.type == "email" ? .never : (kind == .license ? .characters : .words),
                       bottom: bottom, kind: kind ?? .plain(max: isAddress ? 120 : nil), fieldID: e.label, errors: errors,
                       required: WizardRules.rule(for: e.label, type: e.type)?.required ?? false)
            if e.label == "Real estate agent email" {
                Text("Client & agent emails are used to send the finished report.")
                    .font(VFont.ui(12)).foregroundStyle(VC.ink3)
                    .padding(.horizontal, 2).padding(.top, -2).padding(.bottom, 6)
                agentCopy
            }
        }
    }

    /// v1.4: "Send the report to the real estate agent" — set to the state's `agentCopyDefault` when the state
    /// changes (off for New Hampshire, whose rule note is shown under it); stored on the inspection.
    @ViewBuilder
    private var agentCopy: some View {
        CheckboxRow(label: "Send the report to the real estate agent",
                    isOn: Binding(get: { draft.sendsReportToAgent }, set: { draft.sendToAgent = $0 }))
            .padding(.horizontal, 2)
            .padding(.bottom, 6)
            .id("sendToAgent")
        if let rule = store.config.stateRule(draft.state), rule.agentCopyDefault == false, let note = rule.note {
            Text(note)
                .font(VFont.ui(12)).foregroundStyle(VC.signalDeep)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2).padding(.bottom, 10)
        }
    }

    // MARK: chips

    private func isInline(_ e: WizardEntry) -> Bool {
        let o = e.options ?? []
        return o.count <= 3 && o.allSatisfy { $0.count <= 7 }
    }

    @ViewBuilder
    private func chips(_ e: WizardEntry) -> some View {
        let opts = e.options ?? []
        if e.id == "wdepth" {
            SectionLabel(text: e.label)
            Text("Changes how much detail each section asks for. You can also set a default for new inspections in Settings.")
                .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.top, -4).padding(.bottom, 9)
                .fixedSize(horizontal: false, vertical: true)
            ChipGroup(options: opts, selection: Binding(get: { [draft.depth.label] }, set: { if let f = $0.first { draft.depth = Depth(label: f) } }),
                      single: true, required: true)
        } else if isInline(e) && e.label != "Weather & site conditions" {
            HStack(spacing: 8) {
                Text(e.label).font(VFont.ui(14.5, .semibold)).foregroundStyle(VC.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChipGroup(options: opts, selection: selection(e), single: e.single ?? true)
                    .fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VC.line, lineWidth: 1))
            .padding(.bottom, 9)
            .padding(.top, e.label == "Power is on" ? 14 : 0)
        } else {
            if e.label != "Weather & site conditions" { SectionLabel(text: e.label) }
            ChipGroup(options: opts, selection: selection(e), single: e.single ?? true)
                .padding(.bottom, e.label == "Weather & site conditions" ? 0 : 0)
            if e.id == "wstories", draft.fields[e.label] == "Other" {
                VTextArea(text: $draft.storiesOther, placeholder: "Describe what 'other' consists of (e.g. split-level, loft, partial third story)…")
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
    }

    /// The JSON typeFields carry no placeholders; these match the prototype.
    static let typeFieldPlaceholders = ["sponsorName": "Sponsor name", "sponsorLicense": "TREC license #",
                                        "insuredName": "Name on the insurance application", "policyNumber": "Policy or application number"]

    private func typeFormTitle(_ type: String) -> String {
        switch store.catalog.reportLayout(for: type) {
        case .texas: return "Texas TREC form"
        case .fourPoint: return "4-Point form"
        case .standard: return "\(type) form"
        }
    }

    private func selection(_ e: WizardEntry) -> Binding<[String]> {
        Binding(
            get: { (draft.fields[e.label] ?? "").split(separator: "|").map(String.init).filter { !$0.isEmpty } },
            set: { draft.fields[e.label] = $0.joined(separator: "|") })
    }

    // MARK: dynamic (type of inspection / property type)

    @ViewBuilder
    private func dynamic(_ e: WizardEntry) -> some View {
        let w = store.config.wizard
        if e.id == "wtype" {
            SectionLabel(text: e.label)
            ChipGroup(options: w.inspectionTypes, selection: Binding(get: { [draft.inspType] }, set: { if let f = $0.first { draft.inspType = f } }),
                      single: true, required: true)
            if draft.inspType == "Component" {
                SectionLabel(text: "Component(s) to inspect")
                ChipGroup(options: w.componentOptions, selection: Binding(
                    get: { draft.components.isEmpty ? [] : draft.components },
                    set: { draft.components = $0 }), single: false)
                    .onAppear { if draft.components.isEmpty, let f = w.componentOptions.first { draft.components = [f] } }
            }
            // wizard.typeFields — Texas: sponsor + sponsor TREC license; 4 Point: insured/applicant + policy #
            let tf = store.catalog.typeFields(for: draft.inspType)
            if !tf.isEmpty {
                SectionLabel(text: typeFormTitle(draft.inspType))
                ForEach(tf, id: \.key) { f in
                    VTextField(label: f.label, text: text(f.key), placeholder: f.placeholder ?? Self.typeFieldPlaceholders[f.key] ?? "",
                               capitalization: f.key.lowercased().contains("license") || f.key.lowercased().contains("number") ? .characters : .words,
                               kind: WizardRules.kind(for: f.key, type: nil), fieldID: f.key, errors: errors,
                               required: WizardRules.rule(for: f.key, type: nil)?.required ?? false)
                }
            }
        } else if e.id == "wstruct" {
            SectionLabel(text: e.label, top: 2)
            ChipGroup(options: w.structureTypes, selection: Binding(get: { [draft.structure] }, set: { v in
                guard let f = v.first else { return }
                draft.structure = f
                if let ext = w.structureSideEffects[f]?["exterior"], !draft.exterior.contains(ext) { draft.exterior.append(ext) }
                if f == "Multi-Unit", draft.unitMix.isEmpty { draft.unitMix = w.unitMixDefault }
            }), single: true, required: true)
            if draft.structure == "Multi-Unit" {
                SectionLabel(text: "Unit mix")
                ForEach(store.config.unitMixOrder, id: \.self) { k in
                    CounterRow(label: k, value: Binding(get: { draft.unitMix[k] ?? 0 }, set: { draft.unitMix[k] = $0 }), range: 0...99)
                }
            }
        }
    }
}

/// A form field that holds a date or time string and edits it with the system picker.
struct DateFieldBox: View {
    let label: String
    @Binding var value: String
    let format: String
    let components: DatePickerComponents
    var error: String? = nil
    var minimumDate: Date? = nil
    var required = false

    var body: some View {
        let selection = Binding(get: { Fmt.parse(value, format) ?? Date() }, set: { value = Fmt.date($0, format) })
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label, required: required)
            FieldBox(focused: false, error: error != nil) {
                Group {
                    if let minimumDate {
                        DatePicker(label, selection: selection, in: minimumDate..., displayedComponents: components)
                    } else {
                        DatePicker(label, selection: selection, displayedComponents: components)
                    }
                }
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Fmt.locale)
            }
            if let error { FieldError(text: error) }
        }
    }
}
