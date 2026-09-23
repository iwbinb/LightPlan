import Foundation
import LightPlanCore

extension AppState {
    /// Persist before cancelling so a failed disk write does not silently disable
    /// a reminder for an active plan. Restoring a plan never re-enables old reminders.
    func setPlanCompleted(_ plan: ShootPlan, completed: Bool, showNotice: Bool = true) async {
        guard var current = plans.first(where: { $0.id == plan.id }) else { return }
        guard completed != (current.completedAt != nil) else { return }
        current.completedAt = completed ? Date() : nil
        current.reminderLeadMinutes = nil
        current.updatedAt = Date()
        do {
            try upsert(current)
            await ReminderService.cancel(planID: current.id)
            if showNotice { noticeKey = completed ? "library.completedNotice" : "library.reopenedNotice" }
        } catch { if showNotice { errorKey = "error.save" } }
    }
}
