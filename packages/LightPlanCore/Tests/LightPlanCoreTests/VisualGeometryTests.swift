import XCTest
@testable import LightPlanCore

final class VisualGeometryTests: XCTestCase {
    func testFractionClamps() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 100), duration: 100)
        XCTAssertEqual(VisualGeometry.fraction(at: Date(timeIntervalSince1970: 50), in: interval), 0)
        XCTAssertEqual(VisualGeometry.fraction(at: Date(timeIntervalSince1970: 250), in: interval), 1)
    }
    func testFractionMidpoint() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 100), duration: 90_000)
        XCTAssertEqual(VisualGeometry.fraction(at: interval.start.addingTimeInterval(45_000), in: interval), 0.5)
    }
    func testEndStaysInsideDay() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 82_800)
        XCTAssertEqual(VisualGeometry.instant(at: 1, in: interval).timeIntervalSince1970, 82_799)
    }
    func testNonFiniteFractionClamps() {
        let i = DateInterval(start: Date(timeIntervalSince1970: 100), duration: 100)
        XCTAssertEqual(VisualGeometry.instant(at: .nan, in: i), i.start)
    }
    func testAnglesDoNotSpinThroughSouth() {
        XCTAssertEqual(VisualGeometry.shortestAngle(from: 359, to: 1, fraction: 0.5), 0, accuracy: 0.00001)
        XCTAssertEqual(VisualGeometry.shortestAngle(from: 1, to: 359, fraction: 0.5), 0, accuracy: 0.00001)
    }
    func testNorthRay() throws {
        let c = try Coordinate(latitude: 0, longitude: 0)
        let d = try VisualGeometry.destination(from: c, bearing: 0, meters: 1000)
        XCTAssertEqual(d.longitude, 0, accuracy: 0.0001)
        XCTAssertEqual(d.latitude, 0.0089932, accuracy: 0.00001)
    }
    func testDatelineRayNormalizes() throws {
        let c = try Coordinate(latitude: 0, longitude: 179.999)
        let d = try VisualGeometry.destination(from: c, bearing: 90, meters: 5000)
        XCTAssertLessThan(d.longitude, 0)
        XCTAssertGreaterThan(d.longitude, -180)
    }
    func testNegativeDistanceRejected() throws {
        XCTAssertThrowsError(try VisualGeometry.destination(from: Place.example.coordinate, bearing: 0, meters: -1))
    }
    func testSamplerEndpointsAndBounds() throws {
        let date = try LocalDay.date(year: 2026, month: 9, day: 17, timeZone: Place.example.timeZone)
        let summary = try DayEngine.calculate(place: Place.example, date: date)
        let samples = try VisualSampler.samples(for: summary, count: 25)
        XCTAssertEqual(samples.count, 25)
        XCTAssertEqual(samples.first?.instant, summary.start)
        XCTAssertLessThan(try XCTUnwrap(samples.last?.instant), summary.end)
        XCTAssertTrue(samples.allSatisfy { $0.sun.azimuth >= 0 && $0.sun.azimuth < 360 })
    }
    func testSamplerRejectsUnboundedAllocation() throws {
        let summary = try DayEngine.calculate(place: .example, date: Date(timeIntervalSince1970: 1_789_632_000))
        XCTAssertThrowsError(try VisualSampler.samples(for: summary, count: 1_000_000))
    }
    func testTwentyThreeHourDayUsesElapsedSeconds() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let date = try LocalDay.date(year: 2026, month: 3, day: 29, timeZone: zone)
        let day = try LocalDay.interval(containing: date, timeZone: zone)
        XCTAssertEqual(day.duration, 82_800)
        XCTAssertEqual(VisualGeometry.instant(at: 0.5, in: day).timeIntervalSince(day.start), 41_400)
    }
}
