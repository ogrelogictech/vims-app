import Foundation
import SwiftData
import CommonCrypto

// SwiftData models. Ownership columns (userID / companyID) are real attributes so every fetch is
// scoped by owner; the nested inspection content (answers, photo refs, findings, report info) is a
// Codable payload owned by the inspection's user.

@Model
final class UserRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var email: String       // lowercased
    var name: String
    var companyID: UUID
    var passwordHash: String                    // PBKDF2-SHA256, hex — TODO(backend): Laravel API owns credentials
    var salt: String
    var createdAt: Date
    var settingsData: Data?                     // AppSettings (per user)

    init(id: UUID, email: String, name: String, companyID: UUID, passwordHash: String, salt: String, createdAt: Date) {
        self.id = id
        self.email = email
        self.name = name
        self.companyID = companyID
        self.passwordHash = passwordHash
        self.salt = salt
        self.createdAt = createdAt
    }
}

@Model
final class CompanyRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var joinCode: String
    var name: String
    var profileData: Data           // CompanyProfile: details, logo file, inspectors & roles, feedback email
    var subscriptionData: Data      // SubscriptionState: plans & prices, seats, trial, payment label
    var overridesData: Data         // ChecklistOverrides: admin checklist edits + custom sections
    var updatedAt: Date

    init(id: UUID, joinCode: String, name: String, profileData: Data, subscriptionData: Data, overridesData: Data) {
        self.id = id
        self.joinCode = joinCode
        self.name = name
        self.profileData = profileData
        self.subscriptionData = subscriptionData
        self.overridesData = overridesData
        self.updatedAt = Date()
    }
}

@Model
final class InspectionRecord {
    @Attribute(.unique) var id: UUID
    var userID: UUID
    var companyID: UUID
    var scheduled: Date
    var updatedAt: Date
    var payload: Data               // Inspection (wizard values, sections, answers, photo refs, findings, report)

    init(id: UUID, userID: UUID, companyID: UUID, scheduled: Date, payload: Data) {
        self.id = id
        self.userID = userID
        self.companyID = companyID
        self.scheduled = scheduled
        self.updatedAt = Date()
        self.payload = payload
    }
}

// MARK: - Local credential hashing (stub until the Laravel API)

enum PasswordHasher {
    static func newSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ password: String, salt: String) -> String {
        let pw = Array(password.utf8).map { Int8(bitPattern: $0) }
        let s = Array(salt.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, pw.count, s, s.count,
                             CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 20_000, &out, out.count)
        return out.map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ password: String, hash: String, salt: String) -> Bool {
        let h = self.hash(password, salt: salt)
        // constant-time compare
        guard h.count == hash.count else { return false }
        return zip(h.utf8, hash.utf8).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
