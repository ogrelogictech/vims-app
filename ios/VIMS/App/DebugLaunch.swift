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
    /// -scrubTo F: the PDF preview scrolls to fraction F (0…1) and holds the page scroller's dragged look.
    static var scrubTo: CGFloat?
    /// -markupZoom Z: the markup viewer opens zoomed to Z (review screenshots of the photo zoom).
    static var markupZoom: CGFloat?
    /// -scrollToItem Q: the section screen scrolls to the first checklist item with question Q.
    static var scrollToItem: String?
}

#if DEBUG
/// DEBUG-only screen jumper for review screenshots, e.g.
///   xcrun simctl launch "iPhone 17" com.vims.app -skipLogin -screen summary
/// Arguments:
///   -resetData                 wipe the SwiftData store + files and reseed the demo account
///   -video / -noVideo          force / skip the launch video (skipped by default with -screen)
///   -signInAs EMAIL            sign in as that local account
///   -ownerStatus               print OWNERTEST lines (signed-in master admin flag + owner matching for sample emails)
///   -pricingStatus             print PRICINGTEST lines (VIMS plans / yearly prices / company plan, period, total)
///   -checklistStatus           print CHECKLISTTEST lines (company edits, each inspection's kept sections + item counts)
///   -period monthly|yearly     with -screen subscribe: preselect the billing period
///   -plan ID                   with -screen subscribe: preselect a plan
///   -customSection "NAME|Group"  add a custom checklist section (as Manage checklist → Add section)
///   -confirmRestore NAME|all|picked|"A,B"  with -screen manage: open the restore confirmation (picked = every
///                              Edited / Added section, or the named ones, as Restore selected checklists confirms)
///   -teamAccount EMAIL         add a second local account (Sam Rivera / inspect2026) to the demo company
///   -eulaVersion V             pretend shared/legal/eula.json has version V (re-acceptance gate test)
///   -eulaGate                  show the EULA gate even with -screen / -skipLogin
///   -profilePhotoSample        set the signed-in user's profile photo from an inspection photo
///   -activeSub                 mark the signed-in company's subscription active (Square · Visa ····4242)
///   -subPeriod monthly|yearly  with -activeSub: the billing period (prints CANCELTEST: paid, days left, refund)
///   -subStartedDaysAgo N       with -activeSub: the subscription started N days ago (pro-rated refund checks)
///   -confirmCancel             with -screen billing: open the Cancel subscription confirmation
///   -pickRestore [-pickAll]    with -screen manage: open Restore selected checklists (all ticked)
///   -eulaStatus                print each local account's accepted EULA version to the console
///   -mailSelfTest              print the report email draft (to/CC/BCC/subject/attachment) + state-document drafts
///   -state XX                  set the chosen inspection's property state (OK summary disclosure, OR cover notice)
///   -cover "C|Cat|Opt|Style"   set the chosen inspection's report cover (e.g. "Blue|Holidays|4th of July|Shaded")
///   -wizState TX[,UT]          pick those states in order when the wizard opens (prints STATETEST lines)
///   -ackStateDocs              with -wizState: tick "Provided to the client with the inspection agreement"
///   -wizScroll ID              scroll wizard step 1 to a block (sendToAgent, agreementLine, State)
///   -ownAgreement NAME         use bundled NAME.pdf as the company's own uploaded agreement (same path as Upload your own)
///   -useVimsAgreement          revert the company to the VIMS agreement
///   -editedAgreement           give the company an edited copy of the VIMS agreement (same path as Edit → Save)
///   -agreementScroll disclosures  scroll the agreement viewer to the state disclosures (`card`: Company profile's agreement card)
///   -agreementStatus           print AGREEMENTTEST (bundled agreement loaded, state keys, own file, edited copy's form blocks)
///   -legacyEditedAgreement     an edited agreement saved before the form block was locked (form lines in its text)
///   -agreementState XX         with -screen agreement: open the viewer from the wizard for state XX (else from Company profile)
///   -landscape / -portrait     rotate the iPad simulator window (review screenshots; refused in iPadOS 26 windowed mode)
///   -openPicker                with -screen wizard: open the State picker
///   -openComment               with -screen markup: open the quick-comment list
///   -openPreview               with -screen reportReady / report: open the PDF preview
///   -scrubTo F                 with -openPreview: scroll the PDF to fraction F (0…1) and hold the page scroller's
///                              dragged look ("Page X of N" bubble) for review screenshots
///   -photoComment TEXT         with -screen markup / flag: the section's photos carry this saved comment
///                              (e.g. "<quick comment> — <custom>", split back into the two fields)
///   -sampleFindings            replace the chosen inspection's findings with the client's Oct 16 examples (+ one legacy)
///   -oct17 fill|blank          add Radon, Meth Test, Termite (WDI), Lead, Septic and Wind Mitigation (OIR-B1-1802) to the
///                              chosen inspection, marked done; `fill` answers them, `blank` leaves the two forms unopened
///                              (their prefill values print / fill in on first open). Prints OCT17TEST lines.
///   -companyName NAME          rename the signed-in company (Company profile name; report cover footer check)
///   -openShare                 with -screen reportReady: Email to client (share sheet without Mail);
///                              with -screen agreement: Download (agreement PDF share sheet)
///   -offlineFor N              the connection reads as offline for N seconds, then reconnects (auto-sync test)
///   -markQueued                mark every inspection as waiting to sync
///   -autoSync on|off           set Settings → "Auto-sync when online"
///   -methLegacy [TEXT]         with -oct17: Meth Test gets a pre-v1.9.1 "Test date and time" answer (+ AM/PM = PM)
///   -seedPlatform "FB|BCC"     store these platform Feedback / BCC addresses directly (as an older build would have;
///                              empty part = keep), bypassing the owner check — the v1.9.2 migration runs on the next launch
///   -platformStatus            print PLATFORMTEST lines (stored settings, what this launch migrated, owner list, session)
///   -validate                  submit the form once so its validation errors show
///   -skipLogin                 sign in as the demo owner
///   -noSplash                  don't show the free-look splash
///   -trialDaysLeft N           override the free-look days left (0 = trial ended → New inspection shows Subscribe)
///   -showerPan                 with -screen phase2: answer the Plumbing shower pan items and mark the section done
///   -staleOverride NAME        an admin edit of NAME saved before its "Shower pan" items (-legacyOverride: no baseItems)
///   -wizType TYPE              with -screen wizard / editWizard: the draft's Type of inspection (e.g. "Tests Only")
///   -resetDeviceTrial          clear the Keychain one-trial-per-device record (testers: the next Create account gets 30 days)
///   -deviceTrialStatus         print DEVICETRIAL lines (Keychain records, signed-in company trial, can start new inspection)
///   -screen NAME               login signup forgot join home splash wizard sections section drawer photos
///                              markup flag summary report reportReady settings company instructions manage
///                              editSection plans inspectors subscribe subscribed billing feedback phase1 phase2
///                              agreement agreementEditor
///   -step N                    wizard step (1–4)
///   -depth high|standard|fast  checklist depth for the demo inspection
///   -section NAME              section to open (default Roof / Outside Utilities for high)
///   -generate                  with -screen reportReady: regenerate the PDF first
///   -inspection PREFIX         inspection whose address starts with PREFIX, or whose type equals it (default 1428…)
///   -iaq fill|blank|legacy     add the Indoor Air Quality test to that inspection and mark it done: `fill` = the
///                              report.html sample readings, `blank` = no readings, `legacy` = pre-v1.7 choices
///                              ("Formaldehyde (HCHO)": "2" …) to exercise the rating migration, `overflow` = `fill`
///                              plus long High Detail Report Information text so the table breaks across pages
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
        // -resetData reseeds a fresh demo (its Keychain trial clock too); the device's own trial record stays.
        if has("-resetData") { SwiftDataRepository.wipeStore(); FileStore().wipeAll(); DeviceTrial.clearDemo() }
        // -resetDeviceTrial: forget this device's free-trial record (and the demo's), so the next Create account gets 30 days.
        if has("-resetDeviceTrial") { DeviceTrial.clear(); print("DEVICETRIAL cleared") }
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

    /// Client Oct 29 (data v1.12) checks on the chosen inspection:
    ///   -roomCounts "bathrooms=2,bedrooms=3"  set the wizard room counts and rebuild the section list
    ///   -addRooms "Garage,Attic,Kitchen"       add those interior rooms
    ///   -legacyCompressor V                    Outside Utilities answer saved under the old "Compressor size (sq ft)" key
    ///   -oct29Fill                             answer the new items (Water Pressure High, receptacle counts, Non GFCI) and
    ///                                          mark those sections done, so they print in the report
    ///   -oct29Status                           print OCT29TEST lines (options / pre-answers / migration / progress / report)
    @MainActor
    static func seedOct29(_ store: AppStore, _ id: UUID) {
        guard var insp = store.inspection(id) else { return }
        var rebuild = false
        if let rc = value("-roomCounts") {
            for pair in rc.split(separator: ",") {
                let kv = pair.split(separator: "=").map(String.init)
                if kv.count == 2, let n = Int(kv[1]) { insp.counts[kv[0]] = n }
            }
            rebuild = true
        }
        if let r = value("-addRooms") {
            for n in r.split(separator: ",").map(String.init) where !insp.rooms.contains(n) { insp.rooms.append(n) }
            rebuild = true
        }
        if rebuild { store.buildChecklist(from: insp) }
        let cat = { store.catalog(for: id) }
        if let v = value("-legacyCompressor"), let i = store.inspection(id) {
            let keyed = ItemKeys.keyed(cat().items("Outside Utilities", depth: .high).items)
            if let k = keyed.first(where: { $0.item.renamedFrom != nil }), let old = k.item.renamedFrom, let q = k.item.q,
               let r = k.id.range(of: "›" + q, options: .backwards) {
                let oldKey = k.id.replacingCharacters(in: r, with: "›" + old)
                var a = i.answers["Outside Utilities"] ?? store.defaultAnswers("Outside Utilities")
                a.text[k.id] = nil
                a.text[oldKey] = v
                store.update(id, markDirty: false) { $0.answers["Outside Utilities"] = a; $0.status["Outside Utilities"] = .done }
                print("OCT29TEST seeded legacy key=\(oldKey) value=\(v)")
            }
        }
        if has("-oct29Fill"), let i = store.inspection(id) {
            let fills: [String: [String: String]] = [
                "Exterior Walls": ["Water Pressure rating": "High"],
                "Garage": ["Receptacles": "Non GFCI", "GFCI receptacles (count)": "2", "Standard receptacles (count)": "6"],
                "Attic": ["Receptacles": "Non GFCI", "GFCI receptacles (count)": "1", "Standard receptacles (count)": "3"],
                "Kitchen": ["GFCI receptacles (count)": "5", "Standard receptacles (count)": "4"]
            ]
            for (sec, vals) in fills where i.leafSections.contains(sec) {
                var a = i.answers[sec] ?? store.defaultAnswers(sec)
                for k in ItemKeys.keyed(cat().items(sec, depth: i.depth).items) {
                    guard let q = k.item.q, let v = vals[q], !k.id.contains("#") else { continue }
                    if k.item.kind == .num { a.text[k.id] = v } else { a.choices[k.id] = [v] }
                }
                store.update(id, markDirty: false) { $0.answers[sec] = a; $0.status[sec] = .done }
            }
        }
        guard has("-oct29Status"), let i = store.inspection(id) else { return }
        print("OCT29TEST insp=\(i.addressLine1) depth=\(i.depth.rawValue) counts=\(i.counts.sorted { $0.key < $1.key }) leaves=\(i.leafSections.filter { $0.hasPrefix("Bath") || $0.hasPrefix("Bed") || ["Garage", "Attic", "Kitchen"].contains($0) })")
        for sec in i.leafSections where sec.hasPrefix("Bathroom") || sec.hasPrefix("Bedroom") {
            let first = cat().items(sec, depth: i.depth).items.first
            print("OCT29TEST \(sec) item=\(first?.q ?? "-") options=\(first?.options ?? []) preAnswer=\(store.roomNumberDefaults(i, sec)) status=\(i.status[sec].map { "\($0)" } ?? "nil")")
        }
        // The pre-answer alone doesn't make a section In progress; a real answer does.
        if let sec = i.leafSections.first(where: { $0.hasPrefix("Bathroom ") }) {
            let pre = store.prefilled(store.answers(id, sec), id, sec)
            var touched = pre; touched.comments = "x"
            print("OCT29TEST progress \(sec) prefilled=\(pre.choices) entered=\(store.hasEnteredContent(i, sec, pre)) withComment=\(store.hasEnteredContent(i, sec, touched))")
        }
        if let a = i.answers["Outside Utilities"] {
            let keyed = ItemKeys.keyed(cat().items("Outside Utilities", depth: .high).items)
            let m = a.migratingLegacy(keyed)
            print("OCT29TEST compressor migrated=\(m.text.filter { $0.key.contains("Compressor size") })")
        }
        for (sec, qs) in [("Exterior Walls", ["Water Pressure rating"]), ("Outside Utilities", ["Compressor size (home sq ft)"]),
                          ("Garage", ["Receptacles", "GFCI receptacles (count)", "Standard receptacles (count)"]),
                          ("Attic", ["Receptacles", "GFCI receptacles (count)", "Standard receptacles (count)"]),
                          ("Kitchen", ["GFCI receptacles (count)", "Standard receptacles (count)"])] {
            let items = cat().items(sec, depth: .high).items
            print("OCT29TEST \(sec): " + qs.map { q in "\(q)=\(items.first { $0.q == q }.map { $0.options ?? ["num integer=\($0.integer ?? false)"] } ?? ["MISSING"])" }.joined(separator: " | "))
        }
        let data = ReportData.make(i, config: store.config, overrides: store.catalog(for: i).overrides, company: store.company,
                                   repo: store.files, logo: nil)
        for s in data.sections where ["Exterior Walls", "Outside Utilities", "Garage", "Attic", "Kitchen"].contains(s.name) || s.name.hasPrefix("Bathroom") || s.name.hasPrefix("Bedroom") {
            let lines = s.rows.compactMap { r -> String? in
                if case .line(let q, let v) = r.kind, q.contains("Water Pressure") || q.contains("Compressor size") || q.contains("eceptacles") || q.hasSuffix(" No.") { return "\(q)=\(v)" }
                return nil
            }
            print("OCT29TEST report \(s.name): \(lines)")
        }
    }

    /// -iaq: Indoor Air Quality on the chosen inspection (report table / migration checks).
    @MainActor
    static func seedAirQuality(_ store: AppStore, _ id: UUID, mode: String) {
        let name = "Indoor Air Quality"
        guard var insp = store.inspection(id) else { return }
        if !insp.tests.contains(name) { insp.tests.append(name); store.buildChecklist(from: insp) }
        guard let depth = store.inspection(id)?.depth else { return }
        let keyed = ItemKeys.keyed(store.catalog.items(name, depth: depth).items)
        var a = store.defaultAnswers(name)
        let sample: [String: (String, String)] = ["HCHO": ("0.03", "2"), "TVOC": ("0.21", "2"), "PM2.5": ("8", "1"),
                                                  "PM10": ("22", "2"), "CO2": ("610", "3"), "Ozone": ("0.02", "1"), "CO": ("0", "1")]
        switch mode {
        case "fill", "overflow":
            for k in keyed {
                if k.item.kind == .airReading, let v = sample[k.item.code ?? ""] { a.text[k.id] = v.0; a.choices[k.id] = [v.1] }
                // Data v1.7.1: Date / Time are `date` / `time` items (stored like the wizard: yyyy-MM-dd, HH:mm).
                if k.item.kind == .date { a.text[k.id] = Fmt.date(Date(), "yyyy-MM-dd") }
                if k.item.kind == .time { a.text[k.id] = "10:15" }
                if k.item.kind == .text {
                    a.text[k.id] = ["Client name": insp.clientName, "Date": Fmt.date(Date(), "MMMM d, yyyy"), "Time": "10:15 AM",
                                    "Property address": insp.addressLine1][k.item.q ?? ""]
                    if mode == "overflow", k.item.q == "Property address" {
                        a.text[k.id] = Array(repeating: "\(insp.addressLine1) — readings taken on the main floor, basement and the finished attic room.", count: 9).joined(separator: " ")
                    }
                }
            }
        case "legacy":
            // Standard keys before v1.7 (no header) with the old "1 Good" style options.
            for (q, v) in [("Formaldehyde (HCHO)", "2"), ("TVOC", "2"), ("PM2.5", "1 Good"), ("PM10", "2"), ("CO2", "3 Mild"), ("CO", "1 Good")] {
                a.choices["›\(q)"] = [v]
            }
        default: break
        }
        a.comments = mode != "blank" && mode != "legacy" ? "Readings taken in the main living area with the meter at breathing height." : ""
        let answers = a
        store.update(id, markDirty: false) { $0.answers[name] = answers; $0.status[name] = .done }
        print("IAQTEST mode=\(mode) depth=\(depth.rawValue) readings=\(keyed.filter { $0.item.kind == .airReading }.count)")
    }

    /// -oct17 fill|blank: adds Lead, Meth Test, Radon, Septic, Termite (WDI) and Wind Mitigation (OIR-B1-1802) to the
    /// chosen inspection and marks them done — `fill` answers them like an inspector would (Lead 3 samples with locations,
    /// Meth "Other" area, a Radon level, every Wind Mitigation question, a WDI with findings B), `blank` leaves only the
    /// prefill values (Wind Mitigation never opened). Prints OCT17TEST lines.
    @MainActor
    static func seedOct17(_ store: AppStore, _ id: UUID, mode: String) {
        let names = ["Radon", "Meth Test", "Termite", "Lead", "Septic", "Wind Mitigation"]
        guard var insp = store.inspection(id) else { return }
        let missing = names.filter { !insp.tests.contains($0) }
        if !missing.isEmpty { insp.tests += missing; store.buildChecklist(from: insp) }
        let fill = mode == "fill"
        let values: [String: [String: [String]]] = [
            "Radon": ["Test performed": ["Yes"], "Measured level (pCi/L)": ["2.7"]],
            "Meth Test": ["Test performed": ["Yes"], "Area tested": ["Kitchen", "Other"], "Other area tested": ["Hall closet behind the water heater"]],
            "Lead": ["Test performed": ["Yes"], "Samples taken": ["3"], "Sample 1 location": ["Kitchen window sill"],
                     "Sample 2 location": ["Front door trim"], "Sample 3 location": ["Basement stair rail"], "Sample 4 location": ["(hidden — not printed)"]],
            "Septic": ["System type": ["Conventional"], "Tank material": ["Concrete"]],
            "Termite": ["Company business license no.": ["UT-PC-20931"], "Structure(s) inspected": ["House and detached garage"],
                        "Findings": ["B. Visible evidence of wood destroying insects was observed as follows:"],
                        "1. Live insects (description and location)": ["Subterranean termites in the NE crawlspace sill plate"],
                        "2. Dead insects, insect parts, frass, shelter tubes, exit holes, or staining (description and location)": ["Shelter tubes on the north foundation wall"],
                        "3. Visible damage from wood destroying insects (description and location)": ["Damaged sill plate, about 4 ft, NE corner"],
                        "Structure(s) appear to have been previously treated": ["Yes"],
                        "Visible evidence of possible previous treatment": ["Drill holes in the garage slab"],
                        "Recommendation": ["Recommend treatment"], "Recommend treatment for the control of": ["Subterranean termites"],
                        "Crawlspace — obstructed or inaccessible": ["Stored items along the east wall"], "Attic — obstructed or inaccessible": ["Insulation over the ceiling joists"],
                        "Additional comments": ["Wood-to-soil contact at the rear deck posts."], "Attachments": ["Photos (5)"]],
            "Wind Mitigation": ["Contact person": ["Tysen Gough"], "County": ["Weber"], "Insurance company": ["Citizens Property Insurance"],
                                "Policy #": ["CPI-4471-22"], "Year of home": ["2004"], "# of stories": ["2"],
                                "Building code": ["A. Built in compliance with the FBC"], "Year built": ["2004"], "Building permit application date (FBC)": ["2003-05-14"],
                                "Roof covering types in use": ["Asphalt/Fiberglass Shingle", "Metal"],
                                "Asphalt/Fiberglass Shingle: permit application date": ["2018-06-02"], "Asphalt/Fiberglass Shingle: FBC or MDC product approval #": ["FL10124-R23"],
                                "Asphalt/Fiberglass Shingle: year of original installation or replacement": ["2018"],
                                "Metal: year of original installation or replacement": ["2004"], "Metal: no information provided for compliance": ["Yes"],
                                "Roof covering compliance": ["C. One or more do not meet A or B"],
                                "Roof deck attachment": ["B. Plywood/OSB min 7/16\" by 8d common nails max 12\" in the field, or equivalent (≥103 psf)"],
                                "Roof to wall attachment": ["B. Clips"],
                                "Minimal conditions for B, C or D (all visible metal connectors are)": ["Secured to truss/rafter with a minimum of three (3) nails"],
                                "Clips — type": ["Metal connectors with a minimum of 1 strap that wraps over the top, secured with a minimum of 3 nails"],
                                "Roof geometry": ["A. Hip roof"], "Total length of non-hip features (feet)": ["18"], "Total roof system perimeter (feet)": ["212"],
                                "Secondary water resistance": ["B. No SWR"],
                                "Windows or entry doors (glazed)": ["B"], "Garage doors (glazed)": ["N/A"], "Skylights": ["N/A"], "Glass block": ["N/A"],
                                "Entry doors (non-glazed)": ["D"], "Garage doors (non-glazed)": ["A"], "Opening protection (weakest)": ["B.2"],
                                "I hold an active license as a": ["Home inspector licensed under Section 468.8314, F.S., with hurricane mitigation training and proficiency exam"]]
        ]
        for name in names {
            let keyed = ItemKeys.keyed(store.catalog.items(name, depth: store.catalog.isForm(name) ? .standard : (store.inspection(id)?.depth ?? .standard)).items)
            var a = store.prefilled(store.defaultAnswers(name), id, name)
            if fill || !store.catalog.isForm(name) {
                for k in keyed {
                    guard let v = values[name]?[k.item.q ?? ""] else { continue }
                    switch k.item.kind {
                    case .single, .multi: a.choices[k.id] = v
                    default: a.text[k.id] = v.first
                    }
                }
            }
            // -methLegacy: a pre-v1.9.1 Meth answer ("Test date and time" typed + AM/PM chips) to exercise the migration
            // onto the Test date / Test time pickers.
            if name == "Meth Test", has("-methLegacy") {
                a.text["Meth Testing Report›Test date and time"] = value("-methLegacy").flatMap { $0.hasPrefix("-") ? nil : $0 } ?? "10/20/2026 2:30"
                a.choices["Meth Testing Report›AM/PM"] = ["PM"]
            }
            let answers = a
            // blank: a form section is left never opened (no answers) — the report prints its prefill values and opening
            // it fills them in.
            let neverOpened = !fill && store.catalog.isForm(name)
            store.update(id, markDirty: false) { $0.answers[name] = neverOpened ? nil : answers; $0.status[name] = .done }
            // fill: the form sections get a photo too (their pictures page prints right after the form).
            if fill, store.catalog.isForm(name), let cat = store.catalog.photoCategories(name, depth: .standard).first,
               let sample = store.inspection(id)?.photos.values.flatMap({ $0.values.flatMap { $0 } }).first {
                var ref = sample
                ref.id = UUID(); ref.flag = nil; ref.comment = "Sample photo for the \(store.catalog.title(name)) pictures page"
                let photo = ref
                store.update(id, markDirty: false) { $0.photos[name, default: [:]][cat] = [photo] }
            }
            let shown = ItemVisibility.visible(keyed, answers: answers).count
            print("OCT17TEST \(name) title=\(store.catalog.title(name)) items=\(keyed.count) visible=\(shown) form=\(store.catalog.formReport(name) ?? "-") note=\(store.catalog.reportNote(name).count)")
        }
    }

    /// -sampleFindings: replace the chosen inspection's findings with the client's Oct 16 examples, added through
    /// `addFinding` like the Flag a finding / Concern / photo sheets, plus one pre-Oct 16 finding (text only).
    @MainActor
    static func seedOct16Findings(_ store: AppStore, _ id: UUID) {
        store.update(id, markDirty: false) { $0.findings = [] }
        let q = store.config.findings.quickComments
        store.addFinding(id, category: 1, custom: "", quick: q[3], section: "Landscaping")
        store.addFinding(id, category: 1, custom: "lets see how this attaches to the summary", quick: nil, section: "Exterior Walls")
        // photo flag carried over as "quick — custom": the quick copy is dropped from the custom part
        store.addFinding(id, category: 1, custom: "\(q[1]) — insulation is dry and cracking and falling off the coolant line", quick: q[1], section: "Outside Utilities")
        store.addFinding(id, category: 2, custom: "water is leaking from the bottom of the swamp cooler I recommend adjusting the float to better control water levels in the pan",
                         quick: q[4], section: "Outside Utilities")
        store.addFinding(id, category: 2, custom: "loose at the northeast corner", quick: q[6], section: "Roof", item: "Gutters")
        store.addFinding(id, category: 3, custom: "", quick: q[6], section: "Roof", item: "Flashing")
        store.update(id, markDirty: false) {
            $0.findings.append(Finding(category: 3, text: "Minor settling crack in the garage slab — monitor.", section: "Garage"))
        }
        for f in store.inspection(id)?.findings ?? [] { print("FINDINGTEST cat=\(f.category) \(f.section) | custom=\(f.custom ?? "nil") | quick=\(f.quick ?? "nil") | line=\(f.section) — \(f.detail)") }
    }

    @MainActor
    static func apply(to store: AppStore) {
        let screen = value("-screen")
        // The launch video only plays on a plain launch (or with -video).
        if (screen != nil || has("-skipLogin") || has("-noVideo")) && !has("-video") { store.showVideoSplash = false }
        // -teamAccount EMAIL: a second account (Sam Rivera, password inspect2026) on the demo company, as if they joined
        // with the company code (ownership-transfer checks: transfer, then -signInAs EMAIL to transfer back).
        if let email = value("-teamAccount")?.lowercased(), store.repo.user(email: email) == nil,
           let demo = store.repo.user(email: DemoSeed.loginEmail), var c = store.repo.company(id: demo.companyID) {
            let salt = PasswordHasher.newSalt()
            let u = UserAccount(id: UUID(), email: email, name: "Sam Rivera", companyID: demo.companyID,
                                passwordHash: PasswordHasher.hash(DemoSeed.loginPassword, salt: salt), salt: salt, createdAt: Date(),
                                settings: nil, eulaVersion: store.eula.version, eulaAcceptedAt: Date())
            if (try? store.repo.insertUser(u)) != nil {
                c.profile.inspectors.removeAll { $0.email.caseInsensitiveCompare(email) == .orderedSame }
                c.profile.inspectors.append(Inspector(id: u.id, name: u.name, email: u.email))
                store.repo.saveCompany(c)
            }
        }
        if let email = value("-signInAs"), let u = store.repo.user(email: PlatformOwner.normalized(email)) { store.loadSession(u) }
        if has("-ownerStatus") {
            print("OWNERTEST session=\(store.session?.email ?? "none") isPlatformOwner=\(store.isPlatformOwner) isAdmin=\(store.isAdmin) company=\(store.company.name)")
            for e in [" Masteradmin@VIMSInspect.com ", "ADMIN@vimsinspect.com", "masteradmin@vimsinspection.com", "jeremy@visionpropertyinspections.com"] {
                print("OWNERTEST isOwner(\"\(e)\")=\(PlatformOwner.isOwner(email: e, config: store.config))")
            }
        }
        if has("-pricingStatus") {
            let p = store.pricing, sub = store.subscription
            print("PRICINGTEST stored=\(store.platform.plans != nil) plans=" + p.plans.map { "\($0.id):\($0.price)/\($0.priceYearly.map { String($0) } ?? "-")\($0.isComingSoon ? ":soon" : "")" }.joined(separator: ",")
                  + " extra=\(p.extraMonthly)/\(p.extraYearly)")
            print("PRICINGTEST company=\(store.company.name) selected=\(sub.selectedPlan) period=\(sub.period.rawValue) active=\(sub.active) total=\(sub.totalLabel(seats: store.seats())) next=\(Fmt.date(sub.nextBillingDate, "MMM d, yyyy")) companyPlans=" + sub.plans.map { "\($0.id):\($0.price)" }.joined(separator: ","))
        }
        // -customSection "NAME|Group": add a custom section the way Manage checklist → Add section does (restore checks).
        if let v = value("-customSection"), store.session != nil {
            let p = v.split(separator: "|").map(String.init)
            _ = store.addCustomSection(name: p[0], group: p.count > 1 ? p[1] : "Exterior")
        }
        if has("-checklistStatus") {
            let o = store.state.overrides
            print("CHECKLISTTEST company=\(store.company.name) edited=\(o.sections.keys.filter { store.isEditedSection($0) }.sorted()) custom=\(o.custom.filter { !$0.value.isEmpty })")
            for i in store.inspections {
                let cat = store.catalog(for: i)
                let watch = i.leafSections.filter { ["Chimney", "Roof"].contains($0) || store.isCustomSection($0) || i.savedSections?[$0] != nil }
                print("CHECKLISTTEST insp=\(i.addressLine1) saved=\((i.savedSections ?? [:]).keys.sorted()) " + watch.map { "\($0)=\(cat.items($0, depth: .standard).items.filter { !$0.isHeader }.count)" }.joined(separator: " "))
            }
            for n in ["Chimney", "Roof", "Solar Panels"] { print("CHECKLISTTEST new-inspection \(n)=\(store.catalog.section(n)?.items.filter { !$0.isHeader }.count ?? -1)") }
        }
        if has("-platformStatus") {
            let p = store.platform
            print("PLATFORMTEST stored feedback=\(p.feedbackEmail) bccOn=\(p.reportBccOn) bcc=\(p.reportBccEmail) migratedThisLaunch=\(store.platformMigrated)")
            print("PLATFORMTEST config feedback=\(store.config.support.feedbackEmail) bcc=\(store.config.support.reportBcc?.email ?? "-") replaced=\(store.config.support.replacedDefaults.map { "\($0.feedbackEmail ?? []) / \($0.reportBccEmail ?? [])" } ?? "-") domainEmails=\(store.config.support.domainEmails?.count ?? 0)")
            print("PLATFORMTEST owners=\(PlatformOwner.emails(store.config)) supportEmail=\(store.supportEmail) session=\(store.session?.email ?? "none") isPlatformOwner=\(store.isPlatformOwner)")
        }
        if let v = value("-seedPlatform") {
            let parts = v.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            var p = store.repo.platformSettings() ?? store.platform
            if let fb = parts.first, !fb.isEmpty { p.feedbackEmail = fb }
            if parts.count > 1, !parts[1].isEmpty { p.reportBccEmail = parts[1] }
            store.repo.savePlatformSettings(p)
            print("PLATFORMTEST seeded feedback=\(p.feedbackEmail) bcc=\(p.reportBccEmail) (applies after relaunch)")
        }
        // -offlineFor N: the connection reads as offline for N seconds, then comes back (auto-sync on reconnect test);
        // -markQueued: every inspection starts queued (needs sync); -autoSync on|off: the Settings switch.
        if let v = value("-autoSync") { store.state.settings.autoSync = v != "off" }
        if has("-markQueued") { for i in store.inspections { store.update(i.id) { _ in } } }
        if let s = value("-offlineFor"), let n = Double(s) {
            store.debugOfflineUntil = Date().addingTimeInterval(n)
            store.setOnline(false)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(n * 1_000_000_000) + 50_000_000)
                print("AUTOSYNC back online, queued=\(store.pendingSyncCount)")
                store.setOnline(true)
            }
        }
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
            store.state.subscription.cardOnFile = CardOnFile(brand: "Visa", last4: "4242", expMonth: 8, expYear: 2028)
            store.state.subscription.startedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
            store.state.subscription.cancelledAt = nil
            store.state.subscription.endedAt = nil
            store.state.subscription.refundAmount = nil
            store.state.subscription.refundDays = nil
            // -subPeriod monthly|yearly, -subStartedDaysAgo N: the period and start date (yearly cancel / refund checks).
            if let p = value("-subPeriod") { store.state.subscription.billingPeriod = p }
            if let d = value("-subStartedDaysAgo"), let n = Int(d) {
                store.state.subscription.startedAt = Calendar.current.date(byAdding: .day, value: -n, to: Date())
            }
            store.state.subscription.paidAmount = store.state.subscription.total(seats: store.seats())
            let sub = store.state.subscription, r = sub.proratedRefund(seats: store.seats())
            print("CANCELTEST period=\(sub.period.rawValue) paid=\(r.paid) daysLeft=\(r.daysLeft) daysInPeriod=\(r.daysInPeriod) refund=\(r.amount) next=\(Fmt.date(sub.nextBillingDate, "MMM d, yyyy"))")
        }
        // -companyName NAME: rename the signed-in company, as Company profile → Company name → Save does.
        if let n = value("-companyName"), store.session != nil { store.state.company.name = n }
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
        // -editedAgreement: give the company an edited copy (title changed) through the same save as the editor.
        // Stored as the block editor saves it (JSON blocks): title changed, the second body paragraph deleted, a
        // paragraph added after the disclosures heading.
        if has("-editedAgreement"), store.session != nil, let doc = InspectionAgreement.bundled {
            var blocks = AgreementContent.vims(doc, company: store.company.name, stateCode: nil, stateName: { store.config.stateName($0) ?? $0 }).blocks
            if let i = blocks.firstIndex(where: { if case .title = $0 { return true } else { return false } }) { blocks[i] = .title("Home Inspection Agreement") }
            if let i = blocks.firstIndex(where: { $0.editableText?.hasPrefix("Please read and sign") == true }) { blocks.remove(at: i) }
            if let i = blocks.firstIndex(where: { if case .heading = $0 { return true } else { return false } }) {
                blocks.insert(.paragraph("Disclosures below apply only to inspections in the listed state.", lead: false), at: i + 1)
            }
            store.saveEditedAgreement(EditedAgreement(blocks: blocks).encoded)
        }
        // -legacyEditedAgreement: an edit saved before the form block was locked (form lines in the text, one field
        // name deleted) — the viewer / PDF / editor must show the locked block once.
        if has("-legacyEditedAgreement"), store.session != nil, let doc = InspectionAgreement.bundled {
            var full = AgreementContent.vims(doc, company: store.company.name, stateCode: nil, stateName: { store.config.stateName($0) ?? $0 }).plainText
            full = full.replacingOccurrences(of: "Clients Name ________________________", with: "________________________")
            store.state.company.agreementText = full.replacingOccurrences(of: "Inspection Agreement\n", with: "Home Inspection Agreement\n", options: .anchored)
            print("AGREEMENTTEST legacy edited chars=\(full.count) stripped=\(AgreementContent.strippingFormLines(full, formLines: store.agreementFormLines).count)")
        }
        if let n = value("-ownAgreement"), store.session != nil {
            if let u = Bundle.main.url(forResource: n, withExtension: "pdf") { store.saveAgreement(from: u) }
            else { print("AGREEMENTTEST missing bundled \(n).pdf") }
        }
        if has("-agreementStatus") {
            let a = InspectionAgreement.bundled
            print("AGREEMENTTEST loaded=\(a != nil) version=\(a?.version ?? "-") states=\(a?.disclosureStates.joined(separator: ",") ?? "-") own=\(store.company.agreementName ?? "none") file=\(store.ownAgreementURL?.lastPathComponent ?? "none")")
            if let e = store.editedAgreementContent {
                let forms = e.blocks.filter { if case .form = $0 { return true } else { return false } }
                let formLines = Set(store.agreementFormLines)
                let leaked = e.blocks.filter { if case .paragraph(let t, _) = $0 { return t.components(separatedBy: "\n").contains { formLines.contains($0) } } else { return false } }.count
                print("AGREEMENTTEST edited title=\(e.title) formBlocks=\(forms.count) formLinesMatch=\(e.formLines == store.agreementFormLines) leakedFormParagraphs=\(leaked) blocks=\(e.blocks.count) stored=\(EditedAgreement.decode(store.company.agreementText ?? "") != nil ? "blocks" : "plain") pdfPages=\(AgreementPDF.render(e, company: store.company.name).pageCount)")
                print("AGREEMENTTEST first blocks: " + e.blocks.prefix(4).map { b -> String in
                    switch b { case .title(let t): return "title(\(t))"; case .form: return "form"; default: return "p(\(String((b.editableText ?? "").prefix(30))))" }
                }.joined(separator: " | "))
            }
        }
        // -staleOverride NAME [-legacyOverride]: an admin edit of NAME saved before the JSON gained its "Shower pan" items
        // (with baseItems = what the JSON had then; -legacyOverride: no baseItems, as saved before data v1.10). Prints
        // CHECKLISTTEST with the items new inspections get.
        if let n = value("-staleOverride"), store.session != nil, var d = store.config.sections.first(where: { $0.name == n }) {
            d.items.removeAll { ($0.q ?? "").hasPrefix("Shower pan") }
            d.baseItems = has("-legacyOverride") ? nil : (d.items + (d.itemsHigh ?? [])).map(\.editKey)
            store.state.overrides.sections[n] = d
            let items = store.catalog.items(n, depth: .standard).items.compactMap(\.q)
            print("CHECKLISTTEST override=\(n) legacy=\(has("-legacyOverride")) items=\(items.count) last3=\(items.suffix(3))")
        }
        // -oldCompressorEdit: a company edit of Outside Utilities saved before data v1.12, with the old
        // "Compressor size (sq ft)" label (and baseItems naming it) — the catalog renames it; prints OCT29TEST.
        if has("-oldCompressorEdit"), store.session != nil, var d = store.config.sections.first(where: { $0.name == "Outside Utilities" }) {
            let rename = { (list: [ItemDef]) in list.map { it -> ItemDef in
                var r = it
                if let old = it.renamedFrom { r.q = old; r.renamedFrom = nil }
                return r
            } }
            d.items = rename(d.items); d.itemsHigh = d.itemsHigh.map(rename)
            d.baseItems = (d.items + (d.itemsHigh ?? [])).map(\.editKey)
            store.state.overrides.sections[d.name] = d
            let qs = store.catalog.items(d.name, depth: .high).items.compactMap(\.q).filter { $0.hasPrefix("Compressor size") }
            print("OCT29TEST companyEdit compressorItems=\(qs)")
        }
        if has("-deviceTrialStatus") {
            let f = ISO8601DateFormatter()
            print("DEVICETRIAL firstTrialStart=\(DeviceTrial.date(.firstTrialStart).map(f.string) ?? "none") demoTrialStart=\(DeviceTrial.date(.demoTrialStart).map(f.string) ?? "none")")
            let sub = store.subscription
            print("DEVICETRIAL session=\(store.session?.email ?? "none") company=\(store.company.name) trialStart=\(f.string(from: sub.trialStart)) daysLeft=\(sub.trialDaysLeft) active=\(sub.active) deviceTrialUsed=\(sub.deviceTrialUsed ?? false) trialEnded=\(sub.trialEnded) canStartNewInspection=\(store.canStartNewInspection) exempt=\(store.isSubscriptionExempt)")
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
        if let f = value("-scrubTo").flatMap(Double.init) { DebugFlags.scrubTo = CGFloat(f) }
        if let z = value("-markupZoom").flatMap(Double.init) { DebugFlags.markupZoom = CGFloat(z) }
        if let q = value("-scrollToItem") { DebugFlags.scrollToItem = q }
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
        // A retired type (data v1.10, "Code") works too: it stands in for an inspection saved before the type was retired.
        if store.config.wizard.inspectionTypes.contains(pick) || store.config.wizard.isRetired(pick),
           !store.inspections.contains(where: { $0.inspType == pick }) {
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
        // -cover "Color|Category|Option|Style": the report cover on that inspection (PDF cover checks).
        if let cv = value("-cover") {
            let p = cv.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if p.count == 4 { store.update(id, markDirty: false) { $0.cover = CoverChoice(color: p[0], category: p[1], option: p[2], style: p[3]) } }
        }
        if let d = value("-depth"), let depth = Depth(rawValue: d) { store.update(id, markDirty: false) { $0.depth = depth } }
        if let mode = value("-iaq") { seedAirQuality(store, id, mode: mode) }
        if has("-sampleFindings") { seedOct16Findings(store, id) }
        if let mode = value("-oct17") { seedOct17(store, id, mode: mode) }
        seedOct29(store, id)
        let depth = store.inspection(id)?.depth ?? .standard
        let section = value("-section") ?? (ridge.leafSections.contains("Roof") ? (depth == .high ? "Outside Utilities" : "Roof") : (ridge.leafSections.first ?? "Roof"))

        // -photoComment TEXT: that section's photos carry this saved comment (markup / flag prefill checks).
        if let pc = value("-photoComment") {
            store.update(id, markDirty: false) { insp in
                for (c, arr) in insp.photos[section] ?? [:] { for i in arr.indices { insp.photos[section]?[c]?[i].comment = pc } }
            }
        }

        switch screen {
        case "login": break
        case "signup": store.path = [.signup]
        case "forgot": store.path = [.forgot]
        case "join": store.path = [.join]
        case "menu": break
        case "home": break
        case "splash": DebugFlags.suppressSplash = false; store.showSplash = true
        case "wizard": DebugFlags.wizardStep = step; store.path = [.wizard(editing: nil)]
        case "editWizard": DebugFlags.wizardStep = step; store.path = [.sections(id), .wizard(editing: id)]
        case "sections": store.path = [.sections(id)]
        case "section": store.path = [.sections(id), .section(id, section)]
        case "drawer": DebugFlags.openDrawer = true; store.path = [.sections(id), .section(id, section)]
        case "photos": store.path = store.catalog.isPhotosOnly(section) ? [.sections(id), .photos(id, section)] : [.sections(id), .section(id, section), .photos(id, section)]
        case "markup": DebugFlags.openMarkup = true; store.path = [.sections(id), .section(id, section), .photos(id, section)]
        case "flag": DebugFlags.openMarkup = true; DebugFlags.openFlag = true; store.path = [.sections(id), .section(id, section), .photos(id, section)]
        case "summary": store.path = [.sections(id), .summary(id)]
        case "report": store.path = [.sections(id), .summary(id), .report(id)]
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
            // -depth: the phase inspection's checklist depth (shower pan items at High Detail / Standard / Fast).
            if let d = value("-depth"), let depth = Depth(rawValue: d) { store.update(pid, markDirty: false) { $0.depth = depth } }
            // -showerPan: answer Phase 2 — Plumbing's shower pan items (Yes / No) and mark it done (PDF check).
            if has("-showerPan"), let insp = store.inspection(pid), let sec = insp.leafSections.first(where: { $0.hasSuffix("Plumbing") }) {
                var a = store.defaultAnswers(sec)
                for k in ItemKeys.keyed(store.catalog.items(sec, depth: insp.depth).items) where (k.item.q ?? "").hasPrefix("Shower pan") {
                    a.choices[k.id] = [(k.item.q ?? "").hasSuffix("testing") ? "Yes" : "No"]
                    if insp.depth == .fast { a.present.append(k.item.q ?? "") }     // Fast Entry: "Items reviewed" chips
                }
                let answers = a
                store.update(pid, markDirty: false) { $0.answers[sec] = answers; $0.status[sec] = .done }
                print("SHOWERPANTEST depth=\(insp.depth.rawValue) answered=\(answers.choices.keys.sorted())")
            }
            // -section NAME: open that phase section (full name or its end, e.g. "Plumbing") instead of the first.
            let leaves = store.inspection(pid)?.leafSections ?? []
            let first = value("-section").flatMap { n in leaves.first { $0 == n || $0.hasSuffix(n) } } ?? leaves.first ?? ""
            store.path = has("-overview") ? [.sections(pid)] : [.sections(pid), .section(pid, first)]
        default: break
        }
    }
}
#endif
