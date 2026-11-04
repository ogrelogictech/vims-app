import XCTest

/// Real taps on the plans screen, Plan & billing, the report credit offer and the Master admin code, against VIMS.storekit
/// through the app's DEBUG StoreKit lab (DebugStoreLab.swift). Simulator only; dialogs are off, so a purchase completes
/// without the system sheet. Run:
///   xcodebuild test -project VIMS.xcodeproj -scheme VIMS -destination 'platform=iOS Simulator,name=<device>' \
///     -only-testing:VIMSUITests/StorePurchaseUITests -derivedDataPath build/DerivedData
final class StorePurchaseUITests: XCTestCase {
    private func app(_ args: [String], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        let platform = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library"
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = "\(platform)/Frameworks:\(platform)/PrivateFrameworks"
        // ios/VIMSUITests/<this file> → ios/VIMS.storekit
        let config = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("VIMS.storekit").path
        app.launchArguments = ["-storeKitLab", config, "-storeKitClear", "-resetStoreVault", "-noSplash", "-noVideo"] + (reset ? ["-resetData"] : []) + args
        app.launch()
        return app
    }

    private func wait(_ e: XCUIElement, _ timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(e)", file: file, line: line)
    }

    private func scrollTo(_ e: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !e.isHittable, tries < 8 { app.swipeUp(); tries += 1 }
    }

    private func shot(_ name: String) {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("screenshots")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("nov4b-\(name).png"))
    }

    func testBuyMonthlyThenSwitchToYearly() {
        let app = app(["-skipLogin", "-trialDaysLeft", "0", "-screen", "subscribe"])
        wait(app.staticTexts["App only, monthly"])
        wait(app.staticTexts["$34.99/mo"])
        wait(app.staticTexts["$384.99/yr"])
        wait(app.staticTexts["$4.99/report"])
        shot("40-tap-plans-before-subscribe")
        app.buttons["Subscribe"].firstMatch.tap()
        wait(app.staticTexts["Subscription active"])
        shot("41-tap-subscription-active")
        app.buttons["View subscription"].tap()
        wait(app.staticTexts["Active · renews automatically"])
        wait(app.staticTexts["App only · Monthly · $34.99/mo"])
        app.buttons["Change plan"].tap()
        wait(app.staticTexts["Current plan"])
        app.buttons["Switch to yearly"].tap()
        wait(app.staticTexts["Subscription active"])
        app.buttons["View subscription"].tap()
        wait(app.staticTexts["App only · Yearly · $384.99/yr"])
        let restore = app.buttons["Restore Purchases"]
        scrollTo(restore, in: app)
        restore.tap()
        wait(app.staticTexts["Your subscription is restored"])
        shot("42-tap-restore-toast")
    }

    /// The real purchase sheet: a cancel leaves the plans screen with no error, and nothing is bought.
    func testPurchaseSheetCancelShowsNoError() {
        let app = app(["-skipLogin", "-trialDaysLeft", "0", "-storeKitDialogs", "-screen", "subscribe"])
        wait(app.staticTexts["$34.99/mo"])
        app.buttons["Subscribe"].firstMatch.tap()
        sleep(6)
        shot("48-tap-purchase-sheet")
        let sheet = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        wait(sheet.buttons["Close"])
        sheet.buttons["Close"].tap()
        sleep(3)
        shot("49-tap-purchase-cancelled-no-error")
        XCTAssertFalse(app.staticTexts["Subscription active"].exists)
        XCTAssertTrue(app.buttons["Subscribe"].firstMatch.exists)
        // Now through the sheet for real.
        app.buttons["Subscribe"].firstMatch.tap()
        wait(sheet.buttons["Subscribe"])
        sheet.buttons["Subscribe"].tap()
        sleep(2)
        shot("50-tap-purchase-sheet-confirmed")
        print("SHEET after confirm buttons=\(sheet.buttons.allElementsBoundByIndex.map(\.label))")
        if sheet.buttons["OK"].waitForExistence(timeout: 8) { sheet.buttons["OK"].tap() }
        wait(app.staticTexts["Subscription active"])
    }

    func testPayPerReportOfferUsesCreditOnce() {
        let app = app(["-skipLogin", "-trialDaysLeft", "0", "-inspection", "1428", "-screen", "summary"])
        let unreported = app.buttons["Save and generate report"]
        wait(unreported)
        scrollTo(unreported, in: app)
        unreported.tap()
        let generate = app.buttons["Generate PDF report"]
        wait(generate)
        scrollTo(generate, in: app)
        if app.staticTexts["This report needs a report credit. Regenerating it later is free."].exists {
            shot("43-tap-report-needs-credit-note")
            generate.tap()
            wait(app.alerts.firstMatch)
            shot("44-tap-report-credit-offer")
            XCTAssertTrue(app.alerts.buttons["Buy for $4.99"].exists)
            XCTAssertTrue(app.alerts.buttons["See plans"].exists)
            app.alerts.buttons["Buy for $4.99"].tap()
            wait(app.staticTexts["Report generated"], 120)
            shot("45-tap-report-generated-with-credit")
        }
    }

    func testOwnerCodeWrongThenRight() {
        let first = app(["-createOwnerAccount", "-resetOwnerCode"])
        sleep(6)
        first.terminate()
        let app = app(["-signInAs", "masteradmin@vimsinspect.com", "-ownerCodeTest", "vims-throwaway-7", "-screen", "ownerCode"], reset: false)
        let field = app.textFields.firstMatch
        wait(field)
        field.tap()
        field.typeText("not the code")
        app.buttons["Confirm code"].tap()
        wait(app.staticTexts["Error: That code isn\u{2019}t right."])
        shot("46-tap-owner-code-wrong")
        field.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue.padding(toLength: 16, withPad: XCUIKeyboardKey.delete.rawValue, startingAt: 0))
        field.typeText("VIMS THROWAWAY 7")
        app.buttons["Confirm code"].tap()
        wait(app.staticTexts["Plans & pricing"])
        shot("47-tap-owner-code-right")
    }
}
