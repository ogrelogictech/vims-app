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
    @State private var picking = false
    @State private var preview: PreviewDoc?
    @State private var mailDraft: ReportReadyView.MailDraftItem?
    @State private var shareURL: ReportReadyView.ShareItem?

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
            if let error { FieldError(text: error) }
        }
        .padding(.bottom, 13)
        .id(StateFieldIDs.state)
        .sheet(isPresented: $picking) {
            StatePickerSheet(states: cfg.states ?? [], selected: draft.state) { code in
                draft.setState(code, config: cfg)
                errors.set(StateFieldIDs.state, nil)
                errors.set(StateFieldIDs.docsAck, nil)
                picking = false
            }
        }

        if let rule = cfg.stateRule(draft.state) {
            ruleCard(rule)
                .padding(.top, -2).padding(.bottom, 14)
                .sheet(item: $preview) { doc in PDFPreviewSheet(doc: doc) }
                .sheet(item: $mailDraft) { item in
                    MailComposeView(draft: item.draft) { result in
                        mailDraft = nil
                        if result == .sent { store.toast("Sent to the client with the inspection agreement") }
                        else if result == .saved { store.toast("Saved to Drafts") }
                    }
                    .ignoresSafeArea()
                }
                .sheet(item: $shareURL) { item in
                    ActivityView(items: [item.url]).presentationDetents([.medium, .large])
                }
        }
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
            shareURL = .init(url: (try? FileManager.default.copyItem(at: url, to: named)) != nil ? named : url)
        }
    }
}

/// Searchable list of `states` (50 + DC).
struct StatePickerSheet: View {
    let states: [StateDef]
    let selected: String?
    let pick: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [StateDef] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return states }
        return states.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.code.caseInsensitiveCompare(q) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
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
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search states")
            .navigationTitle("State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
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
