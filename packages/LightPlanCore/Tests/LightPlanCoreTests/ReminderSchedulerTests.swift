import XCTest
@testable import LightPlanCore

@MainActor final class ReminderSchedulerTests: XCTestCase {
    private func intent(_ id: UUID = UUID(), hour: Double = 1, title: String = "Saved plan") -> ReminderIntent {
        ReminderIntent(planID: id, fireDate: Date(timeIntervalSince1970: 2_000_000_000 + hour * 3600), title: title, body: "Arrival")
    }

    func testUnrelatedSaveDuringRebuildDoesNotEraseOtherPlans() async throws {
        let a = intent(), b = intent(), c = intent(), d = intent()
        let client = TestReminderClient(existing: [a, b, c])
        await client.blockNextAdd()
        let scheduler = ReminderScheduler(client: client)
        let rebuilding = Task { await scheduler.reconcile { [a, b, c] } }
        await client.waitForBlockedAdd()
        let saving = Task { try await scheduler.schedule(d) }
        await client.waitForPermissionRequest()
        // The new save's intent is now registered while the first replacement is in flight.
        await client.releaseAdd()
        await rebuilding.value
        let result = try await saving.value
        XCTAssertEqual(result, .scheduled)
        let remaining = await client.requests()
        XCTAssertEqual(Set(remaining.map(\.intent.planID)), Set([a, b, c, d].map(\.planID)))
        XCTAssertEqual(remaining.count, 4)
    }

    func testStopDuringCalculationCannotResurrectPlanOrCancelOthers() async {
        let a = intent(), b = intent()
        let client = TestReminderClient(existing: [a, b])
        let scheduler = ReminderScheduler(client: client)
        let gate = TestReminderGate()
        let rebuilding = Task {
            await scheduler.reconcile { await gate.wait(); return [a, b] }
        }
        await gate.waitForEntry()
        await scheduler.cancel(planID: b.planID)
        await gate.release()
        await rebuilding.value
        let remaining = await client.requests()
        XCTAssertEqual(remaining.map(\.intent.planID), [a.planID])
    }

    func testFailedReplacementKeepsOriginalAndContinuesOtherPlans() async {
        let a = intent(), b = intent()
        let client = TestReminderClient(existing: [a, b])
        let original = await client.requests().first { $0.intent.planID == a.planID }
        await client.failNextAdd()
        let scheduler = ReminderScheduler(client: client)
        await scheduler.reconcile { [a, b] }
        let remaining = await client.requests()
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.contains { $0.identifier == original?.identifier })
        XCTAssertTrue(remaining.contains { $0.intent.planID == b.planID })
    }

    func testNewerSamePlanSaveWinsOverInflightReplacement() async throws {
        let original = intent()
        let latest = intent(original.planID, hour: 2, title: "New plan time")
        let client = TestReminderClient(existing: [original])
        await client.blockNextAdd()
        let scheduler = ReminderScheduler(client: client)
        let rebuilding = Task { await scheduler.reconcile { [original] } }
        await client.waitForBlockedAdd()
        let saving = Task { try await scheduler.schedule(latest) }
        await client.waitForPermissionRequest()
        await client.releaseAdd()
        await rebuilding.value
        let result = try await saving.value
        XCTAssertEqual(result, .scheduled)
        let remaining = await client.requests()
        XCTAssertEqual(remaining.map(\.intent), [latest])
    }

    func testConcurrentSavesRespectBudget() async throws {
        let client = TestReminderClient(existing: [])
        let scheduler = ReminderScheduler(client: client, budget: 1)
        let a = intent(), b = intent()
        async let first = scheduler.schedule(a)
        async let second = scheduler.schedule(b)
        let results = try await [first, second]
        XCTAssertEqual(results.filter { $0 == .scheduled }.count, 1)
        XCTAssertEqual(results.filter { $0 == .capacityReached }.count, 1)
        let remaining = await client.requests()
        XCTAssertEqual(remaining.count, 1)
    }

    func testDeniedReconcilePreservesExistingReminders() async {
        let a = intent()
        let client = TestReminderClient(existing: [a])
        await client.setAuthorized(false)
        let scheduler = ReminderScheduler(client: client)
        await scheduler.reconcile { [] }
        let remaining = await client.requests()
        XCTAssertEqual(remaining.map(\.intent), [a])
    }

    func testReconcilePrunesDeletedPlansAndKeepsNearestWithinBudget() async {
        let old = intent(), near = intent(hour: 1), middle = intent(hour: 2), distant = intent(hour: 3)
        let client = TestReminderClient(existing: [old])
        let scheduler = ReminderScheduler(client: client, budget: 2)
        await scheduler.reconcile { [distant, middle, near] }
        let remaining = await client.requests()
        XCTAssertEqual(Set(remaining.map(\.intent.planID)), Set([near.planID, middle.planID]))
    }
}

private actor TestReminderClient: ReminderNotificationClient {
    enum Failure: Error { case simulated }
    private var stored: [String: ScheduledReminder]
    private var authorized = true
    private var blockAdd = false
    private var failAdd = false
    private var addGate: CheckedContinuation<Void, Never>?
    private var addStarted = false
    private var addWaiters: [CheckedContinuation<Void, Never>] = []
    private var permissionRequested = false
    private var permissionWaiters: [CheckedContinuation<Void, Never>] = []

    init(existing: [ReminderIntent]) {
        stored = Dictionary(uniqueKeysWithValues: existing.map { let value = ScheduledReminder(intent: $0); return (value.identifier, value) })
    }
    func isAuthorized(requestPermission: Bool) async throws -> Bool {
        if requestPermission {
            permissionRequested = true
            permissionWaiters.forEach { $0.resume() }; permissionWaiters = []
        }
        return authorized
    }
    func setAuthorized(_ value: Bool) { authorized = value }
    func pendingIdentifiers() -> [String] { Array(stored.keys) }
    func requests() -> [ScheduledReminder] { Array(stored.values) }
    func remove(identifiers: [String]) { for id in identifiers { stored.removeValue(forKey: id) } }
    func failNextAdd() { failAdd = true }
    func blockNextAdd() { blockAdd = true }
    func add(_ request: ScheduledReminder) async throws {
        if blockAdd {
            blockAdd = false
            await withCheckedContinuation { continuation in
                addGate = continuation; addStarted = true
                addWaiters.forEach { $0.resume() }; addWaiters = []
            }
        }
        if failAdd { failAdd = false; throw Failure.simulated }
        stored[request.identifier] = request
    }
    func waitForBlockedAdd() async {
        if addStarted { return }
        await withCheckedContinuation { addWaiters.append($0) }
    }
    func releaseAdd() { addGate?.resume(); addGate = nil }
    func waitForPermissionRequest() async {
        if permissionRequested { return }
        await withCheckedContinuation { permissionWaiters.append($0) }
    }
}

private actor TestReminderGate {
    private var gate: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        await withCheckedContinuation { continuation in
            gate = continuation; waiters.forEach { $0.resume() }; waiters = []
        }
    }
    func waitForEntry() async {
        if gate != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { gate?.resume(); gate = nil }
}
