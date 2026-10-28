import Foundation
import Network

// Backend-dependent services. Phase 1 ships local stubs so the app is fully usable
// offline; each stub is marked TODO(backend) where the Laravel API plugs in.

/// Sign-in failures, so the UI can put the message on the right field.
enum AuthError: LocalizedError {
    case noAccount, wrongPassword
    var errorDescription: String? {
        switch self {
        case .noAccount: return "No account found for that email. Create an account or join with a company code."
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

    func requestPasswordReset(email: String) async throws {
        // TODO(backend): send the reset email. Locally we only check the format.
        guard Validator.error(for: email, rule: .req(.email, "Email")) == nil else { throw ServiceError.invalid("Enter a valid email address") }
    }
}

// MARK: - Subscription (Square)

/// The remembered payment card: a DISPLAY reference only (brand, last 4, expiry) — a placeholder for Square's card-on-file
/// id (TODO(backend): Square Cards API customer card id in `squareCardID`). The card number and CVC are never stored.
struct CardOnFile: Codable, Hashable {
    var brand: String
    var last4: String
    var expMonth: Int
    var expYear: Int          // 4 digits
    var squareCardID: String? = nil

    init(brand: String, last4: String, expMonth: Int, expYear: Int, squareCardID: String? = nil) {
        self.brand = brand; self.last4 = last4; self.expMonth = expMonth; self.expYear = expYear; self.squareCardID = squareCardID
    }

    /// From the entered card: brand, last 4 and the MM/YY expiry (nil when the expiry can't be read).
    init?(_ c: CardEntry) {
        let d = c.expiry.filter(\.isNumber)
        guard d.count == 4, let mm = Int(d.prefix(2)), let yy = Int(d.suffix(2)), (1...12).contains(mm), c.last4.count == 4 else { return nil }
        self.init(brand: c.brand, last4: c.last4, expMonth: mm, expYear: 2000 + yy)
    }

    var expiryLabel: String { String(format: "%02d/%02d", expMonth, expYear % 100) }
    /// "Visa •••• 4242 (exp 08/28)"
    var display: String { "\(brand) •••• \(last4) (exp \(expiryLabel))" }

    func isExpired(now: Date = Date()) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: now), m = cal.component(.month, from: now)
        return expYear < y || (expYear == y && expMonth < m)
    }
}

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

/// How a subscription is paid: a newly entered card, or the card on file (QA Oct 14: "remember the card").
enum SubscriptionPayment {
    case newCard(CardEntry)
    case cardOnFile(CardOnFile)
}

protocol SubscriptionService {
    /// Starts / updates the subscription. Returns a display label for the payment method ("Square · Visa ····4242") and
    /// the card-on-file reference to remember (never the card number or CVC).
    /// `period` = Monthly / Yearly (client Oct 28); extra inspectors are billed on the same period.
    func startSubscription(planID: String, period: BillingPeriod, seats: Int, payment: SubscriptionPayment) async throws -> (label: String, card: CardOnFile)
    /// Stops renewal at the end of the current billing period (EULA 12.3: no refunds or prorated charges).
    func cancelSubscription() async throws
    /// Undoes a pending cancellation before the period ends; auto-pay continues.
    func resumeSubscription() async throws
}

// TODO(backend): Laravel API + Square Web Payments / In-App Payments SDK.
// The real flow tokenizes the card with Square (never touching raw PAN) and the
// backend creates the Square subscription. Phase 1 simulates success.
final class LocalSubscriptionService: SubscriptionService {
    func startSubscription(planID: String, period: BillingPeriod, seats: Int, payment: SubscriptionPayment) async throws -> (label: String, card: CardOnFile) {
        // TODO(backend): Square Subscriptions API — the plan's monthly or yearly subscription plan variation (`period`).
        // Field validation happens in the form (docs/validation-rules.md); the real flow tokenizes with Square.
        try await Task.sleep(nanoseconds: 400_000_000)
        let card: CardOnFile
        switch payment {
        case .newCard(let c):
            // TODO(backend): Square Cards API — CreateCard (customer card on file) from the card nonce; keep its card id
            // in `squareCardID`. Only brand, last 4 and expiry are kept here; the number and CVC are never stored.
            guard let ref = CardOnFile(c) else { throw ServiceError.invalid("Enter the expiry as MM/YY") }
            card = ref
        case .cardOnFile(let ref):
            // TODO(backend): charge / attach the Square card on file (`squareCardID`) to the updated subscription.
            card = ref
        }
        return ("Square · \(card.brand) ····\(card.last4)", card)
    }

    // TODO(backend): Square Subscriptions API — CancelSubscription (sets canceled_date to the end of the
    // paid period) and, for undo, delete the pending CANCEL action (DeleteSubscriptionAction) / ResumeSubscription.
    func cancelSubscription() async throws { try await Task.sleep(nanoseconds: 300_000_000) }
    func resumeSubscription() async throws { try await Task.sleep(nanoseconds: 300_000_000) }
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
