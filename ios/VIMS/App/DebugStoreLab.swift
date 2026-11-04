#if DEBUG
import Foundation
import StoreKit
import SwiftUI

// DEBUG only, never compiled into Release or Store builds.
//
// Launch flags for store state (see the list in DebugLaunch.swift), plus a simulator lab that runs real StoreKit against
// VIMS.storekit without Xcode's Run button. Xcode applies a scheme's StoreKit configuration only when Xcode itself launches
// the app, so `simctl launch` needs this for scripted testing:
//
//   P=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library
//   SIMCTL_CHILD_DYLD_FRAMEWORK_PATH=$P/Frameworks:$P/PrivateFrameworks xcrun simctl launch --terminate-running-process \
//     <device> com.vims.app -storeKitLab "$PWD/VIMS.storekit" -noSplash -noVideo
//
// It loads StoreKitTest's SKTestSession from the simulator runtime (accelerated renewals, expiry, refunds, billing retry).
// Commands: write lines to Documents/storelab-cmd.txt in the app's data container; results are appended to
// Documents/storelab-out.txt. See `run(_:)` for the commands.

extension DebugLaunch {
    /// -ownerCodeTest CODE: the Master admin code screen checks against this throwaway code, hashed like the real one.
    static let ownerCodeTestSpec: OwnerCodeDef? = {
        guard let code = value("-ownerCodeTest") else { return nil }
        let salt = PasswordHasher.newSalt()
        guard let hash = OwnerCode.derive(normalizedCode: OwnerCode.normalized(code), saltHex: salt, iterations: 200_000) else { return nil }
        return OwnerCodeDef(saltHex: salt, iterations: 200_000, hashHex: hash)
    }()

    /// Before the app's store is created (the session must exist before StoreKit is first used).
    static func prepareStoreFlags() {
        MainActor.assumeIsolated { DebugStoreLab.startIfRequested() }
    }

    @MainActor
    static func applyStoreFlags(_ store: AppStore) {
        let p = store.purchases
        if has("-resetStoreVault") { p.debugResetVault() }
        if has("-resetOwnerCode") {
            for e in PlatformOwner.emails(store.config) { OwnerVerification.clear(email: e) }
            if let u = store.currentUser { store.loadSession(u) }
        }
        if let n = value("-storeCredits").flatMap(Int.init) { p.debugSet(credits: n) }
        if let v = value("-seedStoreCache") {
            let parts = v.split(separator: ":").map(String.init)
            let state = StoreSubscriptionStatus.State(rawValue: parts.first ?? "") ?? .subscribed
            let days = parts.count > 1 ? Double(parts[1]) ?? 0 : 0
            p.debugSet(status: StoreSubscriptionStatus(state: state, productID: p.ids?.monthly,
                                                       expiresAt: Date().addingTimeInterval(days * 86_400),
                                                       willAutoRenew: true, verifiedAt: Date()))
        }
        if has("-storeOffline") { p.isReachable = { false } }
        if has("-activeSub") {
            p.debugForcedAccess = true
            p.debugSet(status: StoreSubscriptionStatus(state: .subscribed, productID: p.ids?.monthly,
                                                       expiresAt: Date().addingTimeInterval(20 * 86_400),
                                                       willAutoRenew: true, verifiedAt: Date()))
        }
        if has("-ownerCodeSelfTest") { DebugStoreLab.ownerCodeSelfTest() }
        DebugStoreLab.attach(store)
    }
}

@MainActor
enum DebugStoreLab {
    private static var session: NSObject?
    private static weak var store: AppStore?
    private static var timer: Timer?
    private static var busy = false

    private static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static var commandFile: URL { documents.appendingPathComponent("storelab-cmd.txt") }
    private static var outputFile: URL { documents.appendingPathComponent("storelab-out.txt") }

    static func log(_ line: String) {
        print("STORELAB \(line)")
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: outputFile) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
            try? h.close()
        } else {
            try? data.write(to: outputFile)
        }
    }

    static func startIfRequested() {
        #if targetEnvironment(simulator)
        guard let path = DebugLaunch.value("-storeKitLab") else { return }
        try? FileManager.default.removeItem(at: outputFile)
        // SKTestSession aborts the process if it can't load XCTest, which needs this path (see the launch command above).
        guard ProcessInfo.processInfo.environment["DYLD_FRAMEWORK_PATH"] != nil else {
            log("LAB failed: launch with SIMCTL_CHILD_DYLD_FRAMEWORK_PATH set to the simulator platform's Frameworks and PrivateFrameworks")
            return
        }
        guard dlopen("/Developer/Library/Frameworks/StoreKitTest.framework/StoreKitTest", RTLD_NOW) != nil,
              let cls = NSClassFromString("SKTestSession") as? NSObject.Type else {
            log("LAB failed: StoreKitTest isn't available (\(String(cString: dlerror())))")
            return
        }
        typealias Init = @convention(c) (AnyObject, Selector, NSURL, UnsafeMutablePointer<NSError?>?) -> AnyObject?
        let alloc = cls.perform(NSSelectorFromString("alloc")).takeRetainedValue()
        let sel = NSSelectorFromString("initWithContentsOfURL:error:")
        guard let imp = (alloc as? NSObject)?.method(for: sel) else { log("LAB failed: no initWithContentsOfURL"); return }
        var error: NSError?
        let made = unsafeBitCast(imp, to: Init.self)(alloc, sel, URL(fileURLWithPath: path) as NSURL, &error) as? NSObject
        guard let made else { log("LAB failed: \(error?.localizedDescription ?? "no session")"); return }
        session = made
        made.setValue(!DebugLaunch.has("-storeKitDialogs"), forKey: "disableDialogs")
        if DebugLaunch.has("-storeKitClear") {
            _ = made.perform(NSSelectorFromString("clearTransactions"))
        }
        log("LAB session started from \(path)")
        #endif
    }

    static func attach(_ s: AppStore) {
        guard session != nil else { return }
        store = s
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated { poll() }
        }
    }

    private static func poll() {
        guard !busy, FileManager.default.fileExists(atPath: commandFile.path),
              let text = try? String(contentsOf: commandFile, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: commandFile)
        busy = true
        Task {
            for line in text.split(separator: "\n") {
                let line = line.trimmingCharacters(in: .whitespaces)
                if !line.isEmpty { log("> \(line)"); await run(line) }
            }
            busy = false
        }
    }

    // MARK: Commands

    private static func run(_ line: String) async {
        guard let store, let session else { return }
        let p = store.purchases
        let parts = line.split(separator: " ").map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        func product(_ name: String) -> String {
            switch name {
            case "monthly": return p.ids?.monthly ?? name
            case "yearly": return p.ids?.yearly ?? name
            case "credit": return p.ids?.reportCredit ?? name
            default: return name
            }
        }
        switch parts[0] {
        case "status": dump(store)
        case "transactions":
            for t in transactions(session) {
                log("TX id=\(t.value(forKey: "identifier") ?? "") product=\(t.value(forKey: "productIdentifier") ?? "") state=\(t.value(forKey: "state") ?? "") expires=\(t.value(forKey: "expirationDate") ?? "-") cancel=\(t.value(forKey: "cancelDate") ?? "-") renew=\(t.value(forKey: "autoRenewingEnabled") ?? "") issue=\(t.value(forKey: "hasPurchaseIssue") ?? "") askToBuy=\(t.value(forKey: "pendingAskToBuyConfirmation") ?? "")")
            }
        case "refresh": await p.refresh(); dump(store)
        case "load": await p.loadProducts(); dump(store)
        case "buy":
            await p.loadProducts()
            guard let item = p.product(for: product(arg)) else { log("buy: no product \(arg)"); return }
            log("buy \(arg) -> \(await p.purchase(item))")
            dump(store)
        case "restore": log("restore -> \(await p.restore())"); dump(store)
        case "manage": await p.showManageSubscriptions(); log("manage returned")
        case "expire": callID(session, "expireSubscriptionWithProductIdentifier:error:", product(arg))
        case "renew": callID(session, "forceRenewalOfSubscriptionWithProductIdentifier:error:", product(arg))
        case "refund", "resolve", "approve", "decline", "autorenewoff", "autorenewon":
            let selector = ["refund": "refundTransactionWithIdentifier:error:", "resolve": "resolveIssueForTransactionWithIdentifier:error:",
                            "approve": "approveAskToBuyTransactionWithIdentifier:error:", "decline": "declineAskToBuyTransactionWithIdentifier:error:",
                            "autorenewoff": "disableAutoRenewForTransactionWithIdentifier:error:",
                            "autorenewon": "enableAutoRenewForTransactionWithIdentifier:error:"][parts[0]] ?? ""
            let txs = transactions(session).filter { arg.isEmpty || ($0.value(forKey: "productIdentifier") as? String) == product(arg) }
            guard let t = txs.last, let id = t.value(forKey: "identifier") as? UInt else { log("\(parts[0]): no transaction"); return }
            callNumber(session, selector, id)
        case "rate": session.setValue(Int(arg) ?? 0, forKey: "timeRate"); log("timeRate=\(arg)")
        case "retry": session.setValue(arg == "on", forKey: "billingRetryOnRenewalEnabled"); log("billingRetry=\(arg)")
        case "grace": session.setValue(arg == "on", forKey: "billingGracePeriodEnabled"); log("grace=\(arg)")
        case "asktobuy": session.setValue(arg == "on", forKey: "askToBuyEnabled"); log("askToBuy=\(arg)")
        case "dialogs": session.setValue(arg != "on", forKey: "disableDialogs"); log("dialogs=\(arg)")
        case "clear": _ = session.perform(NSSelectorFromString("clearTransactions")); log("cleared")
        case "offline": p.isReachable = arg == "on" ? { false } : { [weak store] in store?.isOnline ?? true }; await p.refresh(); dump(store)
        case "wait":
            try? await Task.sleep(nanoseconds: UInt64((Double(arg) ?? 1) * 1_000_000_000))
        case "trial":
            store.state.subscription.trialStart = Calendar.current.date(byAdding: .day, value: -(store.state.subscription.trialDays - (Int(arg) ?? 0)), to: Date()) ?? Date()
            dump(store)
        case "signin":
            if let u = store.repo.user(email: PlatformOwner.normalized(arg)) { store.loadSession(u) }
            dump(store)
        case "signout": store.signOut()
        case "create":
            do { try await store.createAccount(name: "Lab Tester", company: "Lab Co", email: arg, password: "Labtester2026") }
            catch { log("create failed: \(error)") }
            DebugFlags.skipEulaGate = true
            store.showSplash = false
            dump(store)
        case "go":
            switch arg {
            case "home": store.goHome()
            case "plans": store.path = [.subscribe]
            case "billing": store.path = [.settings, .billing]
            case "settings": store.path = [.settings]
            case "inspectors": store.path = [.settings, .inspectors]
            case "pricing": store.path = [.settings, .plans]
            case "delete": store.path = [.settings, .deleteAccount]
            case "instructions": store.path = [.settings, .instructions]
            case "ownercode": store.path = [.settings, .ownerCode]
            case "wizard": store.path = [.wizard(editing: nil)]
            default: log("go: unknown \(arg)")
            }
        case "newinspection":
            store.startNewInspection()
            try? await Task.sleep(nanoseconds: 700_000_000)
            log("newinspection canStart=\(store.canStartNewInspection) path=\(store.path)")
        case "inspection":   // a saved inspection, built the way the wizard builds it
            var d = store.newInspectionDraft()
            d.fields[Inspection.streetField] = parts.dropFirst().joined(separator: " ")
            d.fields[Inspection.cityField] = "Ogden"
            d.inspType = "General"
            let id = store.buildChecklist(from: d)
            log("inspection id=\(id) reportUsesCredit=\(store.reportUsesCredit(id))")
        case "list":
            for i in store.inspections { log("INSP \(i.id) \(i.addressLine1) report=\(i.report != nil) usesCredit=\(store.reportUsesCredit(i.id))") }
        case "report":
            guard let i = inspection(store, arg) else { log("report: no inspection"); return }
            let before = p.credits
            let info = await store.generateReport(i.id)
            log("report \(i.addressLine1) generated=\(info != nil) credits \(before) -> \(p.credits)")
        case "open":
            guard let i = inspection(store, arg) else { log("open: no inspection"); return }
            store.path = [.sections(i.id)]
        case "openreport":
            guard let i = inspection(store, arg) else { log("openreport: no inspection"); return }
            store.path = [.sections(i.id), .report(i.id)]
        case "openready":
            guard let i = inspection(store, arg) else { log("openready: no inspection"); return }
            store.path = [.sections(i.id), .reportReady(i.id)]
        case "edit":     // edits a saved inspection and saves it: never blocked
            guard let i = inspection(store, arg) else { log("edit: no inspection"); return }
            store.update(i.id) { $0.fields["Lab note"] = parts.dropFirst(2).joined(separator: " ") }
            log("edit saved field=\(store.inspection(i.id)?.fields["Lab note"] ?? "")")
        case "maildraft":
            guard let i = inspection(store, arg), let url = store.reportURL(i.id) else { log("maildraft: no report"); return }
            let d = store.reportMailDraft(i, pdf: url)
            log("maildraft to=\(d.to) cc=\(d.cc) attachmentExists=\(FileManager.default.fileExists(atPath: url.path))")
        case "invite":     // a row from an earlier build: a person added before companyJoin went off, with no account
            store.state.company.inspectors.append(Inspector(name: "Sam Invited", email: "sam.invited@lab.test"))
        case "ledgertest":
            var l = ReportCreditLedger()
            let a = l.add(transactionID: "7"), again = l.add(transactionID: "7"), b = l.add(transactionID: "8")
            let r = l.revoke(transactionID: "7"), rAgain = l.revoke(transactionID: "7"), afterRevoke = l.add(transactionID: "7")
            log("ledgertest add=\(a) duplicate=\(again) second=\(b) revoke=\(r) revokeAgain=\(rAgain) addAfterRevoke=\(afterRevoke) credits=\(l.credits) (want true false true true false false 1)")
        case "ownercode":
            log("ownercode -> \(await store.verifyOwnerCode(parts.dropFirst().joined(separator: " "))) isPlatformOwner=\(store.isPlatformOwner) needsOwnerCode=\(store.needsOwnerCode)")
        default: log("unknown command \(line)")
        }
    }

    private static func inspection(_ store: AppStore, _ prefix: String) -> Inspection? {
        store.inspections.first { $0.addressLine1.hasPrefix(prefix) }
            ?? store.inspections.first { $0.id.uuidString.hasPrefix(prefix) }
            ?? (prefix.isEmpty ? store.inspections.first : nil)
    }

    private static func dump(_ store: AppStore) {
        let p = store.purchases, s = p.status
        let f = ISO8601DateFormatter()
        log("STATUS email=\(store.session?.email ?? "-") hasSub=\(p.hasSubscription) state=\(s.state.rawValue) product=\(s.productID ?? "-") expires=\(s.expiresAt.map(f.string) ?? "-") willRenew=\(s.willAutoRenew) pending=\(s.pendingProductID ?? "-") answered=\(p.storeAnswered) credits=\(p.credits) canStartNew=\(store.canStartNewInspection) trialLeft=\(store.subscription.trialDaysLeft) exempt=\(store.isSubscriptionExempt) needsOwnerCode=\(store.needsOwnerCode) productsState=\(p.productsState) prices=\(p.products.map { "\($0.key)=\($0.value.displayPrice)" }.sorted())")
    }

    private static func transactions(_ session: NSObject) -> [NSObject] {
        (session.perform(NSSelectorFromString("allTransactions"))?.takeUnretainedValue() as? [NSObject]) ?? []
    }

    private static func callID(_ session: NSObject, _ name: String, _ id: String) {
        typealias Fn = @convention(c) (AnyObject, Selector, NSString, UnsafeMutablePointer<NSError?>?) -> Bool
        let sel = NSSelectorFromString(name)
        var error: NSError?
        let ok = unsafeBitCast(session.method(for: sel), to: Fn.self)(session, sel, id as NSString, &error)
        log("\(name) \(id) -> \(ok) \(error?.localizedDescription ?? "")")
    }

    private static func callNumber(_ session: NSObject, _ name: String, _ id: UInt) {
        typealias Fn = @convention(c) (AnyObject, Selector, UInt, UnsafeMutablePointer<NSError?>?) -> Bool
        let sel = NSSelectorFromString(name)
        var error: NSError?
        let ok = unsafeBitCast(session.method(for: sel), to: Fn.self)(session, sel, id, &error)
        log("\(name) \(id) -> \(ok) \(error?.localizedDescription ?? "")")
    }

    // MARK: Master admin code self test (a throwaway code; the real code is never in the repo)

    static func ownerCodeSelfTest() {
        let code = "vims test-42 throwaway"
        let saltHex = "00112233445566778899aabbccddeeff"
        let normalized = OwnerCode.normalized(code)
        guard let hash = OwnerCode.derive(normalizedCode: normalized, saltHex: saltHex, iterations: 200_000) else {
            log("OWNERCODETEST derive failed"); return
        }
        let spec = OwnerCodeDef(saltHex: saltHex, iterations: 200_000, hashHex: hash)
        // RFC-style check of the derivation itself: PBKDF2-HMAC-SHA256("password", "salt", 1 iteration).
        let known = OwnerCode.derive(normalizedCode: "password", saltHex: Data("salt".utf8).map { String(format: "%02x", $0) }.joined(), iterations: 1)
        log("OWNERCODETEST normalized=\(normalized) known-vector=\(known == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")")
        let checks: [(String, Bool)] = [("vims test-42 throwaway", true), ("VIMSTEST42THROWAWAY", true), (" v-i-m-s test 42 throwaway! ", true),
                                        ("vims test-43 throwaway", false), ("", false), ("---", false)]
        for (input, want) in checks {
            let got = OwnerCode.matches(input, spec: spec)
            log("OWNERCODETEST \(got == want ? "PASS" : "FAIL") input=\"\(input)\" matches=\(got)")
        }
    }
}
#endif
