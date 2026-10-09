import SwiftUI
import QuickLook

// VIMS default inspection agreement (shared/legal/inspection-agreement.json, data v1.4) — prototype
// #s-agreementdoc (renderAgreement). Text is rendered verbatim; `{companyName}` → the signed-in company's name.

/// "Inspection agreement" screen. `stateCode == nil` (Company profile) lists every state's disclosure;
/// a code (wizard step 1) shows only that state's entry, or "No additional disclosures for <State>."
/// A company using its edited copy sees that text instead (in full — it can't be filtered by state).
/// The header's share button downloads exactly what's shown as a PDF (every user).
struct InspectionAgreementView: View {
    @Environment(AppStore.self) private var store
    let stateCode: String?
    @State private var quickLook: URL?
    @State private var jump = FormErrors()     // only used for the DEBUG -agreementScroll jump
    @State private var shareAnchor = PopoverAnchor()

    /// What's on screen (and in the download): the edited copy, else the VIMS agreement; nil if it can't be loaded.
    private var content: AgreementContent? {
        if store.agreementInUse == .edited, let text = store.company.agreementText {
            return .edited(text, company: store.company.name)
        }
        return InspectionAgreement.bundled.map {
            AgreementContent.vims($0, company: store.company.name, stateCode: stateCode, stateName: stateName)
        }
    }

    var body: some View {
        let content = content
        Screen(title: "Inspection agreement", subtitle: store.company.name,
               actions: (content == nil ? [] : [HeaderAction(symbol: "upload-logo-png", label: "Download agreement PDF", anchor: shareAnchor) { download() }])
                        + [store.homeAction()],
               errors: jump) {
            if let content {
                document(content)
            } else {
                Text("The VIMS inspection agreement couldn't be loaded.")
                    .font(VFont.ui(13)).foregroundStyle(VC.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vCard()
            }
        }
        .quickLookPreview($quickLook)
        #if DEBUG
        .task {
            // -agreementScroll disclosures: scroll to the state disclosures (review screenshots).
            // -openShare: tap Download (share-sheet anchor check on iPad).
            try? await Task.sleep(nanoseconds: 500_000_000)
            if DebugLaunch.value("-agreementScroll") != nil { jump.scrollTarget = "agreement-disclosures" }
            if DebugFlags.openShare { DebugFlags.openShare = false; download() }
        }
        #endif
    }

    private func stateName(_ code: String) -> String { store.config.stateName(code) ?? code }

    /// Renders what's shown into "Inspection-Agreement-<Company>.pdf" and opens the share sheet
    /// (Save to Files, Mail, AirDrop, Print). On iPad the sheet points at the header button.
    private func download() {
        guard let content, let url = AgreementPDF.write(content, company: store.company.name) else {
            store.toast("Couldn't create the agreement PDF"); return
        }
        ShareSheet.present([url], from: shareAnchor, title: "Share agreement")
    }

    private func document(_ content: AgreementContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch store.agreementInUse {
            case .uploaded:
                if let own = store.company.agreementName { ownNotice(own) }
            case .edited:
                Text("Your company\u{2019}s edited version of the VIMS agreement.")
                    .font(VFont.ui(13)).foregroundStyle(VC.signalDeep).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            case .vims:
                EmptyView()
            }
            ForEach(Array(content.blocks.enumerated()), id: \.offset) { _, b in block(b) }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
    }

    /// The company uses its own uploaded agreement: say so, and offer to open their file.
    private func ownNotice(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("Your company uses its own agreement (") + Text(name).bold() + Text("). Below is the VIMS agreement for reference."))
                .font(VFont.ui(13)).foregroundStyle(VC.signalDeep).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let url = store.ownAgreementURL {
                Button { quickLook = url } label: { IconLabel("Open your agreement", icon: "file", iconSize: 16) }
                    .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 44, fullWidth: false))
                    .font(VFont.ui(13.5, .semibold))
                    .accessibilityLabel("Open your agreement, \(name)")
            }
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func block(_ b: AgreementContent.Block) -> some View {
        switch b {
        case .title(let t):
            Text(t)
                .font(VFont.display(18, .heavy)).foregroundStyle(VC.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 10)
        case .form(let lines):
            Text(lines.joined(separator: "\n"))
                .font(VFont.mono(11.5)).foregroundStyle(VC.ink2)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(VC.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(VC.line, lineWidth: 1))
                .padding(.bottom, 12)
        case .paragraph(let t, let lead):
            paragraph(t, color: lead ? VC.ink : VC.ink2)   // lead → ink color (prototype)
        case .bullet(let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\u{2022}").font(VFont.ui(13)).foregroundStyle(VC.ink2)
                paragraph(t, color: VC.ink2, bottom: 0)
            }
            .padding(.leading, 4).padding(.bottom, 9)
        case .heading(let t):
            Text(t)
                .font(VFont.display(14, .bold)).foregroundStyle(VC.brandDeep)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 14).padding(.bottom, 8)
                .id("agreement-disclosures")
        case .disclosure(let state, let text):
            (Text("\(state): ").font(VFont.ui(13, .bold)).foregroundColor(VC.ink) + Text(text))
                .font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 9)
        case .note(let t):
            Text(t)
                .font(VFont.ui(12)).foregroundStyle(VC.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 9)
        }
    }

    private func paragraph(_ text: String, color: Color, weight: VWeight = .regular, bottom: CGFloat = 9) -> some View {
        Text(text)
            .font(VFont.ui(13, weight)).foregroundStyle(color).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, bottom)
    }
}

/// Company profile → "Inspection agreement" card: the VIMS agreement by default, the company's edited copy of it,
/// or its own upload. Edit / Upload / Replace / Use VIMS agreement are for company admins only.
struct AgreementCard: View {
    @Environment(AppStore.self) private var store
    let upload: () -> Void
    @State private var confirmRevert = false

    var body: some View {
        let mode = store.agreementInUse
        HStack(spacing: 12) {
            LeadIcon(symbol: "no-agreement-uploaded")
            VStack(alignment: .leading, spacing: 2) {
                Text(title(mode)).font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                    .lineLimit(1).truncationMode(.middle)
                // "All 50 states · in use · View · Edit": one line when it fits, else the links wrap under the
                // status (real buttons, so they're easy tap targets).
                FlowLayout(spacing: 0, lineSpacing: 0) {
                    Text(status(mode)).font(VFont.ui(12)).foregroundStyle(VC.ink3).fixedSize()
                    ForEach(links(mode), id: \.title) { l in
                        HStack(spacing: 0) {
                            dot
                            Button(l.title, action: l.action)
                                .buttonStyle(InlineLinkStyle())
                                .fixedSize()
                                .accessibilityHint(l.hint)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if store.isAdmin {
                Button(mode == .uploaded ? "Replace" : "Upload your own") { upload() }
                    .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 44, fullWidth: false))
                    .fixedSize()
            }
        }
        // Going back to the VIMS agreement deletes an edited version, so ask first (an upload just switches back).
        .confirmationDialog("Use the VIMS agreement?", isPresented: $confirmRevert, titleVisibility: .visible) {
            Button("Use VIMS", role: .destructive) { store.useDefaultAgreement() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your company\u{2019}s edited version of the agreement will be deleted.") }
    }

    private var dot: some View { Text(" \u{00B7} ").font(VFont.ui(12)).foregroundStyle(VC.ink3) }
}

extension AgreementCard {
    struct CardLink { let title: String; let hint: String; let action: () -> Void }

    func title(_ mode: AppStore.AgreementInUse) -> String {
        switch mode {
        case .vims: return "VIMS agreement"
        case .edited: return "Edited VIMS agreement"
        case .uploaded: return store.company.agreementName ?? "Your agreement"
        }
    }

    func status(_ mode: AppStore.AgreementInUse) -> String {
        switch mode {
        case .vims: return "All 50 states \u{00B7} in use"
        case .edited: return "Your edited version \u{00B7} in use"
        case .uploaded: return "Your agreement \u{00B7} in use"
        }
    }

    func links(_ mode: AppStore.AgreementInUse) -> [CardLink] {
        let view = CardLink(title: "View", hint: mode == .edited ? "Opens your edited agreement" : "Opens the VIMS agreement") {
            store.push(.agreement(state: nil))
        }
        let edit = CardLink(title: "Edit", hint: "Edit your company\u{2019}s copy of the agreement") { store.push(.agreementEditor) }
        let revert = CardLink(title: "Use VIMS agreement", hint: "Switches back to the VIMS agreement") {
            if mode == .edited { confirmRevert = true } else { store.useDefaultAgreement() }
        }
        switch mode {
        case .vims: return store.isAdmin ? [view, edit] : [view]
        case .edited: return store.isAdmin ? [view, edit, revert] : [view]
        case .uploaded: return store.isAdmin ? [revert] : []
        }
    }
}

/// Company admins: "Edit agreement" — the company's copy of the VIMS agreement as plain text (the VIMS text with the
/// company name filled in, or their earlier edit). Saving makes it the company's agreement; the VIMS agreement
/// itself never changes for anyone else.
struct AgreementEditorView: View {
    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var original = ""
    @State private var loaded = false
    @State private var errors = FormErrors()
    @State private var confirmDiscard = false
    @FocusState private var focused: Bool

    private var dirty: Bool { loaded && text != original }

    var body: some View {
        Screen(title: "Edit agreement", subtitle: store.company.name,
               onLeading: { leave() }, actions: [], scroll: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your company\u{2019}s copy of the VIMS agreement. Separate paragraphs with a blank line and start a line with \u{2022} for a bullet. The VIMS agreement itself doesn\u{2019}t change.")
                    .font(VFont.ui(12.5)).foregroundStyle(VC.ink3).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                FieldBox(focused: focused, minHeight: 200, error: errors["text"] != nil) {
                    TextEditor(text: $text)
                        .font(VFont.ui(14)).foregroundStyle(VC.ink)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .padding(.horizontal, -5).padding(.vertical, -8)   // TextEditor's own inset
                        .frame(maxHeight: .infinity)
                        .accessibilityLabel("Agreement text")
                        .onChange(of: text) { _, _ in if errors["text"] != nil { errors.clear() } }
                }
                .frame(maxHeight: .infinity)
                HStack {
                    if let e = errors["text"] { FieldError(text: e) }
                    Spacer(minLength: 8)
                    Text("\(Fmt.grouped(Double(text.count))) / \(Fmt.grouped(Double(AgreementContent.maxEditedLength)))")
                        .font(VFont.mono(11)).foregroundStyle(text.count > AgreementContent.maxEditedLength ? VC.c1 : VC.ink3)
                }
                .padding(.top, 6).padding(.bottom, 10)
                HStack(spacing: 10) {
                    Button("Cancel") { leave() }.buttonStyle(.vGhost)
                    Button { save() } label: { IconLabel("Save agreement", icon: "link-my-account") }
                        .buttonStyle(.vPrimary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            .readableColumn()
        }
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { store.back() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Your edits to the agreement haven\u{2019}t been saved.") }
        .onAppear {
            guard !loaded else { return }
            let start = store.company.agreementText ?? store.vimsAgreementPlainText ?? ""
            text = start
            original = start
            loaded = true
            #if DEBUG
            // -validate: try to save an empty agreement once (error state for review screenshots).
            if DebugFlags.validate { DebugFlags.validate = false; text = ""; save() }
            #endif
        }
    }

    private func leave() {
        focused = false
        if dirty { confirmDiscard = true } else { store.back() }
    }

    private func save() {
        // Same messages as Android.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { errors.set("text", "Enter the agreement text"); return }
        if text.count > AgreementContent.maxEditedLength {
            errors.set("text", "Keep the agreement under \(Fmt.grouped(Double(AgreementContent.maxEditedLength))) characters (now \(Fmt.grouped(Double(text.count))))")
            return
        }
        errors.clear()
        focused = false
        if text == original { store.toast("No changes to save"); return }
        store.saveEditedAgreement(trimmed)
        original = text
        store.back()
    }
}

/// Brand-colored inline text link with an enlarged hit area (prototype `<a style="color:var(--brand);font-weight:600">`).
struct InlineLinkStyle: ButtonStyle {
    var size: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VFont.ui(size, .semibold))
            .foregroundStyle(VC.brand.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(minHeight: 28)
            .contentShape(Rectangle().inset(by: -8))
    }
}

/// Step-style checkbox row (22-pt box, 44-pt tall row), used by "Send the report to the real estate agent".
struct CheckboxRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? VC.brand : VC.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isOn ? VC.brand : VC.ink3, lineWidth: 1.5))
                    .overlay { if isOn { ProtoIcon("check", size: 15, lineWidth: 3).foregroundStyle(.white) } }
                    .frame(width: 22, height: 22)
                Text(label)
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
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Checked" : "Not checked")
        .accessibilityAddTraits(.isToggle)
    }
}
