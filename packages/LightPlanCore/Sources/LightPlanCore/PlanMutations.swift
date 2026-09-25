import Foundation

public enum PlanMutationError: Error, Equatable, Sendable {
    case notFound, staleEdit, duplicateID
}

/// Edits compare the snapshot shown to the user; quick actions always modify the
/// latest saved value. Neither path may resurrect a deleted plan.
public enum PlanMutation: Sendable {
    case insert(ShootPlan)
    case replace(expected: ShootPlan, updated: ShootPlan)
    case remove(UUID)
    case disableReminder(UUID, now: Date)
    case setCompleted(UUID, completed: Bool, now: Date)
    case duplicate(UUID, newID: UUID, now: Date)

    public func applying(to archive: Archive) throws -> Archive {
        try archive.validate()
        var result = archive
        func index(_ id: UUID) throws -> Int {
            guard let index = result.plans.firstIndex(where: { $0.id == id }) else {
                throw PlanMutationError.notFound
            }
            return index
        }
        switch self {
        case .insert(let plan):
            guard !result.plans.contains(where: { $0.id == plan.id }) else { throw PlanMutationError.duplicateID }
            result.plans.append(try plan.validated())
        case .replace(let expected, let updated):
            let i = try index(expected.id)
            guard result.plans[i] == expected else { throw PlanMutationError.staleEdit }
            guard updated.id == expected.id, updated.createdAt == expected.createdAt else {
                throw LightPlanError.invalidPlan
            }
            result.plans[i] = try updated.validated()
        case .remove(let id):
            result.plans.remove(at: try index(id))
        case .disableReminder(let id, let now):
            let i = try index(id)
            result.plans[i].reminderLeadMinutes = nil
            result.plans[i].updatedAt = now
        case .setCompleted(let id, let completed, let now):
            let i = try index(id)
            if (result.plans[i].completedAt != nil) != completed {
                result.plans[i].completedAt = completed ? now : nil
                result.plans[i].reminderLeadMinutes = nil
                result.plans[i].updatedAt = now
            }
        case .duplicate(let id, let newID, let now):
            var copy = result.plans[try index(id)]
            guard !result.plans.contains(where: { $0.id == newID }) else { throw PlanMutationError.duplicateID }
            copy.id = newID; copy.createdAt = now; copy.updatedAt = now
            copy.reminderLeadMinutes = nil; copy.completedAt = nil
            result.plans.append(copy)
        }
        // Validate timestamps, nested snapshots and aggregate limits before touching storage.
        _ = try result.encoded()
        return result
    }
}
