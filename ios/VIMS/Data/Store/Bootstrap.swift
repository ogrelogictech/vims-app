import Foundation
import UIKit

/// First-launch setup of the SwiftData store:
///  1. one-time migration of the pre-SwiftData JSON files (Documents/vims/app.json + inspections/*.json)
///     into the demo user/company, moving their photos/reports/logo into the per-owner folders;
///  2. otherwise, the demo account (DemoSeed) when enabled.
@MainActor
enum Bootstrap {
    static func run(repo: any Repository, config: ChecklistConfig) {
        guard repo.userCount() == 0 else { return }
        if migrateLegacyJSON(repo: repo, config: config) { return }
        if DemoSeed.enabled { seedDemoAccount(repo: repo, config: config) }
    }

    static func seedDemoAccount(repo: any Repository, config: ChecklistConfig) {
        let userID = UUID(), companyID = UUID()
        let seeded = DemoSeed.make(config: config, files: repo.files, userFolder: "users/\(userID.uuidString)",
                                   companyFolder: "companies/\(companyID.uuidString)", ownerID: userID)
        repo.saveCompany(CompanyState(id: companyID, profile: seeded.state.company,
                                      subscription: seeded.state.subscription, overrides: seeded.state.overrides))
        let salt = PasswordHasher.newSalt()
        try? repo.insertUser(UserAccount(id: userID, email: DemoSeed.loginEmail.lowercased(), name: DemoSeed.ownerName,
                                         companyID: companyID, passwordHash: PasswordHasher.hash(DemoSeed.loginPassword, salt: salt),
                                         salt: salt, createdAt: Date(), settings: seeded.state.settings))
        for i in seeded.inspections { repo.saveInspection(i, userID: userID, companyID: companyID) }
    }

    /// New company for "Create account": the account owner is its admin; everything else starts empty.
    static func newCompany(name: String, owner: UserAccount, config: ChecklistConfig, repo: Repository) -> CompanyState {
        var state = DemoSeed.emptyState(config: config)
        state.company.name = name
        state.company.joinCode = uniqueJoinCode(for: name, repo: repo)
        state.company.inspectorName = owner.name
        state.company.email = owner.email
        state.company.inspectors = [Inspector(id: owner.id, name: owner.name, email: owner.email, owner: true, admin: true)]
        state.subscription.trialStart = Date()
        return CompanyState(id: owner.companyID, profile: state.company, subscription: state.subscription, overrides: state.overrides)
    }

    static func uniqueJoinCode(for name: String, repo: Repository) -> String {
        var letters = String(name.uppercased().filter { $0.isLetter }.prefix(3))
        while letters.count < 3 { letters += "X" }
        for _ in 0..<50 {
            let code = "\(letters)-\(String(format: "%04d", Int.random(in: 1000...9999)))"
            if repo.company(joinCode: code) == nil { return code }
        }
        return "\(letters)-\(String(format: "%04d", Int.random(in: 0...9999)))"
    }

    // MARK: Legacy JSON → SwiftData (one time)

    private static func migrateLegacyJSON(repo: any Repository, config: ChecklistConfig) -> Bool {
        let files = repo.files
        let appURL = files.url(for: "app.json")
        guard let data = try? Data(contentsOf: appURL) else { return false }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard var state = try? dec.decode(AppState.self, from: data) else { return false }

        let userID = UUID(), companyID = UUID()
        let uf = "users/\(userID.uuidString)", cf = "companies/\(companyID.uuidString)"
        files.move("photos", to: "\(uf)/photos")
        files.move("reports", to: "\(uf)/reports")
        files.move("company", to: cf)
        func remap(_ p: String?) -> String? {
            guard let p else { return nil }
            if p.hasPrefix("photos/") || p.hasPrefix("reports/") { return "\(uf)/\(p)" }
            if p.hasPrefix("company/") { return "\(cf)/" + p.dropFirst("company/".count) }
            return p
        }
        state.company.logoFile = remap(state.company.logoFile)
        // The pre-SwiftData build showed the bundled VIMS mark for the demo company; keep it as its logo.
        if state.company.logoFile == nil, state.company.joinCode == config.sample.company.code,
           let png = UIImage(named: "VimsLogo")?.pngData() {
            state.company.logoFile = files.saveImage(png, folder: cf, name: "logo.png")
        }
        state.company.agreementFile = remap(state.company.agreementFile)

        // The migrated data is the demo account's (the only account that existed on this device).
        let email = (state.session?.email ?? state.company.inspectors.first(where: { $0.owner })?.email ?? DemoSeed.loginEmail).lowercased()
        let name = state.session?.name ?? state.company.inspectors.first(where: { $0.owner })?.name ?? DemoSeed.ownerName
        if let i = state.company.inspectors.firstIndex(where: { $0.owner }) { state.company.inspectors[i].id = userID }
        repo.saveCompany(CompanyState(id: companyID, profile: state.company, subscription: state.subscription, overrides: state.overrides))
        let salt = PasswordHasher.newSalt()
        try? repo.insertUser(UserAccount(id: userID, email: email, name: name, companyID: companyID,
                                         passwordHash: PasswordHasher.hash(DemoSeed.loginPassword, salt: salt), salt: salt,
                                         createdAt: Date(), settings: state.settings))

        let dir = files.url(for: "inspections")
        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
            guard let d = try? Data(contentsOf: url), var insp = try? dec.decode(Inspection.self, from: d) else { continue }
            for (sec, cats) in insp.photos {
                for (cat, arr) in cats {
                    insp.photos[sec]?[cat] = arr.map { var p = $0; p.file = remap(p.file) ?? p.file; p.originalFile = remap(p.originalFile); return p }
                }
            }
            if let r = insp.report { insp.report?.file = remap(r.file) ?? r.file }
            repo.saveInspection(insp, userID: userID, companyID: companyID)
        }
        files.move("app.json", to: "legacy-migrated/app.json")
        files.move("inspections", to: "legacy-migrated/inspections")
        if state.session != nil { repo.currentUserID = userID }
        return true
    }
}
