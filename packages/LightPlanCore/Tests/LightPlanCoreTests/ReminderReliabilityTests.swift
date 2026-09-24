import Foundation
import XCTest
@testable import LightPlanCore

@MainActor final class ReminderReliabilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func intent(_ id: UUID = UUID(), offset: Double = 3600, title: String = "Plan") -> ReminderIntent {
        ReminderIntent(planID: id, fireDate: now.addingTimeInterval(offset), title: title, body: "Saved schedule")
    }
    private func scheduler(_ client: M4ReminderClient, budget: Int = 48) -> ReminderScheduler {
        let date = now
        return ReminderScheduler(client: client, budget: budget, now: { date })
    }
    func testEqualTimesPreserveLibraryOrderAndCapacityIsReported() async {
        let a = intent(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!)
        let b = intent(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let client = M4ReminderClient()
        let result = await scheduler(client, budget: 1).reconcile { [a, b] }
        let values = await client.values()
        XCTAssertEqual(values.map(\.intent), [a])
        XCTAssertEqual(result.scheduled, 1)
        XCTAssertEqual(result.capacityReached, 1)
        XCTAssertTrue(result.needsAttention)
    }

    func testNonfiniteIntentFailsWithoutRequestingPermissionOrDeletingOriginal() async throws {
        let old = intent(), client = M4ReminderClient()
        await client.seed([old])
        let engine = scheduler(client)
        do { _ = try await engine.schedule(ReminderIntent(planID: old.planID, fireDate: Date(timeIntervalSince1970: .nan), title: "", body: "")); XCTFail("Must reject NaN") }
        catch { XCTAssertEqual(error as? LightPlanError, .invalidDate) }
        let values = await client.values(), prompts = await client.promptCount()
        XCTAssertEqual(values.map(\.intent), [old]); XCTAssertEqual(prompts, 0)
    }
    func testExpiredPlanCancelsOldPendingRequestWithoutPermissionPrompt() async throws {
        let old = intent(), client = M4ReminderClient(); await client.seed([old])
        let engine = scheduler(client)
        let result = try await engine.schedule(intent(old.planID, offset: -1))
        let values = await client.values(), prompts = await client.promptCount()
        XCTAssertEqual(result, .expired); XCTAssertTrue(values.isEmpty); XCTAssertEqual(prompts, 0)
    }
    func testPermissionDelayCannotEnqueueAnExpiredEditedReminder() async throws {
        let old = intent(), edited = intent(old.planID, offset: 1), client = M4ReminderClient()
        await client.seed([old])
        let clock = LockedClock(now)
        let gate = M4Gate()
        await client.setAuthorizationGate(gate)
        let engine = ReminderScheduler(client: client, now: { clock.read() })
        let saving = Task { try await engine.schedule(edited) }
        await gate.entered()
        clock.set(now.addingTimeInterval(2))
        await gate.release()
        let result = try await saving.value, values = await client.values()
        XCTAssertEqual(result, .expired); XCTAssertTrue(values.isEmpty)
    }
    func testCalculationFailurePreservesOnlyUnknownPlans() async {
        let unknown = intent(), valid = intent(), deleted = intent()
        let client = M4ReminderClient(); await client.seed([unknown,valid,deleted])
        let oldID = await client.values().first { $0.intent.planID == unknown.planID }?.identifier
        let engine = scheduler(client)
        let result = await engine.reconcileSnapshot { ReminderReconciliationInput(intents: [valid], unresolvedPlanIDs: [unknown.planID]) }
        let values = await client.values()
        XCTAssertEqual(Set(values.map(\.intent.planID)), [unknown.planID,valid.planID])
        XCTAssertTrue(values.contains { $0.identifier == oldID })
        XCTAssertEqual(result.unresolved, 1); XCTAssertTrue(result.needsAttention)
    }
    func testFailureIsReportedButIndependentRemindersContinue() async {
        let a = intent(), b = intent()
        let client = M4ReminderClient(); await client.seed([a,b]); await client.failAdd(for: a.planID)
        let engine = scheduler(client)
        let result = await engine.reconcile { [a,b] }
        let values = await client.values()
        XCTAssertEqual(values.count, 2); XCTAssertEqual(result.failed, 1); XCTAssertEqual(result.scheduled, 1)
        XCTAssertTrue(result.needsAttention)
    }
    func testDeniedRebuildReportsSeparatelyAndDoesNotEraseQueue() async {
        let a = intent(), client = M4ReminderClient(); await client.seed([a]); await client.setAuthorized(false)
        let engine = scheduler(client)
        let result = await engine.reconcile { [] }
        let values = await client.values()
        XCTAssertTrue(result.denied); XCTAssertTrue(result.needsAttention); XCTAssertEqual(values.map(\.intent), [a])
    }
    func testNewestReconciliationWinsDuringAnInflightAdd() async {
        let original = intent(), old = intent(original.planID, offset: 7200), latest = intent(original.planID, offset: 10800)
        let client = M4ReminderClient(); await client.seed([original])
        let addGate = M4Gate(), calculated = M4Gate()
        await client.setAddGate(addGate)
        let engine = scheduler(client)
        let first = Task { await engine.reconcile { [old] } }
        await addGate.entered()
        let next = Task { await engine.reconcile { await calculated.mark(); return [latest] } }
        await calculated.entered()
        await addGate.release()
        let oldResult = await first.value, newResult = await next.value
        let values = await client.values()
        XCTAssertTrue(oldResult.superseded); XCTAssertEqual(newResult.scheduled, 1)
        XCTAssertEqual(values.map(\.intent), [latest])
    }
    func testStaleSavedSnapshotCannotScheduleAfterAuthorization() async throws {
        let old = intent(), client = M4ReminderClient(); await client.seed([old])
        let gate = M4Gate(), validity = M4Validity()
        await client.setAuthorizationGate(gate)
        let engine = scheduler(client)
        let task = Task { try await engine.schedule(old, isCurrent: { await validity.value() }) }
        await gate.entered(); await validity.invalidate(); await gate.release()
        let result = try await task.value, values = await client.values()
        XCTAssertEqual(result, .superseded); XCTAssertEqual(values.map(\.intent), [old])
    }
    func testQueuedCancellationRechecksSavedStateBeforeRemovingRequests() async {
        let saved = intent(), client = M4ReminderClient()
        await client.seed([saved])
        let gate = M4Gate(), validity = M4Validity(), engine = scheduler(client)
        await client.setPendingGate(gate)
        let stopping = Task {
            await engine.cancel(planID: saved.planID, isCurrent: { await validity.value() })
        }
        await gate.entered()
        // The app can persist a newer enabled version while the OS queue is being read.
        await validity.invalidate()
        await gate.release()
        await stopping.value
        let values = await client.values()
        XCTAssertEqual(values.map(\.intent), [saved])
    }
    func testLockedLibrarySnapshotCannotPruneExistingReminders() async {
        let a = intent(), client = M4ReminderClient(); await client.seed([a])
        let engine = scheduler(client)
        let result = await engine.reconcileSnapshot(isCurrent: { false }) { ReminderReconciliationInput(intents: []) }
        let values = await client.values()
        XCTAssertTrue(result.superseded); XCTAssertEqual(values.map(\.intent), [a])
    }
    func testNonfiniteRebuildCandidateIsUnknownRatherThanDeleted() async {
        let a = intent(), client = M4ReminderClient(); await client.seed([a])
        let invalid = ReminderIntent(planID: a.planID, fireDate: Date(timeIntervalSince1970: .infinity), title: "", body: "")
        let engine = scheduler(client)
        let result = await engine.reconcile { [invalid] }
        let values = await client.values()
        XCTAssertEqual(result.unresolved, 1); XCTAssertEqual(values.map(\.intent), [a])
    }
    func testRepeatedRebuildDeduplicatesAndKeepsEarliestIntent() async {
        let a = intent(), later = intent(a.planID, offset: 7200)
        let client = M4ReminderClient(); await client.seed([a,a,later])
        let engine = scheduler(client)
        await engine.reconcile { [later,a,a] }
        await engine.reconcile { [a,a,later] }
        let values = await client.values()
        XCTAssertEqual(values.map(\.intent), [a])
    }
    func testUnknownPlanConsumesCapacityInsteadOfBeingSilentlyRemoved() async {
        let a = intent(), b = intent(), client = M4ReminderClient(); await client.seed([a])
        let engine = scheduler(client, budget: 1)
        let result = await engine.reconcileSnapshot { ReminderReconciliationInput(intents: [b], unresolvedPlanIDs: [a.planID]) }
        let values = await client.values()
        XCTAssertEqual(result.capacityReached, 1); XCTAssertEqual(values.map(\.intent), [a])
    }
    func testCancelWhileBuildingDoesNotApplyPartialResults() async {
        let a = intent(), b = intent(), client = M4ReminderClient(); await client.seed([a,b])
        let gate = M4Gate(), engine = scheduler(client)
        let task = Task { await engine.reconcile { await gate.wait(); return [a] } }
        await gate.entered(); task.cancel(); await gate.release()
        let result = await task.value, values = await client.values()
        XCTAssertTrue(result.superseded); XCTAssertEqual(Set(values.map(\.intent.planID)), [a.planID,b.planID])
    }
}
private actor M4Validity {
    private var valid = true
    func value() -> Bool { valid }
    func invalidate() { valid = false }
}
private actor M4Gate {
    private var hasEntered = false
    private var released = false
    private var entries: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func mark() { hasEntered = true; entries.forEach { $0.resume() }; entries = [] }
    func wait() async {
        mark()
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func entered() async {
        if !hasEntered { await withCheckedContinuation { entries.append($0) } }
    }
    func release() { released = true; waiters.forEach { $0.resume() }; waiters = [] }
}
private actor M4ReminderClient: ReminderNotificationClient {
    private var requests: [String: ScheduledReminder] = [:]
    private var authorized = true
    private var prompts = 0
    private var failingIDs = Set<UUID>()
    private var authorizationGate: M4Gate?
    private var addGate: M4Gate?
    private var pendingGate: M4Gate?
    func seed(_ intents: [ReminderIntent]) {
        for intent in intents { let request = ScheduledReminder(intent: intent); requests[request.identifier] = request }
    }
    func values() -> [ScheduledReminder] { Array(requests.values) }
    func promptCount() -> Int { prompts }
    func setAuthorized(_ value: Bool) { authorized = value }
    func setAuthorizationGate(_ gate: M4Gate) { authorizationGate = gate }
    func setAddGate(_ gate: M4Gate) { addGate = gate }
    func setPendingGate(_ gate: M4Gate) { pendingGate = gate }
    func failAdd(for id: UUID) { failingIDs.insert(id) }
    func isAuthorized(requestPermission: Bool) async throws -> Bool {
        if requestPermission { prompts += 1 }
        if let gate = authorizationGate { authorizationGate = nil; await gate.wait() }
        return authorized
    }
    func pendingIdentifiers() async -> [String] {
        if let gate = pendingGate { pendingGate = nil; await gate.wait() }
        return Array(requests.keys)
    }
    func remove(identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func add(_ request: ScheduledReminder) async throws {
        if let gate = addGate { addGate = nil; await gate.wait() }
        if failingIDs.contains(request.intent.planID) { throw CocoaError(.coderInvalidValue) }
        requests[request.identifier] = request
    }
}
/// Lock protects the test clock across actor/executor boundaries.
private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func read() -> Date { lock.withLock { date } }
    func set(_ value: Date) { lock.withLock { date = value } }
}
