import XCTest
import StoreKitTest

/// Exercises the app against StoreKit's signed local test transactions, not a premium flag.
/// These tests do not substitute for App Store Connect sandbox or physical-device acceptance.
final class ProductUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func store() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "LightPlan")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }
    @MainActor private func launch(tab: Int = 4) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LIGHTPLAN_VISUAL_FIXTURE"] = "1"
        app.launchEnvironment["LIGHTPLAN_VISUAL_LANGUAGE"] = "en"
        app.launchEnvironment["LIGHTPLAN_VISUAL_THEME"] = "light"
        app.launchEnvironment["LIGHTPLAN_VISUAL_TAB"] = String(tab)
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
    @MainActor func testRealPurchasePersistsAndRefundRevokes() async throws {
        let session = try store()
        let app = launch()
        let membership = app.buttons["membership"]
        waitForValue(membership, "locked")
        membership.tap()
        let buy = app.buttons["purchase-buy"]
        waitUntilEnabled(buy)
        buy.tap()
        waitForValue(membership, "unlocked")
        XCTAssertEqual(session.allTransactions().count, 1)
        app.terminate(); app.launch()
        waitForValue(app.buttons["membership"], "unlocked")
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        waitForValue(app.buttons["membership"], "locked")
        app.terminate()
    }
    @MainActor func testPaywallDismissalDoesNotUnlock() throws {
        let session = try store()
        let app = launch()
        waitForValue(app.buttons["membership"], "locked")
        app.buttons["membership"].tap()
        XCTAssertTrue(app.buttons["purchase-buy"].waitForExistence(timeout: 10))
        let close = app.buttons["paywall-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10)); close.tap()
        waitForValue(app.buttons["membership"], "locked")
        XCTAssertTrue(session.allTransactions().isEmpty)
        app.terminate()
    }
    @MainActor func testPurchaseResumesPlanEditorAndSaves() async throws {
        let session = try store()
        let app = launch(tab: 2)
        let create = app.buttons["plan-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        waitUntilEnabled(app.buttons["purchase-buy"]); app.buttons["purchase-buy"].tap()
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
        XCTAssertEqual(session.allTransactions().count, 1)
        app.terminate()
    }
    @MainActor func testManualLocationAcceptsCoordinatesWithoutPermission() async throws {
        let session = try store()
        // The first manually confirmed place is part of the free flow; this test intentionally
        // proves it works without location permission and without manufacturing an off-device purchase.
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
        XCTAssertTrue(session.allTransactions().isEmpty)
        app.terminate()
    }
}
