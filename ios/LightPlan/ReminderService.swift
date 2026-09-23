import Foundation
import UserNotifications
import LightPlanCore

enum ReminderResult { case scheduled, denied, noFutureEvent, capacityReached, superseded }
@MainActor enum ReminderService {
    static let budget = 48 // Product budget; not an assertion about an undocumented OS limit.
    private static let scheduler = ReminderScheduler(client: SystemReminderNotifications(), budget: budget)
    static func cancel(planID: UUID) async { await scheduler.cancel(planID: planID) }
    private static func identifier(_ id: UUID) -> String { "plan." + id.uuidString }
    static func schedule(plan: ShootPlan, summary: DaySummary, language: String) async throws -> ReminderResult {
        guard let intent = intent(plan: plan, summary: summary, language: language, now: Date()) else {
            await scheduler.cancel(planID: plan.id)
            return .noFutureEvent
        }
        switch try await scheduler.schedule(intent) {
        case .scheduled: return .scheduled
        case .denied: return .denied
        case .capacityReached: return .capacityReached
        case .superseded: return .superseded
        }
    }
    private static func intent(plan: ShootPlan, summary: DaySummary, language: String, now: Date) -> ReminderIntent? {
        guard let fire = Planner.reminder(plan: plan, summary: summary, now: now),
              let anchor = Planner.anchorDate(plan: plan, summary: summary) else { return nil }
        let body = L10n.text("notification.body", language: language) + " · " + plan.place.name + " · " + L10n.time(anchor, zone: plan.place.timeZone, language: language) + " (" + plan.place.timeZoneID + ")"
        return ReminderIntent(planID: plan.id, fireDate: fire, title: plan.title, body: body)
    }
    /// Replenish the nearest reminders on foreground/edits/import. Never re-prompt at launch.
    static func reconcile(plans: [ShootPlan], language: String, requestPermission: Bool = false) async {
        let reminderBudget = budget
        await scheduler.reconcile(requestPermission: requestPermission) {
            let now = Date()
            let candidates = plans.compactMap { plan -> (ShootPlan, Date)? in
                guard let lead = plan.reminderLeadMinutes,
                      let interval = try? LocalDay.interval(containing: plan.date, timeZone: plan.place.timeZone), interval.end > now else { return nil }
                return (plan, interval.start.addingTimeInterval(-Double(lead) * 60))
            }.sorted { $0.1 < $1.1 }
            var intents: [ReminderIntent] = []
            for (plan, earliestFire) in candidates {
                guard !Task.isCancelled else { return intents }
                // Stop only when later civil days cannot displace any of the nearest reminders.
                // An arbitrary plan-count prefix can miss valid plans behind polar/no-event days.
                if intents.count >= reminderBudget, earliestFire > intents.map(\.fireDate).sorted()[reminderBudget - 1] { break }
                guard let day = try? await Task.detached(priority: .utility, operation: { try DayEngine.calculate(place: plan.place, date: plan.date) }).value,
                      let next = await intent(plan: plan, summary: day, language: language, now: now) else { continue }
                intents.append(next)
            }
            return intents
        }
    }

    /// Read the system's current scheduling state; saved reminder intent is not delivery proof.
    static func statusKey(plan: ShootPlan, summary: DaySummary) async -> String {
        guard plan.reminderLeadMinutes != nil else { return "v3.reminder.off" }
        guard Planner.anchorDate(plan: plan, summary: summary) != nil else { return "plan.noEvent" }
        guard let expected = Planner.reminder(plan: plan, summary: summary, now: Date()) else { return "notice.pastReminder" }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied { return "notice.notificationDenied" }
        let pending = await center.pendingNotificationRequests()
        let id = identifier(plan.id)
        return pending.contains {
            guard $0.identifier == id || $0.identifier.hasPrefix(id + "."),
                  let trigger = $0.trigger as? UNCalendarNotificationTrigger,
                  let fire = trigger.nextTriggerDate() else { return false }
            return abs(fire.timeIntervalSince(expected)) < 1
        }
            ? "plan.reminderScheduled" : "notice.savedWithoutReminder"
    }
}

private struct SystemReminderNotifications: ReminderNotificationClient {
    func isAuthorized(requestPermission: Bool) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        if requestPermission { return try await center.requestAuthorization(options: [.alert, .sound]) }
        let settings = await center.notificationSettings()
        return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }
    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }
    func remove(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    func add(_ request: ScheduledReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.intent.title; content.body = request.intent.body
        content.sound = .default; content.userInfo = ["planID": request.intent.planID.uuidString]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.intent.fireDate)
        components.calendar = calendar; components.timeZone = .gmt
        let notification = UNNotificationRequest(identifier: request.identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try await UNUserNotificationCenter.current().add(notification)
    }
}

extension Notification.Name { static let lightPlanOpenPlan = Notification.Name("LightPlan.openPlan") }
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["planID"] as? String,
              let id = UUID(uuidString: text) else { return }
        await MainActor.run { NotificationCenter.default.post(name: .lightPlanOpenPlan, object: id) }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
