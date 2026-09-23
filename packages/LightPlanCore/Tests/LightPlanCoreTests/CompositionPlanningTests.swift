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

    func testOpportunitySearchStopsAtSupportedUpperBoundary() throws {
        let zone = Place.example.timeZone
        let start = try LocalDay.date(year: 2100, month: 12, day: 30, timeZone: zone)
        let subject = try VisualGeometry.destination(from: Place.example.coordinate, bearing: 250, meters: 800)
        let values = try CompositionPlanner.opportunities(
            body: .sun,
            place: .example,
            subject: subject,
            starting: start,
            days: 14,
            limit: 7
        )
        XCTAssertLessThanOrEqual(values.count, 2)
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

    @MainActor func testChangingObserverOnSameDayRecomputesAlignment() async throws {
        let place = Place.example
        let interval = try LocalDay.interval(containing: instant("2026-09-17T04:00:00Z"), timeZone: place.timeZone)
        let subject = try VisualGeometry.destination(from: place.coordinate, bearing: 250, meters: 900)
        let moved = try VisualGeometry.destination(from: place.coordinate, bearing: 0, meters: 500)
        let initial = AlignmentRequest(body: .sun, observer: place.coordinate, subject: subject, interval: interval)
        let updated = AlignmentRequest(body: .sun, observer: moved, subject: subject, interval: interval)
        XCTAssertNotEqual(initial, updated)
        let firstValue = try await CompositionPlanner.bestAlignment(for: initial)
        let nextValue = try await CompositionPlanner.bestAlignment(for: updated)
        let first = try XCTUnwrap(firstValue)
        let next = try XCTUnwrap(nextValue)
        XCTAssertEqual(next.subjectBearing, try XCTUnwrap(Geometry.bearing(from: moved, to: subject)), accuracy: 0.000001)
        XCTAssertGreaterThan(abs(first.subjectBearing - next.subjectBearing), 10)
        XCTAssertGreaterThan(abs(first.instant.timeIntervalSince(next.instant)), 60)
    }

    @MainActor func testMoonSearchFindsKnownVisibleAlignment() async throws {
        let place = Place.example
        let interval = try LocalDay.interval(containing: instant("2026-09-17T04:00:00Z"), timeZone: place.timeZone)
        // Choose a visible lunar position independently of the alignment search.
        var visible: (Date, SkyPosition)?
        for minute in stride(from: 0, to: Int(interval.duration / 60), by: 30) {
            let time = interval.start.addingTimeInterval(Double(minute) * 60)
            let position = try Astronomy.position(.moon, at: time, coordinate: place.coordinate)
            if position.altitude > 5 { visible = (time, position); break }
        }
        let target = try XCTUnwrap(visible)
        let subject = try VisualGeometry.destination(from: place.coordinate, bearing: target.1.azimuth, meters: 500)
        let values = try await CompositionPlanner.opportunitiesAsync(body: .moon, place: place,
            subject: subject, starting: target.0, days: 2, limit: 2)
        XCTAssertFalse(values.isEmpty)
        XCTAssertTrue(values.allSatisfy { $0.body == .moon && $0.altitude >= -1 })
        XCTAssertLessThan(try XCTUnwrap(values.first).absoluteErrorDegrees, 0.15)
    }

    @MainActor func testParentCancellationReachesRunningWorker() async throws {
        let probe = CompositionWorkerProbe()
        let parent = Task {
            try await CompositionPlanner.runCancellable {
                await probe.begin()
                let deadline = ContinuousClock.now.advanced(by: .seconds(2))
                do {
                    while ContinuousClock.now < deadline {
                        try Task.checkCancellation()
                        await Task.yield()
                    }
                    return 1
                } catch is CancellationError {
                    await probe.didCancel()
                    throw CancellationError()
                }
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await probe.started), ContinuousClock.now < deadline { await Task.yield() }
        let started = await probe.started
        XCTAssertTrue(started)
        parent.cancel()
        do { _ = try await parent.value; XCTFail("Cancelled worker must not publish a result") }
        catch is CancellationError { }
        let cancelled = await probe.cancelled
        XCTAssertTrue(cancelled, "Cancellation must reach the worker, not just discard its result")
    }

    @MainActor func testAlreadyCancelledSearchDoesNotStartWorker() async {
        let probe = CompositionWorkerProbe()
        let parent = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CompositionPlanner.runCancellable {
                await probe.begin()
                return 1
            }
        }
        do { _ = try await parent.value; XCTFail("Already cancelled search should throw") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        let started = await probe.started
        XCTAssertFalse(started)
    }
}

private actor CompositionWorkerProbe {
    private(set) var started = false
    private(set) var cancelled = false
    func begin() { started = true }
    func didCancel() { cancelled = true }
}
