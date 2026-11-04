import CommonCrypto
import Foundation
import Observation
import Security
import StoreKit
import UIKit

// Phase 1 subscriptions are in-app purchases (shared v1.18.0 `subscription.store`). There is no server, so the App Store
// bills and reports status, and this device keeps the last verified answer. The app's own `AppStore` class shadows
// StoreKit's, so StoreKit's is always written `StoreKit.AppStore` here.

/// Small Keychain store for what must survive upgrades and a reinstall, and must not travel to another device in a backup:
/// the cached store status, the report credit ledger and the master admin verified flags. Same accessibility as `DeviceTrial`.
/// The Keychain belongs to the app ID, so store builds (com.vimsinspect.app) and test builds (com.vims.app) never share it.
enum DeviceVault {
    private static let service = "com.vims.app.store"

    static func data(_ account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    /// Replaces the item in one step, so a crash can't leave it deleted but not rewritten.
    @discardableResult
    static func set(_ data: Data, _ account: String) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        let updated = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func remove(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}

/// The last status the store (or a signed local transaction) reported, cached per `subscription.store.offline`.
struct StoreSubscriptionStatus: Codable, Equatable {
    enum State: String, Codable { case none, subscribed, gracePeriod, billingRetry, expired, revoked }

    var state: State = .none
    var productID: String? = nil
    /// When the paid period (or the store's grace period) ends.
    var expiresAt: Date? = nil
    var willAutoRenew = false
    /// The plan a renewal switches to (a downgrade waiting for the next renewal), when it differs from `productID`.
    var pendingProductID: String? = nil
    var groupID: String? = nil
    var verifiedAt: Date? = nil

    /// Spec `access`: an active store subscription, including any grace or billing-retry period the store reports.
    var grantsAccess: Bool { state == .subscribed || state == .gracePeriod || state == .billingRetry }
    var hasBillingIssue: Bool { state == .gracePeriod || state == .billingRetry }
    /// A subscription this device saw, now over.
    var lapsed: Bool { state == .expired || state == .revoked }

    static let offlineHoldDays = 7

    /// Spec `offline`: with the store out of reach, the cached status holds until expiry plus 7 days.
    func holdsWithoutStore(now: Date = Date()) -> Bool {
        guard grantsAccess, let expiresAt,
              let limit = Calendar(identifier: .gregorian).date(byAdding: .day, value: Self.offlineHoldDays, to: expiresAt) else { return false }
        return now < limit
    }
}

/// Report credits on this device (spec `reportCredit`). `credited` and `revoked` hold store transaction IDs, so a
/// transaction the store delivers twice (or again after a crash before `finish()`) never counts twice.
struct ReportCreditLedger: Codable, Equatable {
    var credits = 0
    var credited: [String] = []
    var revoked: [String] = []

    /// Adds the credit for a purchase. False when this transaction was already applied.
    mutating func add(transactionID: String) -> Bool {
        guard !credited.contains(transactionID), !revoked.contains(transactionID) else { return false }
        credited.append(transactionID)
        credits += 1
        return true
    }

    /// A refund takes back the credit if it hasn't been used; an already used credit can't go below zero.
    mutating func revoke(transactionID: String) -> Bool {
        guard !revoked.contains(transactionID) else { return false }
        if credited.contains(transactionID) { credits = max(0, credits - 1) }
        revoked.append(transactionID)
        return true
    }
}

@MainActor
@Observable
final class StoreKitSubscriptionService {
    enum ProductsState { case idle, loading, loaded, unavailable }
    enum PurchaseOutcome: Equatable { case purchased, pending, cancelled, failed(String) }
    enum RestoreOutcome: Equatable { case restored, nothingFound, cancelled, failed(String) }

    let ids: IOSStoreDef?
    /// Products by ID. Prices shown in the app always come from these.
    private(set) var products: [String: Product] = [:]
    private(set) var productsState: ProductsState = .idle
    /// The last verified status (the cache, once written).
    private(set) var status: StoreSubscriptionStatus
    /// The store answered the last time it was asked, so `status` overrides anything cached.
    private(set) var storeAnswered = false
    private(set) var credits: Int

    /// App-level connection state. With no connection the store isn't asked and the cache rule applies.
    @ObservationIgnored var isReachable: () -> Bool = { true }

    @ObservationIgnored private var ledger: ReportCreditLedger
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    /// The subscription transaction just delivered, in case the store's own answers lag behind it for a few seconds.
    @ObservationIgnored private var recentPurchase: (status: StoreSubscriptionStatus, until: Date)?

    private static let statusKey = "store-status"
    private static let ledgerKey = "report-credit-ledger"

    init(ids: IOSStoreDef?) {
        self.ids = ids
        let dec = JSONDecoder()
        self.status = DeviceVault.data(Self.statusKey).flatMap { try? dec.decode(StoreSubscriptionStatus.self, from: $0) } ?? StoreSubscriptionStatus()
        let l = DeviceVault.data(Self.ledgerKey).flatMap { try? dec.decode(ReportCreditLedger.self, from: $0) } ?? ReportCreditLedger()
        self.ledger = l
        self.credits = l.credits
    }

    /// Listens for transactions from launch on (renewals, refunds, Ask to Buy approvals, purchases on another device) and
    /// picks up any transaction left unfinished by an earlier run.
    func start() {
        guard updatesTask == nil, ids != nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates { await self?.handle(result) }
        }
        Task { [weak self] in
            for await result in Transaction.unfinished { await self?.handle(result) }
            await self?.loadProducts()
            await self?.refresh()
        }
    }

    // MARK: Access

    /// An active store subscription. An answer from the store stands as it is; without one, spec `offline` applies.
    var hasSubscription: Bool {
        #if DEBUG
        if let forced = debugForcedAccess { return forced }
        #endif
        guard status.grantsAccess else { return false }
        return storeAnswered || status.holdsWithoutStore()
    }

    var isOfflineHold: Bool { !storeAnswered && hasSubscription }

    func product(for id: String?) -> Product? { id.flatMap { products[$0] } }
    var monthly: Product? { product(for: ids?.monthly) }
    var yearly: Product? { product(for: ids?.yearly) }
    var reportCredit: Product? { product(for: ids?.reportCredit) }

    // MARK: Products

    /// `unavailable` covers a thrown error and an empty answer (no connection, or a build the store has no products for).
    func loadProducts() async {
        guard let ids else { productsState = .unavailable; return }
        if !products.isEmpty, productsState == .loaded { return }
        productsState = .loading
        do {
            let found = try await Product.products(for: ids.all)
            products = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            productsState = found.isEmpty ? .unavailable : .loaded
        } catch {
            products = [:]
            productsState = .unavailable
        }
    }

    // MARK: Status

    /// Asks the store and updates the cache. Calls that arrive during a refresh wait for it instead of starting another.
    func refresh() async {
        #if DEBUG
        if debugForcedAccess != nil { return }
        #endif
        if let running = refreshTask { await running.value; return }
        let task = Task<Void, Never> { [weak self] in await self?.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        guard let ids else { return }
        let answer = await answerFromStore(ids)
        // A signed, unexpired transaction on the device is better than the cache and works with no connection. It also
        // covers the moment after a purchase, when the store's status can still be the one from before it.
        var local = await localEntitlement(ids)
        if local == nil, let recent = recentPurchase, Date() < recent.until { local = recent.status }
        storeAnswered = answer != nil
        switch (answer, local) {
        case let (a?, l?) where !a.grantsAccess || (a.expiresAt ?? .distantPast) < (l.expiresAt ?? .distantPast): write(l)
        case let (a?, _): write(a)
        case let (nil, l?): write(l)
        case (nil, nil): break
        }
        scheduleExpiryCheck()
    }

    /// nil when the store can't be reached or can't say. An empty list from the store is an answer: no subscription.
    private func answerFromStore(_ ids: IOSStoreDef) async -> StoreSubscriptionStatus? {
        guard isReachable() else { return nil }
        if products.isEmpty { await loadProducts() }
        guard let group = monthly?.subscription?.subscriptionGroupID ?? yearly?.subscription?.subscriptionGroupID ?? status.groupID else { return nil }
        guard let statuses = try? await Product.SubscriptionInfo.status(for: group) else { return nil }
        let rank: [StoreSubscriptionStatus.State: Int] = [.subscribed: 5, .gracePeriod: 4, .billingRetry: 3, .expired: 2, .revoked: 1, .none: 0]
        var best = StoreSubscriptionStatus(groupID: group, verifiedAt: Date())
        for s in statuses {
            guard case .verified(let t) = s.transaction, ids.subscriptionIDs.contains(t.productID) else { continue }
            var renewal: Product.SubscriptionInfo.RenewalInfo?
            if case .verified(let r) = s.renewalInfo { renewal = r }
            let state: StoreSubscriptionStatus.State
            switch s.state {
            case .subscribed: state = .subscribed
            case .inGracePeriod: state = .gracePeriod
            case .inBillingRetryPeriod: state = .billingRetry
            case .expired: state = .expired
            case .revoked: state = .revoked
            default: state = .none
            }
            guard rank[state, default: 0] > rank[best.state, default: 0] else { continue }
            // Revoked: when it was refunded, not when the refunded period would have ended.
            let ends = t.revocationDate ?? [t.expirationDate, renewal?.gracePeriodExpirationDate].compactMap { $0 }.max()
            best = StoreSubscriptionStatus(state: state, productID: t.productID, expiresAt: ends,
                                           willAutoRenew: renewal?.willAutoRenew ?? false,
                                           pendingProductID: renewal?.autoRenewPreference == t.productID ? nil : renewal?.autoRenewPreference,
                                           groupID: group, verifiedAt: Date())
        }
        return best
    }

    private func localEntitlement(_ ids: IOSStoreDef) async -> StoreSubscriptionStatus? {
        var latest: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, ids.subscriptionIDs.contains(t.productID),
                  t.revocationDate == nil, !t.isUpgraded else { continue }
            if (t.expirationDate ?? .distantPast) > (latest?.expirationDate ?? .distantPast) { latest = t }
        }
        guard let t = latest else { return nil }
        return StoreSubscriptionStatus(state: .subscribed, productID: t.productID, expiresAt: t.expirationDate,
                                       willAutoRenew: status.productID == t.productID ? status.willAutoRenew : true,
                                       pendingProductID: status.productID == t.productID ? status.pendingProductID : nil,
                                       groupID: t.subscriptionGroupID, verifiedAt: Date())
    }

    private func write(_ s: StoreSubscriptionStatus) {
        status = s
        if let data = try? JSONEncoder().encode(s) { DeviceVault.set(data, Self.statusKey) }
    }

    /// Asks again when the paid period ends, so a subscription that lapses while the app is open is noticed. One-shot.
    private func scheduleExpiryCheck() {
        expiryTask?.cancel()
        guard status.grantsAccess, let end = status.expiresAt else { return }
        let wait = end.timeIntervalSinceNow + 2
        guard wait > 0 else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if !Task.isCancelled { await self?.refresh() }
        }
    }

    // MARK: Transactions

    private func handle(_ result: VerificationResult<Transaction>) async {
        // An unverified transaction unlocks nothing and stays unfinished.
        guard case .verified(let t) = result else { return }
        #if DEBUG
        DebugStoreLab.log("TRANSACTION delivered id=\(t.id) product=\(t.productID) revoked=\(t.revocationDate != nil)")
        #endif
        if t.productID == ids?.reportCredit {
            if applyCredit(t) { await t.finish() }
        } else {
            await t.finish()
            await refreshSettled(after: t)
        }
    }

    /// After a transaction: now, and once more shortly after, when the store's status has caught up (a pending plan change
    /// shows only then).
    private func refreshSettled(after t: Transaction) async {
        recentPurchase = nil
        if t.revocationDate == nil, !t.isUpgraded, (t.expirationDate ?? .distantPast) > Date() {
            let s = StoreSubscriptionStatus(state: .subscribed, productID: t.productID, expiresAt: t.expirationDate, willAutoRenew: true,
                                            groupID: t.subscriptionGroupID, verifiedAt: Date())
            recentPurchase = (s, Date().addingTimeInterval(15))
        }
        await refresh()
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { await self?.refresh() }
        }
    }

    /// Spec `reportCredit`: the credit is saved first, and the transaction is finished only after that. False = not saved.
    private func applyCredit(_ t: Transaction) -> Bool {
        var next = ledger
        let id = String(t.id)
        let changed = t.revocationDate != nil ? next.revoke(transactionID: id) : next.add(transactionID: id)
        guard changed else { return true }
        return saveLedger(next)
    }

    private func saveLedger(_ next: ReportCreditLedger) -> Bool {
        guard let data = try? JSONEncoder().encode(next), DeviceVault.set(data, Self.ledgerKey) else { return false }
        ledger = next
        credits = next.credits
        return true
    }

    /// Generating an inspection's first report with no subscription and no trial. False when there is no credit to use.
    func useCredit() -> Bool {
        guard ledger.credits > 0 else { return false }
        var next = ledger
        next.credits -= 1
        return saveLedger(next)
    }

    // MARK: Purchase, restore, manage

    /// Pending (Ask to Buy, an extra bank step) and cancelled are not errors. A pending purchase arrives later through
    /// `Transaction.updates`.
    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let t) = result else {
                    return .failed("We couldn't verify that purchase with Apple. Try Restore Purchases.")
                }
                if t.productID == ids?.reportCredit {
                    // Left unfinished, so the store delivers it again next launch.
                    guard applyCredit(t) else { return .failed("That purchase couldn't be saved on this device yet. Open VIMS again to finish it.") }
                    await t.finish()
                } else {
                    await t.finish()
                    await refreshSettled(after: t)
                }
                return .purchased
            case .pending: return .pending
            case .userCancelled: return .cancelled
            @unknown default: return .cancelled
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed("The purchase didn't go through. Check your connection and try again.")
        }
    }

    func restore() async -> RestoreOutcome {
        do {
            try await StoreKit.AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed("Purchases couldn't be restored right now. Check your connection and try again.")
        }
        for await result in Transaction.unfinished { await handle(result) }
        await refresh()
        return hasSubscription ? .restored : .nothingFound
    }

    /// The store's own screen; Safari's account page if it can't open here.
    func showManageSubscriptions() async {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        if let scene {
            do {
                try await StoreKit.AppStore.showManageSubscriptions(in: scene)
                await refresh()
                return
            } catch {}
        }
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") { await UIApplication.shared.open(url) }
    }

    // MARK: DEBUG

    #if DEBUG
    /// -activeSub (screen jumper): reads as subscribed without asking the store.
    @ObservationIgnored var debugForcedAccess: Bool?
    func debugSet(status s: StoreSubscriptionStatus) { write(s) }
    func debugSet(credits n: Int) {
        var next = ledger
        next.credits = n
        _ = saveLedger(next)
    }
    func debugResetVault() {
        DeviceVault.remove(Self.statusKey)
        DeviceVault.remove(Self.ledgerKey)
        status = StoreSubscriptionStatus()
        ledger = ReportCreditLedger()
        credits = 0
        storeAnswered = false
    }
    func debugHandle(_ result: VerificationResult<Transaction>) async { await handle(result) }
    #endif
}

// MARK: - Master admin code (support.ownerCode)

/// The platform-owner emails are public, so the account is a normal user until this code is entered once on the device.
/// Compare: strip everything but letters and digits, uppercase, PBKDF2-HMAC-SHA256 over the UTF-8 result, with the
/// hex-decoded salt. The code itself is never in the repo or the app, only the salt and hash in the shared JSON.
enum OwnerCode {
    static func normalized(_ input: String) -> String {
        String(input.filter { $0.isLetter || $0.isNumber }).uppercased()
    }

    static func hexBytes(_ hex: String) -> [UInt8]? {
        let chars = Array(hex)
        guard !chars.isEmpty, chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let b = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            out.append(b)
        }
        return out
    }

    /// The hash of an already normalized code, in lowercase hex. nil if the salt isn't valid hex or the derivation fails.
    static func derive(normalizedCode: String, saltHex: String, iterations: Int) -> String? {
        guard let salt = hexBytes(saltHex), iterations > 0 else { return nil }
        let pw = Array(normalizedCode.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = pw.withUnsafeBufferPointer { p in
            p.withMemoryRebound(to: Int8.self) { password in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress, password.count, salt, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &out, out.count)
            }
        }
        guard status == 0 else { return nil }
        return out.map { String(format: "%02x", $0) }.joined()
    }

    static func matches(_ input: String, spec: OwnerCodeDef) -> Bool {
        let code = normalized(input)
        guard !code.isEmpty, let hash = derive(normalizedCode: code, saltHex: spec.saltHex, iterations: spec.iterations) else { return false }
        let want = spec.hashHex.lowercased()
        guard hash.count == want.count else { return false }
        return zip(hash.utf8, want.utf8).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// The verified flag, per account (by normalized email) and per device, in the Keychain: an upgrade keeps it, a backup
/// restored to another device doesn't carry it, and Delete account removes it.
enum OwnerVerification {
    private static func key(_ email: String) -> String { "owner-verified:\(PlatformOwner.normalized(email))" }

    static func isVerified(email: String) -> Bool {
        #if DEBUG
        // -ownerBypass: every platform-owner email reads as verified (developer builds only).
        if CommandLine.arguments.contains("-ownerBypass") { return true }
        #endif
        return DeviceVault.data(key(email)) != nil
    }

    @discardableResult
    static func setVerified(email: String) -> Bool { DeviceVault.set(Data([1]), key(email)) }

    static func clear(email: String) { DeviceVault.remove(key(email)) }
}
