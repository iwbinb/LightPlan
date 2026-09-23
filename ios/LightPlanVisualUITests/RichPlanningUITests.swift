import XCTest

/// End-to-end persistence and editing checks for the paid-download planning tools.
/// These inspect real native controls; store sales and physical lock-screen delivery
/// are deliberately outside this simulator suite's evidence boundary.
final class RichPlanningUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(tab: Int, future: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = "en"
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = "light"
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = String(tab)
        app.launchEnvironment["LIGHTPLAN_VISUAL_ARCHIVE"] = UUID().uuidString
        if future {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
            let date = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
            app.launchEnvironment["LIGHTPLAN_VISUAL_DAY"] = ISO8601DateFormatter().string(from: date)
        }
        app.launch()
        return app
    }

    @MainActor func testFramingAndProjectSurviveSaveEditRelaunchAndMapRestore() throws {
        let app = launch(tab: 1)
        defer { app.terminate() }
        try enterComposition(in: app)
        let preview = app.buttons["composition-preview"]
        revealComposition(preview, in: app); preview.tap()
        let focal = app.textFields["frame-focal-length"]
        reveal(focal, in: app)
        let preset = app.buttons["frame-focal-200"]
        if !preset.isHittable {
            let strips = app.scrollViews.containing(.button, identifier: "frame-focal-200").allElementsBoundByIndex
            let strip = try XCTUnwrap(strips.filter { $0.frame.height > 0 }.min(by: { $0.frame.height < $1.frame.height }))
            for _ in 0..<3 where !preset.isHittable { strip.swipeLeft() }
        }
        XCTAssertTrue(preset.isHittable); preset.tap()
        XCTAssertEqual(focal.value as? String, "200")
        let portrait = app.segmentedControls.buttons["Portrait"].firstMatch
        reveal(portrait, in: app); portrait.tap()
        XCTAssertTrue(portrait.isSelected)
        let slider = app.sliders["frame-reference-slider"]
        reveal(slider, in: app); slider.adjust(toNormalizedSliderPosition: 2.0 / 3.0)
        let angleField = app.textFields["frame-reference-angle"]
        let angle = try XCTUnwrap(Double(try XCTUnwrap(angleField.value as? String)))
        XCTAssertTrue((-30...60).contains(angle) && angle != 0, "The slider must select a valid nondefault angle; persistence checks below use the actual selected value")
        let angleText = String(format: "%.1f°", angle)
        capture("framing-editor-200mm-portrait", in: app)
        app.buttons["frame-apply"].tap()
        XCTAssertTrue(focal.waitForNonExistence(timeout: 10))

        let saveComposition = app.buttons["composition-save-plan"]
        revealComposition(saveComposition, in: app); saveComposition.tap()
        let title = app.textFields["plan-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        let collection = app.textFields["plan-collection"]
        collection.tap(); collection.typeText("Coastal framing trip")
        let reminder = app.switches["plan-reminder-toggle"]
        reveal(reminder, in: app)
        if reminder.value as? String == "1" { reminder.tap() }
        try saveEditor(in: app)

        relaunch(app, tab: 2)
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Coastal framing trip"].exists)
        card.tap()
        assertSavedFraming(angleText: angleText, in: app)
        capture("saved-framing-with-project", in: app)

        let edit = app.buttons["plan-edit"]
        reveal(edit, in: app); edit.tap()
        XCTAssertEqual(app.textFields["plan-collection"].value as? String, "Coastal framing trip")
        let notes = element("plan-notes", in: app)
        reveal(notes, in: app); notes.tap(); notes.typeText("Bring the long lens and meet at the north gate.")
        try saveEditor(in: app)
        assertSavedFraming(angleText: angleText, in: app)
        let savedNotes = app.staticTexts["saved-plan-notes"]
        XCTAssertTrue(savedNotes.exists)
        XCTAssertEqual(savedNotes.label, "Bring the long lens and meet at the north gate.")
        let map = app.buttons["plan-view-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10)); map.tap()
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        let restoredInstant = app.staticTexts["selected-time"].label
        let summary = app.staticTexts["composition-framing-summary"]
        revealComposition(summary, in: app)
        XCTAssertEqual(app.staticTexts["selected-time"].label, restoredInstant, "Scrolling to the saved framing must not scrub its restored time")
        XCTAssertTrue(summary.label.contains("200 mm"))
        XCTAssertTrue(summary.label.contains("Portrait"))
        XCTAssertTrue(summary.label.contains(angleText))
        capture("saved-framing-restored-on-map", in: app)
        let search = app.buttons["composition-search"]
        revealComposition(search, in: app)
        XCTAssertEqual(app.staticTexts["selected-time"].label, restoredInstant, "Scrolling to search must preserve the exact restored plan time")
        search.tap()
        let all = app.buttons["opportunity-preset-all"]
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        XCTAssertTrue(all.isSelected, "An unrestricted saved plan must reopen All candidates instead of silently adopting low-sky defaults")
        capture("saved-unrestricted-search-restored", in: app)
    }

    @MainActor func testProjectSearchFieldCompletionAndReopenSurviveRelaunch() throws {
        let app = launch(tab: 2, future: true)
        defer { app.terminate() }
        let create = app.buttons["plan-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 15)); create.tap()
        let collection = app.textFields["plan-collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 15)); collection.tap(); collection.typeText("Coastal weekend")
        let notes = element("plan-notes", in: app)
        reveal(notes, in: app); notes.tap(); notes.typeText("Tripod by the northern gate.")
        try saveEditor(in: app, allowNotifications: true)
        relaunch(app, tab: 4)
        assertPendingCount(1, in: app)
        relaunch(app, tab: 2)
        let search = app.textFields["plan-library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "Tapping the library search bar must focus its input")
        search.typeText("Coastal weekend\n")
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "plan-card").count, 1)
        capture("plan-library-project-search", in: app)
        card.tap()
        let reminderStatus = app.staticTexts["plan-reminder-status"]
        reveal(reminderStatus, in: app)
        waitForLabel(reminderStatus, equals: "Reminder scheduled by the system")
        let field = app.buttons["plan-field-mode"]
        reveal(field, in: app); field.tap()
        let fieldStatus = app.descendants(matching: .any)["field-session-status"].firstMatch
        waitForLabel(fieldStatus, contains: "Until planned arrival")
        XCTAssertTrue(app.staticTexts["field-session-countdown"].exists)
        capture("field-session-countdown-and-brief", in: app)
        let complete = app.buttons["field-session-complete"]
        reveal(complete, in: app); complete.tap(); dismissNotice(in: app)
        reveal(fieldStatus, in: app); waitForLabel(fieldStatus, contains: "Plan completed")
        capture("field-session-completed", in: app)

        relaunch(app, tab: 4)
        assertPendingCount(0, in: app)
        capture("completed-plan-system-notification-queue-empty", in: app)
        relaunch(app, tab: 2)
        tapFilter("completed", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
        reveal(reminderStatus, in: app)
        waitForLabel(reminderStatus, equals: "Reminder not configured")
        XCTAssertFalse(app.buttons["plan-stop-reminder"].exists)
        let edit = app.buttons["plan-edit"]
        reveal(edit, in: app); edit.tap()
        let reminder = app.switches["plan-reminder-toggle"]
        reveal(reminder, in: app)
        XCTAssertEqual(reminder.value as? String, "0")
        XCTAssertFalse(reminder.isEnabled)
        app.buttons["Cancel"].firstMatch.tap()
        let reopen = app.buttons["plan-toggle-completed"]
        reveal(reopen, in: app); reopen.tap(); dismissNotice(in: app)
        relaunch(app, tab: 4)
        assertPendingCount(0, in: app)
        relaunch(app, tab: 2)
        tapFilter("completed", in: app)
        XCTAssertTrue(element("plan-library-empty-results", in: app).waitForExistence(timeout: 15))
        tapFilter("upcoming", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
        reveal(reminderStatus, in: app)
        waitForLabel(reminderStatus, equals: "Reminder not configured")
        XCTAssertFalse(app.buttons["plan-stop-reminder"].exists)
        capture("reopened-plan-keeps-reminders-off", in: app)
    }

    @MainActor func testMoonSearchOptionsApplyAndCancelPreserveResultWindows() throws {
        let app = launch(tab: 1)
        defer { app.terminate() }
        try enterComposition(in: app)
        let moon = app.segmentedControls.buttons["Moon"].firstMatch
        revealComposition(moon, in: app); moon.tap()
        let search = app.buttons["composition-search"]
        revealComposition(search, in: app); search.tap()
        let all = app.buttons["opportunity-preset-all"]
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        for _ in 0..<3 {
            if all.isHittable { break }
            app.scrollViews["opportunity-filter"].swipeLeft()
        }
        XCTAssertTrue(all.isHittable); all.tap()
        let options = app.buttons["opportunity-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 10)); options.tap()
        try chooseMenu("opportunity-days-presets", value: "30", in: app)
        app.buttons["opportunity-apply-options"].tap()
        let days = app.staticTexts["opportunity-searched-days"]
        waitForLabel(days, contains: "30", timeout: 120)
        let range = app.staticTexts["opportunity-searched-range"]
        let previousRange = range.label
        let opportunity = app.buttons.matching(identifier: "composition-opportunity").firstMatch
        XCTAssertTrue(opportunity.waitForExistence(timeout: 20))
        let time = opportunity.staticTexts["composition-opportunity-time"].label
        let duration = opportunity.staticTexts["opportunity-window-duration"]
        XCTAssertFalse(duration.label.isEmpty)
        XCTAssertTrue(opportunity.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Shooting window:", "UTC")).firstMatch.exists)
        reveal(duration, in: app)
        capture("moon-search-30-day-window", in: app)

        options.tap()
        try chooseMenu("opportunity-days-presets", value: "90", in: app)
        try chooseMenu("opportunity-moon-condition", value: "Bright Moon · 80–100%", in: app)
        app.buttons["Cancel"].firstMatch.tap()
        waitForLabel(days, contains: "30")
        XCTAssertEqual(range.label, previousRange)
        XCTAssertEqual(opportunity.staticTexts["composition-opportunity-time"].label, time)
        XCTAssertFalse(element("opportunity-search-busy", in: app).exists)

        options.tap()
        try chooseMenu("opportunity-days-presets", value: "90", in: app)
        try chooseMenu("opportunity-moon-condition", value: "Bright Moon · 80–100%", in: app)
        app.buttons["opportunity-apply-options"].tap()
        waitForLabel(days, contains: "90", timeout: 180)
        XCTAssertNotEqual(range.label, previousRange)
        XCTAssertTrue(opportunity.waitForExistence(timeout: 20))
        XCTAssertFalse(opportunity.staticTexts["opportunity-window-duration"].label.isEmpty)
        let illuminated = opportunity.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Illuminated:")).firstMatch
        XCTAssertTrue(illuminated.exists)
        let percent = try XCTUnwrap(Double(illuminated.label.filter { $0.isNumber || $0 == "." }))
        XCTAssertTrue((80...100).contains(percent), "The applied bright-Moon condition must affect results")
        capture("moon-search-90-day-bright-phase", in: app)
        options.tap()
        let moonCondition = element("opportunity-moon-condition", in: app)
        reveal(moonCondition, in: app)
        XCTAssertTrue(accessibleText(moonCondition).contains("Bright Moon"))
        app.buttons["Cancel"].firstMatch.tap()
    }

    @MainActor func testMoonTemplateReplacesPreviouslySelectedDarkMoonConditions() throws {
        let app = launch(tab: 1)
        defer { app.terminate() }
        try enterComposition(in: app)
        let moon = app.segmentedControls.buttons["Moon"].firstMatch
        revealComposition(moon, in: app); moon.tap()
        let search = app.buttons["composition-search"]
        revealComposition(search, in: app); search.tap()
        let all = app.buttons["opportunity-preset-all"]
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        for _ in 0..<3 {
            if all.isHittable { break }
            app.scrollViews["opportunity-filter"].swipeLeft()
        }
        XCTAssertTrue(all.isHittable); all.tap()
        let options = app.buttons["opportunity-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 10)); options.tap()
        try chooseMenu("opportunity-days-presets", value: "30", in: app)
        try chooseMenu("opportunity-moon-condition", value: "Dark Moon · 0–20%", in: app)
        app.buttons["opportunity-apply-options"].tap()
        let days = app.staticTexts["opportunity-searched-days"]
        waitForLabel(days, contains: "30", timeout: 120)
        let conditions = app.staticTexts["opportunity-conditions-summary"]
        XCTAssertTrue(conditions.waitForExistence(timeout: 15))
        XCTAssertTrue(conditions.label.contains("0–20%"))
        let opportunity = app.buttons.matching(identifier: "composition-opportunity").firstMatch
        XCTAssertTrue(opportunity.waitForExistence(timeout: 20))
        reveal(opportunity, in: app)
        capture("selected-dark-moon-search-before-template", in: app)
        opportunity.tap()
        XCTAssertTrue(options.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))

        let today = app.tabBars.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 10)); today.tap()
        let template = app.buttons["today-template-moon"]
        revealTodayTemplate(template, in: app)
        XCTAssertTrue(template.exists)
        // A control must be visibly above the floating tabs before synthesizing its tap.
        let tabs = app.tabBars.firstMatch
        if tabs.frame.minY > app.frame.midY {
            for _ in 0..<4 {
                if template.frame.maxY < tabs.frame.minY - 12 { break }
                drag(in: app, upward: true)
            }
            XCTAssertLessThan(template.frame.maxY, tabs.frame.minY - 12)
        }
        XCTAssertTrue(template.isHittable)
        template.tap()
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 15))
        XCTAssertTrue(moon.isSelected, "The Moon task must retain the Moon body after replacing the previous search")
        revealComposition(search, in: app); search.tap()
        XCTAssertTrue(conditions.waitForExistence(timeout: 15))
        XCTAssertTrue(conditions.label.contains("80–100%"), "The fresh template must replace a previously selected dark-Moon filter")
        XCTAssertFalse(conditions.label.contains("0–20%"))
        waitForLabel(days, equals: "Days searched: 30", timeout: 120)
        capture("moon-template-bright-conditions-30-days", in: app)
    }

    @MainActor func testTodayPullToRefreshAndQuickTabSwitchPreserveSummary() throws {
        let app = launch(tab: 0)
        defer { app.terminate() }
        let lightWindow = app.segmentedControls["today-light-window"]
        XCTAssertTrue(lightWindow.waitForExistence(timeout: 20), "The initial destination-day summary must load")
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        // Exercise the real refreshable gesture at the top of Today, then immediately
        // leave and return. No direct model call or mocked refresh result is involved.
        let upper = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.18))
        let lower = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.68))
        upper.press(forDuration: 0.05, thenDragTo: lower)
        app.tabBars.buttons["Map"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(lightWindow.waitForExistence(timeout: 20), "Cancelling a view task must not leave the app's current-day summary blank")
        let template = app.buttons["today-template-moon"]
        revealTodayTemplate(template, in: app)
        XCTAssertTrue(template.exists && template.isHittable)
        capture("today-summary-after-native-refresh-and-tab-switch", in: app)
        template.tap()
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.segmentedControls.buttons["Moon"].firstMatch.isSelected)
        XCTAssertTrue(element("composition-card", in: app).exists)
        capture("moon-planner-after-native-today-refresh", in: app)
    }

    @MainActor func testMapTimelineVerticalScrollPreservesTimeAndHorizontalScrubChangesIt() throws {
        let app = launch(tab: 1)
        defer { app.terminate() }
        let selected = app.staticTexts["selected-time"]
        XCTAssertTrue(selected.waitForExistence(timeout: 20))
        let timeline = element("solar-timeline", in: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 15))
        XCTAssertTrue(timeline.isHittable)
        let initial = selected.label
        // Begin inside the chart and move vertically through the surrounding panel.
        // The old minimum-distance-zero scrub changed the time at the starting x.
        let chartCenter = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        chartCenter.press(forDuration: 0.05, thenDragTo: chartCenter.withOffset(CGVector(dx: 0, dy: 85)))
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertEqual(selected.label, initial, "A vertical chart gesture belongs to scrolling, not time selection")
        capture("map-timeline-vertical-scroll-keeps-time", in: app)

        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        XCTAssertTrue(timeline.isHittable)
        let left = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25))
        let right = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.25))
        left.press(forDuration: 0.05, thenDragTo: right)
        expectation(for: NSPredicate(format: "label != %@", initial), evaluatedWith: selected)
        waitForExpectations(timeout: 15)
        let scrubbed = selected.label
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        expectation(for: NSPredicate(format: "label != %@", scrubbed), evaluatedWith: selected)
        waitForExpectations(timeout: 15)
        capture("map-timeline-horizontal-scrub-and-tap-select-time", in: app)
    }

    @MainActor private func enterComposition(in app: XCUIApplication) throws {
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 20))
        let mode = app.buttons["map-composition"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15)); mode.tap()
    }

    @MainActor private func assertSavedFraming(angleText: String, in app: XCUIApplication) {
        let diagram = element("framing-diagram", in: app)
        reveal(diagram, in: app)
        XCTAssertTrue(diagram.exists)
        let focal = element("frame-focal-summary", in: app)
        reveal(focal, in: app)
        XCTAssertTrue(accessibleText(focal).contains("200 mm"))
        let angle = element("frame-angle-summary", in: app)
        XCTAssertTrue(accessibleText(angle).contains(angleText))
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

    @MainActor private func chooseMenu(_ id: String, value: String, in app: XCUIApplication) throws {
        let menu = element(id, in: app)
        reveal(menu, in: app); menu.tap()
        let option = app.buttons[value].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10)); option.tap()
    }

    @MainActor private func assertPendingCount(_ count: Int, in app: XCUIApplication) {
        let pending = element("settings-reminder-count", in: app)
        // This reads the actual UNUserNotificationCenter count, not a tappable
        // control. A static row need not make its enclosing iPad List hittable.
        XCTAssertTrue(pending.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "value == %@", String(count)), evaluatedWith: pending)
        waitForExpectations(timeout: 20)
    }

    @MainActor private func tapFilter(_ name: String, in app: XCUIApplication) {
        let button = app.buttons["plan-library-filter-" + name]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        if !button.isHittable {
            let strips = app.scrollViews.containing(.button, identifier: button.identifier).allElementsBoundByIndex
            if let strip = strips.filter({ $0.frame.height > 0 }).min(by: { $0.frame.height < $1.frame.height }) {
                strip.swipeLeft()
            }
        }
        XCTAssertTrue(button.isHittable); button.tap()
    }

    @MainActor private func revealComposition(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        let panel = app.scrollViews.containing(.any, identifier: "composition-card").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let upper = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let lower = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        for _ in 0..<4 {
            if element.isHittable { return }
            upper.press(forDuration: 0.05, thenDragTo: lower)
        }
        for _ in 0..<9 {
            if element.isHittable { return }
            lower.press(forDuration: 0.05, thenDragTo: upper)
        }
        capture("rich-composition-action-unreachable", in: app)
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            guard let container = activeScroll(for: element, in: app) else { break }
            let visible = scrollViewport(container, in: app)
            guard !visible.isNull, visible.width > 60, visible.height > 80 else { break }
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            if exists && element.isHittable {
                let fits = frame.height <= visible.height && frame.width <= visible.width
                if fits ? visible.contains(frame) : visible.intersects(frame) { return }
            }
            // Missing lazy Form rows are below the current viewport. Do not begin
            // with a downward finger drag that can dismiss a sheet or refresh Today.
            let targetAbove = exists && frame.height > 0 && frame.minY < visible.minY
            let maximum = visible.height * 0.4
            let overflow = targetAbove ? visible.minY - frame.minY : frame.maxY - visible.maxY
            let distance = exists ? min(maximum, max(20, overflow + 10)) : maximum
            let center = visible.minY + visible.height * 0.48
            let top = CGPoint(x: visible.midX, y: center - distance / 2)
            let bottom = CGPoint(x: visible.midX, y: center + distance / 2)
            let start = targetAbove ? top : bottom, end = targetAbove ? bottom : top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(
                    CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
        }
        capture("rich-control-unreachable-" + (element.exists ? element.identifier : "missing-element"), in: app)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "rich-control-unreachable-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTFail("The requested control must be reachable inside its visible scroll container")
    }

    @MainActor private func activeScroll(for target: XCUIElement, in app: XCUIApplication) -> XCUIElement? {
        func eligible(_ candidates: [XCUIElement]) -> [XCUIElement] {
            candidates.filter {
                $0.exists && $0.frame.width > 120 && $0.frame.height > 120 && $0.isHittable
            }.sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        }
        if target.exists {
            let id = target.identifier
            if !id.isEmpty {
                let ancestors = app.collectionViews.containing(.any, identifier: id).allElementsBoundByIndex
                    + app.tables.containing(.any, identifier: id).allElementsBoundByIndex
                    + app.scrollViews.containing(.any, identifier: id).allElementsBoundByIndex
                if let parent = eligible(ancestors).first { return parent }
            }
        }
        // Forms may lazily omit an offscreen target. Prefer the exposed modal-sized
        // collection/table/scroll view; dimmed background containers are not hittable.
        let candidates = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            + app.scrollViews.allElementsBoundByIndex
        return eligible(candidates).first
    }

    @MainActor private func scrollViewport(_ container: XCUIElement, in app: XCUIApplication) -> CGRect {
        var rect = container.frame.intersection(app.frame)
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.isHittable {
            if bar.frame.intersects(rect), bar.frame.maxY > rect.minY, bar.frame.maxY < rect.maxY {
                let bottom = rect.maxY
                rect.origin.y = bar.frame.maxY; rect.size.height = bottom - rect.minY
            }
        }
        if app.keyboards.firstMatch.exists {
            let keyboard = app.keyboards.firstMatch.frame
            if keyboard.minX < rect.midX, keyboard.maxX > rect.midX {
                rect.size.height = max(0, min(rect.maxY, keyboard.minY) - rect.minY)
            }
        }
        for overlay in [app.buttons["plan-view-map"], app.tabBars.firstMatch] where overlay.exists && overlay.isHittable {
            let top = overlay.frame.minY - 12
            if top > rect.minY, top < rect.maxY { rect.size.height = top - rect.minY }
        }
        return rect.insetBy(dx: 2, dy: 4)
    }

    @MainActor private func revealTodayTemplate(_ template: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        for _ in 0..<18 {
            var visible = scroll.frame.intersection(app.frame)
            let tabs = app.tabBars.firstMatch
            if tabs.exists, tabs.frame.minY > visible.midY {
                visible.size.height = max(0, tabs.frame.minY - 12 - visible.minY)
            }
            guard !visible.isNull, visible.height > 100 else { break }
            // Check existence before every snapshot-dependent property. The template
            // can be absent from the accessibility tree until it enters the viewport.
            if template.exists && template.isHittable && visible.contains(template.frame) { return }
            // The guide sits below the Today hero. Move down through its content only;
            // a preliminary downward finger drag would instead trigger pull-to-refresh.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let top = CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.28)
            let bottom = CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.64)
            origin.withOffset(CGVector(dx: bottom.x - app.frame.minX, dy: bottom.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(
                    CGVector(dx: top.x - app.frame.minX, dy: top.y - app.frame.minY)))
        }
        capture("rich-today-moon-template-unreachable", in: app)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "rich-today-moon-template-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTFail("The Moon template must be reachable by scrolling down through Today")
    }

    @MainActor private func drag(in app: XCUIApplication, upward: Bool) {
        // The middle of the app's visible frame avoids both floating tabs and sheet edges.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.3))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.67))
        (upward ? bottom : top).press(forDuration: 0.05, thenDragTo: upward ? top : bottom)
    }

    @MainActor private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor private func accessibleText(_ element: XCUIElement) -> String {
        ([element.label, element.value as? String ?? ""] + element.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
    }

    @MainActor private func waitForLabel(_ element: XCUIElement, equals value: String, timeout: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        expectation(for: NSPredicate(format: "label == %@", value), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    @MainActor private func waitForLabel(_ element: XCUIElement, contains value: String, timeout: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        expectation(for: NSPredicate(format: "label CONTAINS %@", value), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    @MainActor private func relaunch(_ app: XCUIApplication, tab: Int) {
        app.terminate(); app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = String(tab); app.launch()
    }

    @MainActor private func dismissNotice(in app: XCUIApplication) {
        if app.alerts.firstMatch.waitForExistence(timeout: 3) { app.alerts.firstMatch.buttons.firstMatch.tap() }
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
