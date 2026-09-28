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
    case plans, inspectors, subscribe, subscriptionStarted, billing, feedbackAdmin
}

@MainActor
@Observable
final class AppStore {
    let config: ChecklistConfig
    let repo: FileRepository
    let auth: AuthService
    let subscriptionService: SubscriptionService
    let syncService: SyncService
    @ObservationIgnored private let connectivity = Connectivity()

    var state: AppState {
        didSet { scheduleAppSave() }
    }
    var inspections: [Inspection]
    var path: [Route] = []

    var toastMessage: String?
    var toastID = UUID()
    var showSplash = false
    var isOnline = true
    var syncing = false

    @ObservationIgnored private var inspectionSaveTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var appSaveTask: Task<Void, Never>?

    init(config: ChecklistConfig, repo: FileRepository,
         auth: AuthService = LocalAuthService(),
         subscriptionService: SubscriptionService = LocalSubscriptionService(),
         syncService: SyncService = LocalSyncService()) {
        self.config = config
        self.repo = repo
        self.auth = auth
        self.subscriptionService = subscriptionService
        self.syncService = syncService

        if let saved = repo.loadAppState() {
            state = saved
            inspections = repo.loadInspections()
        } else {
            // First launch: seed demo data equivalent to the prototype (see DemoSeed.swift).
            let seeded = DemoSeed.make(config: config, repo: repo)
            state = seeded.state
            inspections = seeded.inspections
            repo.saveAppState(seeded.state)
            seeded.inspections.forEach { repo.saveInspection($0) }
        }
        sortInspections()
        connectivity.onChange = { [weak self] online in self?.isOnline = online }
        connectivity.start()
    }

    var catalog: ChecklistCatalog { ChecklistCatalog(config: config, overrides: state.overrides) }
    var company: CompanyProfile { state.company }
    var subscription: SubscriptionState { state.subscription }
    var session: Session? { state.session }
    var isAdmin: Bool { state.session?.isAdmin ?? false }
    var pendingSyncCount: Int { inspections.filter(\.needsSync).count }

    // MARK: Persistence

    private func scheduleAppSave() {
        appSaveTask?.cancel()
        let snapshot = state
        appSaveTask = Task { [repo] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            repo.saveAppState(snapshot)
        }
    }

    func flushNow() {
        repo.saveAppState(state)
        inspections.forEach { repo.saveInspection($0) }
        repo.flush()
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

    // MARK: Session

    func signIn(email: String, password: String) async throws {
        let s = try await auth.signIn(email: email, password: password, company: state.company)
        state.session = s
        path = []
        presentSplashIfNeeded()
    }

    func createAccount(name: String, company: String, email: String, password: String) async throws {
        let s = try await auth.createAccount(name: name, company: company, email: email, password: password)
        // A new account starts its own company on a fresh free look.
        let c = company.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty { state.company.name = c }
        var owner = Inspector(name: s.name, email: s.email, owner: true, admin: true)
        if let i = state.company.inspectors.firstIndex(where: { $0.owner }) {
            owner.id = state.company.inspectors[i].id
            state.company.inspectors[i] = owner
        } else {
            state.company.inspectors.insert(owner, at: 0)
        }
        state.company.inspectorName = s.name
        state.subscription.trialStart = Date()
        state.subscription.active = false
        state.session = Session(name: s.name, email: s.email, inspectorID: owner.id, isAdmin: true)
        path = []
        presentSplashIfNeeded()
    }

    func joinCompany(code: String, name: String, email: String) async throws {
        var s = try await auth.joinCompany(code: code, name: name, email: email, company: state.company)
        let ins = Inspector(name: name, email: email)
        if !state.company.inspectors.contains(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame && !email.isEmpty }) {
            state.company.inspectors.append(ins)
        }
        s.inspectorID = ins.id
        state.session = s
        toast("Linked to \(state.company.name)")
        path = []
    }

    func signOut() {
        flushNow()
        state.session = nil
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
            guard let self, let insp = self.inspection(id) else { return }
            self.repo.saveInspection(insp)
        }
    }

    func newInspectionDraft() -> Inspection {
        let w = config.wizard
        let d = w.defaults
        var fields: [String: String] = [:]
        for e in w.step1 + w.step2 where e.kind == "chips" {
            if let def = e.default, e.id != "wdepth" { fields[e.label] = def }
        }
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
        repo.saveInspection(insp)
        return insp.id
    }

    func deleteInspection(_ id: UUID) {
        inspections.removeAll { $0.id == id }
        repo.deleteInspection(id: id)
    }

    func answers(_ id: UUID, _ section: String) -> SectionAnswers {
        inspection(id)?.answers[section] ?? SectionAnswers(overall: config.overallConditionDefault)
    }

    func setAnswers(_ id: UUID, _ section: String, _ a: SectionAnswers) {
        update(id) { insp in
            insp.answers[section] = a
            if insp.status[section] == nil || insp.status[section] == .todo, a.hasContent { insp.status[section] = .prog }
        }
    }

    func markDone(_ id: UUID, _ section: String) {
        update(id) { insp in
            if insp.answers[section] == nil { insp.answers[section] = SectionAnswers(overall: config.overallConditionDefault) }
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
        guard let path = repo.saveImage(data, folder: "photos/\(id.uuidString)", name: "\(pid.uuidString).jpg") else { return nil }
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
        repo.deleteFile(ref.file)
        if let o = ref.originalFile { repo.deleteFile(o) }
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
                    ref.originalFile = repo.saveImage(d, folder: "photos/\(id.uuidString)", name: origName)
                }
            }
            _ = repo.saveImage(data, folder: "photos/\(id.uuidString)", name: "\(photoID.uuidString).jpg")
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
        return ReportData.make(insp, config: config, overrides: state.overrides, company: state.company, repo: repo, logo: companyLogo())
    }

    /// Renders the PDF on-device and saves it under reports/.
    func generateReport(_ id: UUID) async -> ReportInfo? {
        guard let data = reportData(id) else { return nil }
        let result = await Task.detached(priority: .userInitiated) { ReportRenderer.render(data) }.value
        guard let path = repo.saveFile(result.pdf, folder: "reports", name: "\(id.uuidString).pdf") else { return nil }
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
    }

    // MARK: Company files

    func saveLogo(_ image: UIImage) {
        guard let data = image.pngData() ?? ImageTools.jpegData(image, maxEdge: 1024) else { return }
        let name = "logo-\(UUID().uuidString.prefix(8)).png"
        if let old = state.company.logoFile { repo.deleteFile(old) }
        state.company.logoFile = repo.saveImage(data, folder: "company", name: name)
        toast("Logo updated")
    }

    func companyLogo() -> UIImage {
        if let f = state.company.logoFile, let img = UIImage(contentsOfFile: repo.url(for: f).path) { return img }
        return UIImage(named: "VimsLogo") ?? UIImage()
    }

    func saveAgreement(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { toast("Couldn't read that file"); return }
        if let old = state.company.agreementFile { repo.deleteFile(old) }
        state.company.agreementFile = repo.saveFile(data, folder: "company", name: url.lastPathComponent)
        state.company.agreementName = url.lastPathComponent
        toast("Agreement uploaded")
    }
}
