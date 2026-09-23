import XCTest

/// M3 checks use native taps, real searches and the existing deterministic fixture.
/// No production results are replaced with canned windows or event times.
final class WorkflowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(tab: Int) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = "en"
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = "light"
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = String(tab)
        app.launchEnvironment["LIGHTPLAN_VISUAL_ARCHIVE"] = UUID().uuidString
        app.launch()
        return app
    }

    @MainActor func testManualTimelineTimeIsTheTimePreviewedAndSaved() throws {
        let app = launch(tab: 1)
        defer { app.terminate() }
        enterComposition(app)
        let best = app.buttons["composition-show-best"]
        reveal(best, in: app); best.tap()
        let selected = app.staticTexts["selected-time"]
        reveal(selected, in: app)
        let bestTime = selected.label
        let next = app.buttons["map-next-time"]
        reveal(next, in: app); next.tap()
        expectation(for: NSPredicate(format: "label != %@", bestTime), evaluatedWith: selected)
        waitForExpectations(timeout: 10)
        let chosenTime = selected.label

        let preview = app.buttons["composition-preview"]
        reveal(preview, in: app); preview.tap()
        XCTAssertTrue(app.buttons["frame-apply"].waitForExistence(timeout: 15))
        let previewTime = app.staticTexts["frame-selected-time"]
        reveal(previewTime, in: app)
        XCTAssertEqual(previewTime.label, chosenTime, "Preview must use the manually selected map time")
        capture("m3-preview-uses-manual-time", in: app)
        app.buttons["frame-apply"].tap()
        XCTAssertTrue(app.buttons["frame-apply"].waitForNonExistence(timeout: 10))

        let save = app.buttons["composition-save-plan"]
        reveal(save, in: app); save.tap()
        let anchor = app.staticTexts["plan-anchor-time"]
        reveal(anchor, in: app)
        XCTAssertEqual(anchor.label, chosenTime, "Saving must not silently replace the map time with the daily optimum")
        capture("m3-editor-retains-manual-time", in: app)
        app.buttons["plan-cancel"].tap()
        XCTAssertTrue(app.textFields["plan-title"].waitForNonExistence(timeout: 10), "An untouched editor may close without a discard prompt")
    }

    @MainActor func testUnsavedEditorSurvivesCancelAndRotationUntilExplicitDiscard() throws {
        let app = launch(tab: 2)
        defer { app.terminate() }
        let create = app.buttons["plan-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 15)); create.tap()
        let title = app.textFields["plan-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap(); title.typeText(" M3 draft")
        let originalTitle = try XCTUnwrap(title.value as? String)
        let project = app.textFields["plan-collection"]
        project.tap(); project.typeText("Sunrise weekend")
        app.buttons["plan-cancel"].tap()
        let keep = app.buttons["Keep editing"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 10)); keep.tap()
        XCTAssertEqual(title.value as? String, originalTitle)
        XCTAssertEqual(project.value as? String, "Sunrise weekend")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, originalTitle)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        XCTAssertEqual(project.value as? String, "Sunrise weekend")
        capture("m3-unsaved-draft-kept-after-cancel-and-rotation", in: app)
        app.buttons["plan-cancel"].tap()
        let discard = app.buttons["Discard changes"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 10)); discard.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "plan-card").count, 0, "Discard must not write a plan")
    }

    @MainActor func testEmptySearchRecoveryAndAppliedOptionsSurviveReopening() throws {
        let app = launch(tab: 1)
        defer { app.terminate() }
        enterComposition(app)
        openSearch(app)
        let empty = element("opportunity-empty", in: app)
        XCTAssertTrue(empty.waitForExistence(timeout: 60))
        let change = app.buttons["opportunity-change-conditions"]
        reveal(change, in: app); change.tap()
        XCTAssertTrue(element("opportunity-days-presets", in: app).waitForExistence(timeout: 10))
        // Canceling this nested options draft must retain the actual empty result.
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        let relax = app.buttons["opportunity-clear-conditions"]
        reveal(relax, in: app); relax.tap()
        let days = app.staticTexts["opportunity-searched-days"]
        waitForLabel(days, "Days searched: 14", timeout: 120)
        XCTAssertTrue(app.buttons["opportunity-preset-all"].isSelected)
        app.buttons["opportunity-options"].tap()
        chooseMenu("opportunity-days-presets", value: "30", in: app)
        app.buttons["opportunity-apply-options"].tap()
        waitForLabel(days, "Days searched: 30", timeout: 180)
        let previousRange = app.staticTexts["opportunity-searched-range"].label
        chooseMenu("opportunity-sort", value: "Date", in: app)
        XCTAssertFalse(element("opportunity-search-busy", in: app).exists, "Sorting must not restart the astronomical search")
        capture("m3-recovered-search-applied-options", in: app)
        app.buttons["opportunity-close"].tap()
        XCTAssertTrue(days.waitForNonExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        app.tabBars.buttons["Map"].tap()
        openSearch(app)
        waitForLabel(days, "Days searched: 30", timeout: 180)
        XCTAssertEqual(app.staticTexts["opportunity-searched-range"].label, previousRange)
        XCTAssertTrue(app.buttons["opportunity-preset-all"].isSelected)
        let sort = element("opportunity-sort", in: app)
        reveal(sort, in: app)
        XCTAssertTrue(accessibleText(sort).contains("Date"))
        capture("m3-search-reopened-with-applied-range-and-order", in: app)
    }

    @MainActor func testStoppedSearchRetainsOptionsAndCanRestart() throws {
        let app = launch(tab: 1)
        defer { app.terminate() }
        enterComposition(app)
        openSearch(app)
        XCTAssertTrue(app.buttons["opportunity-options"].waitForExistence(timeout: 15))
        app.buttons["opportunity-options"].tap()
        chooseMenu("opportunity-days-presets", value: "90", in: app)
        app.buttons["opportunity-apply-options"].tap()
        let stop = app.buttons["opportunity-stop-search"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        reveal(stop, in: app); stop.tap()
        let resume = app.buttons["opportunity-resume-search"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        XCTAssertFalse(element("opportunity-search-busy", in: app).exists)
        app.buttons["opportunity-options"].tap()
        let duration = element("opportunity-days-presets", in: app)
        reveal(duration, in: app)
        XCTAssertTrue(accessibleText(duration).contains("90"))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        capture("m3-stopped-search-retains-90-day-options", in: app)
        reveal(resume, in: app); resume.tap()
        waitForLabel(app.staticTexts["opportunity-searched-days"], "Days searched: 90", timeout: 180)
        XCTAssertFalse(resume.exists)
        capture("m3-restarted-search-completed", in: app)
    }

    @MainActor private func enterComposition(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 20))
        app.buttons["map-composition"].tap()
        XCTAssertTrue(app.buttons["composition-subject-coordinates"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["composition-choose-observer"].exists)
    }

    @MainActor private func openSearch(_ app: XCUIApplication) {
        let search = app.buttons["composition-search"]
        reveal(search, in: app); search.tap()
        XCTAssertTrue(app.buttons["opportunity-options"].waitForExistence(timeout: 15))
    }

    @MainActor private func chooseMenu(_ identifier: String, value: String, in app: XCUIApplication) {
        let control = element(identifier, in: app)
        reveal(control, in: app); control.tap()
        let item = app.buttons[value].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10)); item.tap()
    }

    @MainActor private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor private func accessibleText(_ element: XCUIElement) -> String {
        ([element.label, element.value as? String ?? ""] + element.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
    }

    @MainActor private func waitForLabel(_ element: XCUIElement, _ text: String, timeout: TimeInterval) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    @MainActor private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        var geometry: [String] = []
        for _ in 0..<24 {
            let candidates = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            let containers = candidates.filter {
                let visible = $0.frame.intersection(app.frame)
                return $0.exists && !visible.isNull && visible.width > 120 && visible.height > 100
            }
            let owners = target.exists ? containers.filter { $0.descendants(matching: .any).matching(identifier: target.identifier).count > 0 } : []
            let exposedForms = containers.filter {
                ($0.elementType == .collectionView || $0.elementType == .table) && $0.buttons.allElementsBoundByIndex.contains { $0.isHittable }
            }
            guard let container = owners.min(by: { $0.frame.height < $1.frame.height }) ?? exposedForms.last ?? containers.first else {
                Thread.sleep(forTimeInterval: 0.1); continue
            }
            var viewport = container.frame.intersection(app.frame)
            for bar in app.navigationBars.allElementsBoundByIndex where bar.isHittable {
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
        capture("m3-control-unreachable", in: app)
        let diagnostic = XCTAttachment(string: geometry.joined(separator: "\n") + "\n" + app.debugDescription)
        diagnostic.name = "m3-unreachable-geometry"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTFail("Control must be visible and hittable: " + target.identifier)
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
