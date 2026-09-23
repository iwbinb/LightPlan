import XCTest
@testable import LightPlanCore

final class PlanFieldBriefTests: XCTestCase {
    func testNotesRoundTripAndLegacyMissingNotes() throws {
        let plan = try ShootPlan(title: "Dawn", place: .example, date: Date(timeIntervalSince1970: 1_789_617_600),
                                 target: .sunrise, notes: "Tripod · 三脚架\nMeet at the gate")
        let data = try Archive(places: [], plans: [plan]).encoded()
        XCTAssertEqual(try Archive.decode(data).plans.first?.notes, plan.notes)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var plans = try XCTUnwrap(json["plans"] as? [[String: Any]])
        plans[0].removeValue(forKey: "notes")
        json["plans"] = plans
        XCTAssertNil(try Archive.decode(JSONSerialization.data(withJSONObject: json)).plans.first?.notes)
    }

    func testOversizedImportedNotesRejected() throws {
        var plan = try ShootPlan(title: "Dawn", place: .example, date: Date(timeIntervalSince1970: 1_789_617_600), target: .sunrise)
        plan.notes = String(repeating: "a", count: 2001)
        XCTAssertThrowsError(try plan.validated())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try Archive.decode(encoder.encode(Archive(places: [], plans: [plan]))))
    }

    func testCompositionBriefPreservesCrossDayArrivalAndObserverLink() throws {
        let place = try Place(name: "Gate & ridge #1", coordinate: Coordinate(latitude: 40.7, longitude: -74), timeZoneID: "America/New_York")
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T04:15:00Z"))
        let composition = try CompositionPlan(body: .moon, subject: Coordinate(latitude: 40.71, longitude: -74), desiredOffsetDegrees: 0, instant: instant)
        let plan = try ShootPlan(title: "Moon", place: place, date: instant, target: .composition, arrivalLeadMinutes: 30, composition: composition)
        let summary = try DayEngine.calculate(place: place, date: instant)
        let brief = try PlanFieldBrief(plan: plan, summary: summary)
        XCTAssertEqual(brief.shootAt, instant)
        XCTAssertEqual(brief.arriveAt, instant.addingTimeInterval(-1800))
        XCTAssertFalse(LocalDay.same(brief.arriveAt, brief.shootAt, timeZone: place.timeZone))
        let url = try XCTUnwrap(URLComponents(url: brief.mapURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.host, "maps.apple.com")
        XCTAssertEqual(url.queryItems?.first(where: { $0.name == "ll" })?.value, "40.7,-74.0")
        XCTAssertEqual(url.queryItems?.first(where: { $0.name == "q" })?.value, place.name)
    }

    func testBriefRejectsDifferentDestinationSummary() throws {
        let date = Date(timeIntervalSince1970: 1_789_617_600)
        let plan = try ShootPlan(title: "Dawn", place: .example, date: date, target: .sunrise)
        let elsewhere = try Place(name: "Elsewhere", coordinate: Coordinate(latitude: 0, longitude: 0), timeZoneID: "UTC")
        XCTAssertThrowsError(try PlanFieldBrief(plan: plan, summary: DayEngine.calculate(place: elsewhere, date: date)))
    }
}
