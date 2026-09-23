import Foundation

/// The platform adapter owns authorization and notification delivery. This scheduler only
/// coordinates changes, so races can be tested without a simulator or notification permission.
public protocol ReminderNotificationClient: Sendable {
    func isAuthorized(requestPermission: Bool) async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ request: ScheduledReminder) async throws
    func remove(identifiers: [String]) async
}

public struct ReminderIntent: Sendable, Equatable {
    public let planID: UUID
    public let fireDate: Date
    public let title: String
    public let body: String
    public init(planID: UUID, fireDate: Date, title: String, body: String) {
        self.planID = planID; self.fireDate = fireDate; self.title = title; self.body = body
    }
}

public struct ScheduledReminder: Sendable, Equatable {
    public let identifier: String
    public let intent: ReminderIntent
    public init(intent: ReminderIntent) {
        self.identifier = "plan." + intent.planID.uuidString + "." + UUID().uuidString
        self.intent = intent
    }
}

public enum ReminderSchedulingResult: Sendable { case scheduled, denied, capacityReached, superseded }

public actor ReminderScheduler {
    private let client: any ReminderNotificationClient
    private let budget: Int
    private var planVersions: [UUID: UInt64] = [:]
    private var reconciliationVersion: UInt64 = 0
    private var tail: Task<Void, Never>?

    public init(client: any ReminderNotificationClient, budget: Int = 48) {
        self.client = client; self.budget = max(1, budget)
    }

    private func advance(_ id: UUID) -> UInt64 {
        let next = (planVersions[id] ?? 0) &+ 1
        planVersions[id] = next
        return next
    }
    private func matches(_ id: UUID, version: UInt64) -> Bool { (planVersions[id] ?? 0) == version }
    private func belongs(_ identifier: String, to planID: UUID) -> Bool {
        let prefix = "plan." + planID.uuidString
        return identifier == prefix || identifier.hasPrefix(prefix + ".")
    }
    private func planID(in identifier: String) -> UUID? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 2, parts[0] == "plan" else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    /// Serialize system mutations, while accepting newer intent/version changes immediately.
    /// This prevents both capacity races and an older removal from deleting a newer save.
    private func enqueue<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    public func cancel(planID: UUID) async {
        let version = advance(planID)
        try? await enqueue { await self.removePlan(planID, version: version) }
    }
    private func removePlan(_ id: UUID, version: UInt64) async {
        let pending = await client.pendingIdentifiers()
        guard matches(id, version: version) else { return }
        await client.remove(identifiers: pending.filter { belongs($0, to: id) })
    }

    public func schedule(_ intent: ReminderIntent) async throws -> ReminderSchedulingResult {
        let version = advance(intent.planID)
        guard try await client.isAuthorized(requestPermission: true) else { return .denied }
        guard matches(intent.planID, version: version) else { return .superseded }
        return try await enqueue { try await self.replace(intent, version: version) }
    }
    private func replace(_ intent: ReminderIntent, version: UInt64) async throws -> ReminderSchedulingResult {
        guard matches(intent.planID, version: version) else { return .superseded }
        let pending = await client.pendingIdentifiers()
        guard matches(intent.planID, version: version) else { return .superseded }
        let previous = pending.filter { belongs($0, to: intent.planID) }
        guard pending.count - previous.count < budget else { return .capacityReached }
        let request = ScheduledReminder(intent: intent)
        // Preserve the working reminder until its replacement was accepted by the OS.
        try await client.add(request)
        guard matches(intent.planID, version: version) else {
            await client.remove(identifiers: [request.identifier]); return .superseded
        }
        await client.remove(identifiers: previous)
        return .scheduled
    }

    /// The generator runs after versions are captured. A stop/save during calculation
    /// invalidates only that plan, and cannot resurrect a stale reminder from the snapshot.
    public func reconcile(requestPermission: Bool = false,
                          makeIntents: @escaping @Sendable () async -> [ReminderIntent]) async {
        reconciliationVersion &+= 1
        let generation = reconciliationVersion, versions = planVersions
        guard (try? await client.isAuthorized(requestPermission: requestPermission)) == true else { return }
        let intents = await makeIntents()
        guard generation == reconciliationVersion, !Task.isCancelled else { return }
        try? await enqueue { await self.apply(intents, generation: generation, versions: versions) }
    }
    private func apply(_ intents: [ReminderIntent], generation: UInt64, versions: [UUID: UInt64]) async {
        guard generation == reconciliationVersion else { return }
        var seen = Set<UUID>()
        let chosen = intents.sorted { $0.fireDate < $1.fireDate }.filter { seen.insert($0.planID).inserted }.prefix(budget)
        let desired = Set(chosen.map(\.planID))
        let pending = await client.pendingIdentifiers()
        guard generation == reconciliationVersion else { return }
        // Prune only plans absent from the new desired set and unchanged since calculation.
        // Existing reminders for desired plans stay until each replacement succeeds.
        let obsolete = pending.filter { identifier in
            guard let id = planID(in: identifier), !desired.contains(id) else { return false }
            return matches(id, version: versions[id] ?? 0)
        }
        await client.remove(identifiers: obsolete)
        for intent in chosen {
            guard generation == reconciliationVersion else { return }
            guard matches(intent.planID, version: versions[intent.planID] ?? 0) else { continue }
            do { _ = try await replace(intent, version: versions[intent.planID] ?? 0) }
            catch { continue } // Keep this plan's prior reminder; still reconcile independent plans.
        }
    }
}
