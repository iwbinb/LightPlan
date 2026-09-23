import XCTest
@testable import LightPlanCore

final class PlanLibraryTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_789_617_600)
    private func plan(place: Place = .example, date: Date? = nil, target: PlanTarget = .sunset,
                      title: String = "Waterfront", notes: String? = nil, collection: String? = nil,
                      completed: Date? = nil) throws -> ShootPlan {
        try ShootPlan(title: title, place: place, date: date ?? instant, target: target,
                      now: instant, notes: notes, collectionName: collection, completedAt: completed)
    }

    func testCollectionAndCompletionPersistWithoutChangingExistingPlanData() throws {
        let original = try plan(notes: "Tripod by the northern path", collection: "Autumn trip", completed: instant)
        let decoded = try Archive.decode(Archive(places: [.example], plans: [original]).encoded())
        XCTAssertEqual(decoded.plans, [original])
        XCTAssertEqual(decoded.plans[0].collectionName, "Autumn trip")
        XCTAssertEqual(decoded.plans[0].completedAt, instant)
    }

    func testOldArchivesWithoutLibraryFieldsRemainReadableInBothSchemas() throws {
        for version in [1, 2] {
            let original = try plan()
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Archive(places: [], plans: [original]).encoded()) as? [String: Any])
            json["schemaVersion"] = version
            var plans = try XCTUnwrap(json["plans"] as? [[String: Any]])
            plans[0].removeValue(forKey: "collectionName")
            plans[0].removeValue(forKey: "completedAt")
            json["plans"] = plans
            let decoded = try Archive.decode(JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(decoded.plans[0].collectionName)
            XCTAssertNil(decoded.plans[0].completedAt)
            XCTAssertEqual(decoded.plans[0], original)
        }
    }

    func testInvalidLibraryValuesAreRejectedOnCreateAndArchiveDecode() throws {
        XCTAssertThrowsError(try plan(collection: String(repeating: "x", count: 61)))
        XCTAssertThrowsError(try plan(completed: Date(timeIntervalSince1970: .infinity)))
        XCTAssertNoThrow(try plan(collection: String(repeating: "旅", count: 60)))
        var invalid = try plan()
        invalid.collectionName = String(repeating: "x", count: 61)
        XCTAssertThrowsError(try invalid.validated())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try Archive.decode(encoder.encode(Archive(places: [], plans: [invalid]))))
    }

    func testCompletedPlanCannotScheduleAnOldEnabledReminder() throws {
        let original = try plan(completed: instant)
        let day = try DayEngine.calculate(place: original.place, date: original.date)
        XCTAssertNil(Planner.reminder(plan: original, summary: day, now: day.start))
        var reopened = original
        reopened.completedAt = nil
        XCTAssertNotNil(Planner.reminder(plan: reopened, summary: day, now: day.start))
    }

    func testSearchMatchesAllWordsAcrossTitlePlaceNotesAndProject() throws {
        let original = try plan(title: "Café reflections", notes: "Tripod north gate", collection: "Autumn trip")
        let entries = try PlanLibrary.entries(plans: [original], now: instant.addingTimeInterval(-7 * 3600 * 24))
        XCTAssertEqual(PlanLibrary.filtered(entries, query: "CAFE gate autumn", locale: Locale(identifier: "en")).map(\.id), [original.id])
        XCTAssertEqual(PlanLibrary.filtered(entries, query: original.place.name).count, 1)
        XCTAssertTrue(PlanLibrary.filtered(entries, query: "mountain").isEmpty)
        XCTAssertEqual(PlanLibrary.filtered(entries, query: "   \n  ").count, 1)
    }

    func testTodayUsesActualSunriseAndSunsetInsteadOfArbitraryStoredDate() throws {
        let morning = try plan(target: .sunrise)
        let evening = try plan(target: .sunset)
        let summary = try DayEngine.calculate(place: morning.place, date: morning.date)
        let sunrise = try XCTUnwrap(summary.first(.sunrise)?.date)
        let sunset = try XCTUnwrap(summary.first(.sunset)?.date)
        let now = sunrise.addingTimeInterval(sunset.timeIntervalSince(sunrise) / 2)
        let entries = try PlanLibrary.entries(plans: [morning, evening], now: now)
        XCTAssertEqual(PlanLibrary.filtered(entries, filter: .past).map(\.id), [morning.id])
        XCTAssertEqual(PlanLibrary.filtered(entries, filter: .upcoming).map(\.id), [evening.id])
        XCTAssertEqual(entries[0].anchor, sunrise)
        XCTAssertEqual(entries[1].anchor, sunset)
    }

    func testCompositionInstantAndCompletionOverrideDestinationDayStatus() throws {
        let subject = try VisualGeometry.destination(from: Place.example.coordinate, bearing: 250, meters: 900)
        let composition = try CompositionPlan(body: .moon, subject: subject, desiredOffsetDegrees: 0, instant: instant)
        var original = try ShootPlan(title: "Moon", place: .example, date: instant, target: .composition, now: instant, composition: composition)
        var entries = try PlanLibrary.entries(plans: [original], now: instant.addingTimeInterval(-1))
        XCTAssertEqual(PlanLibrary.filtered(entries, filter: .upcoming).count, 1)
        entries = try PlanLibrary.entries(plans: [original], now: instant)
        XCTAssertEqual(PlanLibrary.filtered(entries, filter: .past).count, 1)
        original.completedAt = instant
        entries = try PlanLibrary.entries(plans: [original], now: instant.addingTimeInterval(-1))
        XCTAssertTrue(PlanLibrary.filtered(entries, filter: .upcoming).isEmpty)
        XCTAssertEqual(PlanLibrary.filtered(entries, filter: .completed).count, 1)
    }

    func testDestinationDayKeepsDateLineAndDSTBoundaries() throws {
        let place = try Place(name: "Kiritimati", coordinate: Coordinate(latitude: 1.87, longitude: -157.36), timeZoneID: "Pacific/Kiritimati")
        let value = try plan(place: place)
        let day = try LocalDay.interval(containing: value.date, timeZone: place.timeZone)
        let entries = try PlanLibrary.entries(plans: [value], now: day.end)
        XCTAssertEqual(PlanLibrary.filtered(entries, filter: .past).count, 1)
        XCTAssertEqual(entries[0].destinationDay, day)
        let ny = try Place(name: "New York", coordinate: Coordinate(latitude: 40.7, longitude: -74), timeZoneID: "America/New_York")
        let dstDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z"))
        let dstPlan = try plan(place: ny, date: dstDate)
        let dstEntries = try PlanLibrary.entries(plans: [dstPlan], now: dstDate.addingTimeInterval(-7 * 3600 * 24))
        XCTAssertEqual(dstEntries[0].destinationDay.duration, 25 * 3600)
    }

    func testPolarNoEventDoesNotPromiseAnUpcomingShoot() throws {
        let north = try Place(name: "Longyearbyen", coordinate: Coordinate(latitude: 78.22, longitude: 15.65), timeZoneID: "Arctic/Longyearbyen")
        let winter = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-21T12:00:00Z"))
        let value = try plan(place: north, date: winter, target: .sunrise)
        let entries = try PlanLibrary.entries(plans: [value], now: winter)
        XCTAssertTrue(entries[0].hasNoEventToday)
        XCTAssertTrue(PlanLibrary.filtered(entries, filter: .upcoming).isEmpty)
        XCTAssertEqual(PlanLibrary.filtered(entries).count, 1)
    }

    func testGroupingTrimsNamesAndPreservesDistinctProjectsAndUnfiled() throws {
        let a = try plan(collection: " Coast ")
        let b = try plan(collection: "Coast")
        let c = try plan(collection: "   ")
        let d = try plan(collection: "unfiled")
        let entries = try PlanLibrary.entries(plans: [a, b, c, d], now: instant.addingTimeInterval(-7 * 3600 * 24))
        let groups = PlanLibrary.groups(entries)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].name, "Coast")
        XCTAssertEqual(groups[0].entries.map(\.id), [a.id, b.id])
        XCTAssertNil(groups[1].name)
        XCTAssertNotEqual(groups[1].id, groups[2].id)
    }

    func testFastPassPublishes5000DistinctSitesWithoutInventingEventTimes() throws {
        let plans = try (0..<5000).map { index in
            let place = try Place(name: "Site \(index)", coordinate: Coordinate(latitude: 20 + Double(index) * 0.001,
                longitude: 118), timeZoneID: "Asia/Shanghai")
            return try plan(place: place)
        }
        let entries = try PlanLibrary.entries(plans: plans, now: instant, resolveToday: false)
        XCTAssertEqual(entries.count, 5000)
        XCTAssertTrue(entries.allSatisfy { $0.needsTimeResolution && $0.anchor == nil && !$0.hasNoEventToday })
        XCTAssertTrue(PlanLibrary.filtered(entries, filter: .upcoming).isEmpty)
        XCTAssertTrue(PlanLibrary.filtered(entries, filter: .past).isEmpty)
        XCTAssertEqual(PlanLibrary.filtered(entries, query: "Site 4999").count, 1)
    }

    @MainActor func testResolverReusesOneDayForAllTargetsAndMinuteRefreshes() async throws {
        let resolver = PlanLibraryTimeResolver()
        let sunrise = try plan(target: .sunrise), sunset = try plan(target: .sunset)
        let initial = try await resolver.prepare(plans: [sunrise, sunset], now: instant)
        XCTAssertTrue(initial.allSatisfy(\.needsTimeResolution))
        let resolved = try await resolver.resolve(initial, now: instant)
        XCTAssertTrue(resolved.allSatisfy { !$0.needsTimeResolution && $0.anchor != nil })
        let initialCount = await resolver.calculationCount
        XCTAssertEqual(initialCount, 1)
        let afterSunrise = try XCTUnwrap(resolved[0].anchor).addingTimeInterval(60)
        let refreshed = try await resolver.prepare(plans: [sunrise, sunset], now: afterSunrise)
        XCTAssertTrue(refreshed[0].isPast)
        XCTAssertFalse(refreshed[1].isPast)
        let countAfterRefresh = await resolver.calculationCount
        XCTAssertEqual(countAfterRefresh, 1)
        // An unseen target at the same site/day also uses the retained day result.
        let golden = try plan(target: .goldenEvening)
        let extra = try await resolver.prepare(plans: [golden], now: instant)
        XCTAssertFalse(extra[0].needsTimeResolution)
        XCTAssertNotNil(extra[0].anchor)
    }

    @MainActor func testResolverCachesNoEventWithoutConfusingItWithUnresolved() async throws {
        let place = try Place(name: "Polar night", coordinate: Coordinate(latitude: 78.22, longitude: 15.65), timeZoneID: "Arctic/Longyearbyen")
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-21T12:00:00Z"))
        let original = try plan(place: place, date: date, target: .sunrise)
        let resolver = PlanLibraryTimeResolver()
        let initial = try await resolver.prepare(plans: [original], now: date)
        XCTAssertTrue(initial[0].needsTimeResolution)
        XCTAssertFalse(initial[0].hasNoEventToday)
        let resolved = try await resolver.resolve(initial, now: date)
        XCTAssertTrue(resolved[0].hasNoEventToday)
        XCTAssertFalse(resolved[0].needsTimeResolution)
        let refreshed = try await resolver.prepare(plans: [original], now: date.addingTimeInterval(60))
        XCTAssertTrue(refreshed[0].hasNoEventToday)
        XCTAssertFalse(refreshed[0].needsTimeResolution)
        let count = await resolver.calculationCount
        XCTAssertEqual(count, 1)
    }

    @MainActor func testResolverKeysIncludeCoordinatesZoneAndCivilDayButNotPlaceName() async throws {
        let resolver = PlanLibraryTimeResolver()
        let original = try plan()
        let initial = try await resolver.prepare(plans: [original], now: instant)
        _ = try await resolver.resolve(initial, now: instant)
        var renamed = original
        renamed.place = try Place(name: "Same coordinate", coordinate: original.place.coordinate, timeZoneID: original.place.timeZoneID)
        let renamePass = try await resolver.prepare(plans: [renamed], now: instant)
        XCTAssertFalse(renamePass[0].needsTimeResolution)
        let otherZone = try plan(place: Place(name: "Other civil day", coordinate: original.place.coordinate, timeZoneID: "UTC"))
        let zonePass = try await resolver.prepare(plans: [otherZone], now: instant)
        XCTAssertTrue(zonePass[0].needsTimeResolution)
        var next = original
        next.date = try LocalDay.interval(containing: instant, timeZone: original.place.timeZone).end.addingTimeInterval(3600)
        let nextPass = try await resolver.prepare(plans: [next], now: next.date)
        XCTAssertTrue(nextPass[0].needsTimeResolution)
    }

    @MainActor func testCacheBoundEvictsOldDayWithoutDroppingPlans() async throws {
        let resolver = PlanLibraryTimeResolver(capacity: 2)
        let originals = try (0..<3).map { index in
            try plan(place: Place(name: "Site \(index)", coordinate: Coordinate(latitude: 24 + Double(index), longitude: 118), timeZoneID: "Asia/Shanghai"))
        }
        let initial = try await resolver.prepare(plans: originals, now: instant)
        _ = try await resolver.resolve(initial, now: instant)
        let count = await resolver.cachedDayCount
        XCTAssertEqual(count, 2)
        let refreshed = try await resolver.prepare(plans: originals, now: instant)
        XCTAssertEqual(refreshed.count, 3)
        XCTAssertTrue(refreshed[0].needsTimeResolution)
        XCTAssertFalse(refreshed[1].needsTimeResolution)
        XCTAssertFalse(refreshed[2].needsTimeResolution)
    }

    @MainActor func testBatchResolutionCanBeCancelledDuringAstronomy() async throws {
        let resolver = PlanLibraryTimeResolver()
        let originals = try (0..<128).map { index in
            try plan(place: Place(name: "Site \(index)", coordinate: Coordinate(latitude: 20 + Double(index) * 0.01,
                longitude: 118), timeZoneID: "Asia/Shanghai"))
        }
        let initial = try await resolver.prepare(plans: originals, now: instant)
        let time = instant
        let worker = Task { try await resolver.resolve(initial, now: time) }
        try await Task.sleep(for: .milliseconds(20))
        worker.cancel()
        do { _ = try await worker.value; XCTFail("Cancelled batch should not publish a complete result") }
        catch is CancellationError { }
        let calculated = await resolver.calculationCount
        XCTAssertLessThan(calculated, 128)
        // Already completed day entries stay useful after cancellation.
        let resumed = try await resolver.prepare(plans: originals, now: instant)
        XCTAssertEqual(resumed.filter { !$0.needsTimeResolution }.count, calculated)
    }

    func testFastPassKeepsCompletedAndOtherCivilDaysUsable() throws {
        let completed = try plan(completed: instant)
        let yesterday = try plan(date: LocalDay.interval(containing: instant, timeZone: Place.example.timeZone).start.addingTimeInterval(-3600))
        let tomorrow = try plan(date: LocalDay.interval(containing: instant, timeZone: Place.example.timeZone).end.addingTimeInterval(3600))
        let entries = try PlanLibrary.entries(plans: [completed, yesterday, tomorrow], now: instant, resolveToday: false)
        XCTAssertEqual(PlanLibrary.filtered(entries, filter: .completed).map(\.id), [completed.id])
        XCTAssertEqual(PlanLibrary.filtered(entries, filter: .past).map(\.id), [yesterday.id])
        XCTAssertEqual(PlanLibrary.filtered(entries, filter: .upcoming).map(\.id), [tomorrow.id])
    }
}
