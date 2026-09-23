import XCTest
@testable import LightPlanCore

final class OpportunitySearchTests: XCTestCase {
    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testConstraintsRejectInvalidGeometry() throws {
        XCTAssertThrowsError(try OpportunityConstraints(maximumErrorDegrees: .nan))
        XCTAssertThrowsError(try OpportunityConstraints(maximumErrorDegrees: -1))
        XCTAssertThrowsError(try OpportunityConstraints(maximumErrorDegrees: 181))
        XCTAssertThrowsError(try OpportunityConstraints(altitudeRange: -91...90))
        XCTAssertThrowsError(try OpportunityConstraints(altitudeRange: 4...4))
        XCTAssertThrowsError(try OpportunityConstraints(solarAltitudeRange: -6...Double.infinity))
        XCTAssertNoThrow(try OpportunityConstraints(maximumErrorDegrees: 0, altitudeRange: -90...90))
    }

    func testPolarVisibilityBetweenCoarseSamplesIsNotLost() throws {
        let observer = try Coordinate(latitude: 67.56, longitude: 13.8875)
        let subject = try VisualGeometry.destination(from: observer, bearing: 180, meters: 1_000)
        let interval = DateInterval(start: instant("2026-12-21T00:00:00Z"), end: instant("2026-12-22T00:00:00Z"))
        // Independently verified counterexample: none of the old five-minute samples is visible,
        // but the Sun briefly exceeds -1° between 11:00 and 11:05 UTC.
        for offset in stride(from: 0.0, to: interval.duration, by: 300) {
            XCTAssertLessThan(try Astronomy.position(.sun, at: interval.start.addingTimeInterval(offset),
                                                     coordinate: observer).altitude, -1)
        }
        XCTAssertGreaterThan(try Astronomy.position(.sun, at: instant("2026-12-21T11:02:30Z"),
                                                    coordinate: observer).altitude, -1)
        let value = try XCTUnwrap(CompositionPlanner.bestAlignment(body: .sun, observer: observer,
            subject: subject, interval: interval))
        XCTAssertGreaterThanOrEqual(value.altitude, -1)
        XCTAssertLessThan(value.absoluteErrorDegrees, 0.1)
        XCTAssertTrue(interval.contains(value.instant))
    }

    func testSubsecondAltitudeWindowFindsTheKnownAlignment() throws {
        let observer = Place.example.coordinate
        let target = instant("2026-09-17T09:12:13Z")
        let sky = try Astronomy.position(.sun, at: target, coordinate: observer)
        let subject = try VisualGeometry.destination(from: observer, bearing: sky.azimuth, meters: 800)
        let interval = try LocalDay.interval(containing: target, timeZone: Place.example.timeZone)
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 0.01,
            altitudeRange: (sky.altitude - 0.0001)...(sky.altitude + 0.0001))
        let value = try XCTUnwrap(CompositionPlanner.bestAlignment(body: .sun, observer: observer,
            subject: subject, interval: interval, constraints: constraints))
        XCTAssertTrue(constraints.altitudeRange.contains(value.altitude))
        XCTAssertLessThan(abs(value.instant.timeIntervalSince(target)), 0.1)
        XCTAssertLessThan(value.absoluteErrorDegrees, 0.001)
    }

    func testNarrowVisibilityAtEitherSearchBoundaryIsNotLost() throws {
        let observer = try Coordinate(latitude: 67.56, longitude: 13.8875)
        let target = instant("2026-12-21T11:02:30Z")
        let sky = try Astronomy.position(.sun, at: target, coordinate: observer)
        let subject = try VisualGeometry.destination(from: observer, bearing: sky.azimuth, meters: 1_000)
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 0.01,
            altitudeRange: (sky.altitude - 0.000001)...90)
        for interval in [
            DateInterval(start: instant("2026-12-21T11:01:00Z"), end: instant("2026-12-21T12:01:00Z")),
            DateInterval(start: instant("2026-12-21T10:04:00Z"), end: instant("2026-12-21T11:04:00Z"))
        ] {
            let value = try XCTUnwrap(CompositionPlanner.bestAlignment(body: .sun, observer: observer,
                subject: subject, interval: interval, constraints: constraints))
            XCTAssertTrue(constraints.altitudeRange.contains(value.altitude))
            XCTAssertLessThan(abs(value.instant.timeIntervalSince(target)), 0.1)
        }
    }

    func testConstraintsOptimizeWithinTheWindowRatherThanFilterTheDailyWinner() throws {
        let observer = Place.example.coordinate
        let target = instant("2026-09-17T04:00:00Z")
        let sky = try Astronomy.position(.sun, at: target, coordinate: observer)
        let subject = try VisualGeometry.destination(from: observer, bearing: sky.azimuth, meters: 800)
        let interval = try LocalDay.interval(containing: target, timeZone: Place.example.timeZone)
        let unconstrained = try XCTUnwrap(CompositionPlanner.bestAlignment(body: .sun, observer: observer,
            subject: subject, interval: interval))
        XCTAssertGreaterThan(unconstrained.altitude, 30)
        let constraints = try OpportunityConstraints(altitudeRange: 0...5)
        let constrained = try XCTUnwrap(CompositionPlanner.bestAlignment(body: .sun, observer: observer,
            subject: subject, interval: interval, constraints: constraints))
        XCTAssertTrue(constraints.altitudeRange.contains(constrained.altitude))
        XCTAssertGreaterThan(abs(constrained.instant.timeIntervalSince(unconstrained.instant)), 3_600)
        let precise = try OpportunityConstraints(maximumErrorDegrees: 1, altitudeRange: 0...5)
        XCTAssertNil(try CompositionPlanner.bestAlignment(body: .sun, observer: observer,
            subject: subject, interval: interval, constraints: precise))
    }

    func testBlueLightConstraintOverridesTheLegacyVisibilityCutoff() throws {
        let observer = Place.example.coordinate
        let target = instant("2026-09-17T10:30:00Z")
        let sky = try Astronomy.position(.sun, at: target, coordinate: observer)
        XCTAssertLessThan(sky.altitude, -1)
        let subject = try VisualGeometry.destination(from: observer, bearing: sky.azimuth, meters: 800)
        let interval = try LocalDay.interval(containing: target, timeZone: Place.example.timeZone)
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 0.1,
            altitudeRange: (sky.altitude - 0.1)...(sky.altitude + 0.1))
        let value = try XCTUnwrap(CompositionPlanner.bestAlignment(body: .sun, observer: observer,
            subject: subject, interval: interval, constraints: constraints))
        XCTAssertLessThan(value.altitude, -1)
        XCTAssertLessThan(abs(value.instant.timeIntervalSince(target)), 0.5)
    }

    func testMoonAndNarrowSolarLightingWindowAreIntersected() throws {
        let observer = Place.example.coordinate
        let interval = try LocalDay.interval(containing: instant("2026-09-17T04:00:00Z"), timeZone: Place.example.timeZone)
        // Select the input from independent time samples, not from the search being tested.
        var target: (Date, SkyPosition, Double)?
        for offset in stride(from: 0.0, to: interval.duration, by: 60) {
            let time = interval.start.addingTimeInterval(offset)
            let sun = try Astronomy.position(.sun, at: time, coordinate: observer)
            let moon = try Astronomy.position(.moon, at: time, coordinate: observer)
            if (-6 ... -4).contains(sun.altitude), moon.altitude > 1 {
                target = (time, moon, sun.altitude); break
            }
        }
        let known = try XCTUnwrap(target)
        let subject = try VisualGeometry.destination(from: observer, bearing: known.1.azimuth, meters: 800)
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 0.1, altitudeRange: 0...90,
            solarAltitudeRange: (known.2 - 0.0001)...(known.2 + 0.0001))
        let value = try XCTUnwrap(CompositionPlanner.bestAlignment(body: .moon, observer: observer,
            subject: subject, interval: interval, constraints: constraints))
        let sun = try Astronomy.position(.sun, at: value.instant, coordinate: observer)
        XCTAssertTrue(try XCTUnwrap(constraints.solarAltitudeRange).contains(sun.altitude))
        XCTAssertGreaterThanOrEqual(value.altitude, 0)
        XCTAssertLessThan(abs(value.instant.timeIntervalSince(known.0)), 0.1)
    }

    func testDisjointBodyAndSolarWindowsProduceNoOpportunity() throws {
        let observer = Place.example.coordinate
        let subject = try VisualGeometry.destination(from: observer, bearing: 270, meters: 800)
        let interval = try LocalDay.interval(containing: instant("2026-09-17T04:00:00Z"), timeZone: Place.example.timeZone)
        let constraints = try OpportunityConstraints(altitudeRange: 5...10, solarAltitudeRange: -6 ... -4)
        XCTAssertNil(try CompositionPlanner.bestAlignment(body: .sun, observer: observer,
            subject: subject, interval: interval, constraints: constraints))
    }

    func testMultiDaySearchUsesDestinationCivilDaysAcrossBothDSTChanges() throws {
        let place = try Place(name: "New York", coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                              timeZoneID: "America/New_York")
        let subject = try VisualGeometry.destination(from: place.coordinate, bearing: 270, meters: 800)
        let constraints = try OpportunityConstraints(altitudeRange: 0...10)
        for (date, hours) in [("2026-03-08T16:00:00Z", 23.0), ("2026-11-01T17:00:00Z", 25.0)] {
            let start = instant(date)
            XCTAssertEqual(try LocalDay.interval(containing: start, timeZone: place.timeZone).duration, hours * 3_600)
            let values = try CompositionPlanner.opportunities(body: .sun, place: place, subject: subject,
                starting: start, days: 3, limit: 3, constraints: constraints)
            XCTAssertEqual(values.count, 3)
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = place.timeZone
            let dates = Set(values.map { calendar.startOfDay(for: $0.instant) })
            let expected = Set((0..<3).map { calendar.startOfDay(for: calendar.date(byAdding: .day, value: $0, to: start)!) })
            XCTAssertEqual(dates, expected)
            XCTAssertTrue(values.allSatisfy { constraints.altitudeRange.contains($0.altitude) })
        }
    }

    func testRequestIdentityIncludesEverySearchConstraint() throws {
        let interval = try LocalDay.interval(containing: instant("2026-09-17T04:00:00Z"), timeZone: Place.example.timeZone)
        let subject = try VisualGeometry.destination(from: Place.example.coordinate, bearing: 270, meters: 800)
        func request(_ constraints: OpportunityConstraints?) -> AlignmentRequest {
            AlignmentRequest(body: .moon, observer: Place.example.coordinate, subject: subject,
                             interval: interval, constraints: constraints)
        }
        let all = request(nil)
        let low = request(try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...10))
        let twilight = request(try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...10, solarAltitudeRange: -6...6))
        XCTAssertEqual(Set([all, low, twilight]).count, 3)
    }

    @MainActor func testCancelledConstrainedSearchDoesNotReturnCandidates() async throws {
        let place = Place.example
        let subject = try VisualGeometry.destination(from: place.coordinate, bearing: 270, meters: 800)
        let date = instant("2026-09-17T04:00:00Z")
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...10, solarAltitudeRange: -6...6)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CompositionPlanner.opportunitiesAsync(body: .moon, place: place, subject: subject,
                starting: date, days: 31, limit: 31, constraints: constraints)
        }
        do { _ = try await task.value; XCTFail("Cancelled search must not publish opportunities") }
        catch is CancellationError { }
    }

    func testRecommendedObserverPreservesForwardBearingAtHighLatitudesAndDateline() throws {
        for latitude in [-89.9, -80, 0, 80, 89.9] {
            let subject = try Coordinate(latitude: latitude, longitude: 179.999)
            for bearing in stride(from: 0.0, to: 360, by: 45) {
                let observer = try CompositionPlanner.recommendedObserver(subject: subject, bodyAzimuth: bearing,
                    desiredOffsetDegrees: 10, distanceMeters: 250)
                let actual = try XCTUnwrap(Geometry.bearing(from: observer, to: subject))
                XCTAssertEqual(CompositionPlanner.signedDifference(target: actual, actual: bearing), 10, accuracy: 0.001)
                let destination = try VisualGeometry.destination(from: observer,
                    bearing: Astronomy.normalize(bearing - 10), meters: 250)
                XCTAssertEqual(destination.latitude, subject.latitude, accuracy: 0.000001)
                XCTAssertEqual(CompositionPlanner.signedDifference(target: subject.longitude, actual: destination.longitude),
                               0, accuracy: 0.000001)
            }
        }
    }

    func testImpossiblePolarObserverBearingIsRejected() throws {
        let pole = try Coordinate(latitude: 90, longitude: 0)
        XCTAssertThrowsError(try CompositionPlanner.recommendedObserver(subject: pole, bodyAzimuth: 90, distanceMeters: 250))
    }
}
