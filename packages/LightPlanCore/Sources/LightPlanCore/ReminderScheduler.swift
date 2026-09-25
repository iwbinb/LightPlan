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

public enum ReminderSchedulingResult: Sendable { case scheduled, denied, capacityReached, superseded, expired }

public struct ReminderReconciliationInput: Sendable {
    public let intents: [ReminderIntent]
    /// A failed calculation is unknown, not proof that the saved plan has no event.
    public let unresolvedPlanIDs: Set<UUID>
    public init(intents: [ReminderIntent], unresolvedPlanIDs: Set<UUID> = []) {
        self.intents = intents; self.unresolvedPlanIDs = unresolvedPlanIDs
    }
}
public struct ReminderReconciliationResult: Sendable {
    public var scheduled = 0
    public var failed = 0
    public var capacityReached = 0
    public var unresolved = 0
    public var denied = false
    public var superseded = false
    public var needsAttention: Bool { failed > 0 || capacityReached > 0 || unresolved > 0 || denied }
}

public actor ReminderScheduler {
    private let client: any ReminderNotificationClient
    private let budget: Int
    private let now: @Sendable () -> Date
    private var planVersions: [UUID: UInt64] = [:]
    private var reconciliationVersion: UInt64 = 0
    private var tail: Task<Void, Never>?

    public init(client: any ReminderNotificationClient, budget: Int = 48,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.budget = max(1, budget); self.now = now
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

    public func cancel(planID: UUID,
                       isCurrent: @escaping @Sendable () async -> Bool = { true }) async {
        guard await isCurrent() else { return }
        let version = advance(planID)
        try? await enqueue { await self.removePlan(planID, version: version, isCurrent: isCurrent) }
    }
    private func removePlan(_ id: UUID, version: UInt64, generation: UInt64? = nil,
                            isCurrent: @escaping @Sendable () async -> Bool = { true }) async {
        let pending = await client.pendingIdentifiers()
        guard await isCurrent(), matches(id, version: version),
              generation == nil || generation == reconciliationVersion else { return }
        await client.remove(identifiers: pending.filter { belongs($0, to: id) })
    }

    public func schedule(_ intent: ReminderIntent,
                         isCurrent: @escaping @Sendable () async -> Bool = { true }) async throws -> ReminderSchedulingResult {
        guard await isCurrent() else { return .superseded }
        guard intent.fireDate.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        let version = advance(intent.planID)
        guard intent.fireDate > now() else {
            try? await enqueue { await self.removePlan(intent.planID, version: version, isCurrent: isCurrent) }
            return .expired
        }
        guard try await client.isAuthorized(requestPermission: true) else { return .denied }
        guard matches(intent.planID, version: version) else { return .superseded }
        return try await enqueue { try await self.replace(intent, version: version, isCurrent: isCurrent) }
    }
    private func replace(_ intent: ReminderIntent, version: UInt64,
                         generation: UInt64? = nil,
                         isCurrent: @escaping @Sendable () async -> Bool = { true }) async throws -> ReminderSchedulingResult {
        func current() -> Bool {
            matches(intent.planID, version: version) &&
                (generation == nil || generation == reconciliationVersion)
        }
        guard await isCurrent(), current() else { return .superseded }
        guard intent.fireDate.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        // Authorization, earlier writes or a paused app may have consumed the lead time.
        guard intent.fireDate > now() else {
            await removePlan(intent.planID, version: version, generation: generation, isCurrent: isCurrent)
            return .expired
        }
        let pending = await client.pendingIdentifiers()
        guard await isCurrent(), current() else { return .superseded }
        let previous = pending.filter { belongs($0, to: intent.planID) }
        guard pending.count - previous.count < budget else { return .capacityReached }
        guard intent.fireDate > now() else {
            await client.remove(identifiers: previous)
            return .expired
        }
        let request = ScheduledReminder(intent: intent)
        try await client.add(request)
        guard await isCurrent(), current() else {
            await client.remove(identifiers: [request.identifier]); return .superseded
        }
        guard intent.fireDate > now() else {
            await client.remove(identifiers: previous + [request.identifier]); return .expired
        }
        // A failed replacement leaves the prior request intact.
        await client.remove(identifiers: previous)
        return .scheduled
    }

    @discardableResult
    public func reconcile(requestPermission: Bool = false,
                          makeIntents: @escaping @Sendable () async -> [ReminderIntent]) async -> ReminderReconciliationResult {
        await reconcileSnapshot(requestPermission: requestPermission) {
            ReminderReconciliationInput(intents: await makeIntents())
        }
    }

    /// Capture versions before calculation; never use an incomplete/failed calculation
    /// as evidence that an existing reminder should be removed.
    @discardableResult
    public func reconcileSnapshot(requestPermission: Bool = false,
                                  isCurrent: @escaping @Sendable () async -> Bool = { true },
                                  makeSnapshot: @escaping @Sendable () async -> ReminderReconciliationInput) async -> ReminderReconciliationResult {
        reconciliationVersion &+= 1
        let generation = reconciliationVersion, versions = planVersions
        var result = ReminderReconciliationResult()
        guard !Task.isCancelled else { result.superseded = true; return result }
        do {
            guard try await client.isAuthorized(requestPermission: requestPermission) else {
                result.denied = true; return result
            }
        } catch { result.failed = 1; return result }
        guard generation == reconciliationVersion, !Task.isCancelled else {
            result.superseded = true; return result
        }
        let snapshot = await makeSnapshot()
        guard await isCurrent(), generation == reconciliationVersion, !Task.isCancelled else {
            result.superseded = true; return result
        }
        return (try? await enqueue { await self.apply(snapshot, generation: generation, versions: versions, isCurrent: isCurrent) }) ?? result
    }
    private func apply(_ snapshot: ReminderReconciliationInput, generation: UInt64,
                       versions: [UUID: UInt64], isCurrent: @escaping @Sendable () async -> Bool) async -> ReminderReconciliationResult {
        var result = ReminderReconciliationResult()
        guard await isCurrent(), generation == reconciliationVersion else { result.superseded = true; return result }
        let invalid = Set(snapshot.intents.filter { !$0.fireDate.timeIntervalSince1970.isFinite }.map(\.planID))
        let unresolved = snapshot.unresolvedPlanIDs.union(invalid)
        result.unresolved = unresolved.count
        var seen = Set<UUID>()
        // Preserve saved-library order for equal fire times. UUID ordering would
        // unpredictably change which plan receives the first replacement/failure.
        let eligible = snapshot.intents.enumerated()
            .filter { $0.element.fireDate.timeIntervalSince1970.isFinite && $0.element.fireDate > now() && !unresolved.contains($0.element.planID) }
            .sorted { $0.element.fireDate == $1.element.fireDate ? $0.offset < $1.offset : $0.element.fireDate < $1.element.fireDate }
            .map(\.element).filter { seen.insert($0.planID).inserted }
        let chosen = eligible.prefix(budget)
        result.capacityReached = max(0, eligible.count - chosen.count)
        let desired = Set(chosen.map(\.planID)).union(unresolved)
        let pending = await client.pendingIdentifiers()
        guard await isCurrent(), generation == reconciliationVersion else { result.superseded = true; return result }
        let obsolete = pending.filter { identifier in
            guard let id = planID(in: identifier), !desired.contains(id) else { return false }
            return matches(id, version: versions[id] ?? 0)
        }
        await client.remove(identifiers: obsolete)
        for intent in chosen {
            guard await isCurrent(), generation == reconciliationVersion else { result.superseded = true; return result }
            guard matches(intent.planID, version: versions[intent.planID] ?? 0) else { continue }
            do {
                switch try await replace(intent, version: versions[intent.planID] ?? 0, generation: generation, isCurrent: isCurrent) {
                case .scheduled: result.scheduled += 1
                case .capacityReached: result.capacityReached += 1
                case .superseded: result.superseded = true
                case .denied: result.denied = true
                case .expired: break
                }
            } catch { result.failed += 1 }
        }
        return result
    }
}
