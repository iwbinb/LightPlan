import XCTest

/// Exercises the paid-download app with no in-app purchase session or entitlement switch.
/// App Store distribution and physical-device delivery remain separate acceptance checks.
final class ProductUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(tab: Int = 4, archiveID: String? = nil, day: Date? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = "en"
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = "light"
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = String(tab)
        if let archiveID { app.launchEnvironment["LIGHTPLAN_VISUAL_ARCHIVE"] = archiveID }
        if let day { app.launchEnvironment["LIGHTPLAN_VISUAL_DAY"] = ISO8601DateFormatter().string(from: day) }
        app.launch()
        return app
    }
    @MainActor private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 15) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let predicate = NSPredicate(format: "value == %@", value)
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }
    @MainActor private func waitUntilEnabled(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
        waitForExpectations(timeout: 15)
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if element.exists && element.isHittable { return }
        for _ in 0..<5 {
            app.swipeUp()
            if element.waitForExistence(timeout: 1), element.isHittable { return }
        }
    }
    @MainActor func testPaidDownloadHasNoPurchaseOrRestoreScreen() throws {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["membership"].exists)
        XCTAssertFalse(app.buttons["purchase-buy"].exists)
        XCTAssertFalse(app.buttons["purchase-restore"].exists)
        app.terminate()
    }
    @MainActor func testPlanEditorSavesWithoutPurchase() async throws {
        let app = launch(tab: 2)
        let create = app.buttons["plan-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let field = app.textFields["plan-title"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        // Select all through the keyboard shortcut when supported; append a unique marker otherwise.
        field.typeText(" CI")
        let save = app.buttons["plan-save"]
        reveal(save, in: app)
        waitUntilEnabled(save); save.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "plan-card").count, 2)
        app.terminate()
    }
    @MainActor func testCompositionFiltersAndUsesSelectedOpportunity() throws {
        let app = launch(tab: 1)
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        let composition = app.buttons["map-composition"]
        XCTAssertTrue(composition.waitForExistence(timeout: 10)); composition.tap()
        let search = app.buttons["composition-search"]
        revealComposition(search, in: app); search.tap()

        // A nearest daily result is not automatically a useful low-sky opportunity.
        XCTAssertTrue(app.descendants(matching: .any)["opportunity-empty"].firstMatch.waitForExistence(timeout: 25))
        let allCandidates = app.buttons["opportunity-preset-all"]
        XCTAssertTrue(allCandidates.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            if allCandidates.isHittable { break }
            app.scrollViews["opportunity-filter"].swipeLeft()
        }
        XCTAssertTrue(allCandidates.isHittable); allCandidates.tap()
        let opportunity = app.buttons.matching(identifier: "composition-opportunity").firstMatch
        XCTAssertTrue(opportunity.waitForExistence(timeout: 20))
        let expectedTime = opportunity.staticTexts["composition-opportunity-time"].label
        opportunity.tap()
        XCTAssertTrue(opportunity.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["selected-time"].label, expectedTime)

        let saveSelected = app.buttons["composition-save-plan"]
        revealComposition(saveSelected, in: app); saveSelected.tap()
        XCTAssertTrue(app.textFields["plan-title"].waitForExistence(timeout: 15))
        let selectedAnchor = app.staticTexts["plan-anchor-time"]
        reveal(selectedAnchor, in: app)
        XCTAssertEqual(app.staticTexts.matching(identifier: "plan-anchor-time").count, 1)
        XCTAssertFalse(app.images["plan-anchor-time"].exists, "The time identifier must not label a decorative glyph")
        XCTAssertEqual(selectedAnchor.label, expectedTime, "Saving must retain the chosen search result")
        app.buttons["Cancel"].firstMatch.tap()

        let stand = app.buttons["composition-use-stand"]
        revealComposition(stand, in: app); stand.tap()
        waitForValue(app.buttons["map-place-search"], "Suggested shooting position")
        XCTAssertTrue(app.buttons["composition-show-best"].waitForExistence(timeout: 15))

        app.terminate()
    }

    @MainActor private func revealComposition(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        let panel = app.scrollViews.containing(.any, identifier: "composition-card").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        // Use the visible middle of the panel; its AX frame extends behind the floating tab bar.
        let upper = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let lower = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        for _ in 0..<3 {
            if element.isHittable { return }
            upper.press(forDuration: 0.05, thenDragTo: lower)
        }
        for _ in 0..<6 {
            if element.isHittable { return }
            lower.press(forDuration: 0.05, thenDragTo: upper)
        }
        if !element.isHittable {
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "composition-action-not-hittable"; capture.lifetime = .keepAlways; add(capture)
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor func testSubjectCanBeSelectedOnTheRealMap() throws {
        let app = launch(tab: 1)
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        app.buttons["map-composition"].tap()
        let clear = app.buttons["Clear"].firstMatch
        revealComposition(clear, in: app); clear.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 5))
        let map = app.descendants(matching: .any)["map-canvas"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        // A native map gesture must produce a real subject; the deterministic fixture is cleared.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.58)).tap()
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["composition-best-time"].waitForExistence(timeout: 20))
        let coordinates = app.buttons["composition-subject-coordinates"]
        revealComposition(coordinates, in: app); coordinates.tap()
        let latitude = app.textFields["subject-latitude"]
        let longitude = app.textFields["subject-longitude"]
        XCTAssertTrue(latitude.waitForExistence(timeout: 10))
        let lat = try XCTUnwrap(Double(try XCTUnwrap(latitude.value as? String)))
        let lon = try XCTUnwrap(Double(try XCTUnwrap(longitude.value as? String)))
        XCTAssertTrue((-90...90).contains(lat) && (-180...180).contains(lon))
        XCTAssertGreaterThan(abs(lat - 24.4478) + abs(lon - 118.0679), 0.0001)
        capture("native-map-subject-coordinate", in: app)
        app.terminate()
    }

    @MainActor func testCompositionPlanAndFieldBriefSurviveRelaunch() throws {
        let app = launch(tab: 1, archiveID: UUID().uuidString)
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        let mode = app.buttons["map-composition"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10)); mode.tap()
        let moon = app.segmentedControls.buttons["Moon"].firstMatch
        revealComposition(moon, in: app); moon.tap()
        let right = app.segmentedControls.buttons["Right 10°"].firstMatch
        revealComposition(right, in: app); right.tap()
        let saveComposition = app.buttons["composition-save-plan"]
        revealComposition(saveComposition, in: app); saveComposition.tap()
        let title = app.textFields["plan-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["plan-composition-body"].firstMatch.waitForExistence(timeout: 10))
        title.tap(); title.typeText(" Persist")
        let anchor = app.staticTexts["plan-anchor-time"]
        reveal(anchor, in: app)
        XCTAssertTrue(anchor.waitForExistence(timeout: 15))
        let expectedTime = anchor.label
        let notes = app.descendants(matching: .any)["plan-notes"].firstMatch
        reveal(notes, in: app); notes.tap(); notes.typeText("Tripod and warm layers. Meet at the gate.")
        let save = app.buttons["plan-save"]
        reveal(save, in: app); waitUntilEnabled(save); save.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        dismissNotice(in: app)
        app.terminate()
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = "2"
        app.launch()
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
        XCTAssertTrue(app.staticTexts["saved-plan-notes"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["saved-plan-notes"].label, "Tripod and warm layers. Meet at the gate.")
        let savedTime = app.staticTexts["saved-composition-time"]
        XCTAssertTrue(savedTime.waitForExistence(timeout: 15))
        XCTAssertEqual(savedTime.label, expectedTime)
        XCTAssertEqual(app.staticTexts["saved-composition-body"].label, "Moon")
        XCTAssertEqual(app.staticTexts["saved-composition-offset"].label, "10.0°")
        let subject = app.staticTexts["saved-composition-subject"].label
        XCTAssertFalse(subject.isEmpty)
        let quality = app.staticTexts["saved-composition-quality"]
        reveal(quality, in: app)
        XCTAssertEqual(quality.label, "Weak alignment")
        capture("saved-composition-detail", in: app)

        app.terminate(); app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
        XCTAssertTrue(savedTime.waitForExistence(timeout: 15))
        XCTAssertEqual(savedTime.label, expectedTime)
        XCTAssertEqual(app.staticTexts["saved-composition-subject"].label, subject)
        let share = app.buttons["plan-share-brief"]
        XCTAssertTrue(share.exists)
        XCTAssertTrue(app.buttons["plan-open-maps"].exists)
        XCTAssertEqual(app.staticTexts["saved-plan-notes"].label, "Tripod and warm layers. Meet at the gate.")
        let map = app.buttons["plan-view-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10)); map.tap()
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["selected-time"].label, expectedTime)
        XCTAssertTrue(moon.isSelected)
        capture("restored-composition-map", in: app)
        revealComposition(saveComposition, in: app); saveComposition.tap()
        XCTAssertTrue(app.textFields["plan-title"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["purchase-buy"].exists)
        app.terminate()
    }

    @MainActor func testFutureCompositionReminderIsScheduledAndCanBeStopped() throws {
        let future = Date().addingTimeInterval(2 * 24 * 3600) // Fixture selects a future instant, not civil-day arithmetic.
        let app = launch(tab: 1, archiveID: UUID().uuidString, day: future)
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        let mode = app.buttons["map-composition"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10)); mode.tap()
        let saveComposition = app.buttons["composition-save-plan"]
        revealComposition(saveComposition, in: app); saveComposition.tap()
        XCTAssertTrue(app.textFields["plan-title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["plan-composition-body"].firstMatch.waitForExistence(timeout: 10))
        let save = app.buttons["plan-save"]
        reveal(save, in: app); waitUntilEnabled(save); save.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 5) {
            let labels = ["Allow", "允许", "允許", "許可", "허용", "Erlauben", "Autoriser", "อนุญาต", "Permitir"]
            let allow = labels.map { springboard.alerts.buttons[$0] }.first { $0.exists }
            try XCTUnwrap(allow).tap()
        }
        XCTAssertTrue(app.textFields["plan-title"].waitForNonExistence(timeout: 15))
        dismissNotice(in: app)
        app.terminate(); app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = "2"; app.launch()
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
        let status = app.staticTexts["plan-reminder-status"]
        reveal(status, in: app)
        expectation(for: NSPredicate(format: "label == %@", "Reminder scheduled by the system"), evaluatedWith: status)
        waitForExpectations(timeout: 15)
        capture("composition-reminder-scheduled", in: app)
        let stop = app.buttons["plan-stop-reminder"]
        reveal(stop, in: app); stop.tap()
        XCTAssertTrue(stop.waitForNonExistence(timeout: 10))
        app.terminate()
    }

    @MainActor private func dismissNotice(in app: XCUIApplication) {
        if app.alerts.firstMatch.waitForExistence(timeout: 5) { app.alerts.firstMatch.buttons.firstMatch.tap() }
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testManualLocationAcceptsCoordinatesWithoutPermission() async throws {
        // Coordinate entry must work without location permission or a store connection.
        let app = launch(tab: 3)
        let manual = app.buttons["place-manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10)); manual.tap()
        let name = app.textFields["manual-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("CI London")
        let lat = app.textFields["manual-latitude"]; lat.tap(); lat.typeText("51.5074")
        let lon = app.textFields["manual-longitude"]; lon.tap(); lon.typeText("-0.1278")
        app.buttons["manual-timezone"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Europe/London")
        let zone = app.buttons["Europe/London"]; XCTAssertTrue(zone.waitForExistence(timeout: 10)); zone.tap()
        let use = app.buttons["manual-save"]; XCTAssertTrue(use.waitForExistence(timeout: 10)); use.tap()
        let selectedTime = app.staticTexts["selected-time"]
        XCTAssertTrue(selectedTime.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "CI London").firstMatch.exists || app.staticTexts["CI London"].exists)
        app.terminate()
    }

    @MainActor func testPlacesOffersExplicitLocationAndManualChoice() throws {
        let app = launch(tab: 3)
        defer { app.terminate() }
        let locate = app.buttons["places-use-current-location"]
        let manual = app.buttons["place-manual"]
        XCTAssertTrue(locate.waitForExistence(timeout: 15))
        XCTAssertTrue(manual.exists && manual.isEnabled)
        XCTAssertTrue(locate.isEnabled)
        locate.tap()

        // The permission prompt comes from iOS only after this explicit action.
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if system.alerts.firstMatch.waitForExistence(timeout: 5) {
            let alert = system.alerts.firstMatch
            let allowed = ["Allow While Using App", "Allow Once", "允许在使用App期间", "使用App期间允许", "使用 App 期间允许", "允许一次", "允許使用App期間", "使用App期間允許", "允許一次"]
                .map { alert.buttons[$0] }.first(where: \.exists)
            XCTAssertNotNil(allowed); allowed?.tap()
        }

        // A resolved location opens the map. A denied/unavailable location keeps
        // manual entry available, and missing reverse geocoding offers time zone confirmation.
        let map = app.buttons["map-place-search"]
        let problem = app.staticTexts["Location is unavailable. You can choose a place manually."]
        let zoneProblem = app.staticTexts["The destination time zone could not be resolved. Enter coordinates and a named time zone manually."]
        let outcome = NSPredicate { _, _ in map.exists || problem.exists || zoneProblem.exists }
        let appeared = XCTNSPredicateExpectation(predicate: outcome, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 28), .completed)
        if zoneProblem.exists {
            let confirmation = app.buttons["places-location-timezone"]
            XCTAssertTrue(confirmation.exists && confirmation.isEnabled)
            confirmation.tap()
            let latitude = app.textFields["manual-latitude"]
            XCTAssertTrue(latitude.waitForExistence(timeout: 10))
            XCTAssertEqual(try XCTUnwrap(Double(latitude.value as? String ?? "")), 24.4478, accuracy: 0.001)
        } else if problem.exists {
            XCTAssertTrue(manual.exists && manual.isEnabled)
        } else {
            XCTAssertTrue(map.exists, "A successful location should open its map")
            XCTAssertNotEqual(map.value as? String, "Gulangyu · Xiamen", "The map must display the resolved current location")
        }
    }

    @MainActor func testMapLocationArrowUsesDevicePosition() throws {
        let app = launch(tab: 1)
        defer { app.terminate() }
        let mapPlace = app.buttons["map-place-search"]
        XCTAssertTrue(mapPlace.waitForExistence(timeout: 20))
        let originalPlace = try XCTUnwrap(mapPlace.value as? String)
        let locate = app.buttons["map-use-current-location"]
        XCTAssertTrue(locate.waitForExistence(timeout: 15) && locate.isHittable)
        locate.tap()

        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if system.alerts.firstMatch.waitForExistence(timeout: 5) {
            let alert = system.alerts.firstMatch
            let allowed = ["Allow While Using App", "Allow Once", "允许在使用App期间", "使用App期间允许", "使用 App 期间允许", "允许一次", "允許使用App期間", "使用App期間允許", "允許一次"]
                .map { alert.buttons[$0] }.first(where: \.exists)
            XCTAssertNotNil(allowed); allowed?.tap()
        }

        let manualLatitude = app.textFields["manual-latitude"]
        let locationUnavailable = app.staticTexts["Location is unavailable. You can choose a place manually."]
        let result = NSPredicate { _, _ in
            ((mapPlace.value as? String).map { $0 != originalPlace } ?? false)
                || manualLatitude.exists || locationUnavailable.exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: result, object: app)], timeout: 30), .completed)
        XCTAssertFalse(locationUnavailable.exists, "With a granted, known simulator location, GPS must succeed")
        if manualLatitude.exists {
            XCTAssertEqual(try XCTUnwrap(Double(manualLatitude.value as? String ?? "")), 24.4478, accuracy: 0.001)
        } else if !locationUnavailable.exists {
            XCTAssertNotEqual(mapPlace.value as? String, originalPlace,
                              "The map arrow must select the device location, not just recenter the old place")
            XCTAssertTrue(app.descendants(matching: .any)["map-user-location-dot"].firstMatch
                .waitForExistence(timeout: 10), "The GPS coordinate must appear as a separate blue location dot")
        }
        capture("map-gps-action", in: app)
    }
}
