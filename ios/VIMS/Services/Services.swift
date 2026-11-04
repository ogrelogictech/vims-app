import Foundation
import LocalAuthentication
import Network

// Backend-dependent services. Phase 1 ships local stubs so the app is fully usable
// offline; each stub is marked TODO(backend) where the Laravel API plugs in.

/// Sign-in failures, so the UI can put the message on the right field.
enum AuthError: LocalizedError {
    case noAccount, wrongPassword
    /// Data v1.18 `features.companyJoin`, set at launch. Off in Phase 1: nothing mentions a company code.
    static var companyJoinEnabled = false
    var errorDescription: String? {
        switch self {
        case .noAccount:
            return Self.companyJoinEnabled ? "No account found for that email. Create an account or join with a company code."
                                           : "No account found for that email. Create an account."
        case .wrongPassword: return "That password isn't right. Try again or reset it."
        }
    }
}

enum ServiceError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let m): return m }
    }
}

// MARK: - Auth

@MainActor
protocol AuthService {
    /// Verifies credentials against the account table.
    func signIn(email: String, password: String) async throws -> UserAccount
    /// Creates a user (password stored salted + hashed) attached to `companyID`.
    func register(name: String, email: String, password: String, companyID: UUID) async throws -> UserAccount
    /// Saves a new password with a new salt. Nothing else on the account changes.
    func resetPassword(userID: UUID, newPassword: String) async throws
}

// TODO(backend): Laravel API — POST /auth/login, /auth/register, /companies/join.
// Local stub: a User table in SwiftData with salted PBKDF2 password hashes.
@MainActor
final class LocalAuthService: AuthService {
    let repo: Repository
    init(repo: Repository) { self.repo = repo }

    func signIn(email: String, password: String) async throws -> UserAccount {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let u = repo.user(email: e) else {
            throw AuthError.noAccount
        }
        guard PasswordHasher.verify(password, hash: u.passwordHash, salt: u.salt) else {
            throw AuthError.wrongPassword
        }
        return u
    }

    func register(name: String, email: String, password: String, companyID: UUID) async throws -> UserAccount {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        if repo.user(email: e) != nil { throw ServiceError.invalid("An account with that email already exists. Sign in instead.") }
        let salt = PasswordHasher.newSalt()
        let u = UserAccount(id: UUID(), email: e, name: name, companyID: companyID,
                            passwordHash: PasswordHasher.hash(password, salt: salt), salt: salt, createdAt: Date(), settings: nil)
        try repo.insertUser(u)
        return u
    }

    func resetPassword(userID: UUID, newPassword: String) async throws {
        let salt = PasswordHasher.newSalt()
        try repo.updatePassword(userID: userID, hash: PasswordHasher.hash(newPassword, salt: salt), salt: salt)
    }
}

/// Reset password (`features.passwordReset` = "device"): the device's own Face ID / Touch ID / passcode confirms it's the
/// owner, since Phase 1 passwords exist only on the device and no reset email can be sent.
enum DeviceOwnerCheck {
    enum Result { case confirmed, cancelled, noScreenLock, failed }

    @MainActor
    static func confirm(reason: String) async -> Result {
        #if DEBUG
        // -resetAuth ok|cancel|nolock|failed: skips the system prompt (automation; a simulator always reports a screen lock).
        switch DebugLaunch.value("-resetAuth") {
        case "ok": return .confirmed
        case "cancel": return .cancelled
        case "nolock": return .noScreenLock
        case "failed": return .failed
        default: break
        }
        #endif
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return error?.code == LAError.Code.passcodeNotSet.rawValue ? .noScreenLock : .failed
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .confirmed : .failed
        } catch let e as LAError {
            switch e.code {
            case .userCancel, .systemCancel, .appCancel, .notInteractive: return .cancelled
            case .passcodeNotSet: return .noScreenLock
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}

// Subscriptions: StoreKitService.swift (App Store in-app purchases, shared v1.18.0).

// MARK: - Sync

protocol SyncService {
    /// Uploads pending inspections; returns the IDs that are now synced.
    func sync(_ inspections: [Inspection]) async throws -> [UUID]
}

// TODO(backend): Laravel API — upload inspections, answers, photos, findings, and
// generated reports; pull checklist/plan changes made in the web portal (Phase 2).
final class LocalSyncService: SyncService {
    func sync(_ inspections: [Inspection]) async throws -> [UUID] {
        try await Task.sleep(nanoseconds: 350_000_000)
        return inspections.filter(\.needsSync).map(\.id)
    }
}

// MARK: - Connectivity

@MainActor
final class Connectivity {
    private let monitor = NWPathMonitor()
    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.onChange?(online) }
        }
        monitor.start(queue: DispatchQueue(label: "vims.connectivity"))
    }
}
