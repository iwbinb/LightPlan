import Foundation

/// The same destination-day schedule powers the saved plan and its portable field brief.
public struct PlanFieldBrief: Sendable {
    public let plan: ShootPlan
    public let shootAt: Date
    public let arriveAt: Date
    public let mapURL: URL

    public init(plan: ShootPlan, summary: DaySummary) throws {
        _ = try plan.validated()
        guard let anchor = Planner.anchorDate(plan: plan, summary: summary) else {
            throw LightPlanError.noEvent
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(plan.place.coordinate.latitude),\(plan.place.coordinate.longitude)"),
            URLQueryItem(name: "q", value: plan.place.name)
        ]
        guard let url = components.url else { throw LightPlanError.invalidPlan }
        self.plan = plan
        shootAt = anchor
        arriveAt = anchor.addingTimeInterval(-Double(plan.arrivalLeadMinutes) * 60)
        mapURL = url
    }
}
