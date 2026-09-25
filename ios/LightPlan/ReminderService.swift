import Foundation
import UserNotifications
import LightPlanCore

enum ReminderResult { case scheduled, denied, noFutureEvent, capacityReached, superseded }
@MainActor enum ReminderService {
    static let budget = 48 // Product budget; not an assertion about an undocumented OS limit.
    private static let scheduler = ReminderScheduler(client: SystemReminderNotifications(), budget: budget)
    static func cancel(planID: UUID,
                       isCurrent: @escaping @Sendable () async -> Bool = { true }) async {
        await scheduler.cancel(planID: planID, isCurrent: isCurrent)
    }
    private static func identifier(_ id: UUID) -> String { "plan." + id.uuidString }
    static func schedule(plan: ShootPlan, summary: DaySummary, language: String,
                         isCurrent: @escaping @Sendable () async -> Bool = { true }) async throws -> ReminderResult {
        guard await isCurrent() else { return .superseded }
        guard let intent = intent(plan: plan, summary: summary, language: language, now: Date()) else {
            await scheduler.cancel(planID: plan.id, isCurrent: isCurrent)
            return .noFutureEvent
        }
        switch try await scheduler.schedule(intent, isCurrent: isCurrent) {
        case .scheduled: return .scheduled
        case .denied: return .denied
        case .capacityReached: return .capacityReached
        case .superseded: return .superseded
        case .expired: return .noFutureEvent
        }
    }
    private static func intent(plan: ShootPlan, summary: DaySummary, language: String, now: Date) -> ReminderIntent? {
        guard let fire = Planner.reminder(plan: plan, summary: summary, now: now),
              let anchor = Planner.anchorDate(plan: plan, summary: summary) else { return nil }
        let body = L10n.text("notification.body", language: language) + " · " + plan.place.name + " · " + L10n.time(anchor, zone: plan.place.timeZone, language: language) + " (" + plan.place.timeZoneID + ")"
        return ReminderIntent(planID: plan.id, fireDate: fire, title: plan.title, body: body)
    }
    /// Replenish the nearest reminders on foreground/edits/import. Never re-prompt at launch.
    @discardableResult
    static func reconcile(plans: [ShootPlan], language: String, requestPermission: Bool = false,
                          isCurrent: @escaping @Sendable () async -> Bool = { true }) async -> ReminderReconciliationResult {
        let reminderBudget = budget
        return await scheduler.reconcileSnapshot(requestPermission: requestPermission, isCurrent: isCurrent) {
            let now = Date()
            let candidates = plans.compactMap { plan -> (ShootPlan, Date)? in
                guard plan.completedAt == nil, let lead = plan.reminderLeadMinutes,
                      let interval = try? LocalDay.interval(containing: plan.date, timeZone: plan.place.timeZone), interval.end > now else { return nil }
                return (plan, interval.start.addingTimeInterval(-Double(lead) * 60))
            }.sorted { $0.1 < $1.1 }
            var intents: [ReminderIntent] = []
            var unresolved = Set<UUID>()
            for (plan, earliestFire) in candidates {
                guard !Task.isCancelled else { break }
                // Stop only when later civil days cannot displace any of the nearest reminders.
                // An arbitrary plan-count prefix can miss valid plans behind polar/no-event days.
                if intents.count >= reminderBudget, earliestFire > intents.map(\.fireDate).sorted()[reminderBudget - 1] { break }
                do {
                    let worker = Task.detached(priority: .utility) { try DayEngine.calculate(place: plan.place, date: plan.date) }
                    let day = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    try Task.checkCancellation()
                    if let next = await intent(plan: plan, summary: day, language: language, now: now) { intents.append(next) }
                } catch {
                    // Unknown must preserve its prior reminder, unlike a valid no-event day.
                    unresolved.insert(plan.id)
                }
            }
            return ReminderReconciliationInput(intents: intents, unresolvedPlanIDs: unresolved)
        }
    }

    /// Read the system's current scheduling state; saved reminder intent is not delivery proof.
    static func statusKey(plan: ShootPlan, summary: DaySummary) async -> String {
        guard plan.completedAt == nil, plan.reminderLeadMinutes != nil else { return "v3.reminder.off" }
        guard Planner.anchorDate(plan: plan, summary: summary) != nil else { return "plan.noEvent" }
        guard let expected = Planner.reminder(plan: plan, summary: summary, now: Date()) else { return "notice.pastReminder" }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied { return "notice.notificationDenied" }
        let pending = await center.pendingNotificationRequests()
        let id = identifier(plan.id)
        let owned = pending.filter { $0.identifier == id || $0.identifier.hasPrefix(id + ".") }
        let expectedContent = intent(plan: plan, summary: summary, language: L10n.language, now: Date())
        return owned.count == 1 && owned.contains {
            guard $0.trigger?.repeats == false,
                  $0.content.title == expectedContent?.title, $0.content.body == expectedContent?.body,
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
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        // Drain the center's serial request queue before a subsequent capacity/status read.
        _ = await center.pendingNotificationRequests()
    }
    func add(_ request: ScheduledReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.intent.title; content.body = request.intent.body
        content.sound = .default; content.userInfo = ["planID": request.intent.planID.uuidString]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.intent.fireDate)
        components.calendar = calendar; components.timeZone = .gmt
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        guard let next = trigger.nextTriggerDate(), next > Date(),
              abs(next.timeIntervalSince(request.intent.fireDate)) < 1 else { throw LightPlanError.invalidDate }
        let notification = UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
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
