import XCTest

/// Real taps through the client's Nov 6 counts (shared v1.20). Run in this order on a throwaway simulator:
///   testSteppersAndKitchenChip, testLockedTypesDisableSteppers, testBuildEightCopies, testGenerateReport, testUpdateLowersAndRaises
/// with xcodebuild test-without-building … -only-testing:VIMSUITests/Nov6CountsUITests/<name>
final class Nov6CountsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ args: [String], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-resetData"] : []) + ["-skipLogin", "-noSplash", "-noVideo"] + args
        app.launch()
        return app
    }

    private func wait(_ e: XCUIElement, _ timeout: TimeInterval = 90, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(e)", file: file, line: line)
    }

    private func scrollTo(_ e: XCUIElement, in app: XCUIApplication, up: Bool = false) {
        var tries = 0
        while !(e.exists && e.isHittable), tries < 16 {
            if up { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            tries += 1
        }
    }

    private func plus(_ app: XCUIApplication, _ label: String) -> XCUIElement { app.buttons["Increase \(label)"].firstMatch }
    private func minus(_ app: XCUIApplication, _ label: String) -> XCUIElement { app.buttons["Decrease \(label)"].firstMatch }
    private func count(_ app: XCUIApplication, _ label: String) -> String { app.staticTexts["count-\(label)"].firstMatch.label }
    private func chip(_ app: XCUIApplication, _ title: String) -> XCUIElement { app.buttons[title].firstMatch }
    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title),")).firstMatch
    }

    /// One group is open at a time on the Sections screen.
    private func openGroup(_ app: XCUIApplication, _ heading: String, showing section: String) {
        if !row(app, section).exists {
            let header = app.staticTexts[heading].firstMatch
            scrollTo(header, in: app, up: true)
            header.tap()
        }
        wait(row(app, section), 20)
        scrollTo(row(app, section), in: app)
    }

    private func shot(_ name: String) {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOV6_SHOTS"] ?? NSTemporaryDirectory())
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "se"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("nov6-\(name)-\(device).png"))
    }

    /// Upgraded from 0.31.0 (no reset): the accepted EULA is 2026-10-28, so the updated one is asked for first.
    func testEulaReaccept() {
        let app = XCUIApplication()
        app.launchArguments = ["-noSplash", "-noVideo"]
        app.launch()
        wait(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'revised November 6, 2026'")).firstMatch)
        shot("05-eula-gate")
        let agree = app.buttons["I agree"].firstMatch
        wait(agree)
        scrollTo(agree, in: app)
        agree.tap()
        wait(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH[c] 'Today'")).firstMatch, 60)
        shot("06-after-eula")
    }

    /// Upgraded from 0.31.0 (no reset): the counts read the saved inspection's defaults and Update checklist changes nothing.
    func testSavedUpdateKeepsChecklist() {
        let app = launch(["-screen", "editWizard", "-inspection", "1428", "-step", "3"], reset: false)
        wait(plus(app, "Kitchen"))
        for (l, v) in [("Kitchen", "1"), ("HVAC Units", "1"), ("Water Heaters", "1"), ("Electrical Panels", "1")] {
            scrollTo(plus(app, l), in: app)
            XCTAssertEqual(count(app, l), v, l)
        }
        shot("07-saved-step3")
        let next = app.buttons["Next"]
        scrollTo(next, in: app)
        next.tap()
        let up = app.buttons["Update checklist"]
        wait(up)
        scrollTo(up, in: app)
        up.tap()
        wait(app.staticTexts["Property Exterior"])
    }

    /// Order of the rows, minimums, maximum 12, and the Kitchen chip and stepper mirroring each other both ways.
    func testSteppersAndKitchenChip() {
        let app = launch(["-screen", "wizard", "-step", "3", "-wizType", "Real Estate Sale"])
        wait(plus(app, "Kitchen"))
        shot("10-step3-top")
        for (l, v) in [("Bedrooms", "4"), ("Bathrooms", "3"), ("Hallways", "2"), ("Kitchen", "1"), ("HVAC Units", "1"), ("Water Heaters", "1"), ("Electrical Panels", "1")] {
            scrollTo(plus(app, l), in: app)
            XCTAssertEqual(count(app, l), v, l)
        }
        shot("11-step3-counts")
        XCTAssertFalse(minus(app, "HVAC Units").isEnabled, "minimum 1")
        XCTAssertFalse(minus(app, "Water Heaters").isEnabled)
        XCTAssertFalse(minus(app, "Electrical Panels").isEnabled)
        XCTAssertTrue(minus(app, "Kitchen").isEnabled, "minimum 0")

        scrollTo(chip(app, "Kitchen"), in: app)
        XCTAssertTrue(chip(app, "Kitchen").isSelected)
        // Stepper at 0 turns the chip off.
        scrollTo(minus(app, "Kitchen"), in: app, up: true)
        minus(app, "Kitchen").tap()
        XCTAssertEqual(count(app, "Kitchen"), "0")
        XCTAssertFalse(chip(app, "Kitchen").isSelected, "stepper 0: chip off")
        // Above 0 turns it on.
        plus(app, "Kitchen").tap()
        plus(app, "Kitchen").tap()
        XCTAssertEqual(count(app, "Kitchen"), "2")
        XCTAssertTrue(chip(app, "Kitchen").isSelected, "stepper above 0: chip on")
        // Chip off sets 0, chip on sets 1.
        scrollTo(chip(app, "Kitchen"), in: app)
        chip(app, "Kitchen").tap()
        XCTAssertEqual(count(app, "Kitchen"), "0")
        chip(app, "Kitchen").tap()
        XCTAssertEqual(count(app, "Kitchen"), "1")
        XCTAssertTrue(chip(app, "Kitchen").isSelected)
        shot("12-step3-chips")

        // Maximum 12.
        scrollTo(plus(app, "Electrical Panels"), in: app, up: true)
        for _ in 1..<12 { plus(app, "Electrical Panels").tap() }
        XCTAssertEqual(count(app, "Electrical Panels"), "12")
        XCTAssertFalse(plus(app, "Electrical Panels").isEnabled, "maximum 12")
    }

    /// `areasLockedTypes`: the four new steppers are off; Bedrooms, Bathrooms and Hallways stay editable (`_areasLockedAbout`).
    func testLockedTypesDisableSteppers() {
        for t in ["Phase 1 Foundation", "Phase 2 Pre-Dry Wall", "Tests Only", "4 Point Inspection"] {
            let app = launch(["-screen", "wizard", "-step", "3", "-wizType", t])
            wait(plus(app, "Bedrooms"))
            for l in ["Kitchen", "HVAC Units", "Water Heaters", "Electrical Panels"] {
                scrollTo(plus(app, l), in: app)
                XCTAssertFalse(plus(app, l).isEnabled, "\(t) \(l) +")
                XCTAssertFalse(minus(app, l).isEnabled, "\(t) \(l) -")
            }
            scrollTo(plus(app, "Bedrooms"), in: app, up: true)
            XCTAssertTrue(plus(app, "Bedrooms").isEnabled, "\(t) Bedrooms")
            XCTAssertTrue(plus(app, "Hallways").isEnabled, "\(t) Hallways")
            shot("13-step3-locked-\(t.prefix(5))")
            app.terminate()
        }
    }

    /// 2 panels, 2 water heaters, 3 HVAC, 2 kitchens through Build checklist; one copy answered by hand.
    func testBuildEightCopies() {
        let app = launch(["-screen", "wizard", "-step", "3", "-nov6Wizard"])
        wait(plus(app, "Kitchen"))
        for (l, n) in [("Kitchen", 1), ("HVAC Units", 2), ("Water Heaters", 1), ("Electrical Panels", 1)] {
            scrollTo(plus(app, l), in: app)
            for _ in 0..<n { plus(app, l).tap() }
        }
        shot("20-step3-set")
        let next = app.buttons["Next"]
        scrollTo(next, in: app)
        next.tap()
        let build = app.buttons["Build checklist"]
        wait(build)
        scrollTo(build, in: app)
        build.tap()
        wait(app.staticTexts["Property Exterior"])

        // Each group's rows, expanded, in order on the screen.
        if !row(app, "Landscaping").exists { app.staticTexts["Property Exterior"].firstMatch.tap() }
        wait(row(app, "Cooling System #2"))
        scrollTo(row(app, "Cooling System #3"), in: app)
        XCTAssertTrue(row(app, "Outside Utilities").frame.maxY <= row(app, "Cooling System #2").frame.minY + 1)
        XCTAssertTrue(row(app, "Cooling System #2").frame.maxY <= row(app, "Cooling System #3").frame.minY + 1)
        XCTAssertFalse(row(app, "Cooling System").exists, "the plain name is never listed")
        shot("21-sections-cooling")

        openGroup(app, "Property Interior", showing: "Electrical 2")
        shot("22-sections-utility")
        XCTAssertTrue(row(app, "Electrical").exists)
        XCTAssertTrue(row(app, "Electrical").frame.maxY <= row(app, "Electrical 2").frame.minY + 1, "copies together")
        row(app, "Electrical 2").tap()
        // An answer of its own: the first option of the first question, and a comment.
        wait(app.staticTexts["Electrical 2"].firstMatch)
        shot("23-section-electrical-2")
        let save = app.buttons["Save"].firstMatch
        chip(app, "Secondary Panel").tap()
        XCTAssertTrue(chip(app, "Secondary Panel").isSelected)
        let comments = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Notes for this section\u{2026}")).firstMatch
        scrollTo(comments, in: app)
        comments.tap()
        comments.typeText("Sub panel in the garage")
        if app.keyboards.count > 0 { app.swipeDown(velocity: .fast) }
        scrollTo(save, in: app)
        save.tap()
        wait(row(app, "Electrical 2"))

        openGroup(app, "Property Exterior", showing: "Cooling System #2")
        row(app, "Cooling System #2").tap()
        wait(app.staticTexts["Cooling System #2"].firstMatch)
        shot("24-section-cooling-2")
    }

    /// The new agreement line in the viewer; VoiceOver text says which box is ticked.
    func testAgreementViewerTicks() {
        for (type, expect) in [("Texas", "Texas checked Tests Only not checked"), ("Tests Only", "Texas not checked Tests Only checked")] {
            let app = launch(["-screen", "inspectionAgreement", "-nov6Agreement", type], reset: false)
            let line = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", expect)).firstMatch
            wait(line)
            scrollTo(line, in: app)
            shot("50-agreement-\(type.prefix(5))")
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Wind Mitigation checked'")).firstMatch.exists)
            app.terminate()
        }
    }

    /// Run after testBuildEightCopies and a launch with -nov6Fill: the real Generate PDF report button.
    func testGenerateReport() {
        let app = launch(["-screen", "report", "-inspection", "418", "-nov6Fill", "-nov6Status"], reset: false)
        wait(app.staticTexts["Generate report"].firstMatch)
        shot("30-report-contents")
        let generate = app.buttons["Generate PDF report"].firstMatch
        scrollTo(generate, in: app)
        shot("31-report-contents-bottom")
        generate.tap()
        let ready = app.staticTexts["Report ready"].firstMatch
        if !ready.waitForExistence(timeout: 30) { shot("32-report-not-yet") }
        wait(ready, 240)
        shot("32-report-ready")
    }

    /// Lowering a count on Update checklist drops the extra copies and keeps their data, like Bathroom; raising brings them back.
    func testUpdateLowersAndRaises() {
        var app = launch(["-screen", "editWizard", "-inspection", "418", "-step", "3"], reset: false)
        wait(minus(app, "Electrical Panels"))
        scrollTo(minus(app, "Electrical Panels"), in: app)
        minus(app, "Electrical Panels").tap()
        XCTAssertEqual(count(app, "Electrical Panels"), "1")
        minus(app, "HVAC Units").tap()
        XCTAssertEqual(count(app, "HVAC Units"), "2")
        func update() {
            let next = app.buttons["Next"]
            scrollTo(next, in: app)
            next.tap()
            let up = app.buttons["Update checklist"]
            wait(up)
            scrollTo(up, in: app)
            up.tap()
        }
        update()
        wait(app.staticTexts["Property Exterior"])
        shot("40-after-lowering")
        app.terminate()

        app = launch(["-screen", "editWizard", "-inspection", "418", "-step", "3", "-nov6Status"], reset: false)
        wait(plus(app, "Electrical Panels"))
        scrollTo(plus(app, "Electrical Panels"), in: app)
        plus(app, "Electrical Panels").tap()
        plus(app, "HVAC Units").tap()
        update()
        wait(app.staticTexts["Property Exterior"])
        openGroup(app, "Property Interior", showing: "Electrical 2")
        XCTAssertTrue(row(app, "Electrical 2").label.contains("Done"), "came back with its status")
        shot("41-after-raising")
    }
}
