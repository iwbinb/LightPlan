import Foundation
import XCTest
@testable import LightPlanCore

final class PlanMutationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func plan() throws -> ShootPlan {
        try ShootPlan(title: "Original", place: .example, date: now, target: .sunset,
                      now: now, notes: "Notes", collectionName: "Project")
    }
    func testInsertCannotOverwriteExistingID() throws {
        let a = try plan(), archive = Archive(places: [], plans: [a])
        XCTAssertThrowsError(try PlanMutation.insert(a).applying(to: archive)) {
            XCTAssertEqual($0 as? PlanMutationError, .duplicateID)
        }
        XCTAssertEqual(try PlanMutation.insert(a).applying(to: Archive(places: [], plans: [])).plans, [a])
    }
    func testReplacingSnapshotPreservesIdentityAndCreationTime() throws {
        let a = try plan(); var b = a; b.title = "Edited"; b.updatedAt = now.addingTimeInterval(10)
        let updated = try PlanMutation.replace(expected: a, updated: b).applying(to: Archive(places: [], plans: [a]))
        XCTAssertEqual(updated.plans, [b]); XCTAssertEqual(updated.plans[0].createdAt, a.createdAt)
        var invalid = b; invalid.id = UUID()
        XCTAssertThrowsError(try PlanMutation.replace(expected: a, updated: invalid).applying(to: Archive(places: [], plans: [a])))
        invalid = b; invalid.createdAt = now.addingTimeInterval(1)
        XCTAssertThrowsError(try PlanMutation.replace(expected: a, updated: invalid).applying(to: Archive(places: [], plans: [a])))
    }
    func testStaleEditorCannotOverwriteNewNotesEvenWithSameTimestamp() throws {
        let a = try plan(); var latest = a; latest.notes = "Edited elsewhere"
        var draft = a; draft.title = "Old editor draft"
        XCTAssertThrowsError(try PlanMutation.replace(expected: a, updated: draft).applying(to: Archive(places: [], plans: [latest]))) {
            XCTAssertEqual($0 as? PlanMutationError, .staleEdit)
        }
    }
    func testStaleActionsCannotResurrectDeletedPlan() throws {
        let a = try plan(), empty = Archive(places: [], plans: [])
        let actions: [PlanMutation] = [.replace(expected: a, updated: a), .disableReminder(a.id, now: now),
            .setCompleted(a.id, completed: true, now: now), .duplicate(a.id, newID: UUID(), now: now), .remove(a.id)]
        for action in actions {
            XCTAssertThrowsError(try action.applying(to: empty)) { XCTAssertEqual($0 as? PlanMutationError, .notFound) }
        }
    }
    func testStopUsesLatestStoredPlanAndDoesNotRevertEditedFields() throws {
        var latest = try plan(); latest.title = "New title"; latest.notes = "New notes"; latest.collectionName = "New project"
        let stopped = try PlanMutation.disableReminder(latest.id, now: now.addingTimeInterval(10))
            .applying(to: Archive(places: [], plans: [latest])).plans[0]
        XCTAssertEqual(stopped.title, latest.title); XCTAssertEqual(stopped.notes, latest.notes)
        XCTAssertEqual(stopped.collectionName, latest.collectionName); XCTAssertEqual(stopped.createdAt, latest.createdAt)
        XCTAssertNil(stopped.reminderLeadMinutes)
    }
    func testDuplicateUsesLatestAndClearsCompletionAndReminderOnly() throws {
        var a = try plan(); a.completedAt = now; a.notes = "Latest notes"
        let id = UUID(), stamp = now.addingTimeInterval(20)
        let copied = try PlanMutation.duplicate(a.id, newID: id, now: stamp).applying(to: Archive(places: [.example], plans: [a]))
        XCTAssertEqual(copied.plans[0], a); XCTAssertEqual(copied.places, [.example])
        let copy = copied.plans[1]
        XCTAssertEqual(copy.id, id); XCTAssertEqual(copy.notes, a.notes); XCTAssertEqual(copy.place, a.place)
        XCTAssertEqual(copy.date, a.date); XCTAssertEqual(copy.collectionName, a.collectionName)
        XCTAssertNil(copy.completedAt); XCTAssertNil(copy.reminderLeadMinutes)
        XCTAssertEqual(copy.createdAt, stamp); XCTAssertEqual(copy.updatedAt, stamp)
    }
    func testDuplicateRejectsIDCollision() throws {
        let a = try plan()
        XCTAssertThrowsError(try PlanMutation.duplicate(a.id, newID: a.id, now: now).applying(to: Archive(places: [], plans: [a])))
    }
    func testCompletionAndReopenNeverReactivateAnOldReminder() throws {
        let a = try plan(), archive = Archive(places: [], plans: [a])
        let completed = try PlanMutation.setCompleted(a.id, completed: true, now: now).applying(to: archive)
        XCTAssertEqual(completed.plans[0].completedAt, now); XCTAssertNil(completed.plans[0].reminderLeadMinutes)
        XCTAssertEqual(try PlanMutation.setCompleted(a.id, completed: true, now: now.addingTimeInterval(1)).applying(to: completed), completed)
        let reopened = try PlanMutation.setCompleted(a.id, completed: false, now: now.addingTimeInterval(2)).applying(to: completed)
        XCTAssertNil(reopened.plans[0].completedAt); XCTAssertNil(reopened.plans[0].reminderLeadMinutes)
        XCTAssertEqual(reopened.plans[0].notes, a.notes)
    }
    func testRemoveLeavesOtherPlansAndSavedPlacesUntouched() throws {
        let a = try plan(), b = try plan()
        let result = try PlanMutation.remove(a.id).applying(to: Archive(places: [.example], plans: [a,b]))
        XCTAssertEqual(result.plans, [b]); XCTAssertEqual(result.places, [.example])
    }
    func testInvalidMutationDoesNotChangeInput() throws {
        let a = try plan(), original = Archive(places: [.example], plans: [a])
        XCTAssertThrowsError(try PlanMutation.disableReminder(a.id, now: Date(timeIntervalSince1970: .nan)).applying(to: original))
        XCTAssertEqual(original.plans, [a])
    }
}
