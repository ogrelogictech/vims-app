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

protocol AuthService {
    func signIn(email: String, password: String, company: CompanyProfile) async throws -> Session
    func createAccount(name: String, company: String, email: String, password: String) async throws -> Session
    func requestPasswordReset(email: String) async throws
    func joinCompany(code: String, name: String, email: String, company: CompanyProfile) async throws -> Session
}

// TODO(backend): Laravel API — POST /auth/login, /auth/register, /auth/forgot, /companies/join.
final class LocalAuthService: AuthService {
    func signIn(email: String, password: String, company: CompanyProfile) async throws -> Session {
        let e = email.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty, !password.isEmpty else { throw ServiceError.invalid("Enter your email and password.") }
        // Any non-empty credentials sign in. Match a known inspector by email; otherwise treat as the owner.
        if let ins = company.inspectors.first(where: { $0.email.caseInsensitiveCompare(e) == .orderedSame }) {
            return Session(name: ins.name, email: ins.email, inspectorID: ins.id, isAdmin: ins.isAdmin)
        }
        let owner = company.inspectors.first(where: { $0.owner })
        return Session(name: owner?.name ?? e, email: e, inspectorID: owner?.id, isAdmin: true)
    }

    func createAccount(name: String, company: String, email: String, password: String) async throws -> Session {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              email.contains("@"), !password.isEmpty else {
            throw ServiceError.invalid("Enter your name, a valid email, and a password.")
        }
        return Session(name: name, email: email, inspectorID: nil, isAdmin: true)
    }

    func requestPasswordReset(email: String) async throws {
        guard email.contains("@") else { throw ServiceError.invalid("Enter a valid email.") }
    }

    func joinCompany(code: String, name: String, email: String, company: CompanyProfile) async throws -> Session {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard !c.isEmpty else { throw ServiceError.invalid("Enter the company code") }
        guard c == company.joinCode.uppercased() else { throw ServiceError.invalid("That company code wasn't found.") }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ServiceError.invalid("Enter your name") }
        return Session(name: name, email: email, inspectorID: nil, isAdmin: false)
    }
}

// MARK: - Subscription (Square)

struct CardEntry {
    var number: String
    var expiry: String
    var cvc: String

    var digits: String { number.filter(\.isNumber) }
    var last4: String { String(digits.suffix(4)) }
    var brand: String {
        switch digits.first {
        case "4": return "Visa"
        case "5": return "Mastercard"
        case "3": return "Amex"
        case "6": return "Discover"
        default: return "Card"
        }
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
        guard card.digits.count >= 12 else { throw ServiceError.invalid("Enter a valid card number.") }
        guard card.expiry.filter(\.isNumber).count == 4 else { throw ServiceError.invalid("Enter the expiry as MM / YY.") }
        guard (3...4).contains(card.cvc.filter(\.isNumber).count) else { throw ServiceError.invalid("Enter the CVC.") }
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
