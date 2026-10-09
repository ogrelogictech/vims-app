import Foundation
import UIKit
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
    /// -wizState TX[,UT]: states picked in the wizard on open (auto type / revert test).
    static var wizardStates: [String]?
    /// Screenshot jumps (-screen / -skipLogin) skip the EULA gate unless -eulaGate or -eulaVersion is given.
    static var skipEulaGate = false
    /// iPad review screenshots: open the State picker / quick-comment list / PDF preview / share sheet on arrival.
    static var openStatePicker = false
    static var openCommentList = false
    static var openPreview = false
    static var openShare = false
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
///   -profilePhotoSample        set the signed-in user's profile photo from an inspection photo
///   -activeSub                 mark the signed-in company's subscription active (Square · Visa ····4242)
///   -eulaStatus                print each local account's accepted EULA version to the console
///   -mailSelfTest              print the report email draft (to/CC/BCC/subject/attachment) + state-document drafts
///   -state XX                  set the chosen inspection's property state (OK summary disclosure, OR cover notice)
///   -wizState TX[,UT]          pick those states in order when the wizard opens (prints STATETEST lines)
///   -ackStateDocs              with -wizState: tick "Provided to the client with the inspection agreement"
///   -wizScroll ID              scroll wizard step 1 to a block (sendToAgent, agreementLine, State)
///   -ownAgreement NAME         use bundled NAME.pdf as the company's own uploaded agreement (same path as Upload your own)
///   -useVimsAgreement          revert the company to the VIMS agreement
///   -agreementScroll disclosures  scroll the agreement viewer to the state disclosures
///   -agreementStatus           print AGREEMENTTEST (bundled agreement loaded, state keys, own file)
///   -agreementState XX         with -screen agreement: open the viewer from the wizard for state XX (else from Company profile)
///   -landscape / -portrait     rotate the iPad simulator window (review screenshots; refused in iPadOS 26 windowed mode)
///   -openPicker                with -screen wizard: open the State picker
///   -openComment               with -screen markup: open the quick-comment list
///   -openPreview               with -screen reportReady / report: open the PDF preview
///   -openShare                 with -screen reportReady: Email to client (share sheet without Mail);
///                              with -screen agreement: Download (agreement PDF share sheet)
///   -validate                  submit the form once so its validation errors show
///   -skipLogin                 sign in as the demo owner
///   -noSplash                  don't show the free-look splash
///   -trialDaysLeft N           override the free-look days left
///   -screen NAME               login signup forgot join home splash wizard sections section drawer photos
///                              markup flag summary report reportReady settings company instructions manage
///                              editSection plans inspectors subscribe subscribed billing feedback phase1 phase2
///                              agreement agreementEditor
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

    /// -landscape / -portrait: rotate the iPad simulator's window for review screenshots (iPhone stays portrait).
    @MainActor
    static func applyOrientation() {
        let mask: UIInterfaceOrientationMask? = has("-landscape") ? .landscapeRight : has("-portrait") ? .portrait : nil
        guard let mask, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { print("ORIENTATION failed: \($0)") }
    }

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
        let d = store.reportMailDraft(insp, pdf: url)
        print("MAILTEST canSendMail=\(MFMailComposeViewController.canSendMail())")
        print("MAILTEST to=\(d.to) cc=\(d.cc) bcc=\(d.bcc) subject=\(d.subject) attachment=\(d.attachmentName) bytes=\((try? Data(contentsOf: url))?.count ?? 0)")
        print("MAILTEST signedIn=\(store.session?.email ?? "none") ccInspector=\(store.config.support.ccInspector != nil)")
        // State documents (stateRules docs) — the wizard's "Send to client" draft.
        for (code, rule) in (store.config.stateRules?.byState ?? [:]).sorted(by: { $0.key < $1.key }) {
            for doc in rule.requiredDocs {
                guard let pdf = doc.bundleURL else { print("MAILTEST statedoc \(code) MISSING \(doc.file)"); continue }
                let sd = ReportMailDraft.stateDocument(doc, pdf: pdf, insp: insp, company: store.company, sender: store.session?.name ?? "")
                print("MAILTEST statedoc \(code) to=\(sd.to) cc=\(sd.cc) bcc=\(sd.bcc) subject=\(sd.subject) attachment=\(sd.attachmentName) bytes=\((try? Data(contentsOf: pdf))?.count ?? 0)")
            }
        }
        // v1.4 "Send the report to the real estate agent": the same inspection picked in NH (agentCopyDefault false)
        // and UT (no rule → on), through the wizard's state setter.
        for code in ["NH", "UT"] {
            var v = insp; v.state = nil; v.setState(code, config: store.config)
            let dv = store.reportMailDraft(v, pdf: url)
            print("MAILTEST state=\(code) sendToAgent=\(v.sendsReportToAgent) to=\(dv.to) cc=\(dv.cc) bcc=\(dv.bcc)")
        }
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
        // -profilePhotoSample: use the first inspection photo on this device as the signed-in user's profile photo.
        if has("-profilePhotoSample"), store.currentUser?.photoFile == nil,
           let ref = store.inspections.lazy.flatMap({ $0.photos.values.flatMap { $0.values.flatMap { $0 } } }).first,
           let img = UIImage(contentsOfFile: store.files.url(for: ref.file).path) {
            store.saveProfilePhoto(img)
        }
        if has("-useVimsAgreement"), store.session != nil { store.useDefaultAgreement() }
        if let n = value("-ownAgreement"), store.session != nil {
            if let u = Bundle.main.url(forResource: n, withExtension: "pdf") { store.saveAgreement(from: u) }
            else { print("AGREEMENTTEST missing bundled \(n).pdf") }
        }
        if has("-agreementStatus") {
            let a = InspectionAgreement.bundled
            print("AGREEMENTTEST loaded=\(a != nil) version=\(a?.version ?? "-") states=\(a?.disclosureStates.joined(separator: ",") ?? "-") own=\(store.company.agreementName ?? "none") file=\(store.ownAgreementURL?.lastPathComponent ?? "none")")
        }
        if let v = value("-wizState") { DebugFlags.wizardStates = v.split(separator: ",").map(String.init) }
        if has("-mailSelfTest") { mailSelfTest(store) }
        guard let screen else { return }
        if ["login", "signup", "forgot", "join", "signupEula"].contains(screen), store.session != nil {
            let v = DebugFlags.validate
            store.signOut()
            DebugFlags.validate = v
        }
        if screen == "menu" { DebugFlags.openMenu = true }
        if has("-validate") { DebugFlags.validate = true }
        if has("-openPicker") { DebugFlags.openStatePicker = true }
        if has("-openComment") { DebugFlags.openCommentList = true }
        if has("-openPreview") { DebugFlags.openPreview = true }
        if has("-openShare") { DebugFlags.openShare = true }
        if let g = value("-group") { DebugFlags.adminGroup = g }
        // Screens that don't need an inspection.
        let general: [String: [Route]] = [
            "signup": [.signup], "forgot": [.forgot], "join": [.join], "wizard": [.wizard(editing: nil)],
            "settings": [.settings], "company": [.settings, .company], "instructions": [.settings, .instructions],
            "plans": [.settings, .plans], "subscribe": [.subscribe], "billing": [.settings, .billing],
            "feedback": [.settings, .feedbackAdmin], "agreement": value("-agreementState").map { [.wizard(editing: nil), .agreement(state: $0)] } ?? [.settings, .company, .agreement(state: nil)], "agreementEditor": [.settings, .company, .agreementEditor], "eula": [.settings, .eula], "deleteAccount": [.settings, .deleteAccount], "signupEula": [.signup, .eula], "reportBcc": [.settings, .reportBcc], "inspectors": [.settings, .inspectors], "manage": [.settings, .manageChecklist]
        ]
        if let r = general[screen] {
            if screen == "wizard" { DebugFlags.wizardStep = value("-step").flatMap(Int.init) }
            store.path = r
            return
        }

        let step = value("-step").flatMap(Int.init)
        let pick = value("-inspection") ?? "1428"
        // -inspection TYPE for a type with no inspection yet (e.g. Texas, "4 Point Inspection"): create one.
        if store.config.wizard.inspectionTypes.contains(pick), !store.inspections.contains(where: { $0.inspType == pick }) {
            var draft = store.newInspectionDraft()
            draft.inspType = pick
            draft.fields["Inspection address"] = "2207 Lakeview Ter, Austin, 78703"
            draft.fields["Client name"] = "Marisol Vega"
            _ = store.buildChecklist(from: draft)
        }
        guard let ridge = store.inspections.first(where: { $0.address.hasPrefix(pick) || $0.inspType == pick })
                ?? store.inspections.first else { return }
        let id = ridge.id
        // -state XX: set the property state on that inspection (summary disclosure / cover notice checks).
        if let st = value("-state") { store.update(id, markDirty: false) { $0.state = st; $0.stateDocsAck = nil } }
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
