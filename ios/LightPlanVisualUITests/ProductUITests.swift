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
        XCUIDevice.shared.orientation = .portrait
        let app = launch(tab: 1)
        defer { app.terminate() }
        let composition = waitForCompositionEntry(in: app)
        XCTAssertFalse(composition.isSelected)
        // One real tap. Do not retry the action or inject composition state when it fails.
        composition.tap()
        assertCompositionOpened(in: app)
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

    @MainActor func testMapCompositionEntryAcceptsFullHitTarget() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(tab: 1, archiveID: UUID().uuidString)
        defer { app.terminate() }
        let entry = waitForCompositionEntry(in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "map-composition").count, 1)
        XCTAssertGreaterThanOrEqual(entry.frame.width, 44)
        XCTAssertGreaterThanOrEqual(entry.frame.height, 44)
        XCTAssertFalse(entry.isSelected)
        let selectedTime = app.staticTexts["selected-time"].label
        // Inside the 44pt target, outside the drawn circle/glyph. This tests the real hit region.
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.12)).tap()
        assertCompositionOpened(in: app)
        XCTAssertEqual(app.staticTexts["selected-time"].label, selectedTime,
                       "Opening composition must not scrub the timeline")
        capture("composition-full-hit-target-opened", in: app)
    }

    @MainActor private func waitForCompositionEntry(in app: XCUIApplication) -> XCUIElement {
        let entry = app.buttons["map-composition"]
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        // Read geometry/enabled state from ONE coherent snapshot per poll. Repeated live
        // attribute queries exhausted the same 10s budget on run 65's cold simulator.
        // The final hit test stays live; no snapshot is treated as proof of hittability.
        var readiness = CompositionEntryReadiness()
        var observations: [String] = []
        let started = ProcessInfo.processInfo.systemUptime
        let ready = NSPredicate { _, _ in
            let pollStarted = ProcessInfo.processInfo.systemUptime
            do {
                guard app.state == .runningForeground else {
                    readiness.reset("application is not foreground")
                    return false
                }
                let observation = Self.compositionEntryObservation(try app.snapshot())
                let stable = readiness.observe(observation, at: ProcessInfo.processInfo.systemUptime)
                let hittable = stable && entry.isHittable
                if stable && !hittable { readiness.reset("live hit test failed") }
                if observations.count < 20 {
                    let now = ProcessInfo.processInfo.systemUptime
                    observations.append("elapsed=\(now - started) poll=\(now - pollStarted) "
                        + "frame=\(String(describing: observation?.frame)) "
                        + "stable=\(stable) hittable=\(hittable) reason=\(readiness.reason)")
                }
                return stable && hittable
            } catch {
                readiness.reset("snapshot unavailable")
                if observations.count < 20 { observations.append("snapshot error: \(error)") }
                return false
            }
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10)
        let diagnostic = XCTAttachment(string: observations.joined(separator: "\n"))
        diagnostic.name = "composition-entry-readiness-polls"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        if result != .completed { captureCompositionFailure("entry-not-ready", in: app) }
        XCTAssertEqual(result, .completed, "The composition entry must be enabled, visible and stable before a single tap")
        XCTAssertTrue(entry.isEnabled && entry.isHittable, "The stable entry must still accept the single tap")
        return entry
    }

    @MainActor private static func compositionEntryObservation(
        _ snapshot: any XCUIElementSnapshot
    ) -> CompositionEntryReadiness.Observation? {
        // A snapshot's descendants are immutable in-process attributes, not new queries.
        var pending: [any XCUIElementSnapshot] = [snapshot]
        var nodes: [any XCUIElementSnapshot] = []
        while let node = pending.popLast() {
            nodes.append(node); pending.append(contentsOf: node.children)
        }
        let entries = nodes.filter { $0.elementType == .button && $0.identifier == "map-composition" }
        guard entries.count == 1, let entry = entries.first else { return nil }
        let windows = nodes.filter { $0.elementType == .window && $0.frame.contains(entry.frame) }
        guard windows.count == 1, let window = windows.first else { return nil }
        return CompositionEntryReadiness.Observation(frame: entry.frame, viewport: window.frame,
            enabled: entry.isEnabled, tabBars: nodes.filter { $0.elementType == .tabBar }.map(\.frame))
    }

    func testCompositionReadinessRequiresTwoConsistentVisibleSamples() {
        let viewport = CGRect(x: 0, y: 0, width: 402, height: 874)
        let frame = CGRect(x: 272.5, y: 624.7, width: 44, height: 44.3)
        let bar = CGRect(x: 0, y: 791, width: 402, height: 83)
        let visible = CompositionEntryReadiness.Observation(frame: frame, viewport: viewport,
                                                          enabled: true, tabBars: [bar])
        var readiness = CompositionEntryReadiness()
        XCTAssertFalse(readiness.observe(visible, at: 7), "One slow snapshot is not stability evidence")
        XCTAssertFalse(readiness.observe(visible, at: 7.2))
        XCTAssertTrue(readiness.observe(visible, at: 7.4))
        var moved = visible; moved.frame.origin.y += 0.5
        XCTAssertFalse(readiness.observe(moved, at: 8), "A changed frame resets settling")
        XCTAssertTrue(readiness.observe(moved, at: 8.4))
        XCTAssertFalse(readiness.observe(nil, at: 9), "Missing or ambiguous snapshots fail closed")
        XCTAssertFalse(readiness.observe(moved, at: 10), "Invalid samples must reset the prior frame")
        XCTAssertTrue(readiness.observe(moved, at: 10.4))
        var invalid = visible; invalid.enabled = false
        XCTAssertFalse(readiness.observe(invalid, at: 11))
        invalid = visible; invalid.frame.origin.x = -1
        XCTAssertFalse(readiness.observe(invalid, at: 12), "Partly offscreen targets are rejected")
        invalid = visible; invalid.frame.origin.y = 780
        XCTAssertFalse(readiness.observe(invalid, at: 13), "A target behind the tab bar is rejected")
        invalid = visible; invalid.frame = .null
        XCTAssertFalse(readiness.observe(invalid, at: 14))
        invalid = visible; invalid.viewport = .zero
        XCTAssertFalse(readiness.observe(invalid, at: 15))
        invalid = visible; invalid.tabBars = []
        XCTAssertFalse(readiness.observe(invalid, at: 16), "This map entry requires a resolved tab bar")
        invalid = visible; invalid.tabBars = [.null]
        XCTAssertFalse(readiness.observe(invalid, at: 17))
        XCTAssertFalse(readiness.observe(visible, at: 18))
        XCTAssertFalse(readiness.observe(visible, at: 17), "Backwards time cannot prove stability")
        XCTAssertFalse(readiness.observe(visible, at: .nan))
    }

    @MainActor private func assertCompositionOpened(in app: XCUIApplication) {
        let entry = app.buttons["map-composition"]
        let panel = app.descendants(matching: .any)["composition-card"].firstMatch
        let opened = NSPredicate { _, _ in entry.exists && entry.isSelected && panel.exists }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: opened, object: app)], timeout: 15)
        if result != .completed { captureCompositionFailure("entry-did-not-open", in: app) }
        XCTAssertEqual(result, .completed, "A single composition tap must expose both its selected state and real panel")
    }

    @MainActor private func captureCompositionFailure(_ name: String, in app: XCUIApplication) {
        capture("composition-" + name, in: app)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "composition-" + name + "-hierarchy"; tree.lifetime = .keepAlways; add(tree)
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

/// Pure geometry/stability checks. This helper never substitutes for the live hit test.
private struct CompositionEntryReadiness {
    struct Observation: Equatable {
        var frame: CGRect
        var viewport: CGRect
        var enabled: Bool
        var tabBars: [CGRect]
    }
    private var previous: Observation?
    private var stableSince: TimeInterval?
    private(set) var reason = "no sample"

    mutating func reset(_ reason: String) {
        previous = nil; stableSince = nil; self.reason = reason
    }

    mutating func observe(_ sample: Observation?, at now: TimeInterval) -> Bool {
        guard now.isFinite, let sample, sample.enabled,
              Self.valid(sample.frame), Self.valid(sample.viewport),
              sample.viewport.contains(sample.frame), !sample.tabBars.isEmpty,
              sample.tabBars.allSatisfy({ Self.valid($0) && sample.frame.maxY <= $0.minY }) else {
            reset("missing, disabled, invalid or obscured geometry"); return false
        }
        guard previous == sample, let since = stableSince, now >= since else {
            previous = sample; stableSince = now; reason = "waiting for a second stable sample"
            return false
        }
        let ready = now - since >= 0.3
        reason = ready ? "stable geometry" : "settling"
        return ready
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isEmpty && !rect.isInfinite
            && [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
    }
}
