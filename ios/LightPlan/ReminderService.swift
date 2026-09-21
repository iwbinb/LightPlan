import Foundation
import UserNotifications
import LightPlanCore

enum ReminderResult { case scheduled, denied, noFutureEvent, capacityReached, superseded }
@MainActor enum ReminderService {
    static let budget = 48 // Product budget; not an assertion about an undocumented OS limit.
    private static var revision = 0
    static func cancel(planID: UUID) async {
        revision += 1
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: old.filter { $0.identifier == identifier(planID) || $0.identifier.hasPrefix(identifier(planID) + ".") }.map(\.identifier))
    }
    private static func identifier(_ id: UUID) -> String { "plan." + id.uuidString }
    static func schedule(plan: ShootPlan, summary: DaySummary, language: String) async throws -> ReminderResult {
        revision += 1; let generation = revision
        guard let fire = Planner.reminder(plan: plan, summary: summary, now: Date()),
              let anchor = summary.first(Planner.anchorKind(plan.target)) else { return .noFutureEvent }
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return .denied }
        guard generation == revision else { return .superseded }
        let id = identifier(plan.id), pending = await center.pendingNotificationRequests()
        guard pending.filter({ $0.identifier != id && !$0.identifier.hasPrefix(id + ".") }).count < budget else { return .capacityReached }
        guard generation == revision else { return .superseded }
        let next = request(plan: plan, fire: fire, anchor: anchor.date, language: language)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier == id || $0.identifier.hasPrefix(id + ".") }.map(\.identifier))
        try await center.add(next)
        guard generation == revision else {
            // An in-flight add can finish after cancellation. Only remove this operation's unique ID.
            center.removePendingNotificationRequests(withIdentifiers: [next.identifier]); return .superseded
        }
        return .scheduled
    }
    private static func request(plan: ShootPlan, fire: Date, anchor: Date, language: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = L10n.text("notification.body", language: language) + " · " + plan.place.name + " · " + L10n.time(anchor, zone: plan.place.timeZone, language: language) + " (" + plan.place.timeZoneID + ")"
        content.sound = .default; content.userInfo = ["planID": plan.id.uuidString]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        components.calendar = calendar; components.timeZone = .gmt
        return UNNotificationRequest(identifier: identifier(plan.id) + "." + UUID().uuidString, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
    /// Replenish the nearest reminders on foreground/edits/import. Never re-prompt at launch.
    static func reconcile(plans: [ShootPlan], language: String, requestPermission: Bool = false) async {
        revision += 1; let generation = revision
        let center = UNUserNotificationCenter.current()
        if requestPermission { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
        let settings = await center.notificationSettings()
        guard generation == revision, [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let now = Date()
        let candidates = plans.filter {
            $0.reminderLeadMinutes != nil && ((try? LocalDay.interval(containing: $0.date, timeZone: $0.place.timeZone).end) ?? .distantPast) > now
        }.sorted { $0.date < $1.date }
        var requests: [(Date, UNNotificationRequest)] = []
        for plan in candidates.prefix(budget * 2) {
            guard generation == revision, !Task.isCancelled else { return }
            guard let day = try? await Task.detached(priority: .utility, operation: { try DayEngine.calculate(place: plan.place, date: plan.date) }).value,
                  let fire = Planner.reminder(plan: plan, summary: day, now: now),
                  let anchor = day.first(Planner.anchorKind(plan.target)) else { continue }
            requests.append((fire, request(plan: plan, fire: fire, anchor: anchor.date, language: language)))
        }
        requests.sort { $0.0 < $1.0 }
        let chosen = Array(requests.prefix(budget)), desired = Set(chosen.map { $0.1.identifier })
        let old = await center.pendingNotificationRequests()
        guard generation == revision else { return }
        center.removePendingNotificationRequests(withIdentifiers: old.filter { $0.identifier.hasPrefix("plan.") && !desired.contains($0.identifier) }.map(\.identifier))
        for (_, request) in chosen {
            guard generation == revision else { return }
            do {
                try await center.add(request)
                if generation != revision { center.removePendingNotificationRequests(withIdentifiers: [request.identifier]); return }
            } catch { return } // Saved plans survive; Settings exposes system state.
        }
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
