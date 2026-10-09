import SwiftUI
import MessageUI

// Data v1.3 — property State (wizard step 1) and `stateRules` (TX / OK / OR / LA). Everything shown here
// (state list, notes, disclosures, documents) comes from shared/data/vims-checklists.json; the PDFs from
// shared/legal/state (SharedLegal synchronized group).

enum StateFieldIDs {
    static let state = "State"
    static let docsAck = "stateDocsAck"
    static let stateError = "Select the property's state"
    static let docsAckError = "Confirm the required state notice was given to the client"
    static let placeholder = "Select the property\u{2019}s state\u{2026}"
    static let ackLabel = "Provided to the client with the inspection agreement"
}

/// Wizard step 1: required "State" picker + the state's rule card (note, documents, acknowledgment).
struct StateFieldBlock: View {
    @Environment(AppStore.self) private var store
    @Binding var draft: Inspection
    let errors: FormErrors
    /// Wizard Return / Next chain: Return on Inspection address opens this picker; a pick moves on to `nextField`.
    var focus: FocusChain? = nil
    var nextField: String? = nil
    @State private var picking = false
    @State private var picked = false
    @State private var preview: PreviewDoc?
    @State private var mailDraft: ReportReadyView.MailDraftItem?
    @State private var sendAnchors = PopoverAnchors()

    var body: some View {
        let cfg = store.config
        let name = cfg.stateName(draft.state)
        let error = errors[StateFieldIDs.state]
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: "State", required: true)
            Button { endEditing(); picking = true } label: {
                FieldBox(focused: false, error: error != nil) {
                    HStack(spacing: 8) {
                        Text(name ?? StateFieldIDs.placeholder)
                            .foregroundStyle(name == nil ? VC.placeholder : VC.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProtoIcon("chevron-right", size: 17).foregroundStyle(VC.ink3).rotationEffect(.degrees(90))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("State, required")
            .accessibilityValue(name ?? "Not selected")
            .accessibilityHint("Opens the list of states")
            // iPhone: the full-height sheet. iPad: a popover hanging off this field.
            .pickerPresentation(isPresented: $picking, padSize: CGSize(width: 420, height: 600)) {
                StatePickerSheet(states: cfg.states ?? [], selected: draft.state) { code in
                    draft.setState(code, config: cfg)
                    errors.set(StateFieldIDs.state, nil)
                    errors.set(StateFieldIDs.docsAck, nil)
                    picked = true
                    picking = false
                }
            }
            if let error { FieldError(text: error) }
        }
        .padding(.bottom, 13)
        .id(StateFieldIDs.state)
        // Return on Inspection address → open the picker (its search field takes the keyboard).
        .onChange(of: focus?.target) { _, target in
            guard target == StateFieldIDs.state else { return }
            focus?.target = nil
            endEditing()
            picking = true
        }
        // A state was picked → move on to the next field once the sheet / popover has gone.
        .onChange(of: picking) { _, open in
            guard !open, picked else { return }
            picked = false
            guard let next = nextField, let focus else { return }
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                focus.target = next
            }
        }
        .task {
            guard DebugFlags.openStatePicker else { return }
            DebugFlags.openStatePicker = false
            try? await Task.sleep(nanoseconds: 600_000_000)
            picking = true
        }

        if let rule = cfg.stateRule(draft.state) {
            ruleCard(rule)
                .padding(.top, -2).padding(.bottom, 14)
                .documentCover(item: $preview) { doc in PDFPreviewSheet(doc: doc) }
                .sheet(item: $mailDraft) { item in
                    MailComposeView(draft: item.draft) { result in
                        mailDraft = nil
                        if result == .sent { store.toast("Sent to the client with the inspection agreement") }
                        else if result == .saved { store.toast("Saved to Drafts") }
                    }
                    .ignoresSafeArea()
                }
        }
        agreementLine
    }

    /// v1.4: "Inspection agreement: View (shows the selected state's section)" → the VIMS agreement viewer,
    /// filtered to the picked state (every state when none is picked yet).
    private var agreementLine: some View {
        var text = AttributedString("Inspection agreement: ")
        var link = AttributedString("View")
        link.link = URL(string: "vims://agreement")
        link.foregroundColor = VC.brand
        link.font = VFont.ui(12.5, .semibold)
        text += link
        // An edited agreement can't be filtered by state, so don't promise the state's section then.
        let edited = store.agreementInUse == .edited
        text += AttributedString(edited ? " (your company\u{2019}s edited version)" : " (shows the selected state\u{2019}s section)")
        return Text(text)
            .font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { endEditing(); store.push(.agreement(state: draft.state)) }
            .environment(\.openURL, OpenURLAction { _ in
                endEditing(); store.push(.agreement(state: draft.state))
                return .handled
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Inspection agreement: View")
            .accessibilityHint(store.agreementInUse == .edited ? "Shows your company's edited agreement"
                               : draft.state == nil ? "Shows every state's section" : "Shows the selected state's section")
            .accessibilityAddTraits(.isLink)
            .padding(.horizontal, 2).padding(.top, -4).padding(.bottom, 14)
            .id("agreementLine")
    }

    @ViewBuilder
    private func ruleCard(_ rule: StateRuleDef) -> some View {
        let docs = rule.requiredDocs
        HStack(spacing: 0) {
            Rectangle().fill(VC.brand).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                if let note = rule.note {
                    Text(note).font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(docs, id: \.file) { doc in docRow(doc) }
                if !docs.isEmpty { ackCheckbox(docs) }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VC.line, lineWidth: 1))
    }

    private func docRow(_ doc: StateDocDef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(doc.name).font(VFont.ui(13, .bold)).foregroundStyle(VC.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { view(doc) } label: { IconLabel("View", icon: "preview-report-format", iconSize: 16) }
                    .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 44))
                    .accessibilityLabel("View \(doc.name)")
                Button { send(doc) } label: { IconLabel("Send to client", icon: "email-to-client", iconSize: 16) }
                    .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 44))
                    .popoverAnchor(sendAnchors[doc.file])
                    .accessibilityLabel("Send \(doc.name) to the client")
            }
            .font(VFont.ui(13.5, .semibold))
        }
        .padding(.top, 12)
    }

    private func ackCheckbox(_ docs: [StateDocDef]) -> some View {
        let on = draft.stateDocsAck?.state == draft.state && draft.state != nil
        let error = errors[StateFieldIDs.docsAck]
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if on { draft.stateDocsAck = nil } else if let st = draft.state {
                    draft.stateDocsAck = StateDocsAck(state: st, docs: docs.map(\.name), acknowledgedAt: Date())
                    errors.set(StateFieldIDs.docsAck, nil)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? VC.brand : VC.paper)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(error != nil ? VC.c1 : (on ? VC.brand : VC.ink3), lineWidth: error != nil ? 2 : 1.5))
                        .overlay { if on { ProtoIcon("check", size: 15, lineWidth: 3).foregroundStyle(.white) } }
                        .frame(width: 22, height: 22)
                    Text(StateFieldIDs.ackLabel)
                        .font(VFont.ui(13.5)).foregroundStyle(VC.ink).lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 1)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(StateFieldIDs.ackLabel)
            .accessibilityValue(on ? "Checked" : "Not checked")
            .accessibilityAddTraits(.isToggle)
            if let error { FieldError(text: error).padding(.leading, 32) }
        }
        .padding(.top, 8)
        .id(StateFieldIDs.docsAck)
    }

    /// Drop the keyboard before a sheet opens, so dismissing it doesn't refocus (and scroll to) the last field.
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func view(_ doc: StateDocDef) {
        endEditing()
        guard let url = doc.bundleURL else { store.toast("Document not found"); return }
        preview = PreviewDoc(url: url, title: doc.name)
    }

    /// Mail composer to the client email with the PDF attached; the share sheet when Mail isn't set up.
    /// TODO(backend): send from the server with the inspection agreement.
    private func send(_ doc: StateDocDef) {
        endEditing()
        guard let url = doc.bundleURL else { store.toast("Document not found"); return }
        if MFMailComposeViewController.canSendMail() {
            mailDraft = .init(draft: ReportMailDraft.stateDocument(doc, pdf: url, insp: draft, company: store.company,
                                                                   sender: store.session?.name ?? ""))
        } else {
            let named = FileManager.default.temporaryDirectory.appendingPathComponent("\(doc.name.replacingOccurrences(of: "/", with: "-")).pdf")
            try? FileManager.default.removeItem(at: named)
            ShareSheet.present([(try? FileManager.default.copyItem(at: url, to: named)) != nil ? named : url], from: sendAnchors[doc.file])
        }
    }
}

/// Searchable list of `states` (50 + DC).
struct StatePickerSheet: View {
    let states: [StateDef]
    let selected: String?
    let pick: (String) -> Void
    @State private var query = ""
    /// The search field has the keyboard as soon as the picker opens (iPhone: the bar's search field).
    @State private var searchActive = false
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// Typing a 2-letter code or a name jumps that state to the top: exact code / name, then names starting with
    /// the text, then a word starting with it ("york" → New York), then names containing it. Return picks the top one.
    private var filtered: [StateDef] { Self.matches(states, query) }

    static func matches(_ states: [StateDef], _ query: String) -> [StateDef] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return states }
        func rank(_ s: StateDef) -> Int? {
            let name = s.name.lowercased()
            if s.code.lowercased() == q || name == q { return 0 }
            if name.hasPrefix(q) { return 1 }
            if name.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 2 }
            if name.contains(q) { return 3 }
            return nil
        }
        return states.enumerated()
            .compactMap { i, s in rank(s).map { (s, $0, i) } }
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .map(\.0)
    }

    private func pickTop() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty, let top = filtered.first else { return }
        pick(top.code)
    }

    var body: some View {
        if Device.isPad { popoverBody } else { sheetBody }
    }

    /// iPad popover: its own search field + list (a NavigationStack's bar doesn't lay out inside a popover).
    private var popoverBody: some View {
        VStack(spacing: 0) {
            FieldBox(focused: false, minHeight: 44) {
                HStack(spacing: 8) {
                    ProtoIcon("search", size: 16).foregroundStyle(VC.ink3)
                    TextField("", text: $query, prompt: Text("Search states").foregroundStyle(VC.placeholder))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($searchFocused)
                        .onSubmit(pickTop)
                        .accessibilityLabel("Search states")
                }
            }
            .padding(12)
            Rectangle().fill(VC.line).frame(height: 1)
            list
        }
        .background(VC.paper)
        .onAppear { searchFocused = true }
        .task {
            // Again once the popover has finished presenting, in case the first request came too early.
            try? await Task.sleep(nanoseconds: 350_000_000)
            searchFocused = true
        }
    }

    private var sheetBody: some View {
        NavigationStack {
            list
            .searchable(text: $query, isPresented: $searchActive, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search states")
            .onSubmit(of: .search, pickTop)
            .onAppear { searchActive = true }
            .task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                searchActive = true
            }
            .navigationTitle("State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private var list: some View {
            List(filtered, id: \.code) { s in
                Button { pick(s.code) } label: {
                    HStack {
                        Text(s.name).font(VFont.ui(15)).foregroundStyle(VC.ink)
                        Spacer()
                        Text(s.code).font(VFont.mono(12.5, .semibold)).foregroundStyle(VC.ink3)
                        if s.code == selected {
                            ProtoIcon("link-my-account", size: 16).foregroundStyle(VC.brand)
                        }
                    }
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(VC.paper)
                .accessibilityAddTraits(s.code == selected ? .isSelected : [])
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(VC.paper)
    }
}

/// Summary screen: the state's permanent disclosure (stateRules[state].summaryDisclosure, e.g. Oklahoma).
struct StateDisclosureCard: View {
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(VC.signal).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(VFont.ui(13, .bold)).foregroundStyle(VC.ink)
                Text(text).font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
