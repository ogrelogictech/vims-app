import SwiftUI
import Observation

enum Route: Hashable {
    case signup, forgot, join
    case wizard(editing: UUID?)
    case sections(UUID)
    case section(UUID, String)
    case photos(UUID, String)
    case summary(UUID)
    case report(UUID)
    case reportReady(UUID)
    case settings, company, instructions
    case manageChecklist
    case editSection(String)
    case plans, inspectors, subscribe, subscriptionStarted, billing, feedbackAdmin, reportBcc
    case eula, deleteAccount
    /// VIMS default inspection agreement viewer: nil = every state's disclosures (Company profile),
    /// a code = only that state's section (wizard step 1).
    case agreement(state: String?)
    /// Company admins: edit this company's copy of the VIMS agreement.
    case agreementEditor
}

@MainActor
@Observable
final class AppStore {
    let config: ChecklistConfig
    /// Client EULA (shared/legal/eula.json). `var` only so a DEBUG launch argument can bump its version.
    var eula: EULADocument
    let repo: any Repository
    let auth: AuthService
    let subscriptionService: SubscriptionService
    let syncService: SyncService
    @ObservationIgnored private let connectivity = Connectivity()

    /// Signed-in user's view of the data. When signed out this is an empty placeholder.
    var state: AppState {
        didSet {
            scheduleAppSave()
            // Auto-sync switched on (or a session loaded with it on): send what's waiting.
            if syncEnabled, state.settings.autoSync, !oldValue.settings.autoSync || oldValue.session?.email != state.session?.email {
                requestAutoSync(after: 1)
            }
        }
    }
    /// Only the signed-in user's inspections are ever loaded.
    var inspections: [Inspection] = []
    var path: [Route] = []
    /// VIMS platform settings — app-level, not per company. Editable only by the platform owner.
    private(set) var platform: PlatformSettings
    private(set) var currentUser: UserAccount?
    private(set) var companyID: UUID?

    var toastMessage: String?
    var toastID = UUID()
    var showSplash = false
    var showVideoSplash = true
    var isOnline = true
    var syncing = false
    /// "Your free trial has ended" (New inspection with the trial over and no subscription).
    var trialEndedPrompt = false

    @ObservationIgnored private var inspectionSaveTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var autoSyncTask: Task<Void, Never>?
    /// Inspections edited while a sync was uploading: they stay queued (and sync again) instead of being marked synced.
    @ObservationIgnored private var editedDuringSync: Set<UUID> = []
    #if DEBUG
    /// -offlineFor N: the connection reads as offline until this time (auto-sync on reconnect test).
    @ObservationIgnored var debugOfflineUntil: Date?
    #endif
    @ObservationIgnored private var appSaveTask: Task<Void, Never>?
    @ObservationIgnored private var loadingSession = false

    init(config: ChecklistConfig, eula: EULADocument, repo: any Repository,
         subscriptionService: SubscriptionService = LocalSubscriptionService(),
         syncService: SyncService = LocalSyncService()) {
        self.config = config
        self.eula = eula
        self.repo = repo
        self.auth = LocalAuthService(repo: repo)
        self.subscriptionService = subscriptionService
        self.syncService = syncService
        self.state = DemoSeed.emptyState(config: config)
        self.platform = PlatformSettings.defaults(config)

        // First launch: migrate the old JSON files, or seed the demo account (see Store/Bootstrap.swift).
        Bootstrap.run(repo: repo, config: config)
        if let saved = repo.platformSettings() {
            platform = saved
        } else {
            // First run of v1.2: platform defaults from the shared JSON; keep a feedback email that was
            // previously edited on the demo company (it used to be stored per company).
            if let fb = repo.company(joinCode: config.sample.company.code)?.profile.feedbackEmail, !fb.isEmpty { platform.feedbackEmail = fb }
            repo.savePlatformSettings(platform)
        }
        // v1.9.2: old shipped feedback / report-quality addresses move to the vimsinspect.com defaults.
        platformMigrated = platform.migrateReplacedDefaults(config)
        if !platformMigrated.isEmpty { repo.savePlatformSettings(platform) }
        // One free trial per device: builds before the Keychain record backfill it from this device's companies.
        DeviceTrial.backfill(companies: repo.allCompanies(), demoCode: config.sample.company.code)
        if let uid = repo.currentUserID, let u = repo.user(id: uid) { loadSession(u) } else { repo.currentUserID = nil }

        connectivity.onChange = { [weak self] online in self?.setOnline(online) }
        connectivity.start()
    }

    var catalog: ChecklistCatalog { ChecklistCatalog(config: config, overrides: state.overrides) }

    /// The checklist an inspection uses: the company's checklist, with the section definitions the inspection kept when
    /// an admin restored the checklist to the VIMS original (`Inspection.savedSections`, client Oct 28) taking priority.
    func catalog(for insp: Inspection?) -> ChecklistCatalog {
        guard let saved = insp?.savedSections, !saved.isEmpty else { return catalog }
        var o = state.overrides
        o.sections.merge(saved) { _, kept in kept }
        return ChecklistCatalog(config: config, overrides: o)
    }
    func catalog(for id: UUID) -> ChecklistCatalog { catalog(for: inspection(id)) }
    var company: CompanyProfile { state.company }
    var subscription: SubscriptionState { state.subscription }
    var session: Session? { state.session }
    var isAdmin: Bool { state.session?.isAdmin ?? false }
    var isPlatformOwner: Bool { state.session?.isPlatformOwner ?? false }
    /// Fields `PlatformSettings.migrateReplacedDefaults` changed at this launch (DEBUG `-platformStatus`).
    @ObservationIgnored private(set) var platformMigrated: [String] = []

    /// The VIMS support address for Help & feedback / How VIMS works: the platform owner's Feedback & support email,
    /// or the shared JSON default (`support.feedbackEmail`) when it is blank.
    var supportEmail: String {
        let e = platform.feedbackEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? config.support.feedbackEmail : e
    }

    /// Platform-owner only (TODO(backend): enforced by the server as well).
    func savePlatform(_ s: PlatformSettings) {
        guard isPlatformOwner else { return }
        platform = s
        repo.savePlatformSettings(s)
    }
    var pendingSyncCount: Int { inspections.filter(\.needsSync).count }

    /// Data v1.10 `features.sync` — false in Phase 1: no sync pills, no Settings Sync section, no sync wording, and the
    /// automatic sync stub never runs. The sync code below stays for Phase 2.
    var syncEnabled: Bool { config.syncEnabled }

    // MARK: Free trial

    /// A new inspection needs the free trial (30 days, `subscription.trialDays`) or an active subscription. Existing
    /// inspections stay viewable and editable, and their reports can still be shared / re-sent.
    var canStartNewInspection: Bool { !subscription.trialEnded }

    /// Every "New inspection" button (Home header +, Home, side menu): the wizard, or the Subscribe prompt.
    func startNewInspection() {
        if canStartNewInspection { push(.wizard(editing: nil)) } else { showTrialEndedPrompt() }
    }

    func showTrialEndedPrompt() { trialEndedPrompt = true }

    /// The signed-in inspector's own email, CC'd on every emailed report (data v1.3 `support.ccInspector`).
    var reportCcEmail: String? {
        guard config.support.ccInspector != nil else { return nil }
        let e = (currentUser?.email ?? session?.email ?? "").trimmingCharacters(in: .whitespaces)
        return e.isEmpty ? nil : e
    }

    /// Email draft for a finished report: To client + agent, CC the inspector, BCC the platform copy when on.
    func reportMailDraft(_ insp: Inspection, pdf: URL) -> ReportMailDraft {
        ReportMailDraft.make(insp, company: company, platform: platform, pdf: pdf, ccInspector: reportCcEmail)
    }

    /// Per-owner file folders (Documents/vims/…).
    var userFolder: String { "users/\(currentUser?.id.uuidString ?? "anonymous")" }
    var companyFolder: String { "companies/\(companyID?.uuidString ?? "none")" }
    var files: FileStore { repo.files }

    // MARK: Persistence

    private func scheduleAppSave() {
        guard !loadingSession, currentUser != nil else { return }
        appSaveTask?.cancel()
        appSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            self?.saveAppStateNow()
        }
    }

    private func saveAppStateNow() {
        guard let user = currentUser, let cid = companyID else { return }
        repo.saveCompany(CompanyState(id: cid, profile: state.company, subscription: state.subscription, overrides: state.overrides))
        var u = repo.user(id: user.id) ?? user
        u.settings = state.settings
        if let s = state.session { u.name = s.name }
        repo.updateUser(u)
        currentUser = u
    }

    func flushNow() {
        guard let user = currentUser, let cid = companyID else { return }
        appSaveTask?.cancel()
        saveAppStateNow()
        for t in inspectionSaveTasks.values { t.cancel() }
        inspectionSaveTasks = [:]
        inspections.forEach { repo.saveInspection($0, userID: user.id, companyID: cid) }
    }

    private func sortInspections() {
        inspections.sort { $0.scheduled < $1.scheduled }
    }

    // MARK: Toast

    func toast(_ message: String) {
        toastMessage = message
        let id = UUID()
        toastID = id
        Task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            if self.toastID == id { withAnimation { self.toastMessage = nil } }
        }
    }

    // MARK: Navigation

    func push(_ r: Route) { path.append(r) }
    func goHome() { path.removeAll() }
    func back() { if !path.isEmpty { path.removeLast() } }

    /// Pop back to the sections overview for an inspection (push it if it isn't on the stack).
    func popToSections(_ id: UUID) {
        if let i = path.lastIndex(of: .sections(id)) {
            path = Array(path.prefix(through: i))
        } else {
            path = [.sections(id)]
        }
    }

    func popTo(_ route: Route) {
        if let i = path.lastIndex(of: route) { path = Array(path.prefix(through: i)) } else { path.append(route) }
    }

    // MARK: Session (per-user isolation)

    /// Loads ONLY this user's inspections and their company's shared data.
    func loadSession(_ u: UserAccount) {
        guard var c = repo.company(id: u.companyID) else { return }
        // QA Oct 14: the signed-in user's inspector row must carry the user's id (the demo seed and invited inspectors were
        // created with their own ids), or the owner isn't recognized and Make owner / own-row checks fail. Healed once.
        if !c.profile.inspectors.contains(where: { $0.id == u.id }),
           let i = c.profile.inspectors.firstIndex(where: { !$0.email.isEmpty && $0.email.caseInsensitiveCompare(u.email) == .orderedSame }) {
            c.profile.inspectors[i].id = u.id
            repo.saveCompany(c)
        }
        loadingSession = true
        defer { loadingSession = false }
        currentUser = u
        companyID = c.id
        let me = c.profile.inspectors.first { $0.id == u.id || $0.email.caseInsensitiveCompare(u.email) == .orderedSame }
        let blank = DemoSeed.emptyState(config: config)
        state = AppState(session: Session(name: u.name, email: u.email, inspectorID: me?.id ?? u.id, isAdmin: me?.isAdmin ?? false,
                                         isPlatformOwner: PlatformOwner.isOwner(email: u.email, config: config)),
                         company: c.profile, subscription: c.subscription, overrides: c.overrides,
                         settings: u.settings ?? blank.settings, seededAt: nil)
        applyPlatformPricing()
        inspections = repo.inspections(userID: u.id)
        // Client Oct 17: older combined addresses become street / City / State / ZIP code (saved once).
        for i in inspections.indices where inspections[i].splitLegacyAddress(states: config.states ?? []) {
            repo.saveInspection(inspections[i], userID: u.id, companyID: c.id)
        }
        sortInspections()
        repo.currentUserID = u.id
        path = []
    }

    // MARK: License agreement (EULA)

    /// True when the signed-in user hasn't accepted the current eula.json version (never accepted, or
    /// the client revised it). RootView then shows the full-screen re-acceptance gate.
    var needsEulaAcceptance: Bool {
        guard let u = currentUser, !DebugFlags.skipEulaGate else { return false }
        return u.eulaVersion != eula.version
    }

    /// Records acceptance of the current EULA on the user.
    /// TODO(backend): send { userID, companyID, eulaVersion, acceptedAt } to the server as the legal record.
    private func stampEula(_ u: inout UserAccount) {
        u.eulaVersion = eula.version
        u.eulaAcceptedAt = Date()
    }

    func acceptEula() {
        guard let cur = currentUser else { return }
        var u = repo.user(id: cur.id) ?? cur
        stampEula(&u)
        repo.updateUser(u)
        currentUser = u
        toast("License agreement accepted")
    }

    func signIn(email: String, password: String) async throws {
        let u = try await auth.signIn(email: email, password: password)
        loadSession(u)
        presentSplashIfNeeded()
    }

    /// Create account = a new user + a new company (the user is its owner/admin). Starts empty.
    func createAccount(name: String, company: String, email: String, password: String) async throws {
        let cid = UUID()
        var u = try await auth.register(name: name, email: email, password: password, companyID: cid)
        stampEula(&u)                                   // the Create account checkbox is required
        repo.updateUser(u)
        repo.saveCompany(Bootstrap.newCompany(name: company, owner: u, config: config, repo: repo))
        loadSession(u)
        presentSplashIfNeeded()
    }

    /// Join with code = attach the user (new, or an existing account after its password checks out) to that company.
    func joinCompany(code: String, name: String, email: String, password: String) async throws {
        guard var c = repo.company(joinCode: code) else { throw ServiceError.invalid("No company uses that code. Check it with your company admin.") }
        var u: UserAccount
        if let existing = repo.user(email: email) {
            u = try await auth.signIn(email: email, password: password)
            if existing.companyID != c.id { u.companyID = c.id; repo.updateUser(u) }
        } else {
            u = try await auth.register(name: name, email: email, password: password, companyID: c.id)
        }
        // Inspectors joining a company are bound by the agreement too (the Join checkbox is required).
        stampEula(&u)
        repo.updateUser(u)
        if let i = c.profile.inspectors.firstIndex(where: { $0.email.caseInsensitiveCompare(u.email) == .orderedSame }) {
            c.profile.inspectors[i].id = u.id            // an invited inspector signing up
        } else if !c.profile.inspectors.contains(where: { $0.id == u.id }) {
            c.profile.inspectors.append(Inspector(id: u.id, name: u.name, email: u.email))
        }
        repo.saveCompany(c)
        loadSession(u)
        toast("Linked to \(c.profile.name)")
    }

    /// Clears everything in memory; the next user starts from a clean slate.
    func signOut() {
        flushNow()
        repo.currentUserID = nil
        loadingSession = true
        currentUser = nil
        companyID = nil
        inspections = []
        state = DemoSeed.emptyState(config: config)
        loadingSession = false
        path = []
        showSplash = false
    }

    func presentSplashIfNeeded() {
        guard state.session != nil, !state.subscription.active, !DebugFlags.suppressSplash else { return }
        Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            withAnimation(.easeOut(duration: 0.24)) { self.showSplash = true }
        }
    }

    // MARK: Inspections

    func inspection(_ id: UUID) -> Inspection? { inspections.first { $0.id == id } }

    func update(_ id: UUID, markDirty: Bool = true, _ body: (inout Inspection) -> Void) {
        guard let i = inspections.firstIndex(where: { $0.id == id }) else { return }
        body(&inspections[i])
        if markDirty {
            inspections[i].needsSync = true
            if syncing { editedDuringSync.insert(id) }
            requestAutoSync()
        }
        scheduleSave(inspections[i].id)
    }

    private func scheduleSave(_ id: UUID) {
        inspectionSaveTasks[id]?.cancel()
        inspectionSaveTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            guard let self, let insp = self.inspection(id), let uid = self.currentUser?.id, let cid = self.companyID else { return }
            self.repo.saveInspection(insp, userID: uid, companyID: cid)
        }
    }

    func newInspectionDraft() -> Inspection {
        let w = config.wizard
        let d = w.defaults
        var fields: [String: String] = [:]
        for e in w.step1 + w.step2 where e.kind == "chips" {
            if let def = e.default, e.id != "wdepth" { fields[e.label] = def }
        }
        let lic = state.company.license.trimmingCharacters(in: .whitespaces)
        if !lic.isEmpty { fields[Inspection.licenseField] = lic }
        fields["Date"] = Fmt.date(Date(), "yyyy-MM-dd")
        fields["Time"] = Fmt.date(Calendar.current.date(bySetting: .minute, value: 0, of: Date().addingTimeInterval(3600)) ?? Date(), "HH:mm")
        return Inspection(
            fields: fields,
            inspType: d.inspType ?? "",          // v1.9.1: nothing preselected; Type of inspection is required
            structure: d.structure,
            depth: state.settings.defaultDepth,
            exterior: w.exteriorOptions.filter { (d.exterior[$0] ?? 0) > 0 },
            rooms: w.roomOptions.filter { (d.rooms[$0] ?? 0) > 0 },
            utilities: w.utilityOptions.filter { (d.utilOpt[$0] ?? 0) > 0 },
            tests: w.testOptions.filter { (d.tests[$0] ?? 0) > 0 },
            counts: ["bedrooms": d.bedrooms, "bathrooms": d.bathrooms, "hallways": d.hallways],
            cover: state.settings.defaultCover
        )
    }

    /// Editing an inspection whose custom sections were kept by a checklist restore (`savedSections`, client Oct 28): the
    /// rebuilt section list keeps them in the group they were in, so its saved checklist doesn't lose them.
    private func keepSavedCustomSections(_ insp: inout Inspection) {
        guard let saved = insp.savedSections, !saved.isEmpty, let old = inspection(insp.id) else { return }
        let isCustom = { (n: String) in saved[n] != nil && !self.config.sections.contains { $0.name == ChecklistCatalog.baseName(n) } }
        let have = Set(insp.leafSections)
        for gi in insp.groups.indices {
            guard let og = old.groups.first(where: { $0.heading == insp.groups[gi].heading }) else { continue }
            for n in og.sections where isCustom(n) && !have.contains(n) { insp.groups[gi].sections.append(n) }
            if let osub = og.sub, insp.groups[gi].sub != nil {
                for n in osub.sections where isCustom(n) && !have.contains(n) { insp.groups[gi].sub?.sections.append(n) }
            }
        }
    }

    /// Wizard "Build checklist": creates (or updates) the inspection and its section list.
    @discardableResult
    func buildChecklist(from draft: Inspection) -> UUID {
        var insp = draft
        insp.splitLegacyAddress(states: config.states ?? [])
        insp.groups = catalog(for: insp).buildGroups(for: insp)
        keepSavedCustomSections(&insp)
        for n in insp.leafSections where insp.status[n] == nil { insp.status[n] = .todo }
        insp.needsSync = true
        if syncing { editedDuringSync.insert(insp.id) }
        requestAutoSync()
        if let i = inspections.firstIndex(where: { $0.id == insp.id }) {
            inspections[i] = insp
        } else {
            inspections.append(insp)
        }
        sortInspections()
        if let uid = currentUser?.id, let cid = companyID { repo.saveInspection(insp, userID: uid, companyID: cid) }
        return insp.id
    }

    /// Deletes one of the signed-in inspector's inspections from this device: the record, its photos folder, its
    /// report PDF and any readable-name copy made for the share sheet. Only the owner can delete — `inspections`
    /// only ever holds the signed-in user's own, and the repository re-checks the owner before deleting.
    /// TODO(backend): once the VIMS server is live, reports are retained server-side (reports 3 years, agreements
    /// 5 years), so deleting here only frees device space; an inspection that never synced is gone for good, so
    /// the confirmation should say so (or sync first) when `needsSync` is still set.
    func deleteInspection(_ id: UUID) {
        guard let insp = inspection(id), let uid = currentUser?.id else { return }
        inspectionSaveTasks[id]?.cancel()      // a pending debounced save would write the record back
        inspectionSaveTasks[id] = nil
        inspections.removeAll { $0.id == id }
        repo.deleteInspection(id: id, userID: uid)
        try? FileManager.default.removeItem(at: Self.shareCopyURL(insp))
    }

    // MARK: Report sharing

    /// Where the share-sheet copy of a report goes (the stored PDF is named by inspection id).
    static func shareCopyURL(_ insp: Inspection) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Inspection Report - \(insp.addressLine1).pdf")
    }

    /// A copy of the report PDF with a readable file name for the share sheet (the stored file if copying fails).
    func shareableReportURL(_ id: UUID) -> URL? {
        guard let insp = inspection(id), let url = reportURL(id) else { return nil }
        let named = Self.shareCopyURL(insp)
        try? FileManager.default.removeItem(at: named)
        return (try? FileManager.default.copyItem(at: url, to: named)) != nil ? named : url
    }

    /// "Save or share report": the share sheet with the PDF (Save to Files, Mail, AirDrop…), a popover on `anchor` on iPad.
    /// `afterDismiss` waits for a menu / confirmation dialog to finish closing so the sheet can present.
    func shareReport(_ id: UUID, from anchor: PopoverAnchor?, afterDismiss: Bool = false) {
        guard let url = shareableReportURL(id) else { toast("The report PDF is missing"); return }
        guard afterDismiss else { ShareSheet.present([url], from: anchor); return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            ShareSheet.present([url], from: anchor)
        }
    }

    /// Default answers: forms have no Overall condition row, so no preselected overall.
    func defaultAnswers(_ section: String) -> SectionAnswers {
        defaultAnswers(section, catalog: catalog)
    }

    func defaultAnswers(_ section: String, catalog cat: ChecklistCatalog) -> SectionAnswers {
        SectionAnswers(overall: cat.isForm(section) ? nil : config.overallConditionDefault)
    }

    func answers(_ id: UUID, _ section: String) -> SectionAnswers {
        inspection(id)?.answers[section] ?? defaultAnswers(section, catalog: catalog(for: id))
    }

    /// The signed-in inspector's name (the inspection's "Inspector" field wins where one is set).
    var inspectorName: String { session?.name ?? company.inspectorName }

    /// v1.9 `prefill`: on a form section's first open, its prefill items start with the inspection / company values
    /// (Wind Mitigation owner name, address, city, ZIP, phone, email, license type, initials). Only empty answers.
    func prefilled(_ a: SectionAnswers, _ id: UUID, _ section: String) -> SectionAnswers {
        guard let insp = inspection(id), insp.answers[section] == nil else { return a }
        var out = a
        for k in ItemKeys.keyed(catalog(for: insp).items(section, depth: .standard).items) {
            guard let key = k.item.prefill, (out.text[k.id] ?? "").isEmpty else { continue }
            let v = insp.prefillValue(key, inspector: inspectorName).trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { out.text[k.id] = v }
        }
        return out
    }

    /// Photos-only sections (Pictures) open straight on their photo screen.
    func sectionRoute(_ id: UUID, _ section: String) -> Route {
        catalog(for: id).isPhotosOnly(section) ? .photos(id, section) : .section(id, section)
    }

    /// Pictures page primary button: marks it done, then Summary (Texas) or Report (4 Point).
    func finishPictures(_ id: UUID, _ section: String) {
        markDone(id, section)
        toast("Pictures saved")
        let toSummary = inspection(id)?.hasSummary ?? true
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            self.popToSections(id)
            self.push(toSummary ? .summary(id) : .report(id))
        }
    }

    func setAnswers(_ id: UUID, _ section: String, _ a: SectionAnswers) {
        update(id) { insp in
            insp.answers[section] = a
            if insp.status[section] == nil || insp.status[section] == .todo, a.hasContent { insp.status[section] = .prog }
        }
    }

    func markDone(_ id: UUID, _ section: String) {
        update(id) { insp in
            if insp.answers[section] == nil { insp.answers[section] = defaultAnswers(section) }
            insp.status[section] = .done
        }
    }

    func nextSection(_ id: UUID, after section: String) -> String? {
        guard let leafs = inspection(id)?.leafSections, let i = leafs.firstIndex(of: section), i + 1 < leafs.count else { return nil }
        return leafs[i + 1]
    }

    enum HomeStatus { case done, queued, prog, scheduled }

    func homeStatus(_ insp: Inspection) -> HomeStatus {
        // "Queued" = report waiting to sync — only with sync on (data v1.10 `features.sync`; Phase 1 doesn't sync).
        if insp.report != nil { return syncEnabled && insp.needsSync ? .queued : .done }
        if insp.status.values.contains(where: { $0 != .todo }) || insp.answers.values.contains(where: \.hasContent) { return .prog }
        return .scheduled
    }

    // MARK: Photos

    func addPhoto(_ id: UUID, section: String, category: String, image: UIImage) -> PhotoRef? {
        guard let data = ImageTools.jpegData(image) else { return nil }
        let pid = UUID()
        guard let path = files.saveImage(data, folder: "\(userFolder)/photos/\(id.uuidString)", name: "\(pid.uuidString).jpg") else { return nil }
        let ref = PhotoRef(id: pid, file: path)
        update(id) { insp in
            insp.photos[section, default: [:]][category, default: []].append(ref)
            if insp.status[section] == nil || insp.status[section] == .todo { insp.status[section] = .prog }
        }
        return ref
    }

    func deletePhoto(_ id: UUID, section: String, category: String, photoID: UUID) {
        guard let ref = inspection(id)?.photos[section]?[category]?.first(where: { $0.id == photoID }) else { return }
        update(id) { insp in
            insp.photos[section]?[category]?.removeAll { $0.id == photoID }
            for i in insp.findings.indices where insp.findings[i].photoID == photoID { insp.findings[i].photoID = nil }
        }
        files.deleteFile(ref.file)
        if let o = ref.originalFile { files.deleteFile(o) }
    }

    func photo(_ id: UUID, section: String, category: String, photoID: UUID) -> PhotoRef? {
        inspection(id)?.photos[section]?[category]?.first { $0.id == photoID }
    }

    /// Saves the flattened markup image (keeps the unmarked original once) and the comment.
    func saveMarkup(_ id: UUID, section: String, category: String, photoID: UUID, flattened: UIImage?, comment: String?) {
        guard var ref = photo(id, section: section, category: category, photoID: photoID) else { return }
        if let flattened, let data = ImageTools.jpegData(flattened, maxEdge: 2400, quality: 0.85) {
            if ref.originalFile == nil {
                let origName = "\(photoID.uuidString)-orig.jpg"
                if let d = try? Data(contentsOf: repo.url(for: ref.file)) {
                    ref.originalFile = files.saveImage(d, folder: "\(userFolder)/photos/\(id.uuidString)", name: origName)
                }
            }
            _ = files.saveImage(data, folder: "\(userFolder)/photos/\(id.uuidString)", name: "\(photoID.uuidString).jpg")
        }
        let trimmed = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        ref.comment = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let updated = ref
        update(id) { insp in
            if let i = insp.photos[section]?[category]?.firstIndex(where: { $0.id == photoID }) {
                insp.photos[section]?[category]?[i] = updated
            }
        }
    }

    // MARK: Findings

    /// `custom` is the typed comment, `quick` the canned quick comment (client Oct 16: stored apart, shown as
    /// "Section — custom — quick"). `item`: a checklist item's question when the finding comes from its "Concern(s)"
    /// answer — the custom part is then "<item>: <description>", or just "<item>" without a description, and the
    /// item is kept on the finding.
    func addFinding(_ id: UUID, category: Int, custom: String, quick: String? = nil, section: String,
                    photo: (String, UUID)? = nil, item: String? = nil) {
        let q = (quick ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var c = Finding.customPart(custom, quick: q)
        if let item { c = c.isEmpty ? item : "\(item): \(c)" }
        if c.isEmpty && q.isEmpty { c = "Finding noted" }
        let text = [c, q].filter { !$0.isEmpty }.joined(separator: " — ")
        update(id) { insp in
            insp.findings.append(Finding(category: category, text: text, section: section, photoID: photo?.1, item: item, custom: c, quick: q))
            if let (cat, pid) = photo, let i = insp.photos[section]?[cat]?.firstIndex(where: { $0.id == pid }) {
                insp.photos[section]?[cat]?[i].flag = category
            }
        }
        toast("Finding added to summary")
    }

    func deleteFinding(_ id: UUID, findingID: UUID) {
        update(id) { insp in
            guard let f = insp.findings.first(where: { $0.id == findingID }) else { return }
            insp.findings.removeAll { $0.id == findingID }
            if let pid = f.photoID, !insp.findings.contains(where: { $0.photoID == pid }) {
                for (cat, arr) in insp.photos[f.section] ?? [:] {
                    if let i = arr.firstIndex(where: { $0.id == pid }) { insp.photos[f.section]?[cat]?[i].flag = nil }
                }
            }
        }
    }

    // MARK: Report

    func reportURL(_ id: UUID) -> URL? {
        guard let r = inspection(id)?.report else { return nil }
        let u = repo.url(for: r.file)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    func reportData(_ id: UUID) -> ReportData? {
        guard let insp = inspection(id) else { return nil }
        return ReportData.make(insp, config: config, overrides: catalog(for: insp).overrides, company: state.company, repo: files, logo: companyLogoImage())
    }

    /// Renders the PDF on-device and saves it under reports/.
    func generateReport(_ id: UUID) async -> ReportInfo? {
        guard let data = reportData(id) else { return nil }
        let result = await Task.detached(priority: .userInitiated) { ReportRenderer.render(data) }.value
        guard let path = files.saveFile(result.pdf, folder: "\(userFolder)/reports", name: "\(id.uuidString).pdf") else { return nil }
        let info = ReportInfo(generatedAt: Date(), pageCount: result.pageCount, file: path)
        update(id) { $0.report = info }
        state.settings.defaultCover = inspection(id)?.cover ?? state.settings.defaultCover
        return info
    }

    // MARK: Sync

    /// Settings → Sync now (always available, with or without auto-sync).
    func syncNow() async {
        guard syncEnabled else { return }
        await performSync(manual: true)
    }

    /// Team QA Oct 22: with "Auto-sync when online" on, queued inspections sync by themselves — when the connection
    /// comes back, when the app comes to the foreground, and a few seconds after a save / report (the delay restarts on
    /// every edit, so typing doesn't sync each keystroke). Off = Sync now only. Quiet: no toast; the header pill and
    /// "N inspections waiting" update as inspections go out. TODO(backend): the upload itself is `syncService`.
    func requestAutoSync(after seconds: Double = 3) {
        guard syncEnabled, state.settings.autoSync, state.session != nil else { return }
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.state.settings.autoSync, self.state.session != nil, self.isOnline, self.pendingSyncCount > 0 else { return }
            if self.syncing { self.requestAutoSync(after: 1); return }
            await self.performSync(manual: false)
        }
    }

    func setOnline(_ online: Bool) {
        var online = online
        #if DEBUG
        if let until = debugOfflineUntil {
            if Date() < until { online = false } else { debugOfflineUntil = nil }
        }
        #endif
        let cameOnline = online && !isOnline
        if isOnline != online { isOnline = online }
        if cameOnline { requestAutoSync(after: 1) }
    }

    private func performSync(manual: Bool) async {
        guard syncEnabled, !syncing else { return }
        syncing = true
        editedDuringSync = []
        do {
            // TODO(backend): Laravel API upload (LocalSyncService is the on-device stub).
            let ids = try await syncService.sync(inspections)
            let synced = ids.filter { !editedDuringSync.contains($0) }
            for id in synced {
                update(id, markDirty: false) { $0.needsSync = false; $0.syncedAt = Date() }
            }
            #if DEBUG
            print("AUTOSYNC \(manual ? "manual" : "auto") synced=\(synced.count) stillQueued=\(pendingSyncCount) online=\(isOnline)")
            #endif
            if manual { toast("Synced to portal") }
        } catch {
            if manual { toast("Sync failed — will retry when online") }
        }
        syncing = false
        // Edited mid-upload: they're still queued, so go again shortly.
        if !editedDuringSync.isEmpty { editedDuringSync = []; requestAutoSync() }
    }

    // MARK: Admin — checklist

    func addCustomSection(name: String, group: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { toast("Enter a section name"); return false }
        if catalog.section(n) == nil {
            state.overrides.sections[n] = SectionDef(
                name: n, number: 99, icon: nil,
                photoCategories: ["Overview", "Concerns"], photoCategoriesHigh: nil,
                items: [.question("Condition", options: ["Good", "Fair", "Poor", "N/A"])], itemsHigh: nil)
        }
        if !(state.overrides.custom[group] ?? []).contains(n) {
            state.overrides.custom[group, default: []].append(n)
        }
        toast("Added “\(n)”")
        return true
    }

    func isCustomSection(_ name: String) -> Bool {
        state.overrides.custom.values.contains { $0.contains(name) }
    }

    func removeCustomSection(_ name: String) {
        for k in state.overrides.custom.keys { state.overrides.custom[k]?.removeAll { $0 == name } }
        state.overrides.sections[name] = nil
        toast("Removed “\(name)”")
    }

    /// A VIMS section this company has edited (custom sections are tagged "Custom" instead).
    func isEditedSection(_ name: String) -> Bool {
        state.overrides.sections[name] != nil && !isCustomSection(name)
    }

    var editedSectionCount: Int { state.overrides.sections.keys.filter { !isCustomSection($0) }.count }
    var customSectionCount: Int { Set(state.overrides.custom.values.flatMap { $0 }).count }
    var hasChecklistEdits: Bool { !state.overrides.sections.isEmpty || customSectionCount > 0 }

    /// Client Oct 28 — Manage checklist → "Restore original" on an edited section: removes the company's edits to it, so
    /// new inspections get the VIMS default from the shared JSON. Inspections already created keep their saved checklist.
    func restoreSection(_ name: String) {
        guard isAdmin, isEditedSection(name) else { return }
        keepSavedChecklist([name])
        state.overrides.sections[name] = nil
        saveAppStateNow()
        toast("\u{201C}\(catalog.title(name))\u{201D} restored to the original")
    }

    /// Client Oct 28 — "Restore entire checklist to original": removes every company edit (edited items and sections,
    /// custom sections). Inspections already created keep their saved checklist. TODO(backend): sync the reset.
    func restoreEntireChecklist() {
        guard isAdmin, hasChecklistEdits else { return }
        keepSavedChecklist(Array(state.overrides.sections.keys))
        state.overrides = ChecklistOverrides()
        saveAppStateNow()
        toast("Checklist restored to the VIMS original")
    }

    /// Before a restore removes these section definitions, every inspection of this company on the device that uses one
    /// of them (the signed-in user's and teammates' who signed in here) keeps a copy in `savedSections`.
    private func keepSavedChecklist(_ names: [String]) {
        let defs = names.reduce(into: [String: SectionDef]()) { $0[$1] = state.overrides.sections[$1] }
        guard !defs.isEmpty, let cid = companyID else { return }
        func keep(_ insp: inout Inspection) -> Bool {
            let used = Set(insp.groups.flatMap(\.leafSections).flatMap { [$0, ChecklistCatalog.baseName($0)] })
            var changed = false
            for (n, d) in defs where used.contains(n) && insp.savedSections?[n] == nil {
                insp.savedSections = (insp.savedSections ?? [:]).merging([n: d]) { a, _ in a }
                changed = true
            }
            return changed
        }
        for i in inspections.indices where keep(&inspections[i]) {
            if let uid = currentUser?.id { repo.saveInspection(inspections[i], userID: uid, companyID: cid) }
        }
        for member in state.company.inspectors where member.id != currentUser?.id && repo.user(id: member.id)?.companyID == cid {
            for var insp in repo.inspections(userID: member.id) where keep(&insp) {
                repo.saveInspection(insp, userID: member.id, companyID: cid)
            }
        }
    }

    func saveSectionOverride(_ def: SectionDef) {
        var def = def
        def.baseItems = catalog.jsonItemKeys(def.name)     // later JSON additions still show (data v1.10)
        state.overrides.sections[def.name] = def
        toast("Checklist updated")
    }

    // MARK: Admin — plans, inspectors, subscription

    func seats() -> Int { max(1, state.company.inspectors.count) }

    // MARK: Master admin — VIMS plans & prices (client Oct 28, data v1.11)

    /// The VIMS plans and per-inspector rates every company subscribes to (stored master-admin edits, else the JSON).
    var pricing: PlatformSettings.Pricing { platform.pricing(config) }

    /// Plans & pricing (master admin only): saves the whole plan list + rates VIMS-wide and refreshes this company's copy.
    /// TODO(backend): the server owns the plans (Square catalog) and enforces the master-admin role.
    func savePricing(_ p: PlatformSettings.Pricing) {
        guard isPlatformOwner, !p.plans.isEmpty else { return }
        var s = platform
        s.plans = p.plans
        s.extraInspectorMonthly = p.extraMonthly
        s.extraInspectorYearly = p.extraYearly
        savePlatform(s)
        applyPlatformPricing()
    }

    /// Plans & pricing → delete a plan (master admin). At least one plan always stays; a company on the deleted plan moves
    /// to the first remaining one it can pick. TODO(backend): DELETE the plan on the server (Square catalog item).
    func deletePlan(_ id: String) {
        var p = pricing
        guard isPlatformOwner, p.plans.count > 1, let i = p.plans.firstIndex(where: { $0.id == id }) else { return }
        let removed = p.plans.remove(at: i)
        savePricing(p)
        toast("Deleted \u{201C}\(removed.name)\u{201D}")
    }

    /// Mirrors the VIMS plans into the signed-in company's subscription (older builds kept a per-company copy that company
    /// admins could edit — it is replaced here, so upgraded companies get the current prices). A company whose plan was
    /// deleted, or that sits on a "Coming soon" plan without an active subscription, moves to the first plan it can pick.
    func applyPlatformPricing() {
        let p = pricing
        var sub = state.subscription
        sub.plans = p.plans
        sub.extraInspectorMonthly = p.extraMonthly
        sub.extraInspectorYearly = p.extraYearly
        let current = sub.plan(sub.selectedPlan)
        if current == nil || (current?.isSelectable == false && !sub.active),
           let first = p.plans.first(where: \.isSelectable) ?? p.plans.first {
            sub.selectedPlan = first.id
        }
        if sub.plan(sub.selectedPlan)?.hasYearly != true, sub.billingPeriod == BillingPeriod.yearly.rawValue { sub.billingPeriod = nil }
        if sub != state.subscription { state.subscription = sub }
    }

    func addInspector(name: String, email: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { toast("Enter a name"); return false }
        state.company.inspectors.append(Inspector(name: n, email: email.trimmingCharacters(in: .whitespaces)))
        let per = state.subscription.period
        toast("Inspector added · +\(Fmt.money(state.subscription.extraRate(per)))\(per.unit)")
        return true
    }

    /// The signed-in user's row in the company's inspector list (by id; by email for a row created before the account).
    private var myInspectorIndex: Int? {
        guard let me = currentUser else { return nil }
        return state.company.inspectors.firstIndex { $0.id == me.id }
            ?? state.company.inspectors.firstIndex { !$0.email.isEmpty && $0.email.caseInsensitiveCompare(me.email) == .orderedSame }
    }

    /// The signed-in user's inspector id (the user id once `loadSession` has healed the row).
    var myInspectorID: UUID? { myInspectorIndex.map { state.company.inspectors[$0].id } }

    /// The signed-in user is the company's owner.
    var isCompanyOwner: Bool { myInspectorIndex.map { state.company.inspectors[$0].owner } ?? false }

    /// Only the CURRENT owner can hand ownership to another team member (security: an admin can never take it). The new
    /// owner is made an admin; the old owner stays an admin and can only get ownership back from the new owner.
    /// TODO(backend): the server enforces this (owner-only transfer).
    func makeOwner(_ id: UUID) {
        guard isCompanyOwner, let m = myInspectorIndex, id != state.company.inspectors[m].id,
              let t = state.company.inspectors.firstIndex(where: { $0.id == id }), !state.company.inspectors[t].email.isEmpty else { return }
        var team = state.company.inspectors          // one write, so the change is saved as a whole
        team[m].owner = false
        team[m].admin = true
        team[t].owner = true
        team[t].admin = true
        state.company.inspectors = team
        state.session?.isAdmin = true
        saveAppStateNow()
        toast("\(team[t].name) is now the owner")
    }

    /// Other people on this company who have a VIMS account (not just an invite).
    var otherCompanyUsers: [Inspector] {
        state.company.inspectors.filter { $0.id != currentUser?.id && repo.user(id: $0.id) != nil }
    }

    /// App Store 5.1.1(v) account deletion. Deletes the user, their inspections, photos and reports on this
    /// device. An owner who is alone on the company also deletes the company (subscription cancelled).
    /// TODO(backend): send a deletion request to the server (completed within 10 working days per the EULA).
    enum DeleteAccountBlock: Error { case ownerWithTeam }
    func deleteAccount() async throws {
        guard let me = currentUser, let cid = companyID else { return }
        if isCompanyOwner && !otherCompanyUsers.isEmpty { throw DeleteAccountBlock.ownerWithTeam }
        flushNow()
        if isCompanyOwner {
            if state.subscription.active && !state.subscription.cancelled {
                try? await subscriptionService.cancelSubscription()
                state.subscription.cancelledAt = Date()
            }
            loadingSession = true          // don't re-save the company we're deleting
            repo.deleteCompany(id: cid)
            // Invited inspectors without an account go with the company.
        } else if var c = repo.company(id: cid) {
            c.profile.inspectors.removeAll { $0.id == me.id }
            repo.saveCompany(c)
        }
        repo.deleteUser(id: me.id)
        loadingSession = false
        repo.currentUserID = nil
        currentUser = nil
        companyID = nil
        inspections = []
        loadingSession = true
        state = DemoSeed.emptyState(config: config)
        loadingSession = false
        path = []
        showSplash = false
        toast("Your account was deleted")
    }

    /// Admins only; never the owner or yourself. TODO(backend): DELETE the member on the server.
    func removeInspector(_ id: UUID) {
        guard isAdmin else { return }
        state.company.inspectors.removeAll { $0.id == id && !$0.owner && $0.id != myInspectorID }
        saveAppStateNow()
    }

    /// Admins grant / take back admin access (never on the owner or their own row). Saved right away.
    func toggleAdmin(_ id: UUID) {
        guard isAdmin, id != myInspectorID,
              let i = state.company.inspectors.firstIndex(where: { $0.id == id }), !state.company.inspectors[i].owner else { return }
        state.company.inspectors[i].admin.toggle()
        let ins = state.company.inspectors[i]
        saveAppStateNow()
        toast(ins.admin ? "\(ins.name) is now an admin" : "\(ins.name) is no longer an admin")
    }

    /// Subscribe → Start / Update subscription with the plan and Monthly / Yearly period chosen on the screen (a plan
    /// without a yearly price is monthly; "Coming soon" plans can't be started).
    func startSubscription(planID: String, period: BillingPeriod, payment: SubscriptionPayment) async throws {
        guard let plan = state.subscription.plan(planID), plan.isSelectable else {
            throw ServiceError.invalid("That plan isn't available yet. Choose another plan.")
        }
        let per: BillingPeriod = plan.hasYearly ? period : .monthly
        let (label, card) = try await subscriptionService.startSubscription(planID: planID, period: per, seats: seats(), payment: payment)
        state.subscription.selectedPlan = planID
        state.subscription.billingPeriod = per.rawValue
        state.subscription.active = true
        state.subscription.paymentLabel = label
        state.subscription.cardOnFile = card
        state.subscription.startedAt = Date()
        state.subscription.cancelledAt = nil
    }

    /// Owner/admin only. Stays active until the end of the billing period, then stops renewing.
    func cancelSubscription() async throws {
        guard isAdmin, state.subscription.active else { return }
        try await subscriptionService.cancelSubscription()
        state.subscription.cancelledAt = Date()
        toast("Subscription cancelled — active until \(Fmt.date(state.subscription.nextBillingDate, "MMM d, yyyy").replacingOccurrences(of: " ", with: "\u{00A0}"))")
    }

    func resumeSubscription() async throws {
        guard isAdmin, state.subscription.cancelled else { return }
        try await subscriptionService.resumeSubscription()
        state.subscription.cancelledAt = nil
        toast("Cancellation undone — auto-pay continues")
    }

    // MARK: Company files (per company)

    func saveLogo(_ image: UIImage) {
        guard isAdmin else { return }        // company profile edits are admin-only (QA Oct 14)
        // Normalize (orientation, max 1024 px) and keep transparency.
        let side = min(1024, max(image.size.width, image.size.height))
        let scale = side / max(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = normalized.pngData() else { return }
        let name = "logo-\(UUID().uuidString.prefix(8)).png"
        if let old = state.company.logoFile { files.deleteFile(old) }
        state.company.logoFile = files.saveImage(data, folder: companyFolder, name: name)
        saveAppStateNow()
        toast("Logo updated")
    }

    func removeLogo() {
        guard isAdmin else { return }        // company profile edits are admin-only (QA Oct 14)
        guard let old = state.company.logoFile else { return }
        files.deleteFile(old)
        state.company.logoFile = nil
        saveAppStateNow()
        toast("Logo removed")
    }

    // MARK: Profile photo (per user — never the company logo)

    /// Saves the signed-in user's own profile photo (square-cropped, 512 px JPEG) under users/<id>/.
    /// TODO(backend): upload to the user's profile on the server.
    func saveProfilePhoto(_ image: UIImage) {
        guard let cur = currentUser else { return }
        let side = min(image.size.width, image.size.height)
        let out: CGFloat = min(512, side)
        let scale = out / side
        let draw = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: fmt).image { _ in
            image.draw(in: CGRect(x: (out - draw.width) / 2, y: (out - draw.height) / 2, width: draw.width, height: draw.height))
        }
        guard let data = img.jpegData(compressionQuality: 0.85) else { return }
        var u = repo.user(id: cur.id) ?? cur
        if let old = u.photoFile { files.deleteFile(old) }
        u.photoFile = files.saveImage(data, folder: userFolder, name: "profile-\(UUID().uuidString.prefix(8)).jpg")
        repo.updateUser(u)
        currentUser = u
        toast("Profile photo updated")
    }

    func removeProfilePhoto() {
        guard let cur = currentUser else { return }
        var u = repo.user(id: cur.id) ?? cur
        guard let old = u.photoFile else { return }
        files.deleteFile(old)
        u.photoFile = nil
        repo.updateUser(u)
        currentUser = u
        toast("Profile photo removed")
    }

    /// A user's own profile photo (nil → initials). Works for any teammate on this device.
    func profilePhoto(userID: UUID) -> UIImage? {
        let f = userID == currentUser?.id ? currentUser?.photoFile : repo.user(id: userID)?.photoFile
        guard let f else { return nil }
        return UIImage(contentsOfFile: files.url(for: f).path)
    }

    /// The company's uploaded logo, or nil (UI shows the initials badge).
    func companyLogoImage() -> UIImage? {
        guard let f = state.company.logoFile else { return nil }
        return UIImage(contentsOfFile: files.url(for: f).path)
    }

    /// Which agreement the company uses: the VIMS default, its edited copy of it, or its own uploaded file.
    enum AgreementInUse: Equatable { case vims, edited, uploaded }

    var agreementInUse: AgreementInUse {
        if state.company.agreementFile != nil { return .uploaded }
        if let t = state.company.agreementText, !t.isEmpty { return .edited }
        return .vims
    }

    /// The locked form lines of the agreement (VIMS agreement `formLines`, company name filled). Shown read-only in
    /// "Edit agreement" and always part of an edited agreement in the viewer and the PDF. Filling them in / signing
    /// is the deferred e-sign add-on.
    var agreementFormLines: [String] {
        InspectionAgreement.bundled.map { $0.formLines.map { InspectionAgreement.fill($0, company: company.name) } } ?? []
    }

    /// The company's edited agreement as shown in the viewer / PDF (locked form block included), or nil.
    var editedAgreementContent: AgreementContent? {
        guard agreementInUse == .edited, let text = company.agreementText else { return nil }
        return .edited(text, company: company.name, form: agreementFormLines)
    }

    /// "Edit agreement" → Save: the edited text becomes this company's agreement and replaces an uploaded file.
    /// TODO(backend): PUT the edited agreement (text + editedAt) to the company record.
    func saveEditedAgreement(_ text: String) {
        guard isAdmin else { return }        // company profile edits are admin-only (QA Oct 14)
        if let old = state.company.agreementFile { files.deleteFile(old) }
        state.company.agreementFile = nil
        state.company.agreementName = nil
        state.company.agreementText = text
        state.company.agreementEditedAt = Date()
        toast("Your edited agreement is now in use")
    }

    func saveAgreement(from url: URL) {
        guard isAdmin else { return }        // company profile edits are admin-only (QA Oct 14)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { toast("Couldn't read that file"); return }
        if let old = state.company.agreementFile { files.deleteFile(old) }
        state.company.agreementFile = files.saveFile(data, folder: companyFolder, name: url.lastPathComponent)
        state.company.agreementName = url.lastPathComponent
        // An uploaded file replaces an edited copy of the VIMS agreement.
        state.company.agreementText = nil
        state.company.agreementEditedAt = nil
        toast("Your agreement is now in use")
    }

    /// The company's own uploaded agreement file (Company profile → Upload your own), nil = VIMS agreement in use.
    var ownAgreementURL: URL? {
        guard let f = state.company.agreementFile else { return nil }
        let url = files.url(for: f)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// "Use VIMS agreement": drop the uploaded file and/or the edited copy and go back to the VIMS default agreement.
    func useDefaultAgreement() {
        guard isAdmin else { return }        // company profile edits are admin-only (QA Oct 14)
        if let old = state.company.agreementFile { files.deleteFile(old) }
        state.company.agreementFile = nil
        state.company.agreementName = nil
        state.company.agreementText = nil
        state.company.agreementEditedAt = nil
        toast("Using the VIMS agreement")
    }
}
