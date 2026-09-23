import XCTest

/// Native interaction checks at the largest requested Dynamic Type category. These tests
/// exercise reachability and keyboard entry; they do not certify VoiceOver or all accessibility.
final class AccessibilityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testGermanLargestTextPlanningAndSubjectEntry() throws {
        try exerciseLargestText(language: "de", morning: "Morgens", evening: "Abends",
                                clear: "Löschen", latitudeInput: "24,5000", longitudeInput: "118,1000")
    }

    @MainActor func testThaiLargestTextPlanningAndSubjectEntry() throws {
        try exerciseLargestText(language: "th", morning: "ช่วงเช้า", evening: "ช่วงเย็น",
                                clear: "ล้าง", latitudeInput: "24.5000", longitudeInput: "118.1000")
    }

    @MainActor private func exerciseLargestText(language: String, morning: String, evening: String,
                                               clear: String, latitudeInput: String,
                                               longitudeInput: String) throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = language
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = "light"
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = "0"
        app.launchEnvironment["LIGHTPLAN_VISUAL_ARCHIVE"] = UUID().uuidString
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any)["screen-today"].firstMatch.waitForExistence(timeout: 15))
        capture("\(language)-axxxl-today-initial", in: app)

        let todayScroll = app.scrollViews.firstMatch
        XCTAssertTrue(todayScroll.waitForExistence(timeout: 10))
        let window = app.segmentedControls["today-light-window"]
        reveal(window, in: app, container: todayScroll, name: "\(language)-light-window")
        let eveningButton = window.buttons[evening]
        let morningButton = window.buttons[morning]
        XCTAssertTrue(eveningButton.isHittable)
        eveningButton.tap()
        XCTAssertTrue(eveningButton.isSelected, "The evening control must actually change the selection")
        XCTAssertFalse(morningButton.isSelected)
        capture("\(language)-axxxl-evening-selected", in: app)
        XCTAssertTrue(morningButton.isHittable)
        morningButton.tap()
        XCTAssertTrue(morningButton.isSelected, "The morning control must actually change the selection")
        XCTAssertFalse(eveningButton.isSelected)
        capture("\(language)-axxxl-morning-selected", in: app)

        let compose = app.buttons["today-start-composition"]
        reveal(compose, in: app, container: todayScroll, name: "\(language)-composition-entry")
        capture("\(language)-axxxl-composition-entry", in: app)
        compose.tap()
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["composition-card"].firstMatch.waitForExistence(timeout: 15),
                      "The Today action must open composition mode, not merely switch tabs")

        let panel = app.scrollViews.containing(.any, identifier: "composition-card").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        // Clear the deterministic example through its actual control. This creates blank fields
        // without depending on a localized Select All menu or guessing a text cursor position.
        let clearSubject = app.buttons[clear].firstMatch
        reveal(clearSubject, in: app, container: panel, name: "\(language)-clear-subject")
        clearSubject.tap()
        XCTAssertTrue(clearSubject.waitForNonExistence(timeout: 10))

        let coordinates = app.buttons["composition-subject-coordinates"]
        reveal(coordinates, in: app, container: panel, name: "\(language)-subject-entry")
        capture("\(language)-axxxl-map-subject-entry", in: app)
        coordinates.tap()

        let latitude = app.textFields["subject-latitude"]
        let longitude = app.textFields["subject-longitude"]
        XCTAssertTrue(latitude.waitForExistence(timeout: 10))
        reveal(latitude, in: app, container: app, name: "\(language)-latitude")
        latitude.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "Coordinate entry must open the keyboard")
        latitude.typeText(latitudeInput)
        XCTAssertEqual(latitude.value as? String, latitudeInput)
        let nextField = app.buttons["subject-next-field"]
        XCTAssertTrue(nextField.waitForExistence(timeout: 5)); nextField.tap()
        reveal(longitude, in: app, container: app, name: "\(language)-longitude")
        longitude.tap()
        longitude.typeText(longitudeInput)
        XCTAssertEqual(longitude.value as? String, longitudeInput)
        capture("\(language)-axxxl-subject-keyboard", in: app)
        let dismissKeyboard = app.buttons["subject-dismiss-keyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5)); dismissKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))

        let save = app.buttons["subject-save"]
        reveal(save, in: app, container: app, name: "\(language)-subject-save")
        XCTAssertTrue(save.isEnabled)
        capture("\(language)-axxxl-subject-save", in: app)
        save.tap()
        XCTAssertTrue(latitude.waitForNonExistence(timeout: 10), "Valid coordinates must save and dismiss the form")
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 10))
        capture("\(language)-axxxl-subject-saved", in: app)

        // Reopening proves that keyboard entry changed the subject, rather than only dismissing
        // the editor. The editor displays normalized coordinate strings on its next appearance.
        reveal(coordinates, in: app, container: panel, name: "\(language)-reopen-subject")
        coordinates.tap()
        XCTAssertTrue(latitude.waitForExistence(timeout: 10))
        XCTAssertEqual(latitude.value as? String, "24.5")
        XCTAssertEqual(longitude.value as? String, "118.1")
        capture("\(language)-axxxl-subject-reopened", in: app)
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                                   container: XCUIElement, name: String) {
        if element.exists && element.isHittable { return }
        // A large-text composition panel can be several screens long. Try both directions
        // because entering composition mode may initially scroll past the panel's first row.
        for direction in [1.0, -1.0] {
            for _ in 0..<24 {
                if element.exists && element.isHittable { return }
                var visible = container.frame.intersection(app.frame)
                if app.keyboards.firstMatch.exists {
                    let keyboardTop = app.keyboards.firstMatch.frame.minY
                    visible.size.height = max(0, min(visible.maxY, keyboardTop) - visible.minY)
                }
                guard !visible.isNull, visible.width > 20, visible.height > 60 else { break }
                let upper = CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.18)
                let lower = CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.65)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let start = direction > 0 ? lower : upper
                let end = direction > 0 ? upper : lower
                origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(
                        CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
            }
        }
        capture("\(name)-not-reachable", in: app)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertTrue(element.exists && element.isHittable, "Control is not reachable at the largest text size: \(name)")
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
