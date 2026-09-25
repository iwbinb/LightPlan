import XCTest

/// Real controls and persisted local plans. These do not certify physical notification
/// delivery, file-provider behavior or radio-off operation on a physical device.
final class FieldReliabilityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(tab: Int) throws -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = "en"
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = "light"
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = String(tab)
        app.launchEnvironment["LIGHTPLAN_VISUAL_ARCHIVE"] = UUID().uuidString
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let future = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: Date()))
        app.launchEnvironment["LIGHTPLAN_VISUAL_DAY"] = ISO8601DateFormatter().string(from: future)
        app.launch()
        return app
    }

    @MainActor func testManualTimeAndNotesPersistThroughSaveRelaunchAndFieldMode() throws {
        let app = try launch(tab: 1)
        defer { app.terminate() }
        let selected = app.staticTexts["selected-time"]
        XCTAssertTrue(selected.waitForExistence(timeout: 20))
        app.buttons["map-composition"].tap()
        let next = app.buttons["map-next-time"]
        reveal(next, in: app)
        let originalTime = selected.label
        next.tap()
        expectation(for: NSPredicate(format: "label != %@", originalTime), evaluatedWith: selected)
        waitForExpectations(timeout: 10)
        let chosenTime = selected.label
        let saveComposition = app.buttons["composition-save-plan"]
        reveal(saveComposition, in: app); saveComposition.tap()
        let title = app.textFields["plan-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let anchor = app.staticTexts["plan-anchor-time"]
        reveal(anchor, in: app); XCTAssertEqual(anchor.label, chosenTime)
        try setReminderEnabled(false, in: app)
        let notes = element("plan-notes", in: app)
        reveal(notes, in: app); notes.tap(); notes.typeText("M4 tripod at the north gate.")
        try saveEditor(in: app)
        relaunch(app, tab: 2)
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        let time = app.staticTexts["saved-composition-time"]
        reveal(time, in: app); XCTAssertEqual(time.label, chosenTime)
        let savedNotes = app.staticTexts["saved-plan-notes"]
        XCTAssertTrue(savedNotes.exists); XCTAssertEqual(savedNotes.label, "M4 tripod at the north gate.")
        let reminderStatus = app.staticTexts["plan-reminder-status"]
        reveal(reminderStatus, in: app)
        XCTAssertEqual(reminderStatus.label, "Reminder not configured")
        XCTAssertFalse(app.buttons["plan-stop-reminder"].exists)
        capture("m4-manual-time-and-notes-restored", in: app)
        let field = app.buttons["plan-field-mode"]
        reveal(field, in: app); field.tap()
        let status = element("field-session-status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Until planned arrival"), evaluatedWith: status)
        waitForExpectations(timeout: 20)
        let countdown = app.staticTexts["field-session-countdown"]
        reveal(countdown, in: app); XCTAssertFalse(countdown.label.isEmpty)
        capture("m4-restored-plan-field-countdown", in: app)
        app.buttons["field-session-close"].tap()
        let map = app.buttons["plan-view-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 15)); map.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 20))
        XCTAssertEqual(selected.label, chosenTime)
        capture("m4-saved-plan-restores-exact-map-time", in: app)
        relaunch(app, tab: 4)
        assertPendingCount(0, in: app)
    }

    @MainActor func testEditedReminderStaysSingleAndDuplicateDoesNotCopyIt() throws {
        let app = try launch(tab: 2)
        defer { app.terminate() }
        let create = app.buttons["plan-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20)); create.tap()
        try saveEditor(in: app, allowNotifications: true)
        relaunch(app, tab: 4); assertPendingCount(1, in: app)
        relaunch(app, tab: 2)
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        let edit = app.buttons["plan-edit"]
        reveal(edit, in: app); edit.tap()
        let title = app.textFields["plan-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap(); title.typeText(" M4 revised")
        let editedTitle = try XCTUnwrap(title.value as? String)
        let notes = element("plan-notes", in: app)
        reveal(notes, in: app); notes.tap(); notes.typeText("Keep this latest note.")
        try saveEditor(in: app, allowNotifications: true)
        let status = app.staticTexts["plan-reminder-status"]
        reveal(status, in: app)
        expectation(for: NSPredicate(format: "label == %@", "Reminder scheduled by the system"), evaluatedWith: status)
        waitForExpectations(timeout: 20)
        let duplicate = app.buttons["plan-duplicate"]
        reveal(duplicate, in: app); duplicate.tap(); dismissNotice(in: app)
        relaunch(app, tab: 4); assertPendingCount(1, in: app)
        relaunch(app, tab: 2)
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons.matching(identifier: "plan-card").count, 2)
        // Both copies keep the edited data. Exactly one may retain reminder intent.
        var configured = 0
        for index in 0..<2 {
            if index > 0 { relaunch(app, tab: 2) }
            let currentCard = app.buttons.matching(identifier: "plan-card").element(boundBy: index)
            XCTAssertTrue(currentCard.waitForExistence(timeout: 20)); currentCard.tap()
            let heading = app.staticTexts["screen-plan-detail"]
            XCTAssertTrue(heading.waitForExistence(timeout: 15)); XCTAssertEqual(heading.label, editedTitle)
            let savedNotes = app.staticTexts["saved-plan-notes"]
            XCTAssertTrue(savedNotes.waitForExistence(timeout: 20)); XCTAssertEqual(savedNotes.label, "Keep this latest note.")
            let reminderStatus = app.staticTexts["plan-reminder-status"]
            reveal(reminderStatus, in: app)
            if app.buttons["plan-stop-reminder"].exists { configured += 1 }
            else { XCTAssertEqual(reminderStatus.label, "Reminder not configured") }
            capture("m4-duplicate-\(index)-preserves-data", in: app)
        }
        XCTAssertEqual(configured, 1)
    }

    @MainActor func testDisablingSavedReminderClearsSystemQueueAndSurvivesRelaunch() throws {
        let app = try launch(tab: 2)
        defer { app.terminate() }
        let create = app.buttons["plan-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20)); create.tap()
        XCTAssertTrue(app.textFields["plan-title"].waitForExistence(timeout: 15))
        try setReminderEnabled(true, in: app)
        try saveEditor(in: app, allowNotifications: true)
        relaunch(app, tab: 4); assertPendingCount(1, in: app)

        relaunch(app, tab: 2)
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        let edit = app.buttons["plan-edit"]
        reveal(edit, in: app); edit.tap()
        XCTAssertTrue(app.textFields["plan-title"].waitForExistence(timeout: 15))
        try setReminderEnabled(false, in: app)
        try saveEditor(in: app)
        let status = app.staticTexts["plan-reminder-status"]
        reveal(status, in: app)
        XCTAssertEqual(status.label, "Reminder not configured")
        XCTAssertFalse(app.buttons["plan-stop-reminder"].exists)
        capture("m4-saved-reminder-explicitly-disabled", in: app)

        // Do not clean the system queue in the test: the normal saved edit and
        // launch reconciliation must remove it and must not recreate it.
        relaunch(app, tab: 4); assertPendingCount(0, in: app)
        capture("m4-disabled-reminder-system-queue-empty", in: app)
        relaunch(app, tab: 2)
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        XCTAssertTrue(app.staticTexts["screen-plan-detail"].waitForExistence(timeout: 15))
        reveal(status, in: app)
        XCTAssertEqual(status.label, "Reminder not configured")
        XCTAssertFalse(app.buttons["plan-stop-reminder"].exists)
    }

    @MainActor private func setReminderEnabled(_ enabled: Bool, in app: XCUIApplication) throws {
        let toggle = app.switches["plan-reminder-toggle"]
        reveal(toggle, in: app)
        XCTAssertTrue(toggle.isEnabled)
        let initialValue = try XCTUnwrap(toggle.value as? String)
        XCTAssertTrue(["0", "1"].contains(initialValue), "Unexpected native Toggle value")
        let expected = enabled ? "1" : "0"
        if initialValue != expected {
            // Run 56's recording showed a row-centre tap leaving the switch on.
            // The accessibility frame includes the label; tap the visible trailing
            // switch within that frame (this fixture is explicitly English/LTR).
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(toggle.value as? String, expected, "Verify user intent before saving")
        capture("m4-editor-reminder-" + (enabled ? "on" : "off"), in: app)
    }

    @MainActor private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }
    @MainActor private func relaunch(_ app: XCUIApplication, tab: Int) {
        app.terminate(); app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = String(tab); app.launch()
    }
    @MainActor private func dismissNotice(in app: XCUIApplication) {
        if app.alerts.firstMatch.waitForExistence(timeout: 3) { app.alerts.firstMatch.buttons.firstMatch.tap() }
    }
    @MainActor private func saveEditor(in app: XCUIApplication, allowNotifications: Bool = false) throws {
        let save = app.buttons["plan-save"]
        reveal(save, in: app)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 20)
        save.tap()
        if allowNotifications {
            let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if system.alerts.firstMatch.waitForExistence(timeout: 5) {
                let names = ["Allow", "允许", "允許", "許可", "허용", "Erlauben", "Autoriser", "อนุญาต", "Permitir"]
                try XCTUnwrap(names.map { system.alerts.buttons[$0] }.first(where: \.exists)).tap()
            }
        }
        XCTAssertTrue(app.textFields["plan-title"].waitForNonExistence(timeout: 15))
        dismissNotice(in: app)
    }

    @MainActor private func assertPendingCount(_ count: Int, in app: XCUIApplication) {
        let pending = element("settings-reminder-count", in: app)
        // This reads the actual UNUserNotificationCenter count, not a tappable
        // control. A static row need not make its enclosing iPad List hittable.
        XCTAssertTrue(pending.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "value == %@", String(count)), evaluatedWith: pending)
        waitForExpectations(timeout: 20)
    }

    @MainActor private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        var geometry: [String] = []
        for _ in 0..<24 {
            let candidates = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            let containers = candidates.filter {
                // Navigation may remove an index-bound background scroll view
                // after enumeration. Check existence before requesting geometry.
                guard $0.exists else { return false }
                let visible = $0.frame.intersection(app.frame)
                return !visible.isNull && visible.width > 120 && visible.height > 100
            }
            let owners = target.exists ? containers.filter {
                $0.exists && $0.descendants(matching: .any).matching(identifier: target.identifier).count > 0
            } : []
            let exposedForms = containers.filter {
                $0.exists && ($0.elementType == .collectionView || $0.elementType == .table)
                    && $0.buttons.allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
            }
            guard let container = owners.min(by: { $0.frame.height < $1.frame.height }) ?? exposedForms.last ?? containers.first else {
                Thread.sleep(forTimeInterval: 0.1); continue
            }
            guard container.exists else { continue }
            var viewport = container.frame.intersection(app.frame)
            for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.isHittable {
                if bar.frame.maxY > viewport.minY && bar.frame.maxY < viewport.maxY {
                    let bottom = viewport.maxY
                    viewport.origin.y = bar.frame.maxY; viewport.size.height = bottom - viewport.minY
                }
            }
            for overlay in [app.keyboards.firstMatch, app.tabBars.firstMatch, app.buttons["plan-view-map"]] where overlay.exists && overlay.isHittable {
                if overlay.frame.minY > viewport.minY && overlay.frame.minY < viewport.maxY { viewport.size.height = overlay.frame.minY - viewport.minY - 12 }
            }
            viewport = viewport.insetBy(dx: 2, dy: 4)
            guard viewport.height > 80, !viewport.isNull else { continue }
            let frame = target.exists ? target.frame : .zero
            geometry.append("viewport=\(viewport), target=\(frame)")
            if target.exists && target.isHittable && viewport.contains(frame) { return }
            let hasFrame = target.exists && frame.height > 0
            let above = hasFrame && frame.midY < viewport.midY
            let distance = min(viewport.height * 0.65, max(28, hasFrame ? abs(frame.midY - viewport.midY) : viewport.height * 0.65))
            let center = viewport.minY + viewport.height * 0.48
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let top = origin.withOffset(CGVector(dx: viewport.minX + 8 - app.frame.minX, dy: center - distance / 2 - app.frame.minY))
            let bottom = origin.withOffset(CGVector(dx: viewport.minX + 8 - app.frame.minX, dy: center + distance / 2 - app.frame.minY))
            (above ? top : bottom).press(forDuration: 0.05, thenDragTo: above ? bottom : top, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        capture("m4-control-unreachable", in: app)
        let diagnostic = XCTAttachment(string: geometry.joined(separator: "\n") + "\n" + app.debugDescription)
        diagnostic.name = "m4-unreachable-geometry"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTFail("Control must be visible and hittable: " + target.identifier)
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
