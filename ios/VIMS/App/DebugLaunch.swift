import Foundation
#if DEBUG
import MessageUI
#endif

/// One-shot initial UI states requested by DEBUG launch arguments (never set in Release).
enum DebugFlags {
    static var wizardStep: Int?
    static var openDrawer = false
    static var openMarkup = false
    static var openFlag = false
    static var coverStep: Int?
    static var suppressSplash = false
    static var adminGroup: String?
    static var openMenu = false
    static var validate = false
    /// Screenshot jumps (-screen / -skipLogin) skip the EULA gate unless -eulaGate or -eulaVersion is given.
    static var skipEulaGate = false
}

#if DEBUG
/// DEBUG-only screen jumper for review screenshots, e.g.
///   xcrun simctl launch "iPhone 17" com.vims.app -skipLogin -screen summary
/// Arguments:
///   -resetData                 wipe the SwiftData store + files and reseed the demo account
///   -video / -noVideo          force / skip the launch video (skipped by default with -screen)
///   -signInAs EMAIL            sign in as that local account
///   -eulaVersion V             pretend shared/legal/eula.json has version V (re-acceptance gate test)
///   -eulaGate                  show the EULA gate even with -screen / -skipLogin
///   -activeSub                 mark the signed-in company's subscription active (Square · Visa ····4242)
///   -eulaStatus                print each local account's accepted EULA version to the console
///   -mailSelfTest              print the report email draft (to/BCC/subject/attachment) to the console
///   -validate                  submit the form once so its validation errors show
///   -skipLogin                 sign in as the demo owner
///   -noSplash                  don't show the free-look splash
///   -trialDaysLeft N           override the free-look days left
///   -screen NAME               login signup forgot join home splash wizard sections section drawer photos
///                              markup flag summary report reportReady settings company instructions manage
///                              editSection plans inspectors subscribe subscribed billing feedback phase1 phase2
///   -step N                    wizard step (1–4) / cover picker step (1–3)
///   -depth high|standard|fast  checklist depth for the demo inspection
///   -section NAME              section to open (default Roof / Outside Utilities for high)
///   -generate                  with -screen reportReady: regenerate the PDF first
///   -inspection PREFIX         inspection whose address starts with PREFIX, or whose type equals it (default 1428…)
enum DebugLaunch {
    static var args: [String] { ProcessInfo.processInfo.arguments }

    static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static func has(_ key: String) -> Bool { args.contains(key) }

    static func prepareStorage() {
        if has("-resetData") { SwiftDataRepository.wipeStore(); FileStore().wipeAll() }
    }

    /// Prints the report email draft (and checks a real MFMailComposeViewController accepts it) so the
    /// BCC wiring can be verified on a simulator, which can't send mail.
    @MainActor
    static func mailSelfTest(_ store: AppStore) {
        // Prefer an inspection with client + agent emails (1428 Ridgeline); any generated PDF works as the attachment.
        let insp = store.inspections.first { !$0.field("Client email").isEmpty } ?? store.inspections.first
        guard let insp, let url = store.reportURL(insp.id) ?? store.inspections.lazy.compactMap({ store.reportURL($0.id) }).first else {
            print("MAILTEST no inspection with a report"); return
        }
        let d = ReportMailDraft.make(insp, company: store.company, platform: store.platform, pdf: url)
        print("MAILTEST canSendMail=\(MFMailComposeViewController.canSendMail())")
        print("MAILTEST to=\(d.to) bcc=\(d.bcc) subject=\(d.subject) attachment=\(d.attachmentName) bytes=\((try? Data(contentsOf: url))?.count ?? 0)")
        print("MAILTEST platform bccOn=\(store.platform.reportBccOn) bccEmail=\(store.platform.reportBccEmail)")
        if MFMailComposeViewController.canSendMail() {
            let vc = MFMailComposeViewController(); d.configure(vc); print("MAILTEST composer configured")
        }
    }

    @MainActor
    static func apply(to store: AppStore) {
        let screen = value("-screen")
        // The launch video only plays on a plain launch (or with -video).
        if (screen != nil || has("-skipLogin") || has("-noVideo")) && !has("-video") { store.showVideoSplash = false }
        if let email = value("-signInAs"), let u = store.repo.user(email: email) { store.loadSession(u) }
        if has("-noSplash") || (screen != nil && screen != "splash" && screen != "home") { DebugFlags.suppressSplash = true }
        if (has("-skipLogin") || (screen != nil && screen != "login" && !["signup", "forgot", "join", "signupEula"].contains(screen!))), store.session == nil,
           let demo = store.repo.user(email: DemoSeed.loginEmail) {
            store.loadSession(demo)
        }
        if let d = value("-trialDaysLeft"), let n = Int(d) {
            store.state.subscription.trialStart = Calendar.current.date(byAdding: .day, value: -(store.state.subscription.trialDays - n), to: Date()) ?? Date()
            store.state.subscription.active = false
            store.state.subscription.cancelledAt = nil
        }
        // -activeSub: pretend the company already subscribed (Plan & billing cancel test).
        if has("-activeSub"), store.session != nil, !store.state.subscription.active {
            store.state.subscription.active = true
            store.state.subscription.paymentLabel = "Square · Visa ····4242"
            store.state.subscription.startedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
            store.state.subscription.cancelledAt = nil
        }
        if let v = value("-eulaVersion") { store.eula.version = v }
        if (screen != nil || has("-skipLogin")), !has("-eulaGate"), value("-eulaVersion") == nil { DebugFlags.skipEulaGate = true }
        if has("-eulaStatus"), let repo = store.repo as? SwiftDataRepository {
            for u in repo.allUsers() {
                print("EULASTATUS \(u.email) version=\(u.eulaVersion ?? "none") acceptedAt=\(u.eulaAcceptedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none") current=\(store.eula.version)")
            }
        }
        if has("-mailSelfTest") { mailSelfTest(store) }
        guard let screen else { return }
        if ["login", "signup", "forgot", "join", "signupEula"].contains(screen), store.session != nil {
            let v = DebugFlags.validate
            store.signOut()
            DebugFlags.validate = v
        }
        if screen == "menu" { DebugFlags.openMenu = true }
        if has("-validate") { DebugFlags.validate = true }
        if let g = value("-group") { DebugFlags.adminGroup = g }
        // Screens that don't need an inspection.
        let general: [String: [Route]] = [
            "signup": [.signup], "forgot": [.forgot], "join": [.join], "wizard": [.wizard(editing: nil)],
            "settings": [.settings], "company": [.settings, .company], "instructions": [.settings, .instructions],
            "plans": [.settings, .plans], "subscribe": [.subscribe], "billing": [.settings, .billing],
            "feedback": [.settings, .feedbackAdmin], "eula": [.settings, .eula], "signupEula": [.signup, .eula], "reportBcc": [.settings, .reportBcc], "inspectors": [.settings, .inspectors], "manage": [.settings, .manageChecklist]
        ]
        if let r = general[screen] {
            if screen == "wizard" { DebugFlags.wizardStep = value("-step").flatMap(Int.init) }
            store.path = r
            return
        }

        let step = value("-step").flatMap(Int.init)
        let pick = value("-inspection") ?? "1428"
        guard let ridge = store.inspections.first(where: { $0.address.hasPrefix(pick) || $0.inspType == pick })
                ?? store.inspections.first else { return }
        let id = ridge.id
        if let d = value("-depth"), let depth = Depth(rawValue: d) { store.update(id, markDirty: false) { $0.depth = depth } }
        let depth = store.inspection(id)?.depth ?? .standard
        let section = value("-section") ?? (ridge.leafSections.contains("Roof") ? (depth == .high ? "Outside Utilities" : "Roof") : (ridge.leafSections.first ?? "Roof"))

        switch screen {
        case "login": break
        case "signup": store.path = [.signup]
        case "forgot": store.path = [.forgot]
        case "join": store.path = [.join]
        case "menu": break
        case "home": break
        case "splash": DebugFlags.suppressSplash = false; store.showSplash = true
        case "wizard": DebugFlags.wizardStep = step; store.path = [.wizard(editing: nil)]
        case "sections": store.path = [.sections(id)]
        case "section": store.path = [.sections(id), .section(id, section)]
        case "drawer": DebugFlags.openDrawer = true; store.path = [.sections(id), .section(id, section)]
        case "photos": store.path = store.catalog.isPhotosOnly(section) ? [.sections(id), .photos(id, section)] : [.sections(id), .section(id, section), .photos(id, section)]
        case "markup": DebugFlags.openMarkup = true; store.path = [.sections(id), .section(id, section), .photos(id, section)]
        case "flag": DebugFlags.openMarkup = true; DebugFlags.openFlag = true; store.path = [.sections(id), .section(id, section), .photos(id, section)]
        case "summary": store.path = [.sections(id), .summary(id)]
        case "report": DebugFlags.coverStep = step; store.path = [.sections(id), .summary(id), .report(id)]
        case "reportReady":
            if has("-generate") {
                Task { @MainActor in
                    _ = await store.generateReport(id)
                    store.path = [.sections(id), .reportReady(id)]
                }
            } else if value("-inspection") != nil { store.path = [.sections(id), .reportReady(id)] }
            else if let other = store.inspections.first(where: { $0.report != nil }) { store.path = [.sections(other.id), .reportReady(other.id)] }
        case "settings": store.path = [.settings]
        case "company": store.path = [.settings, .company]
        case "instructions": store.path = [.settings, .instructions]
        case "manage":
            if let g = value("-group") { DebugFlags.adminGroup = g }
            store.path = [.settings, .manageChecklist]
        case "editSection": store.path = [.settings, .manageChecklist, .editSection(value("-section") ?? "Roof")]
        case "plans": store.path = [.settings, .plans]
        case "inspectors":
            if store.state.company.inspectors.count < 2 {
                store.state.company.inspectors.append(Inspector(name: "Sam Rivera", email: "sam@vpi.com", admin: true))
            }
            store.path = [.settings, .inspectors]
        case "subscribe": store.path = [.subscribe]
        case "subscribed": store.path = [.subscribe, .subscriptionStarted]
        case "billing": store.path = [.settings, .billing]
        case "feedback": store.path = [.settings, .feedbackAdmin]
        case "phase1", "phase2":
            let type = screen == "phase1" ? "Phase 1 Foundation" : "Phase 2 Pre-Dry Wall"
            let existing = store.inspections.first { $0.inspType == type }
            let pid: UUID
            if let existing { pid = existing.id } else {
                var draft = store.newInspectionDraft()
                draft.inspType = type
                draft.fields["Inspection address"] = screen == "phase1" ? "57 Aspen Ridge Ct, Kaysville, UT 84037" : "19 Summit View Ln, Farmington, UT 84025"
                draft.fields["Client name"] = "Wasatch Builders"
                pid = store.buildChecklist(from: draft)
            }
            let first = store.inspection(pid)?.leafSections.first ?? ""
            store.path = has("-overview") ? [.sections(pid)] : [.sections(pid), .section(pid, first)]
        default: break
        }
    }
}
#endif
