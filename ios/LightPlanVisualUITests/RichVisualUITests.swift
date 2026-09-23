import XCTest

/// Native captures of the new computed framing, opportunity and field-session surfaces.
/// Uses the existing example fixture, real calculations and native controls. These are
/// layout/reachability checks, not mother-tongue or VoiceOver certification.
final class RichVisualUITests: XCTestCase {
    private struct Language {
        let code: String
        let all: String
        let inFrame: String
        let beforeArrival: String
    }

    // Expected translations are copied from the current catalog, never used as app data.
    private let languages: [Language] = [
        Language(code: "en", all: "All candidates", inFrame: "Inside the frame", beforeArrival: "Until planned arrival"),
        Language(code: "zh-Hans", all: "全部候选", inFrame: "完整入框", beforeArrival: "距计划到达"),
        Language(code: "zh-Hant", all: "全部候選", inFrame: "完整入框", beforeArrival: "距計畫抵達"),
        Language(code: "ja", all: "全候補", inFrame: "画面内", beforeArrival: "到着予定まで"),
        Language(code: "ko", all: "모든 후보", inFrame: "프레임 안", beforeArrival: "예정 도착까지"),
        Language(code: "de", all: "Alle Kandidaten", inFrame: "Im Bild", beforeArrival: "Bis zur geplanten Ankunft"),
        Language(code: "fr", all: "Tous les candidats", inFrame: "Dans le cadre", beforeArrival: "Avant l’arrivée prévue"),
        Language(code: "th", all: "ทั้งหมด", inFrame: "อยู่ในกรอบทั้งหมด", beforeArrival: "ก่อนเวลาถึงที่หมายตามแผน"),
        Language(code: "pt-PT", all: "Todos", inFrame: "Dentro do enquadramento", beforeArrival: "Até à chegada prevista")
    ]

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testRichScreensAllNineLanguages() throws {
        for language in languages { try exercise(language: language, largestText: false) }
    }

    @MainActor func testPortugueseStandardRichScreens() throws {
        try exercise(language: XCTUnwrap(languages.first { $0.code == "pt-PT" }), largestText: false)
    }

    @MainActor func testGermanLargestTextRichScreens() throws {
        try exercise(language: XCTUnwrap(languages.first { $0.code == "de" }), largestText: true)
    }

    @MainActor func testThaiLargestTextRichScreens() throws {
        try exercise(language: XCTUnwrap(languages.first { $0.code == "th" }), largestText: true)
    }

    @MainActor private func exercise(language: Language, largestText: Bool) throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = language.code
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = "light"
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = "1"
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        defer { app.terminate() }
        let prefix = "rich-" + language.code + (largestText ? "-axxxl" : "-standard")

        XCTAssertTrue(app.staticTexts["selected-time"].waitForExistence(timeout: 20))
        let composition = app.buttons["map-composition"]
        XCTAssertTrue(composition.waitForExistence(timeout: 10)); composition.tap()
        let panel = app.scrollViews.containing(.any, identifier: "composition-card").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let preview = app.buttons["composition-preview"]
        reveal(preview, in: app, container: panel, name: prefix + "-preview")
        preview.tap()

        let focal = app.buttons["frame-focal-24"]
        XCTAssertTrue(focal.waitForExistence(timeout: 15))
        let previewScroll = verticalScroll(containing: "framing-diagram", in: app)
        reveal(focal, in: app, container: previewScroll, name: prefix + "-focal-24")
        focal.tap()
        XCTAssertEqual(app.textFields["frame-focal-length"].value as? String, "24")
        let visibility = app.staticTexts["frame-visibility"]
        XCTAssertTrue(visibility.waitForExistence(timeout: 10))
        XCTAssertEqual(visibility.label, language.inFrame, "The wide-lens example must show the computed celestial disc inside the frame")
        let diagram = element("framing-diagram", in: app)
        reveal(diagram, in: app, container: previewScroll, fully: true, name: prefix + "-full-framing-diagram")
        XCTAssertTrue(visibleRect(of: previewScroll, in: app).contains(diagram.frame), "Capture must include the complete computed 3:2 diagram")
        let apply = app.buttons["frame-apply"]
        XCTAssertTrue(apply.isHittable && apply.isEnabled)
        capture(prefix + "-framing-24mm-in-frame", in: app)
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10))

        let search = app.buttons["composition-search"]
        reveal(search, in: app, container: panel, name: prefix + "-search")
        search.tap()
        let picker = element("opportunity-filter", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        if largestText {
            reveal(picker, in: app, container: app.collectionViews.firstMatch, name: prefix + "-search-filter")
            picker.tap()
            let all = app.buttons[language.all].firstMatch
            XCTAssertTrue(all.waitForExistence(timeout: 10)); all.tap()
        } else {
            let all = app.buttons["opportunity-preset-all"]
            XCTAssertTrue(all.waitForExistence(timeout: 10))
            let strip = app.scrollViews["opportunity-filter"].firstMatch
            for _ in 0..<3 where !all.isHittable || !app.frame.contains(all.frame) { strip.swipeLeft() }
            XCTAssertTrue(all.isHittable && app.frame.contains(all.frame))
            all.tap(); XCTAssertTrue(all.isSelected)
        }
        let opportunity = app.buttons.matching(identifier: "composition-opportunity").firstMatch
        let results = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        // Large localized headers can fill a whole viewport; instantiate the lazy result row first.
        reveal(opportunity, in: app, container: results, name: prefix + "-first-opportunity")
        XCTAssertTrue(opportunity.waitForExistence(timeout: 40))
        let duration = opportunity.staticTexts["opportunity-window-duration"]
        XCTAssertTrue(duration.exists && !duration.label.isEmpty)
        XCTAssertFalse(opportunity.staticTexts["composition-opportunity-time"].label.isEmpty)
        reveal(duration, in: app, container: results, name: prefix + "-window-duration")
        capture(prefix + "-opportunity-window", in: app)
        XCTAssertTrue(app.buttons["opportunity-options"].isHittable)

        // The default fixture seeds one ordinary plan. Its future day is calculated in
        // the destination calendar; no save action, notification prompt or fake event is used.
        app.terminate()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let future = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: Date()))
        app.launchEnvironment["LIGHTPLAN_VISUAL_DAY"] = ISO8601DateFormatter().string(from: future)
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = "2"
        app.launch()
        let card = app.buttons.matching(identifier: "plan-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        let field = app.buttons["plan-field-mode"]
        reveal(field, in: app, container: app.scrollViews.firstMatch, name: prefix + "-field-entry")
        field.tap()
        let status = element("field-session-status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertTrue(status.label.contains(language.beforeArrival))
        let countdown = app.staticTexts["field-session-countdown"]
        XCTAssertTrue(countdown.exists && !countdown.label.isEmpty)
        let fieldScroll = verticalScroll(containing: "field-session-countdown", in: app)
        reveal(countdown, in: app, container: fieldScroll, fully: true, name: prefix + "-countdown")
        capture(prefix + "-field-countdown", in: app)
        if largestText {
            let complete = app.buttons["field-session-complete"]
            reveal(complete, in: app, container: fieldScroll, name: prefix + "-field-complete-control")
            XCTAssertTrue(complete.isEnabled)
            XCTAssertTrue(app.buttons["field-session-close"].isHittable)
        }
    }

    @MainActor private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor private func verticalScroll(containing identifier: String, in app: XCUIApplication) -> XCUIElement {
        let candidates = app.scrollViews.containing(.any, identifier: identifier).allElementsBoundByIndex
            .filter { $0.frame.height > 120 }
        return candidates.min(by: { $0.frame.height < $1.frame.height }) ?? app.scrollViews.firstMatch
    }

    @MainActor private func visibleRect(of container: XCUIElement, in app: XCUIApplication) -> CGRect {
        var rect = (container.exists ? container.frame : app.frame).intersection(app.frame)
        let visibleBars = app.navigationBars.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        if let bottom = visibleBars.map(\.frame.maxY).max(), bottom > rect.minY, bottom < rect.maxY {
            let previousMaxY = rect.maxY
            rect.origin.y = bottom
            rect.size.height = previousMaxY - bottom
        }
        if app.keyboards.firstMatch.exists {
            rect.size.height = max(0, min(rect.maxY, app.keyboards.firstMatch.frame.minY) - rect.minY)
        }
        // SwiftUI can report an offscreen detail button as hittable even when its
        // synthesized tap lands in the fixed map action or floating tab bar.
        // Only treat the unobscured content rectangle as usable for a control.
        for overlay in [app.buttons["plan-view-map"], app.tabBars.firstMatch] {
            if overlay.exists && overlay.isHittable {
                let top = overlay.frame.minY - 12
                if top > rect.minY, top < rect.maxY { rect.size.height = top - rect.minY }
            }
        }
        return rect.insetBy(dx: 2, dy: 3)
    }

    @MainActor private func reveal(_ target: XCUIElement, in app: XCUIApplication, container: XCUIElement,
                                   fully: Bool = false, name: String) {
        var activeContainer = container
        var observations: [String] = []
        for attempt in 0..<18 {
            let visible = visibleRect(of: activeContainer, in: app)
            let exists = target.exists
            let targetFrame = exists ? target.frame : .zero
            let hasTargetFrame = targetFrame.height > 0 && !targetFrame.isNull
            observations.append("attempt=\(attempt) viewport=\(visible) target=\(targetFrame)")
            // Immediately after navigation, firstMatch can still resolve a departing
            // scroll view. Retry its geometry instead of failing before any gesture.
            guard !visible.isNull, visible.width > 30, visible.height > 80 else {
                if exists, !target.identifier.isEmpty {
                    let owners = app.scrollViews.containing(.any, identifier: target.identifier).allElementsBoundByIndex
                    if let owner = owners.filter({
                        let overlap = $0.frame.intersection(app.frame)
                        return !overlap.isNull && overlap.width > 30 && overlap.height > 80
                    }).min(by: { $0.frame.height < $1.frame.height }) { activeContainer = owner }
                }
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            if exists && target.isHittable {
                // A result row may be taller than the viewport at accessibility sizes;
                // its time and duration still receive their own reachability assertions.
                let needsFullFrame = fully || (target.elementType == .button && targetFrame.height <= visible.height)
                if !needsFullFrame || visible.contains(targetFrame) { return }
            }
            let targetIsAbove = hasTargetFrame && targetFrame.minY < visible.minY
            // Long accessibility-size cards may begin several viewports away.
            // Traverse most of the unobscured viewport, then use the same small
            // edge correction once the target is close; endpoints remain inside.
            let maximumDistance = visible.height * 0.7
            let desiredDistance: CGFloat
            if hasTargetFrame {
                let overflow = targetIsAbove ? visible.minY - targetFrame.minY : targetFrame.maxY - visible.maxY
                desiredDistance = max(0, overflow) + 8
            } else { desiredDistance = maximumDistance }
            let distance = min(maximumDistance, max(24, desiredDistance))
            // Drag in the scroll view's blank leading inset, outside full-width button
            // labels. A tiny movement inside a button was recognized as a tap, opening
            // the destination while this helper kept inspecting the covered source.
            // Keep a real pan distance and the existing complete-frame requirements.
            let dragX = visible.minX + 8
            let middleY = visible.minY + visible.height * 0.48
            let top = CGPoint(x: dragX, y: middleY - distance / 2)
            let bottom = CGPoint(x: dragX, y: middleY + distance / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = targetIsAbove ? top : bottom, end = targetIsAbove ? bottom : top
            observations.append("dragStart=\(start) dragEnd=\(end)")
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(
                    CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)),
                    withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        capture(name + "-unreachable", in: app)
        let geometry = XCTAttachment(string: observations.joined(separator: "\n"))
        geometry.name = name + "-scroll-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTFail("Native control or complete diagram was not reachable: " + name)
    }

    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
