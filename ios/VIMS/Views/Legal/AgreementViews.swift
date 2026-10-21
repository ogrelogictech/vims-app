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
        if let edited = store.editedAgreementContent { return edited }
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
    /// QA Oct 14: the uploaded agreement (PDF, Word or an image) opens in Quick Look from the card.
    @State private var quickLook: URL?

    var body: some View {
        let mode = store.agreementInUse
        HStack(spacing: 12) {
            LeadIcon(symbol: "no-agreement-uploaded")
            VStack(alignment: .leading, spacing: 2) {
                Text(title(mode)).font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                    .lineLimit(mode == .uploaded ? 1 : 2).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                // "All 50 states · in use · View · Edit" on one line when it fits; otherwise the status, then the
                // links on the line(s) below (real buttons, so they're easy tap targets).
                let linkList = links(mode)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        statusText(mode).fixedSize()
                        ForEach(linkList, id: \.title) { l in dot; linkButton(l) }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        statusText(mode).fixedSize(horizontal: false, vertical: true)
                        // "View · Edit", then "Use VIMS agreement" on its own line (no line starts with a dot).
                        let main = linkList.filter { !$0.isRevert }
                        if !main.isEmpty {
                            HStack(spacing: 0) {
                                ForEach(Array(main.enumerated()), id: \.element.title) { i, l in
                                    if i > 0 { dot }
                                    linkButton(l)
                                }
                            }
                        }
                        ForEach(linkList.filter(\.isRevert), id: \.title) { linkButton($0) }
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
        .quickLookPreview($quickLook)
    }

    /// Quick Look the company's uploaded agreement file (toast when the file is gone).
    func openOwn() {
        if let url = store.ownAgreementURL { quickLook = url } else { store.toast("The agreement file is missing — upload it again") }
    }

    private var dot: some View { Text(" \u{00B7} ").font(VFont.ui(12)).foregroundStyle(VC.ink3).frame(minHeight: 28) }

    /// Same 28-pt line box as the links, so the baselines line up.
    private func statusText(_ mode: AppStore.AgreementInUse) -> some View {
        Text(status(mode)).font(VFont.ui(12)).foregroundStyle(VC.ink3).frame(minHeight: 28, alignment: .leading)
    }

    private func linkButton(_ l: CardLink) -> some View {
        Button(l.title, action: l.action)
            .buttonStyle(InlineLinkStyle())
            .fixedSize()
            .accessibilityHint(l.hint)
    }
}

extension AgreementCard {
    struct CardLink {
        let title: String
        let hint: String
        let action: () -> Void
        var isRevert: Bool { title == "Use VIMS agreement" }
    }

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
        let open = CardLink(title: "Open", hint: "Opens your company\u{2019}s agreement file") { openOwn() }
        let revert = CardLink(title: "Use VIMS agreement", hint: "Switches back to the VIMS agreement") {
            if mode == .edited { confirmRevert = true } else { store.useDefaultAgreement() }
        }
        switch mode {
        case .vims: return store.isAdmin ? [view, edit] : [view]
        case .edited: return store.isAdmin ? [view, edit, revert] : [view]
        case .uploaded: return store.isAdmin ? [open, revert] : [open]
        }
    }
}

/// Company admins: "Edit agreement" — a block editor over the company's copy of the VIMS agreement (Oct 13 2026). The
/// agreement is shown as the viewer's blocks (title, form, paragraphs, bullets, disclosures heading, state disclosures,
/// closing). The form block and every block with fill-in blanks ("___") or checkboxes (☐) is LOCKED: read-only with a
/// "Locked" tag, can't be deleted. Every other block is a multi-line text box with Delete (asks first) and "Add
/// paragraph" after it; "Add paragraph" at the end too. Save stores the blocks as JSON (`EditedAgreement`) in
/// `CompanyProfile.agreementText`; an edit saved by an earlier build (plain text) loads into blocks. The VIMS agreement
/// itself never changes for anyone else. No fill-in / tappable checkboxes (the deferred e-sign add-on).
struct AgreementEditorView: View {
    @Environment(AppStore.self) private var store
    @State private var blocks: [AgreementEditorBlock] = []
    @State private var original: [AgreementContent.Block] = []
    @State private var loaded = false
    @State private var errors = FormErrors()
    @State private var confirmDiscard = false
    @State private var scrollTo: UUID?
    @FocusState private var focused: UUID?

    private var dirty: Bool { loaded && blocks.map(\.block) != original }
    private var characterCount: Int { blocks.reduce(0) { $0 + ($1.block.editableText?.count ?? 0) } }

    var body: some View {
        Screen(title: "Edit agreement", subtitle: store.company.name,
               onLeading: { leave() }, actions: [], scroll: false) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Your company\u{2019}s copy of the VIMS agreement. Edit any paragraph, delete one, or add your own. Blocks with fill-in lines or checkboxes are locked. The VIMS agreement itself doesn\u{2019}t change.")
                                .font(VFont.ui(12.5)).foregroundStyle(VC.ink3).lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 12)
                            ForEach($blocks) { $b in
                                AgreementBlockCard(item: $b, focused: $focused, error: errors[b.errorID],
                                                   addAfter: { addParagraph(after: b.id) },
                                                   delete: { delete(b.id) })
                                    .id(b.id)
                            }
                            Button { addParagraph(after: nil) } label: { IconLabel("Add paragraph", icon: "hdr-add") }
                                .buttonStyle(.vGhost)
                                .padding(.top, 2)
                                .accessibilityHint("Adds a paragraph at the end of the agreement")
                        }
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 24)
                        .readableColumn(wideMax: PadLayout.documentWidth)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: scrollTo) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                        scrollTo = nil
                    }
                }
                bottomBar
            }
        }
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { store.back() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Your edits to the agreement haven\u{2019}t been saved.") }
        .onChange(of: dirty) { _, d in SwipeBack.blocked = d }
        .onChange(of: blocks.map(\.block)) { _, _ in
            // Once Save has flagged blanks, the highlights follow the edits (a filled-in block clears at once).
            guard errors["text"] != nil else { return }
            let blanks = blankErrors()
            if blanks.isEmpty { errors.clear() } else {
                errors.map = blanks
                errors.map["text"] = blanks.count == 1 ? "Fill in or delete the highlighted block" : "Fill in or delete the \(blanks.count) highlighted blocks"
            }
        }
        .onDisappear { SwipeBack.blocked = false }
        .onAppear {
            guard !loaded else { return }
            let start = startBlocks()
            blocks = start.map { AgreementEditorBlock(block: $0) }
            original = start
            loaded = true
            #if DEBUG
            // -validate: blank the title and the first paragraph, then Save (blank-block highlights for review screenshots).
            if DebugFlags.validate {
                DebugFlags.validate = false
                for i in blocks.indices.filter({ !blocks[$0].locked }).prefix(2) { blocks[i].block = blocks[i].block.withText("") }
                Task { try? await Task.sleep(nanoseconds: 300_000_000); save() }   // after the edit's onChange
            }
            // -agreementScroll first|last|<n>: scroll the editor (review screenshots).
            if let v = DebugLaunch.value("-agreementScroll"), !blocks.isEmpty {
                let i = v == "last" ? blocks.count - 1 : (Int(v) ?? 0)
                let id = blocks[min(max(0, i), blocks.count - 1)].id
                Task { try? await Task.sleep(nanoseconds: 400_000_000); scrollTo = id }
            }
            #endif
        }
    }

    /// The company's edited agreement (blocks JSON, or plain text from an earlier build), else the VIMS agreement with the
    /// company name filled and every state's disclosure.
    private func startBlocks() -> [AgreementContent.Block] {
        let form = store.agreementFormLines
        let content: AgreementContent?
        if let t = store.company.agreementText, !t.isEmpty {
            content = AgreementContent.edited(t, company: store.company.name, form: form)
        } else {
            content = InspectionAgreement.bundled.map {
                AgreementContent.vims($0, company: store.company.name, stateCode: nil, stateName: { store.config.stateName($0) ?? $0 })
            }
        }
        return (content?.blocks ?? []).filter { if case .note = $0 { return false } else { return true } }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                if let e = errors["text"] { FieldError(text: e) }
                Spacer(minLength: 8)
                Text("\(Fmt.grouped(Double(characterCount))) / \(Fmt.grouped(Double(AgreementContent.maxEditedLength)))")
                    .font(VFont.mono(11)).foregroundStyle(characterCount > AgreementContent.maxEditedLength ? VC.c1 : VC.ink3)
                    .accessibilityLabel("\(characterCount) of \(AgreementContent.maxEditedLength) characters")
            }
            .padding(.bottom, 8)
            HStack(spacing: 10) {
                Button("Cancel") { leave() }.buttonStyle(.vGhost)
                Button { save() } label: { IconLabel("Save agreement", icon: "link-my-account") }
                    .buttonStyle(.vPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .readableColumn(wideMax: PadLayout.documentWidth)
        .frame(maxWidth: .infinity)
        .background(VC.paper2)
        .overlay(alignment: .top) { Rectangle().fill(VC.line).frame(height: 1) }
    }

    private func addParagraph(after id: UUID?) {
        let new = AgreementEditorBlock(block: .paragraph("", lead: false))
        if let id, var i = blocks.firstIndex(where: { $0.id == id }) {
            // The locked form block always sits right under the title, so "add after the title" lands below the form.
            if case .title = blocks[i].block, i + 1 < blocks.count, case .form = blocks[i + 1].block { i += 1 }
            blocks.insert(new, at: i + 1)
        } else {
            blocks.append(new)
        }
        scrollTo = new.id
        Task { try? await Task.sleep(nanoseconds: 300_000_000); focused = new.id }
    }

    private func delete(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }), !blocks[i].locked else { return }
        if focused == id { focused = nil }
        _ = withAnimation(.easeInOut(duration: 0.2)) { blocks.remove(at: i) }
    }

    private func leave() {
        focused = nil
        if dirty { confirmDiscard = true } else { store.back() }
    }

    /// Editable blocks left blank: each is highlighted with its own message (same rule as Android — fill it in or delete it).
    private func blankErrors() -> [String: String] {
        var out: [String: String] = [:]
        for b in blocks where !b.locked && (b.block.editableText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if case .title = b.block { out[b.errorID] = "Enter a title" } else { out[b.errorID] = "Enter text or delete this block" }
        }
        return out
    }

    private func save() {
        let blanks = blankErrors()
        if !blanks.isEmpty {
            errors.map = blanks
            errors.map["text"] = blanks.count == 1 ? "Fill in or delete the highlighted block" : "Fill in or delete the \(blanks.count) highlighted blocks"
            scrollTo = blocks.first { blanks[$0.errorID] != nil }?.id
            return
        }
        let out: [AgreementContent.Block] = blocks.map { b in
            guard !b.locked, let t = b.block.editableText else { return b.block }
            return b.block.withText(t.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if characterCount > AgreementContent.maxEditedLength {
            errors.set("text", "Keep the agreement under \(Fmt.grouped(Double(AgreementContent.maxEditedLength))) characters (now \(Fmt.grouped(Double(characterCount))))")
            return
        }
        errors.clear()
        focused = nil
        if out == original { store.toast("No changes to save"); return }
        store.saveEditedAgreement(EditedAgreement(blocks: out).encoded)
        original = out
        blocks = out.map { AgreementEditorBlock(block: $0) }
        store.back()
    }
}

/// One block in "Edit agreement". `locked` is decided when the block is loaded (typing "___" into a paragraph doesn't
/// lock it mid-edit).
struct AgreementEditorBlock: Identifiable, Equatable {
    let id = UUID()
    var block: AgreementContent.Block
    let locked: Bool

    init(block: AgreementContent.Block) {
        self.block = block
        locked = block.isLocked
    }

    var errorID: String { "block-\(id.uuidString)" }
}

/// A block card: label + "Locked" tag and the read-only text, or label + Add paragraph after / Delete and a multi-line
/// text box. Delete asks first; on iPad the dialog points at the trash button.
private struct AgreementBlockCard: View {
    @Binding var item: AgreementEditorBlock
    var focused: FocusState<UUID?>.Binding
    var error: String? = nil
    let addAfter: () -> Void
    let delete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.block.editorLabel.uppercased()).font(VFont.mono(10)).tracking(1).foregroundStyle(VC.ink3)
                    .lineLimit(1)
                if item.locked {
                    Text("Locked").font(VFont.ui(11, .semibold)).foregroundStyle(VC.ink2)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(VC.paper3).clipShape(Capsule())
                }
                Spacer(minLength: 4)
                smallButton("hdr-add", "Add paragraph after this \(item.block.editorLabel.lowercased())", tint: VC.brand, action: addAfter)
                if !item.locked, !isTitle {
                    smallButton("trash", "Delete this \(item.block.editorLabel.lowercased())", tint: VC.c1) { confirmDelete = true }
                        .confirmationDialog("Delete this \(kindNoun)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive, action: delete)
                            Button("Cancel", role: .cancel) {}
                        } message: { Text("It will be removed from your company\u{2019}s agreement when you save.") }
                }
            }
            if item.locked { lockedText } else { editor }
            if let error { FieldError(text: error) }
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 12)
        .background(item.locked ? VC.paper2 : VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }

    /// The title can be edited but not deleted (same as Android).
    private var isTitle: Bool { if case .title = item.block { return true } else { return false } }

    private var kindNoun: String {
        switch item.block {
        case .title: return "title"
        case .bullet: return "bullet"
        case .heading: return "heading"
        case .disclosure: return "disclosure"
        default: return "paragraph"
        }
    }

    @ViewBuilder
    private var lockedText: some View {
        switch item.block {
        case .form(let lines):
            // In full (no inner scroll view, which would fight the page's scrolling), boxed like the viewer.
            Text(lines.joined(separator: "\n"))
                .font(VFont.mono(11.5)).foregroundStyle(VC.ink2).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(VC.line, lineWidth: 1))
            .accessibilityLabel("Form fields, locked")
        default:
            Text(item.block.editableText ?? "")
                .font(VFont.ui(13.5, isLead ? .semibold : .regular)).foregroundStyle(VC.ink2).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isLead: Bool {
        switch item.block {
        case .title, .heading: return true
        case .paragraph(_, let lead): return lead
        default: return false
        }
    }

    private var editor: some View {
        let isFocused = focused.wrappedValue == item.id
        return TextField("", text: Binding(get: { item.block.editableText ?? "" }, set: { item.block = item.block.withText($0) }),
                         prompt: Text("Type the \(kindNoun)\u{2026}").foregroundStyle(VC.placeholder), axis: .vertical)
            .font(isLead ? VFont.ui(14, .semibold) : VFont.ui(14)).foregroundStyle(VC.ink)
            .lineSpacing(3)
            .lineLimit(1...)
            .tint(VC.brand)
            .focused(focused, equals: item.id)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(error != nil ? VC.c1 : (isFocused ? VC.brand : VC.line), lineWidth: isFocused || error != nil ? 2 : 1))
            .accessibilityLabel(item.block.editorLabel)
    }

    private func smallButton(_ symbol: String, _ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ProtoIcon(symbol, size: 15).foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(VC.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(VC.line, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
