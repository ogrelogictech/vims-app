import XCTest
import UIKit

/// Review screenshots in a chosen orientation. `simctl` can't rotate a simulator and iPadOS 26 refuses the app's own
/// rotation request in windowed mode, but `XCUIDevice.shared.orientation` rotates the device for real.
///
/// Driven by a JSON plan whose path comes from the environment (xcodebuild passes `TEST_RUNNER_*` variables on):
///
///     TEST_RUNNER_VIMS_SHOT_PLAN=/abs/plan.json xcodebuild test -project VIMS.xcodeproj -scheme VIMS \
///       -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:VIMSUITests
///
///     { "out": "/abs/output/dir",
///       "shots": [ { "name": "13in-land-home", "orientation": "landscape", "args": ["-skipLogin", "-screen", "home"],
///                    "wait": 2.5, "steps": [ { "tap": "State, required" }, { "wait": 1 }, { "type": "ore" } ] } ] }
///
/// Each shot launches the app with the DEBUG launch arguments (DebugLaunch.swift), rotates, runs the steps and saves
/// `<out>/<name>.png` (also attached to the test result). Steps: `tap` (accessibility label / identifier / static
/// text), `tapAt` ([x, y] as fractions of the window), `type`, `swipeUp` / `swipeDown` (count), `wait` (seconds),
/// `shot` (an extra screenshot named `<name>-<value>`).
final class ReviewScreenshots: XCTestCase {
    struct Plan: Decodable {
        var out: String
        var shots: [Shot]
    }
    struct Shot: Decodable {
        var name: String
        var orientation: String?
        var args: [String]
        var wait: Double?
        var steps: [Step]?
    }
    struct Step: Decodable {
        var tap: String?
        var tapAt: [Double]?
        var type: String?
        var swipeUp: Int?
        var swipeDown: Int?
        var wait: Double?
        var shot: String?
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testPlan() throws {
        guard let path = ProcessInfo.processInfo.environment["VIMS_SHOT_PLAN"] else {
            throw XCTSkip("Set TEST_RUNNER_VIMS_SHOT_PLAN to a JSON plan to take review screenshots.")
        }
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try FileManager.default.createDirectory(atPath: plan.out, withIntermediateDirectories: true)
        for shot in plan.shots { run(shot, out: plan.out) }
    }

    @MainActor
    private func run(_ shot: Shot, out: String) {
        let device = XCUIDevice.shared
        let orientation: UIDeviceOrientation = switch shot.orientation ?? "portrait" {
        case "landscape", "landscapeLeft": .landscapeLeft
        case "landscapeRight": .landscapeRight
        default: .portrait
        }
        device.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = shot.args
        app.launch()
        device.orientation = orientation
        sleep(shot.wait ?? 2.5)
        for step in shot.steps ?? [] {
            if let label = step.tap {
                let el = element(app, label)
                if el.waitForExistence(timeout: 4) { el.tap() } else { print("SHOT \(shot.name): no element '\(label)'") }
            }
            if let p = step.tapAt, p.count == 2 {
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: p[0], dy: p[1])).tap()
            }
            if let t = step.type { app.typeText(t) }
            if let n = step.swipeUp { for _ in 0..<n { app.swipeUp() } }
            if let n = step.swipeDown { for _ in 0..<n { app.swipeDown() } }
            if let w = step.wait { sleep(w) }
            if let s = step.shot { save(app, "\(shot.name)-\(s)", out: out) }
        }
        save(app, shot.name, out: out)
        app.terminate()
    }

    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let byId = app.descendants(matching: .any).matching(identifier: label).firstMatch
        if byId.exists { return byId }
        let pred = NSPredicate(format: "label == %@", label)
        for q in [app.buttons, app.textFields, app.staticTexts, app.otherElements] {
            let m = q.matching(pred).firstMatch
            if m.exists { return m }
        }
        return byId
    }

    private func sleep(_ seconds: Double) {
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }

    @MainActor
    private func save(_ app: XCUIApplication, _ name: String, out: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Draw through UIImage so a landscape capture is written upright.
        let img = shot.image
        let upright = UIGraphicsImageRenderer(size: img.size, format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = img.scale; return f
        }()).image { _ in img.draw(in: CGRect(origin: .zero, size: img.size)) }
        let url = URL(fileURLWithPath: out).appendingPathComponent("\(name).png")
        do { try upright.pngData()?.write(to: url) } catch { print("SHOT write failed \(url.path): \(error)") }
        print("SHOT saved \(url.path) \(Int(img.size.width))x\(Int(img.size.height))")
    }
}
