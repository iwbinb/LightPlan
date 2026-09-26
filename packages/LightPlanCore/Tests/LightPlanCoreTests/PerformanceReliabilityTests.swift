import XCTest
@testable import LightPlanCore

final class PerformanceReliabilityTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1789632000)

    private func assertSky(_ a: SkyPosition, _ b: SkyPosition, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.azimuth.bitPattern, b.azimuth.bitPattern, file: file, line: line)
        XCTAssertEqual(a.altitude.bitPattern, b.altitude.bitPattern, file: file, line: line)
        XCTAssertEqual(a.apparentAltitude.bitPattern, b.apparentAltitude.bitPattern, file: file, line: line)
    }

    func testExactDateCacheReusesSkyWithoutQuantizingNearbyInstants() throws {
        var cache = SearchSkyCache(coordinate: Place.example.coordinate)
        let original = try cache.position(.sun, at: instant)
        assertSky(original, try cache.position(.sun, at: instant))
        XCTAssertEqual(cache.calculationCount, 1)
        let nearby = instant.addingTimeInterval(0.0001)
        assertSky(try cache.position(.sun, at: nearby), try Astronomy.position(.sun, at: nearby, coordinate: Place.example.coordinate))
        XCTAssertEqual(cache.calculationCount, 2)
    }

    func testCacheSeparatesSunAndMoon() throws {
        var cache = SearchSkyCache(coordinate: Place.example.coordinate)
        for body in CelestialBody.allCases {
            assertSky(try cache.position(body, at: instant), try Astronomy.position(body, at: instant, coordinate: Place.example.coordinate))
        }
        XCTAssertEqual(cache.count, 2)
    }

    func testObserverCachesCannotLeakBetweenRequests() throws {
        let other = try Coordinate(latitude: -33.8, longitude: 151.2)
        var a = SearchSkyCache(coordinate: Place.example.coordinate)
        var b = SearchSkyCache(coordinate: other)
        let first = try a.position(.sun, at: instant)
        let second = try b.position(.sun, at: instant)
        XCTAssertNotEqual(first.azimuth.bitPattern, second.azimuth.bitPattern)
        assertSky(second, try Astronomy.position(.sun, at: instant, coordinate: other))
    }

    func testCapacityDoesNotChangeSkyAndZeroDisablesStorage() throws {
        for capacity in [0, 2] {
            var cache = SearchSkyCache(coordinate: Place.example.coordinate, capacity: capacity)
            for seconds in 0..<8 {
                let date = instant.addingTimeInterval(Double(seconds))
                assertSky(try cache.position(.sun, at: date), try Astronomy.position(.sun, at: date, coordinate: Place.example.coordinate))
            }
            XCTAssertEqual(cache.count, capacity)
            XCTAssertEqual(cache.calculationCount, 8)
        }
        XCTAssertEqual(SearchSkyCache(coordinate: Place.example.coordinate, capacity: Int.max).capacity, 4096)
    }

    func testInvalidDatesDoNotPolluteCache() throws {
        var cache = SearchSkyCache(coordinate: Place.example.coordinate)
        for date in [Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity), .distantPast] {
            XCTAssertThrowsError(try cache.position(.sun, at: date))
        }
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.calculationCount, 0)
        XCTAssertNoThrow(try cache.position(.sun, at: instant))
    }

    @MainActor func testCancelledCacheHitStillThrows() async throws {
        let date = instant
        let task = Task.detached {
            var cache = SearchSkyCache(coordinate: Place.example.coordinate)
            _ = try cache.position(.sun, at: date)
            withUnsafeCurrentTask { $0?.cancel() }
            return try cache.position(.sun, at: date)
        }
        do { _ = try await task.value; XCTFail("Cache hits must check cancellation") }
        catch is CancellationError { }
    }

    func testSharedLightingAlignmentSamplesAreBitExactAgainstUncachedSearch() throws {
        let coordinates = [Place.example.coordinate, try Coordinate(latitude: 70, longitude: 20)]
        for coordinate in coordinates {
            let subject = try VisualGeometry.destination(from: coordinate, bearing: 80, meters: 1000)
            let place = try Place(name: "Reference", coordinate: coordinate, timeZoneID: "Europe/Oslo")
            let day = try LocalDay.interval(containing: instant, timeZone: place.timeZone)
            for body in CelestialBody.allCases {
                var cache = SearchSkyCache(coordinate: coordinate)
                let position: (CelestialBody, Date) throws -> SkyPosition = { try cache.position($0, at: $1) }
                let uncached = try OpportunitySearch.intervals(body: body, observer: coordinate, interval: day,
                    altitudeRange: -1...20, solarAltitudeRange: -18...6, step: 300)
                let cached = try OpportunitySearch.intervals(body: body, observer: coordinate, interval: day,
                    altitudeRange: -1...20, solarAltitudeRange: -18...6, step: 300, position: position)
                XCTAssertEqual(cached, uncached)
                let a = try OpportunitySearch.alignmentIntervals(body: body, observer: coordinate, subject: subject,
                    interval: day, desiredOffsetDegrees: 0, maximumErrorDegrees: 3, step: 300)
                let b = try OpportunitySearch.alignmentIntervals(body: body, observer: coordinate, subject: subject,
                    interval: day, desiredOffsetDegrees: 0, maximumErrorDegrees: 3, step: 300, position: position)
                XCTAssertEqual(a, b)
            }
        }
    }

    private func library(_ count: Int = 360) throws -> [PlanLibraryEntry] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = Place.example.timeZone
        let targets: [PlanTarget] = [.goldenMorning, .sunrise, .goldenEvening, .sunset, .blueEvening]
        let plans = try (0..<count).map { index in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: index % 9 - 4, to: instant))
            let id = try XCTUnwrap(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)))
            var plan = try ShootPlan(id: id, title: "Café sunrise \(index)", place: .example, date: date,
                target: targets[index % targets.count], reminderLeadMinutes: nil, now: instant,
                notes: index % 2 == 0 ? "Tripod north" : "港口", collectionName: index % 3 == 0 ? " Coast " : nil)
            if index % 4 == 0 { plan.completedAt = instant.addingTimeInterval(-Double(index % 13)) }
            return plan
        }
        return try PlanLibrary.entries(plans: plans, now: instant, resolveToday: false)
    }

    /// Original M4 comparator retained as an independent reference, not production code.
    private func reference(_ entries: [PlanLibraryEntry], query: String, filter: PlanLibraryFilter, locale: Locale) -> [UUID] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.filter { entry in
            let completed = entry.plan.completedAt != nil
            let include: Bool
            switch filter {
            case .all: include = true
            case .upcoming: include = !completed && !entry.needsTimeResolution && !entry.isPast && !entry.hasNoEventToday
            case .completed: include = completed
            case .past: include = !completed && !entry.needsTimeResolution && entry.isPast
            }
            let text = [entry.plan.title, entry.plan.place.name, entry.plan.notes ?? "", entry.collectionName ?? ""].joined(separator: " ")
            return include && words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil }
        }.sorted { lhs, rhs in
            if filter == .completed {
                let a = lhs.plan.completedAt ?? .distantPast, b = rhs.plan.completedAt ?? .distantPast
                if a != b { return a > b }
            }
            if filter == .all {
                let a = lhs.plan.completedAt != nil ? 2 : (lhs.isPast ? 1 : 0)
                let b = rhs.plan.completedAt != nil ? 2 : (rhs.isPast ? 1 : 0)
                if a != b { return a < b }
            }
            let a = lhs.anchor ?? lhs.destinationDay.start, b = rhs.anchor ?? rhs.destinationDay.start
            if a != b { return filter == .past ? a > b : a < b }
            let order: [PlanTarget] = [.goldenMorning, .sunrise, .goldenEvening, .sunset, .blueEvening, .composition]
            let x = order.firstIndex(of: lhs.plan.target) ?? 0, y = order.firstIndex(of: rhs.plan.target) ?? 0
            if x != y { return x < y }
            return lhs.id.uuidString < rhs.id.uuidString
        }.map(\.id)
    }

    func testDecoratedSortingRetainsEveryFilterLocaleAndTieBreak() throws {
        let values = try library()
        for locale in ["en", "de", "zh-Hans"] {
            for filter in PlanLibraryFilter.allCases {
                for query in ["", "   \n", "CAFE north", "港口", "coast", "unmatched"] {
                    let locale = Locale(identifier: locale)
                    XCTAssertEqual(PlanLibrary.filtered(values, query: query, filter: filter, locale: locale).map(\.id),
                        reference(values, query: query, filter: filter, locale: locale))
                }
            }
        }
    }

    @MainActor func testAsyncGroupsMatchSyncForFiveThousandPlans() async throws {
        let values = try library(5000)
        for filter in PlanLibraryFilter.allCases {
            let sync = PlanLibrary.groups(PlanLibrary.filtered(values, query: "cafe", filter: filter, locale: Locale(identifier: "en")))
            let async = try await PlanLibrary.groupsAsync(values, query: "cafe", filter: filter, locale: Locale(identifier: "en"))
            XCTAssertEqual(async.map(\.id), sync.map(\.id))
            XCTAssertEqual(async.map { $0.entries.map(\.id) }, sync.map { $0.entries.map(\.id) })
        }
    }

    func testFilteringAndGroupingCheckCancellationDuringWork() throws {
        let entries = try library()
        var calls = 0
        XCTAssertThrowsError(try PlanLibrary.filtered(entries, query: "", filter: .all, locale: Locale(identifier: "en"), checkpoint: {
            calls += 1
            if calls > entries.count + 5 { throw CancellationError() }
        })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertGreaterThan(calls, entries.count, "Sorting must also offer cooperative cancellation")
        calls = 0
        XCTAssertThrowsError(try PlanLibrary.groups(entries, checkpoint: {
            calls += 1
            if calls == 10 { throw CancellationError() }
        })) { XCTAssertTrue($0 is CancellationError) }
    }

    @MainActor func testCancelledAsyncLibraryRequestDoesNotReturnOldResults() async throws {
        let entries = try library(5000)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PlanLibrary.groupsAsync(entries)
        }
        do { _ = try await task.value; XCTFail("Cancelled request returned groups") }
        catch is CancellationError { }
        let subsequent = try await PlanLibrary.groupsAsync(entries, query: "unmatched")
        XCTAssertTrue(subsequent.isEmpty)
    }

    @MainActor func testAsyncLibraryRejectsOversizedInput() async throws {
        let entry = try XCTUnwrap(library(1).first)
        do { _ = try await PlanLibrary.groupsAsync(Array(repeating: entry, count: 10001)); XCTFail("Unbounded input accepted") }
        catch { XCTAssertEqual(error as? LightPlanError, .tooManyItems) }
    }

    @MainActor func testVisualSamplingAndProjectionObserveCancellation() async throws {
        let day = try DayEngine.calculate(place: .example, date: instant)
        let samples = try VisualSampler.samples(for: day)
        let sampling = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try VisualSampler.samples(for: day)
        }
        do { _ = try await sampling.value; XCTFail("Cancelled sampling continued") }
        catch is CancellationError { }
        let projection = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try MapProjection.make(summary: day, samples: samples)
        }
        do { _ = try await projection.value; XCTFail("Cancelled projection continued") }
        catch is CancellationError { }
        XCTAssertEqual(try VisualSampler.samples(for: day).map(\.instant), samples.map(\.instant))
    }
}
