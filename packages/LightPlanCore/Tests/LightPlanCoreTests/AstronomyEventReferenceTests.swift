import Foundation
import XCTest
@testable import LightPlanCore

final class AstronomyEventReferenceTests: XCTestCase {
    private struct Document: Decodable { let cases: [Fixture] }
    private struct Fixture: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let timeZone: String
        let civilDate: String
        let intervalStart: String
        let intervalEnd: String
        let expectedEvents: [ExpectedEvent]
    }
    private struct ExpectedEvent: Decodable {
        let kind: LightEventKind
        let timestamp: Double
        let maxErrorSeconds: Double
    }

    func testIndependentSolarLunarEventsAcrossDSTPolarAndDateBoundaries() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "astronomy-events", withExtension: "json", subdirectory: "Fixtures"))
        let fixtures = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)).cases
        XCTAssertEqual(fixtures.count, 31)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for fixture in fixtures {
            let place = try Place(name: fixture.name, coordinate: Coordinate(latitude: fixture.latitude, longitude: fixture.longitude), timeZoneID: fixture.timeZone)
            let components = fixture.civilDate.split(separator: "-").compactMap { Int($0) }
            let date = try LocalDay.date(year: components[0], month: components[1], day: components[2], timeZone: place.timeZone)
            let summary = try DayEngine.calculate(place: place, date: date)
            XCTAssertEqual(summary.start, try XCTUnwrap(formatter.date(from: fixture.intervalStart)), fixture.name)
            XCTAssertEqual(summary.end, try XCTUnwrap(formatter.date(from: fixture.intervalEnd)), fixture.name)
            for kind in LightEventKind.allCases {
                let expected = fixture.expectedEvents.filter { $0.kind == kind }
                let actual = summary.events.filter { $0.kind == kind }
                XCTAssertEqual(actual.count, expected.count, "\(fixture.name) \(kind): independent reference event count")
                for (event, reference) in zip(actual, expected) {
                    XCTAssertEqual(event.date.timeIntervalSince1970, reference.timestamp,
                                   accuracy: reference.maxErrorSeconds, "\(fixture.name) \(kind)")
                }
            }
        }
    }
}
