import XCTest

/// Native screenshot capture harness. NOT executed by the Linux package author.
/// Running this suite produces real SDK-rendered evidence in the .xcresult bundle.
final class VisualUITests: XCTestCase {
    private let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "th", "pt-PT"]
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(language: String, tab: Int, theme: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = language
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = String(tab)
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = theme
        app.launch()
        return app
    }
    @MainActor private func save(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor func testCoreScreensAllLanguages() throws {
        for language in languages {
            for (tab, screen) in [(0, "today"), (1, "map"), (2, "plan")] {
                let app = launch(language: language, tab: tab)
                if tab == 2 {
                    let link = app.buttons["plan-card"].firstMatch
                    let alternative = app.otherElements["plan-card"].firstMatch
                    if link.waitForExistence(timeout: 10) { link.tap() }
                    else { XCTAssertTrue(alternative.waitForExistence(timeout: 5)); alternative.tap() }
                    XCTAssertTrue(app.otherElements["screen-plan-detail"].waitForExistence(timeout: 10))
                } else if tab == 1 {
                    XCTAssertTrue(app.otherElements["map-canvas"].waitForExistence(timeout: 15))
                    // MapKit tile availability is a separate manual/network QA gate; do not infer it from this delay.
                    Thread.sleep(forTimeInterval: 3)
                } else { XCTAssertTrue(app.otherElements["screen-today"].waitForExistence(timeout: 10)) }
                save("v3-\(screen)-\(language)-light")
                app.terminate()
            }
        }
    }
    @MainActor func testDarkScreenAndRotationContinuity() throws {
        let app = launch(language: "zh-Hans", tab: 1, theme: "dark")
        let label = app.staticTexts["selected-time"]
        XCTAssertTrue(label.waitForExistence(timeout: 15))
        let before = label.label
        save("v3-map-zh-Hans-dark-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(label.waitForExistence(timeout: 5)); XCTAssertEqual(label.label, before)
        save("v3-map-zh-Hans-dark-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(label.label, before)
        // Rotation is not a Duo fold/unfold test. Real fold transitions remain a separate gate.
    }
}
