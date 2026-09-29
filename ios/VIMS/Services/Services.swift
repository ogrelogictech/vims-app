import Foundation
import Network

// Backend-dependent services. Phase 1 ships local stubs so the app is fully usable
// offline; each stub is marked TODO(backend) where the Laravel API plugs in.

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
    func requestPasswordReset(email: String) async throws
}

// TODO(backend): Laravel API — POST /auth/login, /auth/register, /auth/forgot, /companies/join.
// Local stub: a User table in SwiftData with salted PBKDF2 password hashes.
@MainActor
final class LocalAuthService: AuthService {
    let repo: Repository
    init(repo: Repository) { self.repo = repo }

    func signIn(email: String, password: String) async throws -> UserAccount {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let u = repo.user(email: e) else {
            throw ServiceError.invalid("No account found for that email. Create an account or join with a company code.")
        }
        guard PasswordHasher.verify(password, hash: u.passwordHash, salt: u.salt) else {
            throw ServiceError.invalid("That password isn't right. Try again or reset it.")
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

    func requestPasswordReset(email: String) async throws {
        // TODO(backend): send the reset email. Locally we only check the format.
        guard Validator.error(for: email, rule: .req(.email, "Email")) == nil else { throw ServiceError.invalid("Enter a valid email address") }
    }
}

// MARK: - Subscription (Square)

struct CardEntry {
    var number: String
    var expiry: String
    var cvc: String
    var name: String = ""
    var zip: String = ""

    var digits: String { number.filter(\.isNumber) }
    var last4: String { String(digits.suffix(4)) }
    var brand: String {
        let b = CardBrand.detect(digits).rawValue
        return b.isEmpty ? "Card" : b
    }
}

protocol SubscriptionService {
    /// Returns a display label for the stored payment method, e.g. "Square · Visa ····4242".
    func startSubscription(planID: String, seats: Int, card: CardEntry) async throws -> String
}

// TODO(backend): Laravel API + Square Web Payments / In-App Payments SDK.
// The real flow tokenizes the card with Square (never touching raw PAN) and the
// backend creates the Square subscription. Phase 1 simulates success.
final class LocalSubscriptionService: SubscriptionService {
    func startSubscription(planID: String, seats: Int, card: CardEntry) async throws -> String {
        // Field validation happens in the form (docs/validation-rules.md); the real flow tokenizes with Square.
        try await Task.sleep(nanoseconds: 400_000_000)
        return "Square · \(card.brand) ····\(card.last4)"
    }
}

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
