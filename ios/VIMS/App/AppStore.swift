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
        didSet { scheduleAppSave() }
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

    @ObservationIgnored private var inspectionSaveTasks: [UUID: Task<Void, Never>] = [:]
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
        if let uid = repo.currentUserID, let u = repo.user(id: uid) { loadSession(u) } else { repo.currentUserID = nil }

        connectivity.onChange = { [weak self] online in self?.isOnline = online }
        connectivity.start()
    }

    var catalog: ChecklistCatalog { ChecklistCatalog(config: config, overrides: state.overrides) }
    var company: CompanyProfile { state.company }
    var subscription: SubscriptionState { state.subscription }
    var session: Session? { state.session }
    var isAdmin: Bool { state.session?.isAdmin ?? false }
    var isPlatformOwner: Bool { state.session?.isPlatformOwner ?? false }

    /// Platform-owner only (TODO(backend): enforced by the server as well).
    func savePlatform(_ s: PlatformSettings) {
        guard isPlatformOwner else { return }
        platform = s
        repo.savePlatformSettings(s)
    }
    var pendingSyncCount: Int { inspections.filter(\.needsSync).count }

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
        guard let c = repo.company(id: u.companyID) else { return }
        loadingSession = true
        defer { loadingSession = false }
        currentUser = u
        companyID = c.id
        let me = c.profile.inspectors.first { $0.id == u.id || $0.email.caseInsensitiveCompare(u.email) == .orderedSame }
        let blank = DemoSeed.emptyState(config: config)
        state = AppState(session: Session(name: u.name, email: u.email, inspectorID: me?.id ?? u.id, isAdmin: me?.isAdmin ?? false,
                                         isPlatformOwner: PlatformOwner.isOwner(email: u.email)),
                         company: c.profile, subscription: c.subscription, overrides: c.overrides,
                         settings: u.settings ?? blank.settings, seededAt: nil)
        inspections = repo.inspections(userID: u.id)
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
        if markDirty { inspections[i].needsSync = true }
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
            inspType: d.inspType,
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

    /// Wizard "Build checklist": creates (or updates) the inspection and its section list.
    @discardableResult
    func buildChecklist(from draft: Inspection) -> UUID {
        var insp = draft
        insp.groups = catalog.buildGroups(for: insp)
        for n in insp.leafSections where insp.status[n] == nil { insp.status[n] = .todo }
        insp.needsSync = true
        if let i = inspections.firstIndex(where: { $0.id == insp.id }) {
            inspections[i] = insp
        } else {
            inspections.append(insp)
        }
        sortInspections()
        if let uid = currentUser?.id, let cid = companyID { repo.saveInspection(insp, userID: uid, companyID: cid) }
        return insp.id
    }

    func deleteInspection(_ id: UUID) {
        inspections.removeAll { $0.id == id }
        if let uid = currentUser?.id { repo.deleteInspection(id: id, userID: uid) }
    }

    /// Default answers: forms have no Overall condition row, so no preselected overall.
    func defaultAnswers(_ section: String) -> SectionAnswers {
        SectionAnswers(overall: catalog.isForm(section) ? nil : config.overallConditionDefault)
    }

    func answers(_ id: UUID, _ section: String) -> SectionAnswers {
        inspection(id)?.answers[section] ?? defaultAnswers(section)
    }

    /// Photos-only sections (Pictures) open straight on their photo screen.
    func sectionRoute(_ id: UUID, _ section: String) -> Route {
        catalog.isPhotosOnly(section) ? .photos(id, section) : .section(id, section)
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
        if insp.report != nil { return insp.needsSync ? .queued : .done }
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

    func addFinding(_ id: UUID, category: Int, text: String, section: String, photo: (String, UUID)? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { insp in
            insp.findings.append(Finding(category: category, text: t.isEmpty ? "Finding noted" : t, section: section, photoID: photo?.1))
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
        return ReportData.make(insp, config: config, overrides: state.overrides, company: state.company, repo: files, logo: companyLogoImage())
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

    func syncNow() async {
        syncing = true
        defer { syncing = false }
        do {
            let ids = try await syncService.sync(inspections)
            for id in ids {
                update(id, markDirty: false) { $0.needsSync = false; $0.syncedAt = Date() }
            }
            toast("Synced to portal")
        } catch {
            toast("Sync failed — will retry when online")
        }
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

    func saveSectionOverride(_ def: SectionDef) {
        state.overrides.sections[def.name] = def
        toast("Checklist updated")
    }

    // MARK: Admin — plans, inspectors, subscription

    func seats() -> Int { max(1, state.company.inspectors.count) }

    func addInspector(name: String, email: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { toast("Enter a name"); return false }
        state.company.inspectors.append(Inspector(name: n, email: email.trimmingCharacters(in: .whitespaces)))
        toast("Inspector added · +\(Fmt.money(state.subscription.extraInspectorMonthly))/mo")
        return true
    }

    /// The signed-in user is the company's owner.
    var isCompanyOwner: Bool {
        guard let me = currentUser else { return false }
        return state.company.inspectors.contains { $0.id == me.id && $0.owner }
    }

    /// Owner only: hand ownership to another admin (the old owner stays an admin).
    func makeOwner(_ id: UUID) {
        guard isCompanyOwner, let me = currentUser,
              let t = state.company.inspectors.firstIndex(where: { $0.id == id }), state.company.inspectors[t].admin,
              let m = state.company.inspectors.firstIndex(where: { $0.id == me.id }) else { return }
        state.company.inspectors[m].owner = false
        state.company.inspectors[m].admin = true
        state.company.inspectors[t].owner = true
        state.company.inspectors[t].admin = true
        toast("\(state.company.inspectors[t].name) is now the owner")
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

    func removeInspector(_ id: UUID) {
        state.company.inspectors.removeAll { $0.id == id && !$0.owner }
    }

    func toggleAdmin(_ id: UUID) {
        guard let i = state.company.inspectors.firstIndex(where: { $0.id == id }), !state.company.inspectors[i].owner else { return }
        state.company.inspectors[i].admin.toggle()
        let ins = state.company.inspectors[i]
        if state.session?.inspectorID == ins.id { state.session?.isAdmin = ins.isAdmin }
        toast(ins.admin ? "\(ins.name) is now an admin" : "\(ins.name) is no longer an admin")
    }

    func startSubscription(card: CardEntry) async throws {
        let label = try await subscriptionService.startSubscription(planID: state.subscription.selectedPlan, seats: seats(), card: card)
        state.subscription.active = true
        state.subscription.paymentLabel = label
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

    func saveAgreement(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { toast("Couldn't read that file"); return }
        if let old = state.company.agreementFile { files.deleteFile(old) }
        state.company.agreementFile = files.saveFile(data, folder: companyFolder, name: url.lastPathComponent)
        state.company.agreementName = url.lastPathComponent
        toast("Agreement uploaded")
    }
}
