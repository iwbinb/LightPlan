import Foundation
import LightPlanCore

extension AppState {
    /// Persist before cancelling so a failed disk write does not silently disable
    /// a reminder for an active plan. Restoring a plan never re-enables old reminders.
    @discardableResult
    func setPlanCompleted(_ plan: ShootPlan, completed: Bool, showNotice: Bool = true) async -> Bool {
        guard let current = plans.first(where: { $0.id == plan.id }) else { return false }
        guard completed != (current.completedAt != nil) else { return true }
        do {
            try applyPlanMutation(.setCompleted(plan.id, completed: completed, now: Date()))
            await ReminderService.cancel(planID: current.id)
            await reconcileReminders()
            if showNotice { noticeKey = completed ? "library.completedNotice" : "library.reopenedNotice" }
            return true
        } catch { if showNotice { errorKey = "error.save" }; return false }
    }
}
