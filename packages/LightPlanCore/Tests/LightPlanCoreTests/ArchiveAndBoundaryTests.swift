import Foundation
import XCTest
@testable import LightPlanCore

final class ArchiveAndBoundaryTests: XCTestCase {
    private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func plan(id: UUID = UUID(), title: String = "Sunset", reminder: Int? = 30) throws -> ShootPlan {
        try ShootPlan(id: id, title: title, place: .example, date: instant("2026-09-21T04:00:00Z"), target: .sunset, reminderLeadMinutes: reminder, now: instant("2026-09-20T04:00:00Z"))
    }
    private func repository() throws -> ArchiveRepository {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return ArchiveRepository(url: directory.appendingPathComponent("archive-v1.json"))
    }
    func testNewRepositoryIsEmpty() throws {
        let repo = try repository(); XCTAssertEqual(try repo.load(), Archive(places: [], plans: []))
    }
    func testAtomicRepositoryRoundTrip() throws {
        let repo = try repository(), archive = Archive(places: [.example], plans: [try plan()])
        try repo.write(archive); XCTAssertEqual(try repo.load(), archive)
    }
    func testPreviousBytesArePreservedBeforeOverwrite() throws {
        let repo = try repository(), first = Archive(places: [.example], plans: [])
        try repo.write(first); let original = try repo.originalBytes()
        try repo.write(Archive(places: [], plans: [try plan()]))
        let previous = repo.url.deletingLastPathComponent().appendingPathComponent("archive-previous.json")
        XCTAssertEqual(try Data(contentsOf: previous), original)
    }
    func testCorruptionNeverBecomesEmptyData() throws {
        let repo = try repository(), damaged = Data("{ damaged archive".utf8)
        try damaged.write(to: repo.url)
        XCTAssertThrowsError(try repo.load())
        XCTAssertThrowsError(try repo.write(Archive(places: [], plans: [])))
        XCTAssertEqual(try repo.originalBytes(), damaged)
    }
    func testExplicitRecoveryPreservesCorruptOriginal() throws {
        let repo = try repository(), damaged = Data("{ broken".utf8)
        try damaged.write(to: repo.url)
        try repo.write(Archive(places: [.example], plans: []), allowRecovery: true)
        let backups = try FileManager.default.contentsOfDirectory(at: repo.url.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("recovered-") }
        XCTAssertEqual(backups.count, 1); XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), damaged)
        XCTAssertEqual(try repo.load().places, [.example])
    }
    func testInvalidSaveDoesNotTouchOriginal() throws {
        let repo = try repository(); try repo.write(Archive(places: [.example], plans: [])); let original = try repo.originalBytes()
        var bad = try plan(); bad.title = ""
        XCTAssertThrowsError(try repo.write(Archive(places: [], plans: [bad])))
        XCTAssertEqual(try repo.originalBytes(), original)
    }
    func testImportPreviewCountsAndKeepLocalPolicy() throws {
        let a = try plan(), b = try plan(); var changed = a; changed.title = "Changed"
        let local = Archive(places: [.example], plans: [a]), incoming = Archive(places: [.example], plans: [changed, b])
        let preview = try ImportPreview(local: local, incoming: incoming)
        XCTAssertEqual(preview.newPlans, 1); XCTAssertEqual(preview.conflictingPlans, 1); XCTAssertEqual(preview.identicalItems, 1)
        let merged = try preview.merged(with: local, policy: .keepLocal)
        XCTAssertEqual(merged.plans[0], a); XCTAssertEqual(merged.plans[1].id, b.id); XCTAssertNil(merged.plans[1].reminderLeadMinutes)
    }
    func testImportIncomingReplacesOnlyConflictingID() throws {
        let a = try plan(), unrelated = try plan(); var changed = a; changed.title = "Updated"
        let local = Archive(places: [], plans: [a, unrelated])
        let merged = try ImportPreview(local: local, incoming: Archive(places: [], plans: [changed])).merged(with: local, policy: .useIncoming)
        XCTAssertEqual(merged.plans[0].title, "Updated"); XCTAssertEqual(merged.plans[1], unrelated)
        XCTAssertNil(merged.plans[0].reminderLeadMinutes)
    }
    func testImportCanExplicitlyPreserveReminderIntent() throws {
        let a = try plan(), local = Archive(places: [], plans: [])
        let merged = try ImportPreview(local: local, incoming: Archive(places: [], plans: [a])).merged(with: local, policy: .keepLocal, enableImportedReminders: true)
        XCTAssertEqual(merged.plans[0].reminderLeadMinutes, 30)
    }
    func testIdenticalImportDoesNotDisableLocalReminder() throws {
        let local = Archive(places: [], plans: [try plan()])
        let merged = try ImportPreview(local: local, incoming: local).merged(with: local, policy: .useIncoming)
        XCTAssertEqual(merged.plans[0].reminderLeadMinutes, 30)
    }
    func testSubsecondRoundTripIsNotAConflict() throws {
        var a = try plan(); a.createdAt = a.createdAt.addingTimeInterval(0.456); a.updatedAt = a.createdAt
        let local = Archive(places: [], plans: [a]), incoming = try Archive.decode(local.encoded())
        let preview = try ImportPreview(local: local, incoming: incoming)
        XCTAssertEqual(preview.conflictingPlans, 0); XCTAssertEqual(preview.identicalItems, 1)
    }
    func testImportStableOrderAndUniqueIDs() throws {
        let a = try plan(), b = try plan(), c = try plan()
        let local = Archive(places: [], plans: [a, b])
        let merged = try ImportPreview(local: local, incoming: Archive(places: [], plans: [c, b])).merged(with: local, policy: .keepLocal)
        XCTAssertEqual(merged.plans.map(\.id), [a.id, b.id, c.id])
    }
    func testMutablePlaceNameStillValidatedAtSave() throws {
        var place = Place.example; place.name = " "
        XCTAssertThrowsError(try Archive(places: [place], plans: []).encoded())
    }
    func testMutablePlanFieldsStillValidatedAtSave() throws {
        var value = try plan(); value.reminderLeadMinutes = 1441
        XCTAssertThrowsError(try Archive(places: [], plans: [value]).encoded())
        value = try plan(); value.updatedAt = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try value.validated())
    }
    func testMalformedIncomingNeverProducesPreview() throws {
        let local = Archive(places: [], plans: [])
        XCTAssertThrowsError(try ImportPreview(local: local, incoming: Archive(places: [.example, .example], plans: [])))
    }
    func testPlanCannotUseSummaryForDifferentDay() throws {
        let p = try plan(); let day = try DayEngine.calculate(place: p.place, date: p.date.addingTimeInterval(86400))
        XCTAssertThrowsError(try Planner.milestones(plan: p, summary: day))
        XCTAssertNil(Planner.reminder(plan: p, summary: day, now: .distantPast))
    }
    func testPlanCannotUseSameIDWithDifferentCoordinates() throws {
        let p = try plan()
        let different = try Place(id: p.place.id, name: "Other", coordinate: Coordinate(latitude: 0, longitude: 0), timeZoneID: p.place.timeZoneID)
        let day = try DayEngine.calculate(place: different, date: p.date)
        XCTAssertThrowsError(try Planner.milestones(plan: p, summary: day))
    }
    func testLocalYearBoundsAllowUTCGuardDays() throws {
        for zoneID in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kathmandu"] {
            let zone = TimeZone(identifier: zoneID)!
            let p = try Place(name: zoneID, coordinate: Coordinate(latitude: 1, longitude: -157), timeZoneID: zoneID)
            for date in [try LocalDay.date(year: 1900, month: 1, day: 1, timeZone: zone), try LocalDay.date(year: 2100, month: 12, day: 31, timeZone: zone)] {
                let day = try DayEngine.calculate(place: p, date: date)
                XCTAssertFalse(day.windows.isEmpty); XCTAssertNotNil(day.first(.sunrise))
            }
        }
    }
    func testOutOfRangeLocalDateRejected() throws {
        let p = Place.example
        XCTAssertThrowsError(try DayEngine.calculate(place: p, date: instant("1899-12-30T12:00:00Z")))
        XCTAssertThrowsError(try ShootPlan(title: "Out of range", place: p, date: instant("2101-01-02T12:00:00Z"), target: .sunset))
    }
    func testRelocationPreservesDestinationCivilDate() throws {
        let source = TimeZone(identifier: "Pacific/Kiritimati")!, destination = TimeZone(identifier: "America/Los_Angeles")!
        let value = try LocalDay.date(year: 2026, month: 9, day: 21, timeZone: source)
        let relocated = try LocalDay.relocating(value, from: source, to: destination)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = destination
        XCTAssertEqual(calendar.component(.day, from: relocated), 21)
        XCTAssertNotEqual(value, relocated)
    }
    func testSkippedRelocatedDateRejected() throws {
        let value = try LocalDay.date(year: 2011, month: 12, day: 30, timeZone: .gmt)
        XCTAssertThrowsError(try LocalDay.relocating(value, from: .gmt, to: TimeZone(identifier: "Pacific/Apia")!))
    }
    func testLunarRiseSetUsesTopocentricSemidiameterNotParallaxTwice() throws {
        let day = try DayEngine.calculate(place: .example, date: instant("2026-09-21T04:00:00Z"))
        for event in day.events.filter({ [.moonrise, .moonset].contains($0.kind) }) {
            let altitude = try Astronomy.position(.moon, at: event.date, coordinate: day.place.coordinate).altitude
            XCTAssertEqual(altitude, Astronomy.horizonThreshold(.moon, at: event.date), accuracy: 0.001)
        }
        XCTAssertTrue(day.events.contains { [.moonrise, .moonset].contains($0.kind) })
    }
    func testSolarAltitudeThresholdChangesWithDistance() {
        let jan = Astronomy.horizonThreshold(.sun, at: instant("2026-01-03T12:00:00Z")), jul = Astronomy.horizonThreshold(.sun, at: instant("2026-07-04T12:00:00Z"))
        XCTAssertLessThan(jan, jul); XCTAssertTrue((-0.85 ... -0.80).contains(jan))
    }
}
