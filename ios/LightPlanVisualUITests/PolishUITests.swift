import XCTest

/// Native layout and latest-query regressions. Inputs are opt-in DEBUG fixtures;
/// results, gestures and plans are real app paths, not substituted screenshots.
final class PolishUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testGermanLargestTextReadingAndEarlyFieldAction() throws {
        try largeText(language: "de", fieldTitle: "Vor Ort fotografieren", frameTitle: "Bildvorschau")
    }

    @MainActor func testThaiLargestTextReadingAndEarlyFieldAction() throws {
        try largeText(language: "th", fieldTitle: "การถ่ายภาพภาคสนาม", frameTitle: "ตัวอย่างองค์ประกอบภาพ")
    }

    @MainActor private func largeText(language: String, fieldTitle: String, frameTitle: String) throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = language
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = "dark"
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = "2"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        reveal(card, in: app)
        card.tap()
        XCTAssertTrue(app.staticTexts["screen-plan-detail"].waitForExistence(timeout: 15))
        let field = app.buttons["plan-field-mode"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        XCTAssertLessThan(field.frame.minY, app.frame.height * 3, "Field entry belongs before the long detail content")
        XCTAssertFalse(app.buttons["plan-view-map"].exists, "Large text must not lose viewport height to a fixed map CTA")
        let inlineMap = app.buttons["plan-inline-view-map"]
        XCTAssertTrue(inlineMap.exists)
        let notes = app.staticTexts["saved-plan-notes"]
        if notes.exists { XCTAssertLessThan(field.frame.minY, notes.frame.minY) }
        reveal(field, in: app)
        capture("m5-" + language + "-early-field-action", in: app)
        field.tap()
        let title = app.staticTexts["field-full-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, fieldTitle)
        reveal(title, in: app)
        XCTAssertTrue(app.frame.contains(title.frame), "Full heading must stay in the reading width")
        capture("m5-" + language + "-field-full-heading", in: app)
        app.buttons["field-session-close"].tap()

        app.terminate()
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 20))
        app.buttons["map-composition"].tap()
        let preview = app.buttons["composition-preview"]
        reveal(preview, in: app); preview.tap()
        let frameHeading = app.staticTexts["frame-full-title"]
        XCTAssertTrue(frameHeading.waitForExistence(timeout: 15))
        XCTAssertEqual(frameHeading.label, frameTitle)
        reveal(frameHeading, in: app)
        XCTAssertTrue(app.frame.contains(frameHeading.frame))
        capture("m5-" + language + "-framing-full-heading", in: app)
        let portrait = app.buttons["frame-orientation-portrait"]
        XCTAssertTrue(portrait.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "frame-orientation-portrait").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "frame-orientation-landscape").count, 1)
        XCTAssertFalse(app.buttons["frame-orientation"].exists, "The heading identifier must not replace either orientation button")
        reveal(portrait, in: app); portrait.tap()
        XCTAssertTrue(portrait.isSelected)
        let landscape = app.buttons["frame-orientation-landscape"]
        reveal(landscape, in: app); landscape.tap()
        XCTAssertTrue(landscape.isSelected)
        capture("m5-" + language + "-stacked-orientation-controls", in: app)
        XCTAssertTrue(app.buttons["frame-apply"].isEnabled)
        app.buttons["frame-apply"].tap()
    }

    @MainActor func testLargeLibraryPublishesOnlyLatestQueryAndFilter() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = "en"
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = "light"
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = "2"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LIBRARY_COUNT"] = "1000"
        app.launch()
        defer { app.terminate() }
        let query = app.textFields["plan-library-search"]
        XCTAssertTrue(query.waitForExistence(timeout: 20))
        query.tap(); query.typeText("M5-0999")
        let wanted = app.staticTexts["M5-0999"]
        XCTAssertTrue(wanted.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["plan-library-query-busy"].firstMatch.waitForNonExistence(timeout: 20))
        XCTAssertEqual(app.buttons.matching(identifier: "plan-card").count, 1)
        capture("m5-library-latest-query", in: app)
        query.typeText("-absent")
        let empty = app.descendants(matching: .any)["plan-library-empty-results"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 20))
        XCTAssertFalse(wanted.exists)
        app.buttons["plan-library-clear-search"].tap()
        let completed = app.buttons["plan-library-filter-completed"]
        reveal(completed, in: app); completed.tap()
        XCTAssertTrue(empty.waitForExistence(timeout: 20))
        XCTAssertTrue(completed.isSelected)
        let all = app.buttons["plan-library-filter-all"]
        reveal(all, in: app); all.tap()
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertFalse(empty.exists)
        XCTAssertTrue(all.isSelected)
        capture("m5-library-filter-recovered", in: app)
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
        capture("m5-control-unreachable", in: app)
        let diagnostic = XCTAttachment(string: geometry.joined(separator: "\n") + "\n" + app.debugDescription)
        diagnostic.name = "m5-unreachable-geometry"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTFail("Control must be visible and hittable: " + (target.exists ? target.identifier : "missing element"))
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
