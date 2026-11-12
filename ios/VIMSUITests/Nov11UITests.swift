import XCTest

/// Real taps through the client's Nov 11 changes (shared v1.23). Run in this order on a throwaway simulator:
///   testZeroCountsBuildChecklist, testCompanyCancellationFee, testAgreementViewerFee
/// with xcodebuild test-without-building … -only-testing:VIMSUITests/Nov11UITests/<name>
final class Nov11UITests: XCTestCase {
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
    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title),")).firstMatch
    }
    private func anyRow(_ app: XCUIApplication, _ base: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "\(base),", "\(base) ")).firstMatch
    }
    private func feeField(_ app: XCUIApplication) -> XCUIElement { app.textFields["Day-of cancellation fee (%)"].firstMatch }

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
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOV11_SHOTS"] ?? NSTemporaryDirectory())
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "se"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("nov11-\(name)-\(device).png"))
    }

    private func replace(_ field: XCUIElement, with text: String, shows: String? = nil, in app: XCUIApplication) {
        let old = (field.value as? String) ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()     // caret after the last character
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
        XCTAssertEqual(field.value as? String, shows ?? text)
        if app.keyboards.count > 0 { app.swipeDown(velocity: .fast) }
    }

    /// Upgrade check, run on the earlier build (no reset, before installing this one): a company profile edit to compare after.
    func testUpgradeSetCompanyProfile() {
        let app = launch(["-screen", "company"], reset: false)
        let address = app.textFields["Address"].firstMatch
        wait(address)
        replace(address, with: "450 Upgrade Way, Ogden, UT 84401", in: app)
        let phone = app.textFields["Phone"].firstMatch
        scrollTo(phone, in: app)
        replace(phone, with: "8015550177", shows: "(801) 555-0177", in: app)
        let save = app.buttons["Save profile"].firstMatch
        scrollTo(save, in: app)
        save.tap()
        wait(app.staticTexts["Company profile saved"], 30)
    }

    /// HVAC Units, Water Heaters and Electrical Panels down to 0 on step 3, then Build checklist: their sections are left out.
    func testZeroCountsBuildChecklist() {
        let app = launch(["-screen", "wizard", "-step", "3", "-nov6Wizard"])
        wait(plus(app, "Kitchen"))
        for l in ["HVAC Units", "Water Heaters", "Electrical Panels"] {
            scrollTo(minus(app, l), in: app)
            XCTAssertEqual(count(app, l), "1", "\(l) default")
            minus(app, l).tap()
            XCTAssertEqual(count(app, l), "0", l)
            XCTAssertFalse(minus(app, l).isEnabled, "\(l) minimum 0")
            XCTAssertTrue(plus(app, l).isEnabled, l)
        }
        shot("10-step3-zero")
        let next = app.buttons["Next"]
        scrollTo(next, in: app)
        next.tap()
        let build = app.buttons["Build checklist"]
        wait(build)
        scrollTo(build, in: app)
        build.tap()
        wait(app.staticTexts["Property Exterior"])

        if !row(app, "Landscaping").exists { app.staticTexts["Property Exterior"].firstMatch.tap() }
        wait(row(app, "Outside Utilities"))
        scrollTo(row(app, "Outside Utilities"), in: app)
        XCTAssertFalse(anyRow(app, "Cooling System").exists, "no Cooling System copy")
        shot("11-sections-exterior")

        openGroup(app, "Property Interior", showing: "Utility Room")
        scrollTo(row(app, "Plumbing"), in: app)
        for s in ["HVAC Mechanical", "Electrical", "Water Heater"] { XCTAssertFalse(anyRow(app, s).exists, "\(s) left out") }
        XCTAssertTrue(row(app, "Utility Room").exists && row(app, "Plumbing").exists)
        shot("12-sections-utility")
    }

    /// Company profile > Day-of cancellation fee (%): over 100 is refused, 25 saves and is there on the next launch.
    func testCompanyCancellationFee() {
        var app = launch(["-screen", "company"], reset: false)
        let field = feeField(app)
        wait(field)
        scrollTo(field, in: app)
        XCTAssertEqual(field.placeholderValue, "e.g. 25")
        shot("20-company-fee-empty")
        field.tap()
        field.typeText("1a01")
        XCTAssertEqual(field.value as? String, "101", "digits only")
        wait(app.staticTexts["Error: Enter a number up to 100"], 30)
        shot("21-company-fee-over")
        let save = app.buttons["Save profile"].firstMatch
        if app.keyboards.count > 0 { app.swipeDown(velocity: .fast) }
        scrollTo(save, in: app)
        save.tap()
        XCTAssertFalse(app.staticTexts["Company profile saved"].waitForExistence(timeout: 3), "101 doesn't save")
        scrollTo(field, in: app, up: true)
        field.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "25")
        XCTAssertEqual(field.value as? String, "25")
        if app.keyboards.count > 0 { app.swipeDown(velocity: .fast) }
        shot("22-company-fee-25")
        scrollTo(save, in: app)
        save.tap()
        wait(app.staticTexts["Company profile saved"], 30)
        app.terminate()

        app = launch(["-screen", "company"], reset: false)
        let again = feeField(app)
        wait(again)
        scrollTo(again, in: app)
        XCTAssertEqual(again.value as? String, "25", "saved in the company record")
        shot("23-company-fee-reopened")
    }

    /// After testCompanyCancellationFee: the filled agreement says "a fee totaling 25% of the amount".
    func testAgreementViewerFee() {
        let app = launch(["-screen", "inspectionAgreement", "-nov6Agreement", "Real Estate Sale"], reset: false)
        let line = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "a fee totaling 25% of the amount of the inspection will be charged.")).firstMatch
        wait(line)
        scrollTo(line, in: app)
        shot("30-agreement-fee")
    }
}
