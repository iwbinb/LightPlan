import XCTest
@testable import LightPlanCore

final class CompositionPlanTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_789_617_600)

    private func plan(body: CelestialBody = .moon, instant: Date? = nil) throws -> ShootPlan {
        let subject = try VisualGeometry.destination(from: Place.example.coordinate, bearing: 250, meters: 900)
        let selected = instant ?? time
        let composition = try CompositionPlan(body: body, subject: subject, desiredOffsetDegrees: 10, instant: selected)
        return try ShootPlan(title: "Saved alignment", place: .example, date: selected, target: .composition,
                             arrivalLeadMinutes: 45, reminderLeadMinutes: 30, now: time, composition: composition)
    }
    private func legacyBytes() throws -> Data {
        let normal = try ShootPlan(title: "Legacy sunset", place: .example, date: time, target: .sunset, now: time)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Archive(places: [.example], plans: [normal]).encoded()) as? [String: Any])
        json["schemaVersion"] = 1
        return try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
    }

    func testCompositionRoundTripPreservesFullSnapshot() throws {
        let original = try plan()
        let restored = try Archive.decode(Archive(places: [.example], plans: [original]).encoded())
        XCTAssertEqual(restored.schemaVersion, 2)
        XCTAssertEqual(restored.plans, [original])
        XCTAssertEqual(restored.plans[0].composition?.body, .moon)
        XCTAssertEqual(restored.plans[0].composition?.instant, time)
        XCTAssertEqual(restored.plans[0].composition?.desiredOffsetDegrees, 10)
    }

    func testLegacyArchiveRemainsReadableAndUpgradesOnWrite() throws {
        let old = try Archive.decode(legacyBytes())
        XCTAssertEqual(old.schemaVersion, 1)
        XCTAssertEqual(old.plans[0].target, .sunset)
        XCTAssertNil(old.plans[0].composition)
        let current = try Archive.decode(old.encoded())
        XCTAssertEqual(current.schemaVersion, 2)
        XCTAssertEqual(current.plans, old.plans)
        XCTAssertEqual(current.places, old.places)
    }

    func testMigrationPreservesOriginalBytesBeyondLaterWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = ArchiveRepository(url: directory.appendingPathComponent("archive-v1.json"))
        let original = try legacyBytes()
        try original.write(to: repository.url)
        var migrated = try repository.load()
        migrated.plans.append(try plan())
        try repository.write(migrated)
        try repository.write(repository.load())
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("archive-schema-1-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
        XCTAssertEqual(try repository.load().schemaVersion, 2)
        XCTAssertEqual(try repository.load().plans.count, 2)
    }

    func testReminderAndMilestonesUseAlignmentInsteadOfSunset() throws {
        let value = try plan()
        let day = try DayEngine.calculate(place: value.place, date: value.date)
        XCTAssertEqual(Planner.anchorDate(plan: value, summary: day), time)
        XCTAssertNotEqual(day.first(.sunset)?.date, time)
        XCTAssertEqual(Planner.reminder(plan: value, summary: day, now: time.addingTimeInterval(-3600)), time.addingTimeInterval(-1800))
        let rows = try Planner.milestones(plan: value, summary: day)
        XCTAssertEqual(rows.map(\.key), ["plan.arrival", "target.composition"])
        XCTAssertEqual(rows.map(\.date), [time.addingTimeInterval(-2700), time])
        XCTAssertNil(Planner.reminder(plan: value, summary: day, now: time.addingTimeInterval(-1800)))
    }

    func testReminderCanCrossTheDestinationMidnight() throws {
        let interval = try LocalDay.interval(containing: time, timeZone: Place.example.timeZone)
        let value = try plan(instant: interval.start.addingTimeInterval(600))
        let day = try DayEngine.calculate(place: value.place, date: value.date)
        let fire = try XCTUnwrap(Planner.reminder(plan: value, summary: day, now: interval.start.addingTimeInterval(-7200)))
        XCTAssertEqual(fire, interval.start.addingTimeInterval(-1200))
        XCTAssertFalse(LocalDay.same(fire, value.date, timeZone: value.place.timeZone))
    }

    func testRepeatedDSTTimeRetainsItsAbsoluteInstant() throws {
        let place = try Place(name: "New York", coordinate: Coordinate(latitude: 40.7128, longitude: -74.006), timeZoneID: "America/New_York")
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T06:30:00Z"))
        let composition = try CompositionPlan(body: .moon, subject: Coordinate(latitude: 40.72, longitude: -74.01), desiredOffsetDegrees: -10, instant: instant)
        let value = try ShootPlan(title: "Second 01:30", place: place, date: instant, target: .composition, now: time, composition: composition)
        let restored = try XCTUnwrap(Archive.decode(Archive(places: [], plans: [value]).encoded()).plans.first)
        let day = try DayEngine.calculate(place: place, date: instant)
        XCTAssertEqual(day.end.timeIntervalSince(day.start), 25 * 3600)
        XCTAssertEqual(restored.composition?.instant, instant)
        XCTAssertEqual(Planner.reminder(plan: restored, summary: day, now: time), instant.addingTimeInterval(-1800))
    }

    func testCompositionRequiresMatchingTargetAndDay() throws {
        let value = try plan()
        XCTAssertThrowsError(try ShootPlan(title: "Missing", place: .example, date: time, target: .composition))
        XCTAssertThrowsError(try ShootPlan(title: "Unexpected", place: .example, date: time, target: .sunset, composition: value.composition))
        let next = try LocalDay.interval(containing: time, timeZone: Place.example.timeZone).end
        XCTAssertThrowsError(try ShootPlan(title: "Wrong day", place: .example, date: next, target: .composition, composition: value.composition))
    }

    func testCompositionRejectsInvalidGeometryAndOffset() throws {
        XCTAssertThrowsError(try CompositionPlan(body: .sun, subject: .init(latitude: 0, longitude: 0), desiredOffsetDegrees: .nan, instant: time))
        XCTAssertThrowsError(try CompositionPlan(body: .sun, subject: .init(latitude: 0, longitude: 0), desiredOffsetDegrees: 91, instant: time))
        let coincident = try CompositionPlan(body: .sun, subject: Place.example.coordinate, desiredOffsetDegrees: 0, instant: time)
        XCTAssertThrowsError(try ShootPlan(title: "Coincident", place: .example, date: time, target: .composition, composition: coincident))
    }

    func testMalformedOrMisversionedCompositionArchiveIsRejected() throws {
        let bytes = try Archive(places: [], plans: [plan()]).encoded()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        json["schemaVersion"] = 1
        XCTAssertThrowsError(try Archive.decode(JSONSerialization.data(withJSONObject: json)))
        json["schemaVersion"] = 2
        var plans = try XCTUnwrap(json["plans"] as? [[String: Any]])
        plans[0].removeValue(forKey: "composition")
        json["plans"] = plans
        XCTAssertThrowsError(try Archive.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testImportedCompositionKeepsGeometryAndDisablesReminderByDefault() throws {
        let value = try plan()
        let preview = try ImportPreview(local: Archive(places: [], plans: []), incoming: Archive(places: [], plans: [value]))
        let merged = try preview.merged(with: Archive(places: [], plans: []), policy: .keepLocal)
        XCTAssertEqual(merged.plans[0].composition, value.composition)
        XCTAssertEqual(merged.plans[0].place, value.place)
        XCTAssertNil(merged.plans[0].reminderLeadMinutes)
    }

    func testCompositionCannotUseAnotherObserversSummary() throws {
        let value = try plan()
        let elsewhere = try Place(name: "Elsewhere", coordinate: Coordinate(latitude: 20, longitude: 100), timeZoneID: value.place.timeZoneID)
        let day = try DayEngine.calculate(place: elsewhere, date: value.date)
        XCTAssertNil(Planner.anchorDate(plan: value, summary: day))
        XCTAssertNil(Planner.reminder(plan: value, summary: day, now: .distantPast))
        XCTAssertThrowsError(try Planner.milestones(plan: value, summary: day))
    }
}
