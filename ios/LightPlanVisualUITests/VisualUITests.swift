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
                    let detail = app.descendants(matching: .any)["screen-plan-detail"].firstMatch
                    XCTAssertTrue(detail.waitForExistence(timeout: 10))
                } else if tab == 1 {
                    let selectedTime = app.staticTexts["selected-time"]
                    XCTAssertTrue(selectedTime.waitForExistence(timeout: 15))
                    // MapKit tile availability is a separate manual/network QA gate; do not infer it from this delay.
                    Thread.sleep(forTimeInterval: 3)
                } else {
                    let today = app.descendants(matching: .any)["screen-today"].firstMatch
                    XCTAssertTrue(today.waitForExistence(timeout: 10))
                }
                save("v3-\(screen)-\(language)-light")
                app.terminate()
            }
        }
    }
    @MainActor func testCompositionPlannerSurface() throws {
        let app = launch(language: "en", tab: 1)
        let selectedTime = app.staticTexts["selected-time"]
        XCTAssertTrue(selectedTime.waitForExistence(timeout: 15))
        let composition = app.buttons["map-composition"]
        XCTAssertTrue(composition.waitForExistence(timeout: 10))
        XCTAssertTrue(composition.isHittable)
        composition.tap()
        let card = app.descendants(matching: .any)["composition-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["composition-search"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["composition-best-time"].waitForExistence(timeout: 15))
        save("composition-planner-en")
        app.terminate()
    }

    @MainActor func testDarkScreenAndRotationContinuity() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "zh-Hans", tab: 1, theme: "dark")
        let label = app.staticTexts["selected-time"]
        XCTAssertTrue(label.waitForExistence(timeout: 15))
        let before = label.label
        save("v3-map-zh-Hans-dark-portrait")
        assertMapControls(in: app, orientation: "portrait")
        XCTAssertEqual(label.label, before)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(label.waitForExistence(timeout: 5)); XCTAssertEqual(label.label, before)
        // Time surviving rotation alone does not prove the controls remain usable.
        save("v3-map-zh-Hans-dark-landscape")
        assertMapControls(in: app, orientation: "landscape")
        XCTAssertEqual(label.label, before)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(label.label, before)
        // Rotation is not a Duo fold/unfold test. Real fold transitions remain a separate gate.
    }

    @MainActor func testMapBaseStyleSwitchesAndSurvivesRelaunch() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "zh-Hans", tab: 1)
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        let style = app.buttons.matching(identifier: "map-style").firstMatch
        XCTAssertTrue(style.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "map-style").count, 1)
        let original = try XCTUnwrap(style.value as? String)
        XCTAssertTrue(["卫星影像", "普通地图"].contains(original))
        XCTAssertTrue(style.isEnabled && style.isHittable)
        save("map-style-before")
        style.tap() // One real action, never a retry to manufacture a passing state.
        let changed = original == "卫星影像" ? "普通地图" : "卫星影像"
        let after = waitForMapStyle(changed, in: app, phase: "after-toggle")
        XCTAssertEqual(after?.buttonValue, changed)
        XCTAssertEqual(after?.canvasValue, changed,
                       "The native map's actual tile configuration must match the button")
        save("map-style-after")
        app.terminate(); app.launch()
        XCTAssertTrue(style.waitForExistence(timeout: 15))
        let restored = waitForMapStyle(changed, in: app, phase: "after-relaunch")
        XCTAssertEqual(restored?.buttonValue, changed, "The selected base map must survive reopening the app")
        XCTAssertEqual(restored?.canvasValue, changed, "The restored native map must use the saved configuration")
        XCTAssertTrue(style.isEnabled && style.isHittable)
        style.tap()
        let reverted = waitForMapStyle(original, in: app, phase: "after-revert")
        XCTAssertEqual(reverted?.buttonValue, original)
        XCTAssertEqual(reverted?.canvasValue, original)
    }

    @MainActor private func waitForMapStyle(
        _ expected: String, in app: XCUIApplication, phase: String
    ) -> MapStyleObservation? {
        // A live value predicate re-resolves its query while MapKit updates its AX
        // hierarchy. Read both values once per poll from the same public snapshot.
        // This validates actual mapType feedback, NOT network tile availability.
        var latest: MapStyleObservation?
        var polls: [String] = []
        let started = ProcessInfo.processInfo.systemUptime
        let ready = NSPredicate { _, _ in
            let pollStarted = ProcessInfo.processInfo.systemUptime
            do {
                var pending: [any XCUIElementSnapshot] = [try app.snapshot()]
                var buttons: [any XCUIElementSnapshot] = []
                var canvases: [any XCUIElementSnapshot] = []
                while let node = pending.popLast() {
                    if node.elementType == .button && node.identifier == "map-style" { buttons.append(node) }
                    if node.identifier == "map-canvas" { canvases.append(node) }
                    pending.append(contentsOf: node.children)
                }
                latest = MapStyleObservation(buttonCount: buttons.count, canvasCount: canvases.count,
                    buttonValue: buttons.first?.value as? String, canvasValue: canvases.first?.value as? String)
            } catch {
                latest = nil
            }
            if polls.count < 20 {
                let now = ProcessInfo.processInfo.systemUptime
                polls.append("elapsed=\(now - started) poll=\(now - pollStarted) values=\(String(describing: latest))")
            }
            return latest?.matches(expected) == true
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10)
        let diagnostic = XCTAttachment(string: polls.joined(separator: "\n"))
        diagnostic.name = "map-style-" + phase + "-polls"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        if result != .completed {
            save("map-style-" + phase + "-failed")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "map-style-" + phase + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertEqual(result, .completed, "Both the unique style button and native map must report " + expected)
        return latest
    }

    func testMapStyleObservationRequiresMatchingUniqueNativeValues() {
        let valid = MapStyleObservation(buttonCount: 1, canvasCount: 1,
            buttonValue: "普通地图", canvasValue: "普通地图")
        XCTAssertTrue(valid.matches("普通地图"))
        XCTAssertFalse(valid.matches("卫星影像"))
        for counts in [(0, 1), (1, 0), (2, 1), (1, 2)] {
            XCTAssertFalse(MapStyleObservation(buttonCount: counts.0, canvasCount: counts.1,
                buttonValue: "普通地图", canvasValue: "普通地图").matches("普通地图"))
        }
        for values: (String?, String?) in [(nil, "普通地图"), ("普通地图", nil),
                                           ("普通地图", "卫星影像"), ("卫星影像", "普通地图")] {
            XCTAssertFalse(MapStyleObservation(buttonCount: 1, canvasCount: 1,
                buttonValue: values.0, canvasValue: values.1).matches("普通地图"))
        }
        XCTAssertFalse(MapStyleObservation(buttonCount: 1, canvasCount: 1,
            buttonValue: "", canvasValue: "").matches(""))
    }

    @MainActor func testLongPressLocationControlCanRecenterShootingPlace() throws {
        let app = launch(language: "zh-Hans", tab: 1)
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        let location = app.buttons["map-use-current-location"]
        XCTAssertTrue(location.waitForExistence(timeout: 10) && location.isHittable)
        location.press(forDuration: 1.2)
        let recenter = app.buttons["map-recenter"]
        XCTAssertTrue(recenter.waitForExistence(timeout: 10), "Recenter remains available as a secondary action")
        recenter.tap()
        XCTAssertTrue(app.staticTexts["selected-time"].exists)
    }

    @MainActor private func assertMapControls(in app: XCUIApplication, orientation: String) {
        for identifier in ["map-style", "map-use-current-location", "map-favorite"] {
            let control = app.buttons[identifier]
            let exists = control.waitForExistence(timeout: 5)
            if !exists {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "missing-\(identifier)-hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertTrue(exists, "Missing \(orientation) control: \(identifier)")
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: control)
            XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 10), .completed,
                           "\(orientation) control is not hittable: \(identifier)")
        }
        app.buttons["map-style"].tap()
        app.buttons["map-style"].tap()
    }
}

/// Pure assertion input: an icon change alone must never prove a native map change.
private struct MapStyleObservation {
    let buttonCount: Int
    let canvasCount: Int
    let buttonValue: String?
    let canvasValue: String?

    func matches(_ expected: String) -> Bool {
        !expected.isEmpty && buttonCount == 1 && canvasCount == 1
            && buttonValue == expected && canvasValue == expected
    }
}
