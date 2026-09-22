import XCTest
@testable import LightPlanCore

final class CompositionPlanningTests: XCTestCase {
    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testSignedDifferenceWrapsNorth() {
        XCTAssertEqual(CompositionPlanner.signedDifference(target: 359, actual: 1), 2, accuracy: 0.000001)
        XCTAssertEqual(CompositionPlanner.signedDifference(target: 1, actual: 359), -2, accuracy: 0.000001)
        XCTAssertEqual(CompositionPlanner.signedDifference(target: 90, actual: 100), 10, accuracy: 0.000001)
    }

    func testRecommendedObserverCreatesBackAlignment() throws {
        let subject = try Coordinate(latitude: 0, longitude: 0)
        let observer = try CompositionPlanner.recommendedObserver(
            subject: subject, bodyAzimuth: 270, distanceMeters: 1_000
        )
        let bearing = try XCTUnwrap(Geometry.bearing(from: observer, to: subject))
        XCTAssertEqual(bearing, 270, accuracy: 0.02)
    }

    func testRecommendedObserverHonorsFrameOffset() throws {
        let subject = try Coordinate(latitude: 24.45, longitude: 118.08)
        let observer = try CompositionPlanner.recommendedObserver(
            subject: subject, bodyAzimuth: 250, desiredOffsetDegrees: 10, distanceMeters: 500
        )
        let subjectBearing = try XCTUnwrap(Geometry.bearing(from: observer, to: subject))
        XCTAssertEqual(CompositionPlanner.signedDifference(target: subjectBearing, actual: 250), 10, accuracy: 0.03)
    }

    func testRecommendedObserverRejectsUnsafeSearchScale() throws {
        XCTAssertThrowsError(try CompositionPlanner.recommendedObserver(
            subject: Place.example.coordinate, bodyAzimuth: 270, distanceMeters: 5
        ))
        XCTAssertThrowsError(try CompositionPlanner.recommendedObserver(
            subject: Place.example.coordinate, bodyAzimuth: 270, distanceMeters: 20_000
        ))
    }

    func testBestAlignmentFindsKnownSunsetBearing() throws {
        let place = Place.example
        let day = try DayEngine.calculate(place: place, date: instant("2026-09-17T04:00:00Z"))
        let sunset = try XCTUnwrap(day.first(.sunset))
        let subject = try VisualGeometry.destination(
            from: place.coordinate, bearing: sunset.azimuth, meters: 1_000
        )
        let result = try XCTUnwrap(CompositionPlanner.bestAlignment(
            body: .sun,
            observer: place.coordinate,
            subject: subject,
            interval: DateInterval(start: day.start, end: day.end)
        ))
        XCTAssertLessThan(result.absoluteErrorDegrees, 0.15)
        XCTAssertGreaterThanOrEqual(result.altitude, -1)
        XCTAssertTrue([AlignmentQuality.exact, .strong].contains(result.quality))
    }

    func testOffsetSearchTargetsRequestedFramePosition() throws {
        let place = Place.example
        let day = try DayEngine.calculate(place: place, date: instant("2026-09-17T04:00:00Z"))
        let sunset = try XCTUnwrap(day.first(.sunset))
        let subject = try VisualGeometry.destination(
            from: place.coordinate, bearing: Astronomy.normalize(sunset.azimuth - 10), meters: 800
        )
        let result = try XCTUnwrap(CompositionPlanner.bestAlignment(
            body: .sun,
            observer: place.coordinate,
            subject: subject,
            interval: DateInterval(start: day.start, end: day.end),
            desiredOffsetDegrees: 10
        ))
        XCTAssertLessThan(result.absoluteErrorDegrees, 0.2)
        XCTAssertEqual(result.actualOffsetDegrees, 10, accuracy: 0.2)
    }

    func testOpportunitySearchIsBoundedAndSorted() throws {
        let place = Place.example
        let subject = try VisualGeometry.destination(from: place.coordinate, bearing: 260, meters: 1_000)
        let values = try CompositionPlanner.opportunities(
            body: .sun,
            place: place,
            subject: subject,
            starting: instant("2026-09-17T04:00:00Z"),
            days: 7,
            limit: 5
        )
        XCTAssertFalse(values.isEmpty)
        XCTAssertLessThanOrEqual(values.count, 5)
        for pair in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.absoluteErrorDegrees, pair.1.absoluteErrorDegrees + 1e-9)
        }
    }

    func testCoincidentSubjectHasNoAlignment() throws {
        let day = try DayEngine.calculate(place: .example, date: instant("2026-09-17T04:00:00Z"))
        XCTAssertNil(try CompositionPlanner.bestAlignment(
            body: .sun,
            observer: Place.example.coordinate,
            subject: Place.example.coordinate,
            interval: DateInterval(start: day.start, end: day.end)
        ))
    }
}
