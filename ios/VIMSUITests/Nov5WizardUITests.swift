import XCTest

/// Real taps through the client's Nov 4 wizard and agreement changes (shared v1.19). Run:
///   xcodebuild test -project VIMS.xcodeproj -scheme VIMS -destination 'platform=iOS Simulator,id=<device>' \
///     -only-testing:VIMSUITests/Nov5WizardUITests -derivedDataPath build/DerivedData
final class Nov5WizardUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func app(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetData", "-skipLogin", "-noSplash", "-noVideo"] + args
        app.launch()
        return app
    }

    private func wait(_ e: XCUIElement, _ timeout: TimeInterval = 90, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(e)", file: file, line: line)
    }

    private func scrollTo(_ e: XCUIElement, in app: XCUIApplication, up: Bool = false) {
        var tries = 0
        while !(e.exists && e.isHittable), tries < 14 {
            if up { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            tries += 1
        }
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func amount(_ app: XCUIApplication, _ title: String) -> XCUIElement { app.textFields["\(title) amount in dollars"].firstMatch }
    private func chip(_ app: XCUIApplication, _ title: String) -> XCUIElement { app.buttons[title].firstMatch }

    /// Drops the decimal keypad, which has no Return key.
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.count > 0 { app.staticTexts["Add any secondary testing for this inspection."].firstMatch.tapIfHittable() }
        if app.keyboards.count > 0 { app.swipeDown(velocity: .fast) }
    }

    /// The State list opens with its search field focused (the list itself is lazy); Return picks the top match.
    private func pickState(_ app: XCUIApplication, _ name: String) {
        let phone = app.searchFields.firstMatch, pad = app.textFields["Search states"].firstMatch
        XCTAssertTrue(phone.waitForExistence(timeout: 60) || pad.exists, "no State search field")
        let field = phone.exists ? phone : pad
        wait(app.keyboards.firstMatch, 30)
        field.typeText(name + "\n")
    }

    private func shot(_ name: String) {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("screenshots")
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : (XCUIScreen.main.screenshot().image.size.width < 400 ? "se" : "phone")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("nov5-\(name)-\(device).png"))
    }

    /// Step 1: the View row is gone; Time of walk through starts empty, sets and clears; License state picks and clears.
    func testStep1() {
        let app = app(["-screen", "wizard", "-step", "1"])
        wait(app.staticTexts["CLIENT & INSPECTION"])
        XCTAssertFalse(any(app, "Inspection agreement: View").exists)
        let licenseState = app.buttons["License state"].firstMatch
        scrollTo(licenseState, in: app)
        XCTAssertEqual(licenseState.value as? String, "Not selected", "the demo company has no license state")
        let walk = app.buttons["Time of walk through"].firstMatch
        scrollTo(walk, in: app)
        XCTAssertEqual(walk.value as? String, "Not set", "no auto-fill")
        shot("10-step1-empty")

        walk.tap()
        wait(app.buttons["Set"])
        shot("11-step1-walkthrough-picker")
        app.buttons["Set"].tap()
        XCTAssertNotEqual(walk.value as? String, "Not set")
        app.buttons["Clear Time of walk through"].firstMatch.tap()
        XCTAssertEqual(walk.value as? String, "Not set", "clearable")
        walk.tap()
        wait(app.buttons["Cancel"])
        app.buttons["Cancel"].tap()
        XCTAssertEqual(walk.value as? String, "Not set", "Cancel sets nothing")

        licenseState.tap()
        pickState(app, "Idaho")
        let picked = app.buttons["License state"].firstMatch
        XCTAssertTrue(picked.waitForExistence(timeout: 20))
        XCTAssertEqual(picked.value as? String, "Idaho")
        // Picking the license state leaves the inspection's State alone.
        XCTAssertEqual(app.buttons["State, required"].firstMatch.value as? String, "Not selected")
        shot("12-step1-license-state")
        app.buttons["Clear license state"].firstMatch.tap()
        XCTAssertEqual(picked.value as? String, "Not selected")
    }

    /// Step 2: every chip; Mobile Home and Manufactured Home both add the undercarriage on step 3.
    func testStep2And3() {
        let app = app(["-screen", "wizard", "-step", "2", "-wizType", "Real Estate Sale"])
        wait(chip(app, "Mobile Home"))
        for t in ["Single Family", "Duplex", "Multi-Unit", "Townhouse", "Condo", "Manufactured Home"] { XCTAssertTrue(chip(app, t).exists, t) }
        XCTAssertFalse(chip(app, "Mobile / Manufactured").exists)
        chip(app, "Manufactured Home").tap()
        XCTAssertTrue(chip(app, "Manufactured Home").isSelected)
        shot("13-step2-manufactured")
        scrollTo(app.buttons["Next"], in: app)
        app.buttons["Next"].tap()
        wait(chip(app, "Mobile Home Undercarriage"))
        XCTAssertTrue(chip(app, "Mobile Home Undercarriage").isSelected, "side effect")
        XCTAssertFalse(chip(app, "Chimney").exists, "Chimney left Exterior areas")
        XCTAssertFalse(app.staticTexts["UTILITY & SYSTEMS"].exists, "Utility & systems left this step")
        shot("14-step3-no-chimney")
    }

    /// Step 4: chips, $ boxes, the sums, the keystroke limits, the agreement and back to step 4, Build checklist.
    func testStep4() {
        let app = app(["-screen", "wizard", "-step", "4", "-wizType", "Real Estate Sale"])
        wait(app.staticTexts["UTILITY & SYSTEMS"])
        for t in ["Chimney", "Heating Oil Tank", "Propane Tank", "Boiler", "Radon"] { XCTAssertTrue(chip(app, t).exists, t) }
        XCTAssertTrue(chip(app, "Chimney").isSelected, "on by default, as it was under Exterior")
        XCTAssertFalse(chip(app, "Boiler").isSelected)
        shot("20-step4-new")

        // Typing above 0 selects.
        let boiler = amount(app, "Boiler")
        boiler.tap()
        boiler.typeText("140.5")
        wait(app.keyboards.firstMatch, 30)
        XCTAssertTrue(chip(app, "Boiler").isSelected, "typing above 0 selects")
        dismissKeyboard(app)
        // Typing 0 doesn't.
        let lead = amount(app, "Lead")
        scrollTo(lead, in: app)
        lead.tap()
        lead.typeText("0")
        XCTAssertFalse(chip(app, "Lead").isSelected, "typing 0 doesn't select")
        lead.typeText("1234567.899")          // 0 then digits: the filter holds it to 5 digits and 2 decimals
        XCTAssertEqual(lead.value as? String, "01,234.89", "limits while typing")
        dismissKeyboard(app)
        XCTAssertTrue(chip(app, "Lead").isSelected)

        // Deselecting clears the amount.
        scrollTo(chip(app, "Lead"), in: app)
        chip(app, "Lead").tap()
        XCTAssertFalse(chip(app, "Lead").isSelected)
        XCTAssertTrue(["", "0.00"].contains(lead.value as? String ?? ""), "cleared")

        let radon = amount(app, "Radon")
        scrollTo(radon, in: app)
        radon.tap()
        radon.typeText("0.10")
        dismissKeyboard(app)
        let wind = amount(app, "Wind Mitigation")
        scrollTo(wind, in: app)
        wind.tap()
        wind.typeText("0.20")
        dismissKeyboard(app)
        XCTAssertTrue(chip(app, "Wind Mitigation").isSelected)

        let termite = amount(app, "Wood Destroying Organism Inspection")
        scrollTo(termite, in: app)
        XCTAssertTrue(termite.exists, "the Termite chip keeps its display name")
        XCTAssertTrue(chip(app, "Septic System").exists, "the Septic chip keeps its display name")
        let fee = app.textFields["Inspection Fee in dollars"].firstMatch
        scrollTo(fee, in: app)
        fee.tap()
        fee.typeText("495")
        dismissKeyboard(app)
        let bundled = any(app, "Bundled Secondary Testing"), total = any(app, "Total Cost of Inspection")
        scrollTo(total, in: app)
        // 140.50 + 0.10 + 0.20
        XCTAssertEqual(bundled.value as? String, "$140.80")
        XCTAssertEqual(total.value as? String, "$635.80")
        shot("21-step4-sums")

        // The agreement button sits above Back / Build checklist, and Back from it returns here with everything kept.
        let view = app.buttons["View Pre-filled Inspection Agreement"]
        scrollTo(view, in: app)
        view.tap()
        wait(app.staticTexts["Inspection agreement"])
        wait(app.buttons["Back"].firstMatch)
        shot("22-agreement-from-wizard")
        app.buttons["Back"].firstMatch.tap()
        wait(view)
        XCTAssertTrue(app.buttons["Build checklist"].exists, "back on step 4")
        XCTAssertEqual(any(app, "Total Cost of Inspection").value as? String, "$635.80")

        // Fees never block: step 1's required fields send it back there, not the amounts.
        app.buttons["Build checklist"].tap()
        wait(app.staticTexts["CLIENT & INSPECTION"])
        wait(app.staticTexts["Error: Client name is required"], 30)
    }

    /// A locked type: note, Utility chips and $ boxes disabled, testing still open, choices back when unlocked.
    func testStep4Locked() {
        let app = app(["-screen", "wizard", "-step", "4", "-wizType", "Phase 1 Foundation"])
        wait(app.staticTexts["UTILITY & SYSTEMS"])
        wait(app.staticTexts["Not used for a Phase 1 Foundation inspection"])
        XCTAssertFalse(chip(app, "Chimney").isEnabled)
        XCTAssertFalse(chip(app, "Boiler").isEnabled)
        XCTAssertFalse(amount(app, "Chimney").exists, "no editable box")
        XCTAssertEqual(any(app, "Chimney amount").value as? String, "Locked")
        XCTAssertTrue(amount(app, "Radon").exists, "testing stays open")
        shot("23-step4-locked")
    }

    /// Company profile > License state, saved, prefills a new inspection (and stays in the company record).
    func testCompanyLicenseState() {
        var app = app(["-screen", "company"])
        let field = app.buttons["License state"].firstMatch
        wait(field)
        scrollTo(field, in: app)
        XCTAssertEqual(field.value as? String, "Not selected")
        field.tap()
        pickState(app, "Nevada")
        wait(field)
        shot("15-company-license-state")
        let save = app.buttons["Save profile"].firstMatch
        scrollTo(save, in: app)
        save.tap()
        wait(app.staticTexts["Company profile saved"], 30)
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-skipLogin", "-noSplash", "-noVideo", "-screen", "wizard", "-step", "1"]
        app.launch()
        wait(app.staticTexts["CLIENT & INSPECTION"])
        let prefilled = app.buttons["License state"].firstMatch
        scrollTo(prefilled, in: app)
        XCTAssertEqual(prefilled.value as? String, "Nevada", "prefilled from the company")
    }

    /// A saved inspection from an earlier build, edited in place (no data reset): the legacy value stays until a type is picked,
    /// Chimney shows selected under Utility & systems, and Update checklist keeps it.
    func testSavedInspectionEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipLogin", "-noSplash", "-noVideo", "-screen", "editWizard", "-inspection", "210", "-step", "2"]
        app.launch()
        wait(chip(app, "Mobile Home"))
        XCTAssertTrue(chip(app, "Mobile Home").isSelected, "the legacy value shows on Mobile Home")
        chip(app, "Mobile Home").tap()
        XCTAssertTrue(chip(app, "Mobile Home").isSelected)
        let next = app.buttons["Next"]
        scrollTo(next, in: app)
        next.tap()
        wait(chip(app, "Mobile Home Undercarriage"))
        XCTAssertTrue(chip(app, "Mobile Home Undercarriage").isSelected)
        scrollTo(next, in: app)
        next.tap()
        wait(app.staticTexts["UTILITY & SYSTEMS"])
        XCTAssertTrue(chip(app, "Chimney").isSelected, "saved under exterior, shown selected here")
        let update = app.buttons["Update checklist"]
        scrollTo(update, in: app)
        update.tap()
        wait(any(app, "Inspection agreement, Filled in for Alicia Moreno \u{00B7} Email to client"))
    }

    /// Fully filled sample through Build checklist, then the checklist's Chimney and the inspection-screen agreement row.
    func testBuildWithFees() {
        let app = app(["-screen", "wizard", "-step", "4", "-nov5Wizard", "-nov5Struct", "Duplex"])
        wait(app.staticTexts["UTILITY & SYSTEMS"])
        let build = app.buttons["Build checklist"]
        scrollTo(build, in: app)
        shot("24-step4-bottom")
        build.tap()
        wait(any(app, "Inspection agreement, Filled in for Morgan Ellis \u{00B7} Email to client"))
        shot("25-checklist-built")
        any(app, "Inspection agreement, Filled in for Morgan Ellis \u{00B7} Email to client").tap()
        wait(app.staticTexts["Inspection agreement"])
        shot("26-agreement-from-row")
    }
}

private extension XCUIElement {
    func tapIfHittable() { if exists && isHittable { tap() } }
}
