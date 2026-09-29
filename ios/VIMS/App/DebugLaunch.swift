import Foundation

/// One-shot initial UI states requested by DEBUG launch arguments (never set in Release).
enum DebugFlags {
    static var wizardStep: Int?
    static var openDrawer = false
    static var openMarkup = false
    static var openFlag = false
    static var coverStep: Int?
    static var suppressSplash = false
    static var adminGroup: String?
}

#if DEBUG
/// DEBUG-only screen jumper for review screenshots, e.g.
///   xcrun simctl launch "iPhone 17" com.vims.app -skipLogin -screen summary
/// Arguments:
///   -resetData                 wipe local data and reseed the demo
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
        if has("-resetData") { FileRepository().wipeAll() }
    }

    @MainActor
    static func apply(to store: AppStore) {
        if let d = value("-trialDaysLeft"), let n = Int(d) {
            store.state.subscription.trialStart = Calendar.current.date(byAdding: .day, value: -(store.state.subscription.trialDays - n), to: Date()) ?? Date()
            store.state.subscription.active = false
        }
        let screen = value("-screen")
        if has("-noSplash") || (screen != nil && screen != "splash" && screen != "home") { DebugFlags.suppressSplash = true }
        if has("-skipLogin") || (screen != nil && screen != "login"), store.session == nil {
            let owner = store.state.company.inspectors.first { $0.owner }
            store.state.session = Session(name: owner?.name ?? "Jeremy Heath", email: owner?.email ?? "", inspectorID: owner?.id, isAdmin: true)
        }
        guard let screen else { return }

        let step = value("-step").flatMap(Int.init)
        let pick = value("-inspection") ?? "1428"
        guard let ridge = store.inspections.first(where: { $0.address.hasPrefix(pick) || $0.inspType == pick })
                ?? store.inspections.first else { return }
        let id = ridge.id
        if let d = value("-depth"), let depth = Depth(rawValue: d) { store.update(id, markDirty: false) { $0.depth = depth } }
        let depth = store.inspection(id)?.depth ?? .standard
        let section = value("-section") ?? (ridge.leafSections.contains("Roof") ? (depth == .high ? "Outside Utilities" : "Roof") : (ridge.leafSections.first ?? "Roof"))

        switch screen {
        case "login": store.state.session = nil
        case "signup": store.state.session = nil; store.path = [.signup]
        case "forgot": store.state.session = nil; store.path = [.forgot]
        case "join": store.state.session = nil; store.path = [.join]
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
