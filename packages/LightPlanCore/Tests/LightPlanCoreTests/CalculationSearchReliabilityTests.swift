import XCTest
@testable import LightPlanCore

/// Numerical/contract regression tests. The deliberately near-tangent solar cases
/// use this app's position model, not an external ephemeris accuracy oracle.
final class CalculationSearchReliabilityTests: XCTestCase {
    private func instant(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func target(_ place: Place, bearing: Double = 270) throws -> Coordinate {
        try VisualGeometry.destination(from: place.coordinate, bearing: bearing, meters: 1_000)
    }

    /// Tune an adversarial, valid manual location to put a brief -4-degree crossing
    /// in an edge cell. The peak finder here is independent of SearchSampling.
    private func edgeFixture(_ date: Date) throws -> (Place, Date) {
        let eq = Astronomy.solar(date)
        let julian = Astronomy.jd(date)
        let t = (julian - 2451545) / 36525
        let greenwich = 280.46061837 + 360.98564736629 * (julian - 2451545)
            + 0.000387933 * t * t - t * t * t / 38710000 + eq.siderealCorrection
        let longitude = Astronomy.normalize(eq.ra - greenwich + 180) - 180
        func peak(latitude: Double) throws -> (Date, Double) {
            let coordinate = try Coordinate(latitude: latitude, longitude: longitude)
            var low = date.addingTimeInterval(-30), high = date.addingTimeInterval(30)
            for _ in 0..<40 {
                let width = high.timeIntervalSince(low)
                let a = low.addingTimeInterval(width / 3), b = high.addingTimeInterval(-width / 3)
                let left = try Astronomy.position(.sun, at: a, coordinate: coordinate).altitude
                let right = try Astronomy.position(.sun, at: b, coordinate: coordinate).altitude
                if left < right { low = a } else { high = b }
            }
            let best = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            return (best, try Astronomy.position(.sun, at: best, coordinate: coordinate).altitude)
        }
        var low = 70.0, high = 71.0
        let wantedAltitude = -4.0 + 0.0000005
        for _ in 0..<42 {
            let middle = (low + high) / 2
            if try peak(latitude: middle).1 > wantedAltitude { low = middle } else { high = middle }
        }
        let latitude = (low + high) / 2
        let best = try peak(latitude: latitude)
        XCTAssertEqual(best.1, wantedAltitude, accuracy: 0.00000001)
        let place = try Place(name: "Numerical edge fixture", coordinate: Coordinate(latitude: latitude, longitude: longitude),
                              timeZoneID: "Etc/UTC")
        return (place, best.0)
    }

    private func assertEdgeEvents(at string: String, firstCell: Bool) throws {
        let (place, peak) = try edgeFixture(instant(string))
        let day = try LocalDay.interval(containing: peak, timeZone: place.timeZone)
        let offset = peak.timeIntervalSince(day.start)
        XCTAssertTrue(firstCell ? (0..<30).contains(offset) : (day.duration - 30..<day.duration).contains(offset))
        let cellStart = firstCell ? day.start : day.end.addingTimeInterval(-60)
        let cellEnd = cellStart.addingTimeInterval(60)
        // Both grid endpoints miss the short excursion. This is the actual regression.
        XCTAssertLessThan(try Astronomy.position(.sun, at: cellStart, coordinate: place.coordinate).altitude, -4)
        XCTAssertLessThan(try Astronomy.position(.sun, at: cellEnd, coordinate: place.coordinate).altitude, -4)
        XCTAssertGreaterThan(try Astronomy.position(.sun, at: peak, coordinate: place.coordinate).altitude, -4)
        let summary = try DayEngine.calculate(place: place, date: peak)
        let events = summary.events.filter { abs($0.date.timeIntervalSince(peak)) < 10 }
        XCTAssertEqual(events.map(\.kind), [.goldenMorningStart, .goldenEveningEnd])
        guard events.count == 2 else { return }
        XCTAssertLessThan(events[0].date, peak)
        XCTAssertGreaterThan(events[1].date, peak)
        XCTAssertGreaterThan(events[1].date.timeIntervalSince(events[0].date), 0.2)
        XCTAssertLessThan(events[1].date.timeIntervalSince(events[0].date), 20)
        XCTAssertTrue(summary.windows.contains { $0.band == .golden && $0.start <= peak && peak < $0.end })
        XCTAssertTrue(summary.events.allSatisfy { day.start <= $0.date && $0.date < day.end })
    }

    func testShortGoldenWindowAtStartOfCivilDayIsRetained() throws {
        try assertEdgeEvents(at: "2026-12-21T00:00:10Z", firstCell: true)
    }

    func testShortGoldenWindowAtEndOfCivilDayIsRetained() throws {
        try assertEdgeEvents(at: "2026-12-21T23:59:50Z", firstCell: false)
    }

    func testDaySamplingRejectsNonprogressingSteps() throws {
        let start = try instant("2026-09-17T00:00:00Z")
        for step in [0, -1, Double.nan, Double.infinity, Double.leastNonzeroMagnitude] {
            XCTAssertThrowsError(try DayEngine.samples(body: .sun, start: start, end: start.addingTimeInterval(60),
                coordinate: Place.example.coordinate, step: step)) {
                    XCTAssertEqual($0 as? LightPlanError, .invalidNumber)
                }
        }
    }

    func testScalarSearchRejectsBadStepsBeforeProducingEmptyResults() throws {
        let day = DateInterval(start: try instant("2026-01-01T00:00:00Z"), duration: 1_200)
        for step in [0, -1, Double.nan, Double.infinity, Double.leastNonzeroMagnitude] {
            XCTAssertThrowsError(try OpportunitySearch.scalarIntervals(interval: day, range: 0...1, step: step) { _ in 2 }) {
                XCTAssertEqual($0 as? LightPlanError, .invalidNumber)
            }
        }
    }

    func testInvalidAlignmentToleranceDoesNotConstructAReversedRange() throws {
        let place = Place.example
        let day = try LocalDay.interval(containing: instant("2026-09-17T04:00:00Z"), timeZone: place.timeZone)
        for error in [-1, 181, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try OpportunitySearch.alignmentIntervals(body: .sun, observer: place.coordinate,
                subject: target(place), interval: day, desiredOffsetDegrees: 0, maximumErrorDegrees: error, step: 300)) {
                    XCTAssertEqual($0 as? LightPlanError, .invalidNumber)
                }
        }
    }

    func testNonfiniteCalculationIsAnErrorNotNoMatch() throws {
        let day = DateInterval(start: try instant("2026-01-01T00:00:00Z"), duration: 1_200)
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try OpportunitySearch.scalarIntervals(interval: day, range: 0...1, step: 300) { _ in bad }) {
                XCTAssertEqual($0 as? LightPlanError, .invalidNumber)
            }
        }
    }

    func testZeroWidthConditionStillMeansNoPositiveDuration() throws {
        let day = DateInterval(start: try instant("2026-01-01T00:00:00Z"), duration: 1_200)
        XCTAssertTrue(try OpportunitySearch.scalarIntervals(interval: day, range: 0.5...0.5, step: 300) { _ in 0.5 }.isEmpty)
    }

    func testScalarWindowAtShortLastGridCellHasBothBoundaries() throws {
        let start = try instant("2026-01-01T00:00:00Z")
        let day = DateInterval(start: start, duration: 1_210)
        let windows = try OpportunitySearch.scalarIntervals(interval: day, range: -0.0001...1, step: 300) {
            -pow($0.timeIntervalSince(start) - 1_208.75, 2)
        }
        XCTAssertEqual(windows.count, 1)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(window.start.timeIntervalSince(start), 1_208.74, accuracy: 0.0002)
        XCTAssertEqual(window.end.timeIntervalSince(start), 1_208.76, accuracy: 0.0002)
    }

    func testSunAndMoonKeepWholeDestinationDaysAcrossOffsetChanges() throws {
        for (zone, latitude, longitude, seed, hours) in [
            ("America/New_York", 40.7128, -74.0060, "2026-03-08T16:00:00Z", 23.0),
            ("America/New_York", 40.7128, -74.0060, "2026-11-01T17:00:00Z", 25.0),
            ("Australia/Lord_Howe", -31.55, 159.08, "2026-04-05T02:00:00Z", 24.5),
            ("Australia/Lord_Howe", -31.55, 159.08, "2026-10-04T02:00:00Z", 23.5),
            ("Pacific/Apia", -13.8, -171.75, "2011-12-29T22:00:00Z", 24.0),
            ("Pacific/Kwajalein", 8.72, 167.73, "1969-09-29T13:30:00Z", 47.0),
            ("Asia/Kathmandu", 27.72, 85.32, "2026-09-17T06:15:00Z", 24.0)
        ] {
            let place = try Place(name: zone, coordinate: Coordinate(latitude: latitude, longitude: longitude), timeZoneID: zone)
            for body in CelestialBody.allCases {
                let result = try CompositionPlanner.opportunityWindows(body: body, place: place,
                    subject: target(place), starting: instant(seed), days: 2,
                    constraints: OpportunityConstraints(altitudeRange: -90...90))
                XCTAssertEqual(result.dayCount, 2)
                XCTAssertEqual(result.windows.count, 2)
                let windows = result.windows.sorted { $0.interval.start < $1.interval.start }
                XCTAssertEqual(windows.first?.interval.duration ?? 0, hours * 3_600, accuracy: 0.001)
                guard windows.count == 2 else { continue }
                XCTAssertEqual(windows[0].interval.end, windows[1].interval.start)
                for window in windows {
                    XCTAssertEqual(window.best.body, body)
                    XCTAssertTrue(window.interval.start <= window.best.instant && window.best.instant < window.interval.end)
                    XCTAssertTrue(LocalDay.same(window.best.instant, window.interval.start, timeZone: place.timeZone))
                }
            }
        }
    }

    func testSearchStopsAtSupportedCivilYearInBothExtremeTimeZones() throws {
        for zone in ["Pacific/Kiritimati", "Etc/GMT+12"] {
            let place = try Place(name: zone, coordinate: Coordinate(latitude: 0, longitude: 179), timeZoneID: zone)
            for body in CelestialBody.allCases {
                let first = try LocalDay.date(year: 1900, month: 1, day: 1, timeZone: place.timeZone)
                let last = try LocalDay.date(year: 2100, month: 12, day: 31, timeZone: place.timeZone)
                for (date, expectedDays) in [(first, 2), (last, 1)] {
                    let result = try CompositionPlanner.opportunityWindows(body: body, place: place,
                        subject: target(place), starting: date, days: 2,
                        constraints: OpportunityConstraints(altitudeRange: -90...90))
                    XCTAssertEqual(result.dayCount, expectedDays)
                    XCTAssertEqual(result.windows.count, expectedDays)
                    for window in result.windows {
                        XCTAssertNoThrow(try LocalDay.validate(window.best.instant, timeZone: place.timeZone))
                    }
                }
            }
        }
    }

    func testContradictorySunConditionsAreAValidEmptySearch() throws {
        let place = Place.example
        let result = try CompositionPlanner.opportunityWindows(body: .sun, place: place,
            subject: target(place), starting: instant("2026-09-17T04:00:00Z"), days: 1,
            constraints: OpportunityConstraints(altitudeRange: 0...10, solarAltitudeRange: -20 ... -10))
        XCTAssertEqual(result.dayCount, 1)
        XCTAssertTrue(result.windows.isEmpty)
        XCTAssertFalse(result.isTruncated)
    }

    func testCancellationDoesNotPoisonNextBodySearch() async throws {
        let place = Place.example
        let subject = try target(place)
        let date = try instant("2026-09-17T04:00:00Z")
        let conditions = try OpportunityConstraints(altitudeRange: -90...90)
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CompositionPlanner.opportunityWindowsAsync(body: .sun, place: place,
                subject: subject, starting: date, days: 90, constraints: conditions)
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled search must not publish results") }
        catch is CancellationError { }
        let result = try await CompositionPlanner.opportunityWindowsAsync(body: .moon, place: place,
            subject: subject, starting: date, days: 1, desiredOffsetDegrees: 20, constraints: conditions)
        let best = try XCTUnwrap(result.windows.first?.best)
        XCTAssertEqual(best.body, .moon)
        XCTAssertEqual(best.desiredOffsetDegrees, 20)
    }

    func testSimultaneousBodySearchesDoNotShareConditionsOrResults() async throws {
        let place = Place.example
        let subject = try target(place)
        let date = try instant("2026-09-17T04:00:00Z")
        let conditions = try OpportunityConstraints(altitudeRange: -90...90)
        async let sun = CompositionPlanner.opportunityWindowsAsync(body: .sun, place: place,
            subject: subject, starting: date, days: 1, desiredOffsetDegrees: -15, constraints: conditions)
        async let moon = CompositionPlanner.opportunityWindowsAsync(body: .moon, place: place,
            subject: subject, starting: date, days: 1, desiredOffsetDegrees: 20, constraints: conditions)
        let (solar, lunar) = try await (sun, moon)
        for (result, body, offset) in [(solar, CelestialBody.sun, -15.0), (lunar, .moon, 20.0)] {
            let best = try XCTUnwrap(result.windows.first?.best)
            XCTAssertEqual(best.body, body)
            XCTAssertEqual(best.desiredOffsetDegrees, offset)
            let direct = try XCTUnwrap(CompositionPlanner.evaluate(body: body, at: best.instant,
                observer: place.coordinate, subject: subject, desiredOffsetDegrees: offset))
            XCTAssertEqual(best.bodyAzimuth, direct.bodyAzimuth, accuracy: 0.0000001)
            XCTAssertEqual(best.altitude, direct.altitude, accuracy: 0.0000001)
        }
    }
}
