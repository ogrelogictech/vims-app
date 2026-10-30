import SwiftUI
import MessageUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 20 Settings

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var photoMenu = false
    @State private var confirmSignOut = false
    var wide = WideLayout()

    var body: some View {
        @Bindable var store = store
        let n = store.company.inspectors.count
        Screen(title: "Settings", actions: [store.homeAction()]) {
            // iPad landscape: account, sync (Phase 2), subscription and admin on the left; help, company, legal and defaults
            // on the right. Same order, one column, everywhere else.
            WideColumns(spacing: 24, wide: wide.isWide) {
            SectionLabel(text: "Account", top: 2)
            HStack(spacing: 13) {
                // The user's own profile photo (initials if none) — tap to change. Not the company logo.
                Button { photoMenu = true } label: {
                    UserAvatar(userID: store.currentUser?.id, name: store.session?.name ?? "", size: 52)
                        .overlay(alignment: .bottomTrailing) {
                            ProtoIcon("camera", size: 11, lineWidth: 2.4).foregroundStyle(.white)
                                .frame(width: 20, height: 20).background(VC.brand).clipShape(Circle())
                                .overlay(Circle().stroke(VC.paper, lineWidth: 2))
                                .offset(x: 3, y: 3)
                        }
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(ChipPressStyle())
                .frame(minWidth: 52, minHeight: 52)
                .accessibilityLabel("Profile photo")
                .accessibilityHint("Take, choose or remove your profile photo")
                // On the photo button, so on iPad the choices pop up next to it.
                .photoSourceDialog(isPresented: $photoMenu, title: "Profile photo",
                                   removeTitle: store.currentUser?.photoFile == nil ? nil : "Remove photo",
                                   onImage: { store.saveProfilePhoto($0) }, onRemove: { store.removeProfilePhoto() })
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.session?.name ?? "").font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                    Text(store.session?.email ?? "").font(VFont.ui(12.5)).foregroundStyle(VC.ink3).lineLimit(1).minimumScaleFactor(0.8)
                    Text(store.company.name).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                    // Client Oct 28: VIMS platform owners see that they have master admin access.
                    if store.isPlatformOwner { MasterAdminBadge().padding(.top, 5) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .vCard()
            .padding(.bottom, 12)
            Button { confirmSignOut = true } label: { IconLabel("Sign out", icon: "sign-out-sync") }
                .buttonStyle(.vGhost)
                .signOutConfirmation(isPresented: $confirmSignOut)
            Button("Delete account") { store.push(.deleteAccount) }
                .buttonStyle(VButtonStyle(kind: .ghost, tint: VC.c1))
                .padding(.top, 10)

            // Data v1.10 `features.sync` is false in Phase 1 (nothing syncs): no Sync section, pending counts or Sync now.
            if store.syncEnabled {
            SectionLabel(text: "Sync")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-sync when online").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                    Text(store.pendingSyncCount == 0 ? "Everything is synced" : "\(store.pendingSyncCount) inspection\(store.pendingSyncCount == 1 ? "" : "s") waiting")
                        .font(VFont.ui(12)).foregroundStyle(VC.ink3)
                }
                Spacer()
                VToggle(isOn: $store.state.settings.autoSync)
            }
            .vCard()
            .padding(.bottom, 12)
            Button { Task { await store.syncNow() } } label: {
                if store.syncing { ProgressView() } else { IconLabel("Sync now", icon: "sync-now-subscription") }
            }
            .buttonStyle(.vGhost)
            .disabled(store.syncing)
            }

            if store.isPlatformOwner {
                // Client Oct 28: VIMS master admin (platform owner) settings, clearly labeled and hidden from every other
                // account. Plans & pricing moved here from the company Admin group.
                SectionLabel(text: "Master admin", top: 10)
                Text("VIMS-wide settings for every company. Only VIMS master admins see these.")
                    .font(VFont.ui(12)).foregroundStyle(VC.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2).padding(.top, -4).padding(.bottom, 10)
                NavRow(symbol: "plans-pricing-edit", title: "Plans & pricing", subtitle: "VIMS subscription plans & prices") { store.push(.plans) }
                NavRow(symbol: "report-bcc", title: "Report quality copy", subtitle: store.platform.bccSummary) { store.push(.reportBcc) }
                NavRow(symbol: "email-to-client", title: "Feedback & support", subtitle: "Change the feedback contact email") { store.push(.feedbackAdmin) }
            }

            SectionLabel(text: "Subscription & licensing")
            NavRow(symbol: "collect-payment-div", title: "Plan & billing", subtitle: planSubtitle) { store.push(.billing) }
            NavRow(symbol: "inspector-accounts-inspector", title: "Inspector accounts", subtitle: "\(n) inspector\(n == 1 ? "" : "s")") { store.push(.inspectors) }

            if store.isAdmin {
                // Company admins: the company's checklist (Inspectors is under Subscription & licensing). Plans & pricing is
                // master admin only since client Oct 28.
                SectionLabel(text: "Admin", top: 10)
                NavRow(symbol: "manage-checklist-add", title: "Manage checklist", subtitle: "Add, edit or restore sections and items") { store.push(.manageChecklist) }
            }

            } trailing: {
            SectionLabel(text: "Help & feedback", top: wide.isWide ? 2 : 10)
            VStack(alignment: .leading, spacing: 0) {
                Text("Questions or feedback?").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                Text("We'd love to hear from you — send us a note and the VIMS team will get back to you.")
                    .font(VFont.ui(12.5)).foregroundStyle(VC.ink3).lineSpacing(3)
                    .padding(.top, 6).padding(.bottom, 12)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    let email = store.supportEmail
                    if let url = URL(string: "mailto:\(email)?subject=VIMS%20app%20feedback") { openURL(url) }
                } label: { IconLabel("Send feedback", icon: "email-to-client") }
                    .buttonStyle(.vGhost)
            }
            .vCard()

            SectionLabel(text: "Company & help")
            NavRow(symbol: "company-profile-logo", title: "Company profile & logo", subtitle: "Inspector info, logo, review link") { store.push(.company) }
            NavRow(symbol: "how-vims-works", title: "How VIMS works", subtitle: "Instructions & new-account tutorial") { store.push(.instructions) }

            SectionLabel(text: "Legal", top: 10)
            NavRow(symbol: "legal-document", title: "End User License Agreement", subtitle: "Revised \(store.eula.revised)") { store.push(.eula) }

            SectionLabel(text: "Defaults", top: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text("Checklist depth").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                Text("Applies to new inspections. High Detail asks for measurements; Fast Entry is quick condition & notes.")
                    .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.top, 4).padding(.bottom, 11)
                    .fixedSize(horizontal: false, vertical: true)
                ChipGroup(options: Depth.allCases.map(\.label),
                          selection: Binding(get: { [store.state.settings.defaultDepth.label] },
                                             set: { if let f = $0.first { store.state.settings.defaultDepth = Depth(label: f) } }),
                          single: true, required: true)
            }
            .vCard()
            .padding(.bottom, 12)
            RowView(title: "Report cover", subtitle: store.state.settings.defaultCover.label) { EmptyView() } trailing: { EmptyView() }
                .padding(.bottom, 10)
            RowView(title: "Photo size", subtitle: "JPG · ~750 KB") { EmptyView() } trailing: { EmptyView() }
            }
            #if DEBUG
            // App + data version: developer builds only (not shown to customers).
            Text("DEBUG · VIMS \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · data \(store.config.version)")
                .font(VFont.mono(10.5)).foregroundStyle(VC.ink3)
                .frame(maxWidth: .infinity).padding(.top, 18)
            #endif
        }
    }
}

extension SettingsView {
    /// "App only · Yearly · $935.00/yr" · "App only · trial" · "Pay per report · $5.00 / report"
    fileprivate var planSubtitle: String {
        let sub = store.subscription
        let name = sub.plan(sub.selectedPlan)?.name ?? ""
        if store.isSubscriptionExempt && !sub.active { return AppStore.exemptLine }
        guard sub.active else { return "\(name) · \(sub.subscriptionEnded ? "cancelled" : sub.trialEnded ? "trial ended" : "trial")" }
        if sub.plan(sub.selectedPlan)?.isPerReport == true { return "\(name) · \(sub.totalLabel(seats: store.seats()))" }
        return "\(name) · \(sub.period.label) · \(sub.totalLabel(seats: store.seats()))"
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 44
    var radius: CGFloat? = nil
    var body: some View {
        Text(Fmt.initials(name))
            .font(VFont.display(size * 0.3, .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [VC.brandBright, VC.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: radius ?? size / 2, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - 21 Company profile

struct CompanyProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var draft: CompanyProfile?
    @State private var logoMenu = false
    @State private var showImporter = false
    @State private var errors = FormErrors()

    var body: some View {
        Screen(title: "Company profile", actions: [store.homeAction()], errors: errors) {
            if !store.isAdmin {
                // QA Oct 14: a plain inspector sees the profile read-only (no edit controls, no Save).
                readOnly
            } else if draft != nil {
                SectionLabel(text: "Company logo", top: 2)
                Text("This logo appears on your report covers.").font(VFont.ui(12)).foregroundStyle(VC.ink3)
                    .padding(.top, -4).padding(.bottom, 10).padding(.horizontal, 2)
                HStack(spacing: 14) {
                    CompanyLogoBadge(size: 76, radius: 16)
                    VStack(alignment: .leading, spacing: 8) {
                        Button { logoMenu = true } label: {
                            IconLabel(store.company.logoFile == nil ? "Upload logo" : "Change logo", icon: "upload-logo-png")
                        }
                        .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 44))
                        .photoSourceDialog(isPresented: $logoMenu, title: "Company logo",
                                           removeTitle: store.company.logoFile == nil ? nil : "Remove logo",
                                           onImage: { store.saveLogo($0) }, onRemove: { store.removeLogo() })
                        Text("PNG or JPG, square works best.").font(VFont.ui(11.5)).foregroundStyle(VC.ink3).padding(.horizontal, 2)
                    }
                }
                .vCard()
                .padding(.bottom, 12)

                SectionLabel(text: "Company details")
                VTextField(label: "Company name", text: bind(\.name), capitalization: .words, kind: .companyName, fieldID: "name", errors: errors, required: true)
                VTextField(label: "Address", text: bind(\.address), contentType: .fullStreetAddress, capitalization: .words,
                           kind: .address, fieldID: "address", errors: errors)
                SectionLabel(text: "Lead inspector")
                VTextField(label: "Inspector name", text: bind(\.inspectorName), contentType: .name, capitalization: .words,
                           kind: .personName, fieldID: "inspector", errors: errors)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) { licenseField(bottom: 0); phoneField(bottom: 0) }
                    VStack(spacing: 0) { licenseField(bottom: 13); phoneField(bottom: 0) }
                }
                .padding(.bottom, 11)
                VTextField(label: "Email", text: bind(\.email), keyboard: .emailAddress, contentType: .emailAddress, capitalization: .never,
                           kind: .email, fieldID: "email", errors: errors)
                SectionLabel(text: "Online review link")
                Text("Add the URL where clients can leave a review of the inspection. It's included with the report so clients can rate you.")
                    .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.top, -4).padding(.bottom, 9).padding(.horizontal, 2)
                    .fixedSize(horizontal: false, vertical: true)
                VTextField(label: "Review URL", text: bind(\.reviewURL), placeholder: "https://g.page/r/your-review-link", keyboard: .URL,
                           contentType: .URL, capitalization: .never, kind: .url, fieldID: "review", errors: errors)
                SectionLabel(text: "Inspection agreement")
                Text(store.isAdmin ? "Every company starts with the VIMS agreement covering all 50 states. Edit your company\u{2019}s copy, or upload your own to use it instead."
                                   : "Every company starts with the VIMS agreement covering all 50 states. Your company admin can edit it or upload their own.")
                    .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.top, -4).padding(.bottom, 10).padding(.horizontal, 2)
                    .fixedSize(horizontal: false, vertical: true)
                AgreementCard { showImporter = true }
                    .vCard(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
                    .padding(.bottom, 12)
                    .id("agreement-card")
                Button { save() } label: { IconLabel("Save profile", icon: "link-my-account") }
                    .buttonStyle(.vPrimary)
            }
        }
        .onAppear {
            if draft == nil { draft = store.company }
            if DebugFlags.validate { DebugFlags.validate = false; draft?.name = ""; draft?.phone = "(801) 55"; draft?.email = "office@vpi"; draft?.reviewURL = "g.page/review"; save() }
        }
        #if DEBUG
        .task {
            // -agreementScroll card: scroll to the Inspection agreement card (review screenshots).
            guard DebugLaunch.value("-agreementScroll") == "card" else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            errors.scrollTarget = "agreement-card"
        }
        #endif
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.pdf, .image] + ["doc", "docx"].compactMap { UTType(filenameExtension: $0) }) { result in
            if case .success(let url) = result { store.saveAgreement(from: url) }
        }
    }

    /// Non-admins: the company's details as text, the agreement card (View only) and who can change them.
    @ViewBuilder private var readOnly: some View {
        let c = store.company
        Banner(symbol: "info", tint: VC.brandDeep, background: VC.brand.opacity(0.08), border: Color(hex: 0xC9DEE6), textColor: VC.brandDeep,
               text: md("Only your company **admin** can edit the company profile, logo and agreement."))
            .padding(.top, 2).padding(.bottom, 14)
        HStack(spacing: 14) {
            CompanyLogoBadge(size: 76, radius: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name).font(VFont.ui(16, .bold)).foregroundStyle(VC.ink).fixedSize(horizontal: false, vertical: true)
                Text("This logo appears on your report covers.").font(VFont.ui(12)).foregroundStyle(VC.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .vCard()
        .padding(.bottom, 12)
        SectionLabel(text: "Company details")
        VStack(spacing: 0) {
            let rows: [(String, String)] = [("Company name", c.name), ("Address", c.address), ("Lead inspector", c.inspectorName),
                                            ("License #", c.license), ("Phone", c.phone), ("Email", c.email), ("Review URL", c.reviewURL)]
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.0).font(VFont.ui(12, .semibold)).foregroundStyle(VC.ink3)
                    Text(r.1.isEmpty ? "—" : r.1).font(VFont.ui(14.5)).foregroundStyle(VC.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .overlay(alignment: .bottom) { if i < rows.count - 1 { Rectangle().fill(VC.line2).frame(height: 1) } }
                .accessibilityElement(children: .combine)
            }
        }
        .background(VC.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.line, lineWidth: 1))
        .padding(.bottom, 4)
        SectionLabel(text: "Inspection agreement")
        Text("Every company starts with the VIMS agreement covering all 50 states. Your company admin can edit it or upload their own.")
            .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.top, -4).padding(.bottom, 10).padding(.horizontal, 2)
            .fixedSize(horizontal: false, vertical: true)
        AgreementCard { }
            .vCard(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
            .padding(.bottom, 12)
            .id("agreement-card")
    }

    private func bind(_ kp: WritableKeyPath<CompanyProfile, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: kp] ?? "" }, set: { draft?[keyPath: kp] = $0 })
    }

    private func licenseField(bottom: CGFloat) -> some View {
        VTextField(label: "License #", text: bind(\.license), placeholder: "e.g. UT-12345", capitalization: .characters,
                   bottom: bottom, kind: .license, fieldID: "license", errors: errors)
    }

    private func phoneField(bottom: CGFloat) -> some View {
        VTextField(label: "Phone", text: bind(\.phone), placeholder: "(801) 555-0134", keyboard: .phonePad, contentType: .telephoneNumber,
                   bottom: bottom, kind: .phone, fieldID: "phone", errors: errors)
    }

    private func save() {
        guard store.isAdmin, var d = draft else { return }
        let fields: [(id: String, value: String, rule: FieldRule)] = [
            ("name", d.name, .req(.companyName, "Company name")),
            ("address", d.address, .opt(.address, "Address")),
            ("inspector", d.inspectorName, .opt(.personName, "Inspector name")),
            ("license", d.license, .opt(.license, "License #")),
            ("phone", d.phone, .opt(.phone, "Phone")),
            ("email", d.email, .opt(.email, "Email")),
            ("review", d.reviewURL, .opt(.url, "Review URL"))
        ]
        guard errors.validate(fields) else { return }
        for kp in [\CompanyProfile.name, \.address, \.inspectorName, \.license, \.phone, \.email, \.reviewURL] {
            d[keyPath: kp] = Validator.trimmed(d[keyPath: kp])
        }
        // Keep files/people managed elsewhere in sync with the live profile.
        d.logoFile = store.company.logoFile
        d.agreementFile = store.company.agreementFile
        d.agreementName = store.company.agreementName
        d.agreementText = store.company.agreementText
        d.agreementEditedAt = store.company.agreementEditedAt
        d.inspectors = store.company.inspectors
        d.feedbackEmail = store.company.feedbackEmail
        d.joinCode = store.company.joinCode
        store.state.company = d
        store.toast("Company profile saved")
    }
}

// MARK: - 22 How VIMS works

struct InstructionsView: View {
    @Environment(AppStore.self) private var store
    @State private var composeSupport = false
    /// The VIMS support address: the platform owner's Feedback & support email (default `support.feedbackEmail` in the
    /// shared JSON).
    private var supportEmail: String { store.supportEmail }

    var body: some View {
        Screen(title: "How VIMS works", actions: [store.homeAction()]) {
            Banner(symbol: "bolt", tint: VC.brand, background: VC.brand.opacity(0.08), border: Color(hex: 0xC3D2F2), textColor: VC.brandDeep,
                   text: md(store.syncEnabled
                            ? "**Everything saves on your device.** All inspection data and photos are stored locally and work fully offline — they upload automatically the next time you are online."
                            : "**Everything saves on your device.** Inspections, photos and reports are stored on this device and work fully offline — they are not copied to a server, so save or share the reports you want to keep."))
                .padding(.bottom, 14)
            card("info", "Getting started",
                 "**New account:** tap **Create account** on sign-in and enter your details, or tap **Join a company with a code** if your company gave you one. New companies start on a **\(store.subscription.trialDays)-day free look** — set up your company profile and logo in Settings first.")
            card("list", "Run an inspection",
                 "Tap **New inspection**, then step through: inspection info → property details → the areas to inspect. On each section, tap the answers that apply, add photos, mark them up, and flag any concern into a category. Use **Save & next section** to move through quickly.")
            card("flask", "Checklist depth",
                 "Pick **High Detail**, **Standard**, or **Fast Entry** per inspection (or set a default in Settings). High Detail asks the most; Fast Entry is a quick condition-and-notes pass.")
            card("file", "Photos & findings",
                 "Tap **Add** to capture a photo, then tap it to draw on it or add a quick comment. Flagging a photo as a concern adds it to the **Summary** under Category 1 Safety, 2 Functional, or 3 Items to monitor.")
            card("file", "Generate the report",
                 store.syncEnabled
                 ? "From the Summary tap **Save and generate report**, choose a cover (color → theme → style), and the app builds your branded PDF. It queues to send when you are back online."
                 : "From the Summary tap **Save and generate report**, choose a cover (color → theme → style), and the app builds your branded PDF on this device. Then email it to your client or save and share it from **Report ready**.")
            card("bolt", "Subscription & inspectors",
                 "Your free look counts down at every sign-in. Subscribe through **Square** any time. Add inspectors under your company license and share your **company code** so they can join.")
            VStack(spacing: 4) {
                Text("Need a hand? Contact VIMS support").font(VFont.ui(13)).foregroundStyle(VC.ink3)
                // Tappable (Oct 13 QA): Mail composer when Mail is set up, else the mailto: handler (another mail app),
                // else the address is copied with a toast. Long-press → Copy email address.
                Button { contactSupport() } label: {
                    Text(supportEmail).font(VFont.mono(13)).foregroundStyle(VC.brandDeep).underline()
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Email \(supportEmail)")
                .accessibilityHint("Opens a new email to VIMS support")
                .contextMenu {
                    Button("Copy email address") { copySupportEmail(note: nil) }
                }
            }
            .frame(maxWidth: .infinity)
            .vCard()
        }
        .sheet(isPresented: $composeSupport) {
            SupportMailView(to: supportEmail, subject: "VIMS help — \(store.company.name)") { composeSupport = false }
                .ignoresSafeArea()
        }
    }

    private func contactSupport() {
        if MFMailComposeViewController.canSendMail() { composeSupport = true; return }
        guard let url = URL(string: "mailto:\(supportEmail)") else { copySupportEmail(note: nil); return }
        UIApplication.shared.open(url) { opened in
            if !opened { copySupportEmail(note: "No mail app is set up") }
        }
    }

    private func copySupportEmail(note: String?) {
        UIPasteboard.general.string = supportEmail
        store.toast(note.map { "\($0) — \(supportEmail) copied" } ?? "\(supportEmail) copied")
    }

    private func card(_ symbol: String, _ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProtoIcon(symbol, size: 17).foregroundStyle(VC.brand)
                    .frame(width: 30, height: 30).background(VC.paper3)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(VFont.display(15, .bold)).foregroundStyle(VC.ink)
            }
            Text(md(body)).font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .vCard()
        .padding(.bottom, 12)
    }
}

// MARK: - 30 Feedback & support (admin)

struct FeedbackAdminView: View {
    @Environment(AppStore.self) private var store
    @State private var email = ""
    @State private var errors = FormErrors()

    var body: some View {
        Screen(title: "Feedback & support", actions: [store.homeAction()], errors: errors) {
            HintText(text: "Master admin (VIMS owner only) — set the email address that receives help & feedback messages sent from the app.")
                .padding(.top, 2).padding(.bottom, 14)
            VTextField(label: "Feedback contact email", text: $email, keyboard: .emailAddress, contentType: .emailAddress,
                       capitalization: .never, kind: .email, fieldID: "email", errors: errors, required: true)
            Button { save() } label: { IconLabel("Save", icon: "link-my-account") }
                .buttonStyle(.vPrimary)
        }
        .onAppear {
            email = store.platform.feedbackEmail
            if DebugFlags.validate { DebugFlags.validate = false; email = "support@vims"; save() }
        }
    }

    private func save() {
        guard errors.validate([("email", email, .req(.email, "Feedback email"))]) else { return }
        var p = store.platform
        p.feedbackEmail = Validator.trimmed(email)
        store.savePlatform(p)
        store.toast("Feedback email saved")
    }
}

// MARK: - Report quality copy — VIMS platform owner only (sent by the VIMS server, never a Bcc on the device compose)

struct ReportBccView: View {
    @Environment(AppStore.self) private var store
    @State private var on = true
    @State private var email = ""
    @State private var errors = FormErrors()

    var body: some View {
        Screen(title: "Report quality copy", actions: [store.homeAction()], errors: errors) {
            Text(md("**Master admin (VIMS owner only)** — when an inspection report is emailed from the app, the **VIMS server sends a separate copy** to this address so report quality can be reviewed. It is never added to the inspector’s email (no Bcc line), so inspectors, clients and agents don’t see this address. Disclosed in the VIMS EULA."))
                .font(VFont.ui(13)).foregroundStyle(VC.ink3).lineSpacing(2)
                .padding(.top, 2).padding(.bottom, 14)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Send a quality copy of every emailed report").font(VFont.ui(14.5, .semibold)).foregroundStyle(VC.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChipGroup(options: ["On", "Off"], selection: Binding(get: { [on ? "On" : "Off"] }, set: { if let f = $0.first { on = f == "On"; errors.clear() } }),
                          single: true, required: true)
                    .fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(VC.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VC.line, lineWidth: 1))
            .padding(.bottom, 14)
            VTextField(label: "Quality copy address", text: $email, placeholder: "you@company.com", keyboard: .emailAddress, contentType: .emailAddress,
                       capitalization: .never, kind: .email, fieldID: "bcc", errors: errors, required: on)
            Button { save() } label: { IconLabel("Save", icon: "link-my-account") }
                .buttonStyle(.vPrimary)
        }
        .onAppear {
            on = store.platform.reportBccOn
            email = store.platform.reportBccEmail
            if DebugFlags.validate { DebugFlags.validate = false; email = "quality@vims"; save() }
        }
    }

    private func save() {
        // The address is required while the quality copy is on; when off it may be blank but must still be valid if entered.
        guard errors.validate([("bcc", email, on ? .req(.email, "Quality copy address") : .opt(.email, "Quality copy address"))]) else { return }
        var p = store.platform
        p.reportBccOn = on
        p.reportBccEmail = Validator.trimmed(email).lowercased()
        store.savePlatform(p)
        store.toast(on ? "The VIMS server will send report copies to \(p.reportBccEmail)" : "Report quality copy turned off")
    }
}

// MARK: - Delete account (App Store 5.1.1(v))

struct DeleteAccountView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmText = ""
    @State private var errors = FormErrors()
    @State private var busy = false
    /// Team QA Oct 22: a last centered "Delete your account?" alert after DELETE is typed.
    @State private var confirmFinal = false

    var body: some View {
        let blocked = store.isCompanyOwner && !store.otherCompanyUsers.isEmpty
        let n = store.inspections.count
        Screen(title: "Delete account", actions: [store.homeAction()], errors: errors) {
            if blocked {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make another admin the owner first").font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink)
                    Text("You own \(store.company.name), and \(store.otherCompanyUsers.map(\.name).joined(separator: ", ")) \(store.otherCompanyUsers.count == 1 ? "still uses" : "still use") it. In Inspectors, make one of them an admin and tap Make owner, then delete your account.")
                        .font(VFont.ui(13)).foregroundStyle(VC.ink2).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .vCard()
                .padding(.bottom, 12)
                Button { store.push(.inspectors) } label: { IconLabel("Open Inspectors", icon: "manage-inspectors-h") }
                    .buttonStyle(.vPrimary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This permanently deletes:").font(VFont.ui(14.5, .bold)).foregroundStyle(VC.ink)
                    bullet("Your VIMS account (\(store.session?.email ?? ""))")
                    bullet("Your \(n) inspection\(n == 1 ? "" : "s"), with their photos and reports, on this device")
                    if store.isCompanyOwner {
                        bullet("The company \(store.company.name) — its profile, logo, checklist changes and inspector invites")
                        if store.subscription.active { bullet("Your subscription is cancelled (no further charges)") }
                    }
                    Text(store.syncEnabled ? "We also delete your data from the VIMS servers within 10 working days. This can't be undone."
                                           : "We also delete your account and company information from the VIMS servers within 10 working days. This can't be undone.")
                        .font(VFont.ui(12.5)).foregroundStyle(VC.ink3).lineSpacing(2).padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
                .background(VC.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VC.c1, lineWidth: 1))
                .padding(.bottom, 16)
                VTextField(label: "Type DELETE to confirm", text: $confirmText, placeholder: "DELETE", capitalization: .characters,
                           fieldID: "confirm", errors: errors, required: true)
                Button { submit() } label: {
                    if busy { ProgressView().tint(.white) } else { Text("Delete my account") }
                }
                .buttonStyle(VButtonStyle(kind: .danger))
                .disabled(busy)
            }
        }
        .alert("Delete your account?", isPresented: $confirmFinal) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.isCompanyOwner ? "Your account, inspections and \(store.company.name) are removed. This can't be undone."
                 : "Your account and inspections are removed. This can't be undone.")
        }
        #if DEBUG
        .task { try? await Task.sleep(nanoseconds: 1_200_000_000); debugConfirm() }
        #endif
    }

    #if DEBUG
    /// -confirmDelete: type DELETE and submit (review/testing only).
    private func debugConfirm() {
        if DebugLaunch.has("-confirmDelete") { confirmText = "DELETE"; if typedDelete() { performDelete() } }
        if DebugLaunch.has("-confirmAlert") { confirmText = "DELETE"; submit() }
    }
    #endif

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(VC.c1).frame(width: 5, height: 5).padding(.top, 7)
            Text(t).font(VFont.ui(13)).foregroundStyle(VC.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func typedDelete() -> Bool {
        errors.validate([("confirm", confirmText, .req(.plain(max: nil), "Confirmation",
                                                       custom: { $0.trimmingCharacters(in: .whitespaces) == "DELETE" ? nil : "Type DELETE in capital letters to confirm" }))])
    }

    private func submit() {
        guard typedDelete() else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        confirmFinal = true
    }

    private func performDelete() {
        busy = true
        Task {
            do { try await store.deleteAccount() }
            catch { errors.set("confirm", "Make another admin the owner first") }
            busy = false
        }
    }
}

/// A plain Mail composer to one address ("How VIMS works" → support email).
struct SupportMailView: UIViewControllerRepresentable {
    let to: String
    let subject: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([to])
        vc.setSubject(subject)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish()
        }
    }
}
