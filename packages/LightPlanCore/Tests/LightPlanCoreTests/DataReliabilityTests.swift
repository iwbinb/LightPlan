import Foundation
import XCTest
@testable import LightPlanCore

final class DataReliabilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func plan(id: UUID = UUID(), title: String = "Field plan") throws -> ShootPlan {
        try ShootPlan(id: id, title: title, place: .example, date: now, target: .sunset,
                      now: now, notes: "Keep my notes", collectionName: "Weekend")
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func repository() throws -> ArchiveRepository { ArchiveRepository(url: try folder().appendingPathComponent("archive-v1.json")) }
    private func values(_ title: String) throws -> Archive { Archive(places: [.example], plans: [try plan(title: title)]) }

    func testBoundedReaderIncludesExactLimitAndRejectsOneExtraByte() throws {
        let url = try folder().appendingPathComponent("input")
        try Data(repeating: 1, count: 65_537).write(to: url)
        XCTAssertEqual(try ArchiveFileReader.read(url, maximumBytes: 65_537).count, 65_537)
        XCTAssertThrowsError(try ArchiveFileReader.read(url, maximumBytes: 65_536)) {
            XCTAssertEqual($0 as? LightPlanError, .tooManyItems)
        }
    }
    func testBoundedReaderHandlesEmptyAndInvalidLimit() throws {
        let url = try folder().appendingPathComponent("empty")
        try Data().write(to: url)
        XCTAssertEqual(try ArchiveFileReader.read(url, maximumBytes: 0), Data())
        XCTAssertThrowsError(try ArchiveFileReader.read(url, maximumBytes: -1))
        XCTAssertThrowsError(try ArchiveFileReader.read(url, maximumBytes: Int.max))
    }
    func testOversizeStoredArchiveFailsInsteadOfLookingEmpty() throws {
        let repo = try repository()
        try Data(repeating: 32, count: Archive.maximumBytes + 1).write(to: repo.url)
        XCTAssertThrowsError(try repo.load()) { XCTAssertEqual($0 as? LightPlanError, .tooManyItems) }
        XCTAssertThrowsError(try repo.write(Archive(places: [], plans: [])))
        XCTAssertEqual(try repo.originalBytes().count, Archive.maximumBytes + 1)
    }
    func testReadPermissionErrorDoesNotReturnAnEmptyLibrary() throws {
        let url = try folder().appendingPathComponent("archive-v1.json")
        let repo = ArchiveRepository(url: url, storage: FaultStorage(live: url, fault: .readDenied))
        XCTAssertThrowsError(try repo.load()) { XCTAssertEqual(($0 as NSError).code, NSFileReadNoPermissionError) }
    }
    func testWriteReturnsTheExactPersistedRepresentation() throws {
        let repo = try repository()
        var value = try plan(); value.updatedAt = now.addingTimeInterval(0.456)
        let written = try repo.write(Archive(places: [.example], plans: [value]))
        XCTAssertEqual(written, try repo.load())
        XCTAssertEqual(written, try Archive.decode(Archive(places: [.example], plans: [value]).encoded()))
    }
    func testFailedBackupCannotTouchTheLiveFile() throws {
        let repo = try repository(), first = try values("Original"), second = try values("Changed")
        try repo.write(first)
        let old = try repo.originalBytes()
        let faulty = ArchiveRepository(url: repo.url, storage: FaultStorage(live: repo.url, fault: .backup))
        XCTAssertThrowsError(try faulty.write(second))
        XCTAssertEqual(try repo.originalBytes(), old)
    }
    func testReplacementFailureRestoresOriginalBytes() throws {
        let repo = try repository(), first = try values("Original"), second = try values("Changed")
        try repo.write(first)
        let old = try repo.originalBytes()
        let faulty = ArchiveRepository(url: repo.url, storage: FaultStorage(live: repo.url, fault: .replacement,
                                                                            candidate: try second.encoded()))
        XCTAssertThrowsError(try faulty.write(second))
        XCTAssertEqual(try repo.originalBytes(), old)
        XCTAssertEqual(try repo.load(), first)
    }
    func testFailedReadbackRollsBackAfterActualWrite() throws {
        let repo = try repository(), first = try values("Original"), second = try values("Changed")
        try repo.write(first); let old = try repo.originalBytes()
        let faulty = ArchiveRepository(url: repo.url, storage: FaultStorage(live: repo.url, fault: .readback,
                                                                            candidate: try second.encoded()))
        XCTAssertThrowsError(try faulty.write(second))
        XCTAssertEqual(try repo.originalBytes(), old)
        XCTAssertEqual(try Data(contentsOf: repo.url.deletingLastPathComponent().appendingPathComponent("archive-previous.json")), old)
    }
    func testFirstWriteReadbackFailureLeavesNoPhantomLibrary() throws {
        let repo = try repository(), archive = try values("First")
        let faulty = ArchiveRepository(url: repo.url, storage: FaultStorage(live: repo.url, fault: .readback,
                                                                            candidate: try archive.encoded()))
        XCTAssertThrowsError(try faulty.write(archive))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.path))
        XCTAssertEqual(try repo.load(), Archive(places: [], plans: []))
    }
    func testRollbackFailureIsExplicitAndRetainsIndependentOriginal() throws {
        let repo = try repository(), first = try values("Original"), second = try values("Changed")
        try repo.write(first); let old = try repo.originalBytes()
        let faulty = ArchiveRepository(url: repo.url, storage: FaultStorage(live: repo.url, fault: .rollback,
                                                                            candidate: try second.encoded()))
        XCTAssertThrowsError(try faulty.write(second)) { XCTAssertEqual($0 as? ArchiveRepositoryError, .rollbackFailed) }
        XCTAssertEqual(try Data(contentsOf: repo.url.deletingLastPathComponent().appendingPathComponent("archive-previous.json")), old)
    }
    func testExplicitRecoveryReadbackFailureRestoresCorruptOriginal() throws {
        let repo = try repository(), archive = try values("Recovered")
        let damaged = Data("{ interrupted".utf8); try damaged.write(to: repo.url)
        let faulty = ArchiveRepository(url: repo.url, storage: FaultStorage(live: repo.url, fault: .readback,
                                                                            candidate: try archive.encoded()))
        XCTAssertThrowsError(try faulty.write(archive, allowRecovery: true))
        XCTAssertEqual(try repo.originalBytes(), damaged)
        let originals = try FileManager.default.contentsOfDirectory(at: repo.url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("recovered-") }
        XCTAssertEqual(originals.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(originals.first)), damaged)
    }
    func testLegacyImportPreservesOriginalAndReopensWithoutNetwork() throws {
        let repo = try repository()
        var old = try values("Legacy"); old.schemaVersion = 1
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(old); try original.write(to: repo.url)
        let loaded = try repo.load()
        XCTAssertEqual(loaded.schemaVersion, 1)
        var edited = loaded; edited.plans[0].notes = "Updated offline"
        try repo.write(edited)
        let reopened = try ArchiveRepository(url: repo.url).load()
        XCTAssertEqual(reopened.schemaVersion, 2); XCTAssertEqual(reopened.plans[0].notes, "Updated offline")
        let originals = try FileManager.default.contentsOfDirectory(at: repo.url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("archive-schema-1-") }
        XCTAssertEqual(originals.count, 1); XCTAssertEqual(try Data(contentsOf: XCTUnwrap(originals.first)), original)
    }
    func testPreviewRejectsChangedOrDeletedLocalData() throws {
        let a = try plan(), local = Archive(places: [], plans: [a])
        var incomingPlan = a; incomingPlan.title = "Incoming"
        let preview = try ImportPreview(local: local, incoming: Archive(places: [], plans: [incomingPlan]))
        var changed = local; changed.plans[0].notes = "A newer edit"
        for value in [changed, Archive(places: [], plans: [])] {
            for policy in ImportConflictPolicy.allCases {
                XCTAssertThrowsError(try preview.merged(with: value, policy: policy)) {
                    XCTAssertEqual($0 as? ImportPreviewError, .staleLocalData)
                }
            }
        }
    }
    func testCancelingPreviewDoesNotWriteAndWholeSecondComparisonIsStable() throws {
        let repo = try repository(), archive = try values("Original")
        try repo.write(archive); let original = try repo.originalBytes()
        _ = try ImportPreview(local: archive, incoming: values("Incoming"))
        XCTAssertEqual(try repo.originalBytes(), original)
        var subsecond = archive; subsecond.plans[0].updatedAt = now.addingTimeInterval(0.999)
        let preview = try ImportPreview(local: subsecond, incoming: archive)
        XCTAssertNoThrow(try preview.merged(with: archive, policy: .keepLocal))
    }
    func testConflictCopiesGetUniqueIDsAndNeverDuplicateReminders() throws {
        let a = try plan(), b = try plan(title: "Unrelated")
        var imported = a; imported.title = "Incoming"; imported.notes = "Incoming note"
        var place = Place.example; place.name = "Renamed"
        let local = Archive(places: [.example], plans: [a, b])
        let merged = try ImportPreview(local: local, incoming: Archive(places: [place], plans: [imported]))
            .merged(with: local, policy: .keepBoth, enableImportedReminders: true)
        XCTAssertEqual(merged.plans.count, 3); XCTAssertEqual(merged.places.count, 2)
        XCTAssertEqual(Array(merged.plans.prefix(2)), [a, b])
        let copy = merged.plans[2]
        XCTAssertNotEqual(copy.id, a.id); XCTAssertNil(copy.reminderLeadMinutes)
        XCTAssertEqual(copy.notes, imported.notes); XCTAssertEqual(copy.place, imported.place)
        XCTAssertNotEqual(merged.places[1].id, place.id)
        XCTAssertEqual(merged.places[1].coordinate, place.coordinate)
    }
    func testIdenticalKeepBothImportDoesNotMakeCopiesOrDisableLocalReminders() throws {
        let local = try values("Same")
        XCTAssertEqual(try ImportPreview(local: local, incoming: local).merged(with: local, policy: .keepBoth), local)
    }
    func testCompositionAndFieldScheduleSurviveStorageAndBackupRoundTrip() throws {
        let repo = try repository()
        let subject = try Coordinate(latitude: 24.45, longitude: 118.07)
        let camera = try CameraFraming(focalLength35mm: 135, orientation: .portrait, referenceAltitudeDegrees: 10)
        let composition = try CompositionPlan(body: .moon, subject: subject, desiredOffsetDegrees: -10,
                                              instant: now, cameraFraming: camera)
        let plan = try ShootPlan(title: "Moon trip", place: .example, date: now, target: .composition,
                                 arrivalLeadMinutes: 120, reminderLeadMinutes: 180, now: now, composition: composition,
                                 notes: "Bring tripod", collectionName: "Island")
        try repo.write(Archive(places: [.example], plans: [plan]))
        let reopened = try ArchiveRepository(url: repo.url).load()
        let restored = try ImportPreview(local: Archive(places: [], plans: []), incoming: reopened)
            .merged(with: Archive(places: [], plans: []), policy: .keepLocal)
        let copy = try XCTUnwrap(restored.plans.first)
        XCTAssertEqual(copy.composition, composition); XCTAssertEqual(copy.notes, plan.notes)
        XCTAssertEqual(copy.collectionName, plan.collectionName); XCTAssertNil(copy.reminderLeadMinutes)
        let day = try DayEngine.calculate(place: copy.place, date: copy.date)
        let brief = try PlanFieldBrief(plan: copy, summary: day)
        XCTAssertEqual(brief.shootAt, now); XCTAssertEqual(brief.arriveAt, now.addingTimeInterval(-7200))
        let before = try FieldSessionStatus(arriveAt: brief.arriveAt, shootAt: brief.shootAt, completedAt: nil, now: now.addingTimeInterval(-10800))
        XCTAssertEqual(before.secondsRemaining, 3600)
        XCTAssertEqual(try FieldSessionStatus(arriveAt: brief.arriveAt, shootAt: brief.shootAt, completedAt: nil, now: now.addingTimeInterval(3600)).phase, .passed)
    }
    func testLargeLibraryRoundTripKeepsEveryIDAndNote() throws {
        let repo = try repository()
        let plans = try (0..<1000).map { try plan(title: "Plan \($0)") }
        let archive = Archive(places: [.example], plans: plans)
        try repo.write(archive)
        let loaded = try repo.load()
        XCTAssertEqual(loaded, archive)
        let merged = try ImportPreview(local: Archive(places: [], plans: []), incoming: loaded)
            .merged(with: Archive(places: [], plans: []), policy: .keepLocal)
        XCTAssertEqual(Set(merged.plans.map(\.id)), Set(plans.map(\.id)))
        XCTAssertTrue(merged.plans.allSatisfy { $0.notes == "Keep my notes" && $0.reminderLeadMinutes == nil })
    }
}

/// Real disk I/O with immutable failure rules; no mocked successful writes.
private struct FaultStorage: ArchiveStorage {
    enum Fault: Sendable { case readDenied, backup, replacement, readback, rollback }
    let live: URL
    let fault: Fault
    var candidate = Data()
    private let local = LocalArchiveStorage()
    func read(_ url: URL, bounded: Bool) throws -> Data {
        if url == live, fault == .readDenied { throw CocoaError(.fileReadNoPermission) }
        let bytes = try local.read(url, bounded: bounded)
        if url == live, bytes == candidate, [.readback, .rollback].contains(fault) { throw CocoaError(.fileReadCorruptFile) }
        return bytes
    }
    func write(_ data: Data, to url: URL) throws {
        if url != live, fault == .backup { throw CocoaError(.fileWriteNoPermission) }
        if url == live, fault == .replacement, data == candidate { throw CocoaError(.fileWriteOutOfSpace) }
        if url == live, fault == .rollback, data != candidate { throw CocoaError(.fileWriteOutOfSpace) }
        try local.write(data, to: url)
    }
    func prepare(_ url: URL) throws { try local.prepare(url) }
    func remove(_ url: URL) throws { try local.remove(url) }
}
