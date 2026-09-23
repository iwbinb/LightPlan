import XCTest
@testable import LightPlanCore

final class OpportunityWindowTests: XCTestCase {
    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func subject(from observer: Coordinate, bearing: Double = 270) throws -> Coordinate {
        try VisualGeometry.destination(from: observer, bearing: bearing, meters: 1_000)
    }
    private func assertEligible(_ date: Date, body: CelestialBody, observer: Coordinate, subject: Coordinate,
                                constraints: OpportunityConstraints, file: StaticString = #filePath,
                                line: UInt = #line) throws {
        let candidate = try XCTUnwrap(CompositionPlanner.evaluate(body: body, at: date, observer: observer,
                                                                 subject: subject), file: file, line: line)
        XCTAssertLessThanOrEqual(candidate.absoluteErrorDegrees, constraints.maximumErrorDegrees, file: file, line: line)
        XCTAssertTrue(constraints.altitudeRange.contains(candidate.altitude), file: file, line: line)
        if let range = constraints.solarAltitudeRange {
            XCTAssertTrue(range.contains(try Astronomy.position(.sun, at: date, coordinate: observer).altitude),
                          file: file, line: line)
        }
        if let range = constraints.moonIlluminationRange {
            XCTAssertTrue(range.contains(Astronomy.moonIllumination(at: date)), file: file, line: line)
        }
    }

    func testIlluminationValidationAndBackwardCompatibleDecoding() throws {
        XCTAssertThrowsError(try OpportunityConstraints(moonIlluminationRange: -0.1...1))
        XCTAssertThrowsError(try OpportunityConstraints(moonIlluminationRange: 0...1.1))
        XCTAssertThrowsError(try OpportunityConstraints(moonIlluminationRange: 0...Double.infinity))
        let old = Data(#"{"maximumErrorDegrees":3,"altitudeRange":{"lowerBound":0,"upperBound":10}}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(OpportunityConstraints.self, from: old).moonIlluminationRange)
        let full = try OpportunityConstraints(moonIlluminationRange: 0.8...1)
        XCTAssertEqual(try JSONDecoder().decode(OpportunityConstraints.self, from: JSONEncoder().encode(full)), full)
        for encoded in [#"{"lowerBound":0.9,"upperBound":0.1}"#,
                        #"{"lowerBound":-0.1,"upperBound":1}"#,
                        #"{"lowerBound":0,"upperBound":1.1}"#,
                        #"{"lowerBound":0.1}"#] {
            let data = Data((#"{"maximumErrorDegrees":3,"altitudeRange":{"lowerBound":0,"upperBound":10},"moonIlluminationRange":"# + encoded + "}").utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(OpportunityConstraints.self, from: data))
        }
        XCTAssertNoThrow(try OpportunityConstraints(moonIlluminationRange: 0.5...0.5))
    }

    func testMorningAndEveningWindowsRemainSeparateWithRealBoundaries() throws {
        let place = Place.example
        let target = try subject(from: place.coordinate)
        let constraints = try OpportunityConstraints(altitudeRange: 0...5)
        let result = try CompositionPlanner.opportunityWindows(body: .sun, place: place, subject: target,
            starting: instant("2026-09-17T04:00:00Z"), days: 1, constraints: constraints)
        XCTAssertEqual(result.dayCount, 1)
        XCTAssertEqual(result.windows.count, 2)
        let spans = result.windows.sorted { $0.interval.start < $1.interval.start }
        XCTAssertLessThan(spans[0].interval.end, spans[1].interval.start)
        for span in spans {
            XCTAssertGreaterThan(span.interval.duration, 60)
            XCTAssertTrue(span.interval.contains(span.best.instant))
            for fraction in [0.001, 0.25, 0.5, 0.75, 0.999] {
                try assertEligible(span.interval.start.addingTimeInterval(span.interval.duration * fraction),
                    body: .sun, observer: place.coordinate, subject: target, constraints: constraints)
            }
            for date in [span.interval.start.addingTimeInterval(-0.1), span.interval.end.addingTimeInterval(0.1)] {
                XCTAssertFalse(constraints.altitudeRange.contains(
                    try Astronomy.position(.sun, at: date, coordinate: place.coordinate).altitude))
            }
        }
    }

    func testAzimuthToleranceProducesAnActualShortWindowNotTheWholeAltitudeBand() throws {
        let place = Place.example
        let time = instant("2026-09-17T09:12:13Z")
        let sky = try Astronomy.position(.sun, at: time, coordinate: place.coordinate)
        let target = try subject(from: place.coordinate, bearing: sky.azimuth)
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 0.001, altitudeRange: -90...90)
        let result = try CompositionPlanner.opportunityWindows(body: .sun, place: place, subject: target,
            starting: time, days: 1, constraints: constraints)
        let window = try XCTUnwrap(result.windows.first { $0.interval.contains(time) })
        XCTAssertLessThan(window.interval.duration, 10)
        XCTAssertGreaterThan(window.interval.duration, 0.01)
        XCTAssertLessThan(abs(window.best.instant.timeIntervalSince(time)), 0.05)
        for edge in [window.interval.start, window.interval.end] {
            let value = try XCTUnwrap(CompositionPlanner.evaluate(body: .sun, at: edge,
                observer: place.coordinate, subject: target))
            XCTAssertEqual(value.absoluteErrorDegrees, 0.001, accuracy: 0.000001)
        }
        for outside in [window.interval.start.addingTimeInterval(-0.1), window.interval.end.addingTimeInterval(0.1)] {
            let value = try XCTUnwrap(CompositionPlanner.evaluate(body: .sun, at: outside,
                observer: place.coordinate, subject: target))
            XCTAssertGreaterThan(value.absoluteErrorDegrees, constraints.maximumErrorDegrees)
        }
    }

    func testMoonIlluminationCutoffUsesActualTimeAndSplitsTheDay() throws {
        let place = Place.example
        let time = instant("2026-09-17T04:00:00Z")
        let phase = Astronomy.moonIllumination(at: time)
        let target = try subject(from: place.coordinate)
        let constraints = try OpportunityConstraints(altitudeRange: -90...90, moonIlluminationRange: phase...1)
        let result = try CompositionPlanner.opportunityWindows(body: .moon, place: place, subject: target,
            starting: time, days: 1, constraints: constraints)
        let window = try XCTUnwrap(result.windows.first)
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertLessThan(window.interval.duration, result.interval.duration)
        XCTAssertLessThan(min(abs(window.interval.start.timeIntervalSince(time)),
                              abs(window.interval.end.timeIntervalSince(time))), 0.01)
        XCTAssertEqual(window.moonIllumination, Astronomy.moonIllumination(at: window.best.instant))
        XCTAssertTrue(try XCTUnwrap(constraints.moonIlluminationRange).contains(window.moonIllumination))
        let best = try XCTUnwrap(CompositionPlanner.bestAlignment(body: .moon, observer: place.coordinate,
            subject: target, interval: result.interval, constraints: constraints))
        XCTAssertTrue(try XCTUnwrap(constraints.moonIlluminationRange).contains(Astronomy.moonIllumination(at: best.instant)))
    }

    func testAllConstraintsHoldThroughoutMoonWindows() throws {
        let place = Place.example
        let date = instant("2026-09-17T04:00:00Z")
        let day = try LocalDay.interval(containing: date, timeZone: place.timeZone)
        var known: (Date, SkyPosition)?
        for offset in stride(from: 0.0, to: day.duration, by: 60) {
            let time = day.start.addingTimeInterval(offset)
            let sun = try Astronomy.position(.sun, at: time, coordinate: place.coordinate)
            let moon = try Astronomy.position(.moon, at: time, coordinate: place.coordinate)
            if (-6 ... -4).contains(sun.altitude), moon.altitude > 1 {
                known = (time, moon); break
            }
        }
        let match = try XCTUnwrap(known)
        let phase = Astronomy.moonIllumination(at: match.0)
        let target = try subject(from: place.coordinate, bearing: match.1.azimuth)
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...90,
            solarAltitudeRange: -6 ... -4, moonIlluminationRange: max(0, phase - 0.01)...min(1, phase + 0.01))
        let result = try CompositionPlanner.opportunityWindows(body: .moon, place: place, subject: target,
            starting: date, days: 1, constraints: constraints)
        XCTAssertFalse(result.windows.isEmpty)
        XCTAssertTrue(result.windows.contains { $0.interval.contains(match.0) })
        for window in result.windows {
            try assertEligible(window.best.instant, body: .moon, observer: place.coordinate,
                               subject: target, constraints: constraints)
            for fraction in [0.001, 0.25, 0.5, 0.75, 0.999] {
                try assertEligible(window.interval.start.addingTimeInterval(window.interval.duration * fraction),
                    body: .moon, observer: place.coordinate, subject: target, constraints: constraints)
            }
        }
    }

    func testWindowsAgreeWithIndependentDenseTimeGridAcrossLatitudesAndBodies() throws {
        for (latitude, longitude, date) in [(31.23, 121.47, "2026-09-17T04:00:00Z"),
                                             (68.2, 20.3, "2026-06-21T04:00:00Z"),
                                             (-33.87, 151.2, "2026-12-21T04:00:00Z")] {
            let place = try Place(name: "Sample", coordinate: Coordinate(latitude: latitude, longitude: longitude),
                                  timeZoneID: "Etc/UTC")
            let target = try subject(from: place.coordinate, bearing: 225)
            let constraints = try OpportunityConstraints(maximumErrorDegrees: 40, altitudeRange: -6...60,
                solarAltitudeRange: -18...30, moonIlluminationRange: 0.05...0.95)
            for body in [CelestialBody.sun, .moon] {
                let result = try CompositionPlanner.opportunityWindows(body: body, place: place, subject: target,
                    starting: instant(date), days: 1, limit: 360, constraints: constraints)
                for offset in stride(from: 23.0, to: result.interval.duration, by: 120) {
                    let time = result.interval.start.addingTimeInterval(offset)
                    let value = try XCTUnwrap(CompositionPlanner.evaluate(body: body, at: time,
                        observer: place.coordinate, subject: target))
                    let sun = try Astronomy.position(.sun, at: time, coordinate: place.coordinate)
                    let eligible = value.absoluteErrorDegrees <= constraints.maximumErrorDegrees &&
                        constraints.altitudeRange.contains(value.altitude) &&
                        constraints.solarAltitudeRange!.contains(sun.altitude) &&
                        constraints.moonIlluminationRange!.contains(Astronomy.moonIllumination(at: time))
                    XCTAssertEqual(result.windows.contains { $0.interval.contains(time) }, eligible,
                                   "\(latitude), \(body), \(time)")
                }
            }
        }
    }

    func testSubsecondAltitudeAndAlignmentIntersectionSurvives() throws {
        let place = Place.example
        let time = instant("2026-09-17T09:12:13Z")
        let sky = try Astronomy.position(.sun, at: time, coordinate: place.coordinate)
        let target = try subject(from: place.coordinate, bearing: sky.azimuth)
        let constraints = try OpportunityConstraints(maximumErrorDegrees: 0.001,
            altitudeRange: (sky.altitude - 0.0001)...(sky.altitude + 0.0001))
        let result = try CompositionPlanner.opportunityWindows(body: .sun, place: place, subject: target,
            starting: time, days: 1, constraints: constraints)
        let window = try XCTUnwrap(result.windows.first)
        XCTAssertLessThan(window.interval.duration, 1)
        XCTAssertTrue(window.interval.contains(time))
        try assertEligible(window.best.instant, body: .sun, observer: place.coordinate,
                           subject: target, constraints: constraints)
    }

    func testNearTangentPolarWindowIsNotDropped() throws {
        let place = try Place(name: "Polar", coordinate: Coordinate(latitude: 67.56, longitude: 13.8875),
                              timeZoneID: "Europe/Oslo")
        let result = try CompositionPlanner.opportunityWindows(body: .sun, place: place,
            subject: subject(from: place.coordinate, bearing: 180), starting: instant("2026-12-21T12:00:00Z"),
            days: 1, constraints: OpportunityConstraints())
        let window = try XCTUnwrap(result.windows.first)
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertLessThan(window.interval.duration, 300)
        XCTAssertGreaterThanOrEqual(window.best.altitude, -1)
        XCTAssertTrue(window.interval.contains(instant("2026-12-21T11:02:30Z")))
    }

    func testScalarExtremaRetainNarrowWindowsAndBothBoundaryCells() throws {
        let start = instant("2026-01-01T00:00:00Z")
        for peak in [1.25, 450.25, 1_198.75] {
            let interval = DateInterval(start: start, duration: 1_200)
            let windows = try OpportunitySearch.scalarIntervals(interval: interval, range: -0.0001...1, step: 300) {
                -pow($0.timeIntervalSince(start) - peak, 2)
            }
            XCTAssertEqual(windows.count, 1)
            let window = try XCTUnwrap(windows.first)
            XCTAssertEqual(window.start.timeIntervalSince(start), peak - 0.01, accuracy: 0.0002)
            XCTAssertEqual(window.end.timeIntervalSince(start), peak + 0.01, accuracy: 0.0002)
        }
    }

    func testWindowRangeCountsRealCivilDaysAcrossDSTAndSkippedDates() throws {
        for (zone, latitude, longitude, date, hours) in [
            ("America/New_York", 40.7128, -74.0060, "2026-03-08T16:00:00Z", 23.0),
            ("America/New_York", 40.7128, -74.0060, "2026-11-01T17:00:00Z", 25.0),
            ("Australia/Lord_Howe", -31.55, 159.08, "2026-10-04T02:00:00Z", 23.5),
            ("Pacific/Apia", -13.8, -171.75, "2011-12-29T22:00:00Z", 24.0)
        ] {
            let place = try Place(name: zone, coordinate: Coordinate(latitude: latitude, longitude: longitude), timeZoneID: zone)
            let result = try CompositionPlanner.opportunityWindows(body: .sun, place: place,
                subject: subject(from: place.coordinate), starting: instant(date), days: 3,
                constraints: OpportunityConstraints(altitudeRange: -90...90))
            XCTAssertEqual(result.dayCount, 3)
            XCTAssertEqual(result.windows.count, 3)
            let windows = result.windows.sorted { $0.interval.start < $1.interval.start }
            XCTAssertEqual(windows[0].interval.duration, hours * 3_600, accuracy: 0.001)
            for (a, b) in zip(windows, windows.dropFirst()) { XCTAssertEqual(a.interval.end, b.interval.start) }
            XCTAssertEqual(result.interval.start, windows.first?.interval.start)
            XCTAssertEqual(result.interval.end, windows.last?.interval.end)
        }
    }

    func testNinetyDaySearchAndOutputLimitAreIndependent() throws {
        let place = Place.example
        let target = try subject(from: place.coordinate)
        let date = instant("2026-09-17T04:00:00Z")
        let allSky = try OpportunityConstraints(altitudeRange: -90...90)
        let result = try CompositionPlanner.opportunityWindows(body: .sun, place: place, subject: target,
            starting: date, days: 90, limit: 7, constraints: allSky)
        XCTAssertEqual(result.dayCount, 90)
        XCTAssertEqual(result.windows.count, 7)
        XCTAssertTrue(result.isTruncated)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = place.timeZone
        XCTAssertEqual(calendar.dateComponents([.day], from: result.interval.start, to: result.interval.end).day, 90)
        let legacy = try CompositionPlanner.opportunities(body: .sun, place: place, subject: target,
            starting: date, days: 90, limit: 90, constraints: allSky)
        XCTAssertEqual(legacy.count, 90)
        for days in [0, 91] {
            XCTAssertThrowsError(try CompositionPlanner.opportunityWindows(body: .sun, place: place,
                subject: target, starting: date, days: days, constraints: allSky))
        }
        for limit in [0, 361] {
            XCTAssertThrowsError(try CompositionPlanner.opportunityWindows(body: .sun, place: place,
                subject: target, starting: date, limit: limit, constraints: allSky))
        }
    }

    func testSupportedRangeTruncationAndNoMatchStillCountSearchedDays() throws {
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            let place = try Place(name: zone, coordinate: Coordinate(latitude: 1, longitude: 179), timeZoneID: zone)
            let date = try LocalDay.date(year: 2100, month: 12, day: 30, timeZone: place.timeZone)
            let result = try CompositionPlanner.opportunityWindows(body: .sun, place: place,
                subject: subject(from: place.coordinate), starting: date, days: 90,
                constraints: OpportunityConstraints(altitudeRange: 40...50, solarAltitudeRange: -10 ... -5))
            XCTAssertEqual(result.dayCount, 2)
            XCTAssertTrue(result.windows.isEmpty)
            XCTAssertFalse(result.isTruncated)
            let last = try LocalDay.date(year: 2100, month: 12, day: 31, timeZone: place.timeZone)
            XCTAssertEqual(result.interval.end, try LocalDay.interval(containing: last, timeZone: place.timeZone).end)
        }
    }

    func testEqualityOnlyConstraintDoesNotInventADuration() throws {
        let place = Place.example
        let result = try CompositionPlanner.opportunityWindows(body: .sun, place: place,
            subject: subject(from: place.coordinate), starting: instant("2026-09-17T04:00:00Z"), days: 1,
            constraints: OpportunityConstraints(maximumErrorDegrees: 0))
        XCTAssertEqual(result.dayCount, 1)
        XCTAssertTrue(result.windows.isEmpty)
    }

    func testMoonIlluminationChangesRequestIdentity() throws {
        let place = Place.example
        let interval = try LocalDay.interval(containing: instant("2026-09-17T04:00:00Z"), timeZone: place.timeZone)
        let target = try subject(from: place.coordinate)
        let all = AlignmentRequest(body: .moon, observer: place.coordinate, subject: target, interval: interval,
            constraints: try OpportunityConstraints())
        let bright = AlignmentRequest(body: .moon, observer: place.coordinate, subject: target, interval: interval,
            constraints: try OpportunityConstraints(moonIlluminationRange: 0.8...1))
        XCTAssertNotEqual(all, bright)
    }

    @MainActor func testCancellationDuringNinetyDaySearchDoesNotReturnPartialResults() async throws {
        let place = Place.example
        let target = try subject(from: place.coordinate)
        let date = instant("2026-09-17T04:00:00Z")
        let task = Task {
            try await CompositionPlanner.opportunityWindowsAsync(body: .moon, place: place, subject: target,
                starting: date, days: 90, constraints: OpportunityConstraints(maximumErrorDegrees: 3,
                    altitudeRange: 0...30, solarAltitudeRange: -18...6, moonIlluminationRange: 0.2...0.9))
        }
        try await Task.sleep(for: .milliseconds(2))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must not publish partial windows") }
        catch is CancellationError { }
    }
}
