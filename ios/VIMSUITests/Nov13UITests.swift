import XCTest

/// Real taps through the client's Nov 13 change (shared v1.24): Out of service area surcharge on wizard step 4. Run on a
/// throwaway simulator: testClientCaseStep4, then testEditAgreementShowsLine, with
/// xcodebuild test-without-building … -only-testing:VIMSUITests/Nov13UITests/<name>
final class Nov13UITests: XCTestCase {
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

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Drops the decimal keypad, which has no Return key.
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.count > 0 { app.staticTexts["Add any secondary testing for this inspection."].firstMatch.tapIfHittable() }
        if app.keyboards.count > 0 { app.swipeDown(velocity: .fast) }
    }

    /// Brings the box into view above the keypad by dragging the page in its upper part (never on the keypad, and never a
    /// downward fling, which would dismiss the keypad and scroll the page), then types with the caret after the last character.
    private func type(_ field: XCUIElement, _ text: String, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        for _ in 0..<12 {
            let bottom = app.keyboards.count > 0 ? app.keyboards.firstMatch.frame.minY : window.frame.height
            if field.exists, field.frame.minY > 110, field.frame.maxY < bottom - 8 { break }
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            let up = !field.exists || field.frame.maxY >= bottom - 8
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: up ? -110 : 110)))
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 10)
        field.typeText(text)
    }

    private func shot(_ name: String) {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOV13_SHOTS"] ?? NSTemporaryDirectory())
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "se"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("nov13-\(name)-\(device).png"))
    }

    /// The client's case: surcharge 75, Inspection Fee 400, Radon 150 → Bundled 150.00, Total 625.00; the pre-filled agreement
    /// prints the surcharge line and Total Amount Due 625.00.
    func testClientCaseStep4() {
        let app = launch(["-screen", "wizard", "-step", "4", "-nov13Wizard"])
        wait(app.staticTexts["UTILITY & SYSTEMS"])
        let surcharge = app.textFields["Out of service area surcharge in dollars"].firstMatch
        let fee = app.textFields["Inspection Fee in dollars"].firstMatch
        scrollTo(fee, in: app)
        XCTAssertTrue(surcharge.exists, "surcharge box on step 4")
        XCTAssertEqual(surcharge.placeholderValue, "0.00")
        XCTAssertLessThan(surcharge.frame.maxY, fee.frame.minY, "surcharge row right above Inspection Fee")
        XCTAssertLessThanOrEqual(surcharge.frame.minX, fee.frame.minX + 1, "same column as Inspection Fee")
        shot("01-step4-empty")

        type(surcharge, "75", in: app)
        XCTAssertFalse(app.buttons["Radon"].firstMatch.isSelected, "the surcharge selects nothing")
        type(fee, "400", in: app)
        type(app.textFields["Radon amount in dollars"].firstMatch, "150", in: app)
        XCTAssertTrue(app.buttons["Radon"].firstMatch.isSelected, "typing an amount selects the test")
        dismissKeyboard(app)
        let bundled = any(app, "Bundled Secondary Testing"), total = any(app, "Total Cost of Inspection")
        scrollTo(total, in: app)
        XCTAssertEqual(surcharge.value as? String, "75")
        XCTAssertEqual(bundled.value as? String, "$150.00", "bundled unchanged by the surcharge")
        XCTAssertEqual(total.value as? String, "$625.00")
        shot("02-step4-625")

        // Same limits as Inspection Fee: no more than 99,999.99 and 2 decimals.
        type(surcharge, String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "1234567.891", in: app)
        XCTAssertEqual(surcharge.value as? String, "12,345.89")
        XCTAssertEqual(total.value as? String, "$12,895.89")
        type(surcharge, String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "75", in: app)
        XCTAssertEqual(total.value as? String, "$625.00")
        dismissKeyboard(app)

        let view = app.buttons["View Pre-filled Inspection Agreement"]
        scrollTo(view, in: app)
        view.tap()
        wait(app.staticTexts["Inspection agreement"])
        let form = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Out of service area surcharge $ 75.00")).firstMatch
        wait(form, 30)
        XCTAssertTrue(form.label.contains("Inspection Fee $ 400.00 Bundled Services $ 150.00 Total Amount Due $ 625.00"), form.label)
        scrollTo(form, in: app)
        app.swipeUp(velocity: .slow)
        shot("03-agreement-viewer")
        app.buttons["Back"].firstMatch.tap()
        wait(view)
        XCTAssertEqual(any(app, "Total Cost of Inspection").value as? String, "$625.00", "back on step 4 with everything kept")
    }

    /// Company profile > Edit agreement: the locked form block shows the new line above Inspection Fee.
    func testEditAgreementShowsLine() {
        let app = launch(["-screen", "agreementEditor"], reset: false)
        let form = any(app, "Form fields, locked")
        wait(form)
        scrollTo(form, in: app)
        // The phone needs more of the form scrolled past to reach the fee lines.
        let swipes = UIDevice.current.userInterfaceIdiom == .pad ? 1 : 3
        for i in 1...swipes {
            app.swipeUp(velocity: .slow)
            shot("04-edit-agreement-form-\(i)")
        }
    }
}

private extension XCUIElement {
    func tapIfHittable() { if exists && isHittable { tap() } }
}
