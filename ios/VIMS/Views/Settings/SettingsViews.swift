import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 20 Settings

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var store = store
        let sub = store.subscription
        let plan = sub.plan(sub.selectedPlan)
        let n = store.company.inspectors.count
        Screen(title: "Settings", actions: [store.homeAction()]) {
            SectionLabel(text: "Account", top: 2)
            HStack(spacing: 13) {
                Avatar(name: store.session?.name ?? "", size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.session?.name ?? "").font(VFont.ui(15, .bold)).foregroundStyle(VC.ink)
                    Text(store.company.name).font(VFont.ui(12.5)).foregroundStyle(VC.ink3)
                }
            }
            .vCard()
            .padding(.bottom, 12)
            Button { store.signOut() } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                .buttonStyle(.vGhost)

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
                if store.syncing { ProgressView() } else { Label("Sync now", systemImage: "arrow.triangle.2.circlepath") }
            }
            .buttonStyle(.vGhost)
            .disabled(store.syncing)

            SectionLabel(text: "Subscription & licensing")
            NavRow(symbol: "creditcard", title: "Plan & billing",
                   subtitle: "\(plan?.name ?? "") · \(sub.active ? sub.totalLabel(seats: store.seats()) : "trial")") { store.push(.billing) }
            NavRow(symbol: "person.2", title: "Inspector accounts", subtitle: "\(n) inspector\(n == 1 ? "" : "s")") { store.push(.inspectors) }

            if store.isAdmin {
                SectionLabel(text: "Admin", top: 10)
                NavRow(symbol: "pencil", title: "Manage checklist", subtitle: "Add & edit sections and items") { store.push(.manageChecklist) }
                NavRow(symbol: "dollarsign", title: "Plans & pricing", subtitle: "Edit subscription plans & prices") { store.push(.plans) }
                NavRow(symbol: "envelope", title: "Feedback & support", subtitle: "Change the feedback contact email") { store.push(.feedbackAdmin) }
            }

            SectionLabel(text: "Help & feedback", top: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text("Questions or feedback?").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink)
                Text("We'd love to hear from you — send us a note and the VIMS team will get back to you.")
                    .font(VFont.ui(12.5)).foregroundStyle(VC.ink3).lineSpacing(3)
                    .padding(.top, 6).padding(.bottom, 12)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    let email = store.company.feedbackEmail
                    if let url = URL(string: "mailto:\(email)?subject=VIMS%20app%20feedback") { openURL(url) }
                } label: { Label("Send feedback", systemImage: "envelope") }
                    .buttonStyle(.vGhost)
            }
            .vCard()

            SectionLabel(text: "Company & help")
            NavRow(symbol: "building.2", title: "Company profile & logo", subtitle: "Inspector info, logo, review link") { store.push(.company) }
            NavRow(symbol: "questionmark.circle", title: "How VIMS works", subtitle: "Instructions & new-account tutorial") { store.push(.instructions) }

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
            Text("VIMS \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · data \(store.config.version)")
                .font(VFont.mono(10.5)).foregroundStyle(VC.ink3)
                .frame(maxWidth: .infinity).padding(.top, 18)
        }
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
    @State private var logoItem: PhotosPickerItem?
    @State private var showImporter = false
    @State private var reviewError: String?

    var body: some View {
        Screen(title: "Company profile", actions: [store.homeAction()]) {
            if draft != nil {
                SectionLabel(text: "Company logo", top: 2)
                Text("This logo appears on your report covers.").font(VFont.ui(12)).foregroundStyle(VC.ink3)
                    .padding(.top, -4).padding(.bottom, 10).padding(.horizontal, 2)
                HStack(spacing: 14) {
                    Image(uiImage: store.companyLogo()).resizable().scaledToFit()
                        .frame(width: 64, height: 64)
                        .frame(width: 76, height: 76)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VC.line, lineWidth: 1))
                        .accessibilityLabel("Company logo")
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Label("Upload logo", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 44))
                        Text("PNG or JPG, square works best.").font(VFont.ui(11.5)).foregroundStyle(VC.ink3).padding(.horizontal, 2)
                    }
                }
                .vCard()
                .padding(.bottom, 12)

                SectionLabel(text: "Company details")
                VTextField(label: "Company name", text: bind(\.name), capitalization: .words)
                VTextField(label: "Address", text: bind(\.address), contentType: .fullStreetAddress, capitalization: .words)
                SectionLabel(text: "Lead inspector")
                VTextField(label: "Inspector name", text: bind(\.inspectorName), contentType: .name, capitalization: .words)
                HStack(alignment: .top, spacing: 10) {
                    VTextField(label: "License #", text: bind(\.license), placeholder: "e.g. UT-12345", capitalization: .characters, bottom: 0)
                    VTextField(label: "Phone", text: bind(\.phone), placeholder: "(801) 555-0134", keyboard: .phonePad, contentType: .telephoneNumber, bottom: 0)
                }
                .padding(.bottom, 11)
                VTextField(label: "Email", text: bind(\.email), keyboard: .emailAddress, contentType: .emailAddress, capitalization: .never)
                SectionLabel(text: "Online review link")
                Text("Add the URL where clients can leave a review of the inspection. It's included with the report so clients can rate you.")
                    .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.top, -4).padding(.bottom, 9).padding(.horizontal, 2)
                    .fixedSize(horizontal: false, vertical: true)
                VTextField(label: "Review URL", text: bind(\.reviewURL), placeholder: "https://g.page/r/your-review-link", keyboard: .URL,
                           contentType: .URL, capitalization: .never, error: reviewError)
                SectionLabel(text: "Inspection agreement")
                Text("Legal requirements vary by state, so use your own agreement. Upload it here and clients sign it before each inspection.")
                    .font(VFont.ui(12)).foregroundStyle(VC.ink3).padding(.top, -4).padding(.bottom, 10).padding(.horizontal, 2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    LeadIcon(symbol: "doc.text")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.company.agreementName ?? "No agreement uploaded").font(VFont.ui(14, .bold)).foregroundStyle(VC.ink).lineLimit(1)
                        Text("PDF or Word document").font(VFont.ui(12)).foregroundStyle(VC.ink3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Upload") { showImporter = true }
                        .buttonStyle(VButtonStyle(kind: .ghost, minHeight: 44, fullWidth: false))
                }
                .vCard(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
                .padding(.bottom, 12)
                Button { save() } label: { Label("Save profile", systemImage: "checkmark") }
                    .buttonStyle(.vPrimary)
            }
        }
        .onAppear { if draft == nil { draft = store.company } }
        .onChange(of: logoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    store.saveLogo(img)
                }
                logoItem = nil
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.pdf] + ["doc", "docx"].compactMap { UTType(filenameExtension: $0) }) { result in
            if case .success(let url) = result { store.saveAgreement(from: url) }
        }
    }

    private func bind(_ kp: WritableKeyPath<CompanyProfile, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: kp] ?? "" }, set: { draft?[keyPath: kp] = $0 })
    }

    private func save() {
        guard var d = draft else { return }
        let url = d.reviewURL.trimmingCharacters(in: .whitespaces)
        if !url.isEmpty, URL(string: url)?.scheme?.hasPrefix("http") != true {
            reviewError = "Enter a full link starting with https://"
            return
        }
        reviewError = nil
        d.reviewURL = url
        // Keep files/people managed elsewhere in sync with the live profile.
        d.logoFile = store.company.logoFile
        d.agreementFile = store.company.agreementFile
        d.agreementName = store.company.agreementName
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

    var body: some View {
        Screen(title: "How VIMS works", actions: [store.homeAction()]) {
            Banner(symbol: "bolt", tint: VC.brand, background: VC.brand.opacity(0.08), border: Color(hex: 0xC3D2F2), textColor: VC.brandDeep,
                   text: md("**Everything saves on your device.** All inspection data and photos are stored locally and work fully offline — they upload automatically the next time you are online."))
                .padding(.bottom, 14)
            card("info.circle", "Getting started",
                 "**New account:** tap **Create account** on sign-in and enter your details, or tap **Join a company with a code** if your company gave you one. New companies start on a **\(store.subscription.trialDays)-day free look** — set up your company profile and logo in Settings first.")
            card("list.bullet", "Run an inspection",
                 "Tap **New inspection**, then step through: inspection info → property details → the areas to inspect. On each section, tap the answers that apply, add photos, mark them up, and flag any concern into a category. Use **Save & next section** to move through quickly.")
            card("flask", "Checklist depth",
                 "Pick **High Detail**, **Standard**, or **Fast Entry** per inspection (or set a default in Settings). High Detail asks the most; Fast Entry is a quick condition-and-notes pass.")
            card("photo", "Photos & findings",
                 "Tap **Add** to capture a photo, then tap it to draw on it or add a quick comment. Flagging a photo as a concern adds it to the **Summary** under Category 1 Safety, 2 Functional, or 3 Items to monitor.")
            card("doc.text", "Generate the report",
                 "From the Summary tap **Save and generate report**, choose a cover (color → theme → style), and the app builds your branded PDF. It queues to send when you are back online.")
            card("bolt", "Subscription & inspectors",
                 "Your free look counts down at every sign-in. Subscribe through **Square** any time. Add inspectors under your company license and share your **company code** so they can join.")
            VStack(spacing: 4) {
                Text("Need a hand? Contact your VIMS setup team").font(VFont.ui(13)).foregroundStyle(VC.ink3)
                Text("support@ogrelogic.com").font(VFont.mono(13)).foregroundStyle(VC.brandDeep)
            }
            .frame(maxWidth: .infinity)
            .vCard()
        }
    }

    private func card(_ symbol: String, _ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(VC.brand)
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
    @State private var error: String?

    var body: some View {
        Screen(title: "Feedback & support", actions: [store.homeAction()]) {
            HintText(text: "Owner admin — set the email address that receives help & feedback messages sent from the app.")
                .padding(.top, 2).padding(.bottom, 14)
            VTextField(label: "Feedback contact email", text: $email, keyboard: .emailAddress, contentType: .emailAddress,
                       capitalization: .never, error: error)
            Button { save() } label: { Label("Save", systemImage: "checkmark") }
                .buttonStyle(.vPrimary)
        }
        .onAppear { email = store.company.feedbackEmail }
    }

    private func save() {
        let v = email.trimmingCharacters(in: .whitespaces)
        guard v.contains("@"), v.contains(".") else { error = "Enter a valid email"; return }
        error = nil
        store.state.company.feedbackEmail = v
        store.toast("Feedback email saved")
    }
}
