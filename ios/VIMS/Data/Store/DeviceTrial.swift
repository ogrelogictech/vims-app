import Foundation
import Security

/// One free trial per device (client Oct 23–25). The first trial started on this device is recorded in the Keychain,
/// which survives deleting and reinstalling the app (the SwiftData store does not):
///  - **Create account** on a device with no record starts the 30-day trial and records it. On a device that already
///    used its trial, the new company starts with the trial used up (Subscribe), `SubscriptionState.deviceTrialUsed`.
///  - **Demo account** (`DemoSeed`): its trial clock is kept here too (`demoTrialStart`), so reinstalling the app, or
///    deleting every account so the demo is seeded again, never gives the demo a fresh trial. The demo does not use up
///    the device's own trial.
///  - Joining a company with a code uses that company's subscription and records nothing.
///  - Upgrades from builds before this record: `backfill` records the earliest trial of the companies created on this
///    device (not the demo company).
/// Items are `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so a backup restored to another device doesn't carry them.
/// DEBUG: `-resetDeviceTrial` clears both records (testers), `-deviceTrialStatus` prints them.
///
/// TODO(backend): the Keychain is cleared by "Erase All Content and Settings", so the server enforces this for real with
/// Apple DeviceCheck (`DCDevice.current.generateToken` sent at Create account; the server reads / sets the device's two
/// DeviceCheck bits, e.g. bit0 = trial used) and refuses a second trial for the same device.
enum DeviceTrial {
    private static let service = "com.vims.app.device-trial"
    enum Key: String { case firstTrialStart, demoTrialStart }

    static func date(_ key: Key) -> Date? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key.rawValue, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    @discardableResult
    static func set(_ date: Date, _ key: Key) -> Bool {
        let data = Data(ISO8601DateFormatter().string(from: date).utf8)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: key.rawValue]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// DEBUG `-resetData`: the reseeded demo starts a fresh 10-day clock.
    static func clearDemo() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: Key.demoTrialStart.rawValue] as CFDictionary)
    }

    static let backfillDoneKey = "vims.deviceTrial.backfilled"

    static func clear() {
        UserDefaults.standard.set(true, forKey: backfillDoneKey)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    /// The trial a company created now gets: a fresh one (recorded) on a device that never had one, else one already
    /// used up (`trialStart` `trialDays` days ago → 0 days left).
    static func trialForNewCompany(trialDays: Int, now: Date = Date()) -> (start: Date, used: Bool) {
        if date(.firstTrialStart) != nil {
            return (Calendar.current.date(byAdding: .day, value: -trialDays, to: now) ?? now, true)
        }
        set(now, .firstTrialStart)
        return (now, false)
    }

    /// The demo company's trial start: the one recorded at its first seeding on this device, else `fresh` (recorded).
    static func demoTrialStart(fresh: Date) -> Date {
        if let d = date(.demoTrialStart) { return d }
        set(fresh, .demoTrialStart)
        return fresh
    }

    /// Builds from before this record: the earliest trial among the companies created on this device, and the demo
    /// company's current trial start.
    /// Runs once per install (UserDefaults flag), so a tester's `-resetDeviceTrial` isn't undone by the companies still on
    /// the device; a reinstall starts with an empty store, so there is nothing to backfill then.
    static func backfill(companies: [CompanyState], demoCode: String) {
        guard !UserDefaults.standard.bool(forKey: backfillDoneKey) else { return }
        UserDefaults.standard.set(true, forKey: backfillDoneKey)
        let isDemo = { (c: CompanyState) in c.profile.joinCode.caseInsensitiveCompare(demoCode) == .orderedSame }
        if date(.firstTrialStart) == nil, let first = companies.filter({ !isDemo($0) }).map(\.subscription.trialStart).min() {
            set(first, .firstTrialStart)
        }
        if date(.demoTrialStart) == nil, let demo = companies.first(where: isDemo) {
            set(demo.subscription.trialStart, .demoTrialStart)
        }
    }
}
