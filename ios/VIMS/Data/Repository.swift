import Foundation
import UIKit
import ImageIO
import SwiftData

// Offline-first local persistence.
//  • Structured data lives in SwiftData (Store/Records.swift): users, companies, inspections.
//  • Photos, reports, logos and agreements are files under Documents/vims/, in per-owner folders:
//      users/<userID>/photos/<inspectionID>/…   users/<userID>/reports/…   companies/<companyID>/…
// Ownership: inspections (with their answers, photo refs, findings, report info) belong to a user;
// the company profile/logo, checklist customizations, plans, inspectors and subscription belong
// to a company. The app only ever loads the signed-in user's rows and their company's row.
// A future Laravel-backed implementation (Phase 2) can sit behind the same protocol.

struct UserAccount: Hashable {
    var id: UUID
    var email: String            // lowercased, unique
    var name: String
    var companyID: UUID
    var passwordHash: String     // TODO(backend): Laravel API owns credentials
    var salt: String
    var createdAt: Date
    var settings: AppSettings?
}

struct CompanyState {
    var id: UUID
    var profile: CompanyProfile
    var subscription: SubscriptionState
    var overrides: ChecklistOverrides
}

@MainActor
protocol Repository: AnyObject {
    // Accounts
    func user(email: String) -> UserAccount?
    func user(id: UUID) -> UserAccount?
    func insertUser(_ u: UserAccount) throws
    func updateUser(_ u: UserAccount)
    func userCount() -> Int
    // Companies
    func company(id: UUID) -> CompanyState?
    func company(joinCode: String) -> CompanyState?
    func saveCompany(_ c: CompanyState)
    // Inspections (always scoped to one user)
    func inspections(userID: UUID) -> [Inspection]
    func saveInspection(_ i: Inspection, userID: UUID, companyID: UUID)
    func deleteInspection(id: UUID, userID: UUID)
    // Platform settings (VIMS-wide; only the platform owner may change them)
    func platformSettings() -> PlatformSettings?
    func savePlatformSettings(_ s: PlatformSettings)
    // Session pointer (which user is signed in on this device)
    var currentUserID: UUID? { get set }
    // Files
    var files: FileStore { get }
    func url(for relativePath: String) -> URL
}

enum RepositoryError: LocalizedError {
    case duplicateEmail
    var errorDescription: String? { "An account with that email already exists." }
}

@MainActor
final class SwiftDataRepository: Repository {
    let container: ModelContainer
    let files: FileStore
    private var context: ModelContext { container.mainContext }
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    nonisolated static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("VIMS.store")
    }

    /// Deletes the SwiftData store (DEBUG -resetData). Must run before a container is opened.
    nonisolated static func wipeStore() {
        let base = storeURL
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: base.path + suffix))
        }
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    nonisolated private static let sessionKey = "vims.currentUserID"

    init(files: FileStore = FileStore()) throws {
        self.files = files
        let cfg = ModelConfiguration(url: Self.storeURL)
        container = try ModelContainer(for: UserRecord.self, CompanyRecord.self, InspectionRecord.self, PlatformRecord.self,
                                       configurations: cfg)
    }

    func url(for relativePath: String) -> URL { files.url(for: relativePath) }

    // MARK: Session pointer

    var currentUserID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.sessionKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.sessionKey) }
    }

    private func save() {
        do { try context.save() } catch { print("SwiftData save failed: \(error)") }
    }

    // MARK: Users

    private func userRecord(email: String) -> UserRecord? {
        let e = email.lowercased()
        var d = FetchDescriptor<UserRecord>(predicate: #Predicate { $0.email == e })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func userRecord(id: UUID) -> UserRecord? {
        var d = FetchDescriptor<UserRecord>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func account(_ r: UserRecord) -> UserAccount {
        UserAccount(id: r.id, email: r.email, name: r.name, companyID: r.companyID, passwordHash: r.passwordHash,
                    salt: r.salt, createdAt: r.createdAt,
                    settings: r.settingsData.flatMap { try? decoder.decode(AppSettings.self, from: $0) })
    }

    func user(email: String) -> UserAccount? { userRecord(email: email).map(account) }
    func user(id: UUID) -> UserAccount? { userRecord(id: id).map(account) }

    func insertUser(_ u: UserAccount) throws {
        if userRecord(email: u.email) != nil { throw RepositoryError.duplicateEmail }
        let r = UserRecord(id: u.id, email: u.email.lowercased(), name: u.name, companyID: u.companyID,
                           passwordHash: u.passwordHash, salt: u.salt, createdAt: u.createdAt)
        r.settingsData = u.settings.flatMap { try? encoder.encode($0) }
        context.insert(r)
        save()
    }

    func updateUser(_ u: UserAccount) {
        guard let r = userRecord(id: u.id) else { return }
        r.name = u.name
        r.companyID = u.companyID
        r.passwordHash = u.passwordHash
        r.salt = u.salt
        r.settingsData = u.settings.flatMap { try? encoder.encode($0) }
        save()
    }

    func userCount() -> Int { (try? context.fetchCount(FetchDescriptor<UserRecord>())) ?? 0 }

    // MARK: Companies

    private func companyRecord(id: UUID) -> CompanyRecord? {
        var d = FetchDescriptor<CompanyRecord>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func companyState(_ r: CompanyRecord) -> CompanyState? {
        guard let p = try? decoder.decode(CompanyProfile.self, from: r.profileData),
              let s = try? decoder.decode(SubscriptionState.self, from: r.subscriptionData),
              let o = try? decoder.decode(ChecklistOverrides.self, from: r.overridesData) else { return nil }
        return CompanyState(id: r.id, profile: p, subscription: s, overrides: o)
    }

    func company(id: UUID) -> CompanyState? { companyRecord(id: id).flatMap(companyState) }

    func company(joinCode: String) -> CompanyState? {
        let code = joinCode.uppercased()
        var d = FetchDescriptor<CompanyRecord>(predicate: #Predicate { $0.joinCode == code })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first.flatMap(companyState)
    }

    func saveCompany(_ c: CompanyState) {
        guard let p = try? encoder.encode(c.profile), let s = try? encoder.encode(c.subscription),
              let o = try? encoder.encode(c.overrides) else { return }
        if let r = companyRecord(id: c.id) {
            r.name = c.profile.name
            r.joinCode = c.profile.joinCode.uppercased()
            r.profileData = p; r.subscriptionData = s; r.overridesData = o
            r.updatedAt = Date()
        } else {
            context.insert(CompanyRecord(id: c.id, joinCode: c.profile.joinCode.uppercased(), name: c.profile.name,
                                         profileData: p, subscriptionData: s, overridesData: o))
        }
        save()
    }

    // MARK: Platform

    private func platformRecord() -> PlatformRecord? {
        var d = FetchDescriptor<PlatformRecord>()
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func platformSettings() -> PlatformSettings? {
        platformRecord().flatMap { try? decoder.decode(PlatformSettings.self, from: $0.settingsData) }
    }

    func savePlatformSettings(_ s: PlatformSettings) {
        guard let data = try? encoder.encode(s) else { return }
        if let r = platformRecord() { r.settingsData = data; r.updatedAt = Date() } else { context.insert(PlatformRecord(settingsData: data)) }
        save()
    }

    // MARK: Inspections

    func inspections(userID: UUID) -> [Inspection] {
        let d = FetchDescriptor<InspectionRecord>(predicate: #Predicate { $0.userID == userID },
                                                 sortBy: [SortDescriptor(\.scheduled)])
        return ((try? context.fetch(d)) ?? []).compactMap { try? decoder.decode(Inspection.self, from: $0.payload) }
    }

    private func inspectionRecord(id: UUID) -> InspectionRecord? {
        var d = FetchDescriptor<InspectionRecord>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func saveInspection(_ i: Inspection, userID: UUID, companyID: UUID) {
        guard let data = try? encoder.encode(i) else { return }
        if let r = inspectionRecord(id: i.id) {
            guard r.userID == userID else { return }    // never write across owners
            r.payload = data
            r.scheduled = i.scheduled
            r.updatedAt = Date()
        } else {
            context.insert(InspectionRecord(id: i.id, userID: userID, companyID: companyID, scheduled: i.scheduled, payload: data))
        }
        save()
    }

    func deleteInspection(id: UUID, userID: UUID) {
        guard let r = inspectionRecord(id: id), r.userID == userID else { return }
        context.delete(r)
        save()
        files.deleteFolder("users/\(userID.uuidString)/photos/\(id.uuidString)")
        files.deleteFile("users/\(userID.uuidString)/reports/\(id.uuidString).pdf")
    }
}

// MARK: - Files (photos, reports, logos, agreements)

final class FileStore {
    let root: URL

    init(root: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? docs.appendingPathComponent("vims", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    /// Writes a file and returns its path relative to the root.
    func saveFile(_ data: Data, folder: String, name: String) -> String? {
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            ImageCache.shared.invalidate(url)
            return "\(folder)/\(name)"
        } catch {
            return nil
        }
    }

    func saveImage(_ data: Data, folder: String, name: String) -> String? { saveFile(data, folder: folder, name: name) }

    func url(for relativePath: String) -> URL { root.appendingPathComponent(relativePath) }

    func deleteFile(_ relativePath: String) {
        let url = url(for: relativePath)
        ImageCache.shared.invalidate(url)
        try? FileManager.default.removeItem(at: url)
    }

    func deleteFolder(_ relativePath: String) {
        try? FileManager.default.removeItem(at: url(for: relativePath))
    }

    func exists(_ relativePath: String) -> Bool { FileManager.default.fileExists(atPath: url(for: relativePath).path) }

    /// Moves a folder (used by the one-time JSON → SwiftData migration).
    func move(_ from: String, to: String) {
        let src = url(for: from), dst = url(for: to)
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.moveItem(at: src, to: dst)
    }

    func wipeAll() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}

// MARK: - Image helpers

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func thumbnail(_ url: URL, maxPixel: CGFloat = 400) -> UIImage? {
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let img = cache.object(forKey: key) { return img }
        guard let img = ImageTools.downsample(url, maxPixel: maxPixel) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    func invalidate(_ url: URL) {
        for size in [200, 300, 400, 600, 900, 1200, 1600] {
            cache.removeObject(forKey: "\(url.path)#\(size)" as NSString)
        }
    }
}

enum ImageTools {
    static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts) else { return nil }
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Normalizes orientation and caps the long edge (camera photos -> ~750 KB JPGs).
    static func jpegData(_ image: UIImage, maxEdge: CGFloat = 2048, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return img.jpegData(compressionQuality: quality)
    }
}
