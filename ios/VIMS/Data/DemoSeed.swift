import UIKit

// ============================================================================
// DEMO SEED — sample data equivalent to the approved prototype, created on first
// launch so the client can review the app with realistic content.
//
// To ship without demo data: make `DemoSeed.enabled` false (a clean company
// profile is created instead), or delete this file and replace the call in
// AppStore.init with `DemoSeed.emptyState(config:)`.
// ============================================================================

enum DemoSeed {
    static let enabled = true

    /// Prefilled on the sign-in screen for review convenience (prototype screen 01).
    static let loginEmail = enabled ? "jeremy@visionpropertyinspections.com" : ""
    static let loginPassword = enabled ? "inspect2026" : ""

    static func make(config: ChecklistConfig, repo: FileRepository) -> (state: AppState, inspections: [Inspection]) {
        guard enabled else { return (emptyState(config: config), []) }
        var state = emptyState(config: config)
        let sample = config.sample
        state.company.name = sample.company.name
        state.company.joinCode = sample.company.code
        state.company.address = "2029 N Main St Suite 103, Sunset, UT 84015"
        state.company.inspectorName = "Jeremy K. Heath"
        state.company.email = "VisionPropertyInspections@Gmail.com"
        state.company.license = "UT-12345"
        state.company.phone = "(801) 555-0134"
        state.company.inspectors = sample.inspectors.map { Inspector(name: $0.name, email: $0.email, owner: $0.owner ?? false, admin: $0.owner ?? false) }
        // Trial: 10 days left, so the urgent free-look splash shows (prototype state).
        state.subscription.trialStart = Calendar.current.date(byAdding: .day, value: -(config.subscription.trialDays - 10), to: Date()) ?? Date()
        state.seededAt = Date()

        let cat = ChecklistCatalog(config: config, overrides: state.overrides)
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today

        func base(_ address: String, client: String, date: Date, time: String, structure: String) -> Inspection {
            let w = config.wizard, d = w.defaults
            var fields: [String: String] = [:]
            for e in w.step1 + w.step2 where e.kind == "chips" {
                if let def = e.default, e.id != "wdepth" { fields[e.label] = def }
            }
            fields["Client name"] = client
            fields["Inspection address"] = address
            fields["Date"] = Fmt.date(date, "yyyy-MM-dd")
            fields["Time"] = time
            fields["Inspector"] = "Jeremy K. Heath"
            fields[Inspection.licenseField] = "UT-12345"
            var i = Inspection(
                fields: fields, inspType: d.inspType, structure: structure, depth: .standard,
                exterior: w.exteriorOptions.filter { (d.exterior[$0] ?? 0) > 0 },
                rooms: w.roomOptions.filter { (d.rooms[$0] ?? 0) > 0 },
                utilities: w.utilityOptions.filter { (d.utilOpt[$0] ?? 0) > 0 },
                tests: w.testOptions.filter { (d.tests[$0] ?? 0) > 0 },
                counts: ["bedrooms": d.bedrooms, "bathrooms": d.bathrooms, "hallways": d.hallways],
                cover: state.settings.defaultCover)
            if let fx = config.wizard.structureSideEffects[structure]?["exterior"], !i.exterior.contains(fx) { i.exterior.append(fx) }
            return i
        }

        func build(_ i: inout Inspection) {
            i.groups = cat.buildGroups(for: i)
            for n in i.leafSections where i.status[n] == nil { i.status[n] = .todo }
        }

        func answer(_ i: inout Inspection, _ section: String, variant: Int) {
            var a = SectionAnswers(overall: config.overallConditionDefault)
            for (idx, k) in ItemKeys.keyed(cat.items(section, depth: i.depth).items).enumerated() {
                switch k.item.kind {
                case .single:
                    let opts = k.item.options ?? []
                    guard !opts.isEmpty else { continue }
                    if opts.contains("Concerns"), (idx + variant) % 9 == 4 { a.choices[k.id] = ["Concerns"] } else { a.choices[k.id] = [opts[0]] }
                case .multi:
                    if let o = k.item.options?.first { a.choices[k.id] = [o] }
                default: break
                }
            }
            i.answers[section] = a
        }

        func addPhotos(_ i: inout Inspection, _ section: String, _ specs: [(String, Int, Int?)]) {
            for (category, count, flag) in specs {
                for n in 0..<count {
                    let img = placeholder(label: category, seed: category.count + n + section.count)
                    guard let data = img.jpegData(compressionQuality: 0.82) else { continue }
                    let pid = UUID()
                    if let path = repo.saveImage(data, folder: "photos/\(i.id.uuidString)", name: "\(pid.uuidString).jpg") {
                        i.photos[section, default: [:]][category, default: []]
                            .append(PhotoRef(id: pid, file: path, flag: n == count - 1 ? flag : nil))
                    }
                }
            }
        }

        // 1) 1428 Ridgeline Dr — in progress (prototype's main sample)
        var ridge = base("1428 Ridgeline Dr, Ogden, UT 84403", client: "Tysen and Chantel Gough", date: today, time: "09:30", structure: "Single Family")
        ridge.fields["Client phone"] = "(801) 555-0134"
        ridge.fields["Client email"] = "tysen.gough@email.com"
        ridge.fields["Real estate agent name"] = "Cyndi Farrais"
        ridge.fields["Real estate agent email"] = "cyndi@ogdenhomes.com"
        ridge.fields["Temperature (°F)"] = "72"
        ridge.fields["Year of construction"] = "1998"
        ridge.fields["Total sq ft"] = "2400"
        ridge.fields["Valuation ($)"] = "450,000"
        ridge.fields["Lot size (acres)"] = "0.25"
        ridge.fields["Basement"] = "Unfinished"
        ridge.fields["Buyer's areas of concern"] = "Buyer asked us to pay particular attention to the roof, the electrical panel, and any signs of water intrusion in the basement."
        ridge.fields["Apparent hazards observed before inspection"] = "Tree branches in contact with the structure on the north side. Section of front walkway concrete lifting — trip hazard."
        build(&ridge)
        for (n, s) in ["Landscaping", "Exterior Walls", "Garage", "Living Room", "Kitchen", "Bedroom 1"].enumerated() {
            ridge.status[s] = .done
            answer(&ridge, s, variant: n)
        }
        for s in ["Roof", "Outside Utilities", "Electrical", "Foundation / Crawl Space"] { ridge.status[s] = .prog }
        ridge.answers["Landscaping"]?.comments = "Vegetation is well kept. Recommend trimming tree branches back from the roof line."
        addPhotos(&ridge, "Roof", [("North Side", 2, 2), ("Concerns", 1, 1)])
        addPhotos(&ridge, "Landscaping", [("Front Yard", 2, nil), ("Back Yard 1", 1, nil), ("Concerns", 1, 1)])
        addPhotos(&ridge, "Exterior Walls", [("Front", 1, nil), ("Left Side", 1, nil), ("Concerns", 1, 2)])
        ridge.findings = sample.findings.map { Finding(category: $0.cat, text: $0.txt, section: $0.sec) }
        ridge.needsSync = true

        // 2) 82 Canyon Crest #4 — condo; report generated, waiting to sync (Queued)
        var canyon = base("82 Canyon Crest #4, Layton, UT 84041", client: "Marcus Webb", date: today, time: "13:00", structure: "Condo")
        canyon.fields["Real estate agent name"] = "Dana Pruitt"
        build(&canyon)
        for (n, s) in canyon.leafSections.prefix(6).enumerated() { canyon.status[s] = .done; answer(&canyon, s, variant: n) }
        canyon.needsSync = true

        // 3) 210 Willow Park, Lot 17 — mobile home; scheduled, synced from the office
        var willow = base("210 Willow Park, Lot 17, Roy, UT 84067", client: "Alicia Moreno", date: today, time: "15:30", structure: "Mobile / Manufactured")
        build(&willow)
        willow.needsSync = false
        willow.syncedAt = today

        // 4) 640 Harrison Blvd — yesterday; report sent & synced (Done)
        var harrison = base("640 Harrison Blvd, Ogden, UT 84404", client: "Priya Natarajan", date: yesterday, time: "10:00", structure: "Single Family")
        build(&harrison)
        for (n, s) in harrison.leafSections.enumerated() { harrison.status[s] = .done; answer(&harrison, s, variant: n) }
        harrison.findings = [Finding(category: 3, text: "Minor settling crack in the garage slab — monitor.", section: "Garage")]
        harrison.needsSync = false
        harrison.syncedAt = yesterday

        // Pre-render reports for the two inspections that already have one.
        for idx in [1, 3] {
            var insp = idx == 1 ? canyon : harrison
            let data = ReportData.make(insp, config: config, overrides: state.overrides, company: state.company,
                                       repo: repo, logo: UIImage(named: "VimsLogo") ?? UIImage())
            let r = ReportRenderer.render(data)
            if let path = repo.saveFile(r.pdf, folder: "reports", name: "\(insp.id.uuidString).pdf") {
                insp.report = ReportInfo(generatedAt: idx == 1 ? today : yesterday, pageCount: r.pageCount, file: path)
            }
            if idx == 1 { canyon = insp } else { harrison = insp }
        }

        return (state, [ridge, canyon, willow, harrison])
    }

    /// Clean state with no demo inspections (used when `enabled` is false).
    static func emptyState(config: ChecklistConfig) -> AppState {
        let cd = config.covers.default
        return AppState(
            session: nil,
            company: CompanyProfile(name: config.sample.company.name, address: "", joinCode: config.sample.company.code,
                                    inspectorName: "", email: "", feedbackEmail: config.support.feedbackEmail,
                                    inspectors: []),
            subscription: SubscriptionState(plans: config.subscription.plans,
                                            extraInspectorMonthly: config.subscription.extraInspectorMonthly,
                                            selectedPlan: config.subscription.plans.first?.id ?? "app",
                                            trialStart: Date(), trialDays: config.subscription.trialDays),
            overrides: ChecklistOverrides(),
            settings: AppSettings(defaultDepth: Depth(rawValue: config.wizard.defaults.depth) ?? .standard,
                                  defaultCover: CoverChoice(color: cd.color, category: cd.category, option: cd.option, style: cd.style)),
            seededAt: nil)
    }

    /// Placeholder "photo" (same look as the prototype's sample thumbnails).
    static func placeholder(label: String, seed: Int) -> UIImage {
        let cols: [UInt32] = [0x4A6572, 0x5B6B78, 0x7A6A55, 0x8A5A4A, 0x5A6B52, 0x6A5A7A]
        let size = CGSize(width: 960, height: 720)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor(hex: cols[seed % cols.count]).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 0, y: 500)); p.addLine(to: CGPoint(x: 360, y: 290)); p.addLine(to: CGPoint(x: 600, y: 420))
            p.addLine(to: CGPoint(x: 960, y: 265)); p.addLine(to: CGPoint(x: 960, y: 720)); p.addLine(to: CGPoint(x: 0, y: 720)); p.close()
            UIColor.black.withAlphaComponent(0.22).setFill(); p.fill()
            UIColor.white.withAlphaComponent(0.5).setFill()
            UIBezierPath(ovalIn: CGRect(x: 690, y: 100, width: 150, height: 150)).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40, weight: .semibold), .foregroundColor: UIColor.white.withAlphaComponent(0.85)]
            (label as NSString).draw(at: CGPoint(x: 36, y: 640), withAttributes: attrs)
        }
    }
}

