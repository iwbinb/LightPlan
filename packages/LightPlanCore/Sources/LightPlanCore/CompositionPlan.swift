import Foundation

/// The confirmed composition, not a cached search result. Observer and time zone
/// live in ShootPlan.place; this snapshot preserves the subject and exact instant.
public struct CompositionPlan: Codable, Equatable, Sendable {
    public let body: CelestialBody
    public let subject: Coordinate
    public let desiredOffsetDegrees: Double
    public let instant: Date
    /// Nil in older archives. Retained so changing a saved plan's date can use the same search conditions.
    public let constraints: OpportunityConstraints?
    /// Nil in older archives; an explicitly configured geometric camera preview.
    public let cameraFraming: CameraFraming?

    public init(body: CelestialBody, subject: Coordinate, desiredOffsetDegrees: Double, instant: Date,
                constraints: OpportunityConstraints? = nil, cameraFraming: CameraFraming? = nil) throws {
        guard desiredOffsetDegrees.isFinite, (-90...90).contains(desiredOffsetDegrees),
              instant.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidPlan }
        _ = try constraints?.validated()
        _ = try cameraFraming?.validated()
        self.body = body
        self.subject = subject
        self.desiredOffsetDegrees = desiredOffsetDegrees
        self.instant = instant
        self.constraints = constraints
        self.cameraFraming = cameraFraming
    }

    public func validated(observer: Place, day: Date) throws -> CompositionPlan {
        try LocalDay.validate(instant, timeZone: observer.timeZone)
        guard LocalDay.same(day, instant, timeZone: observer.timeZone),
              Geometry.bearing(from: observer.coordinate, to: subject) != nil else {
            throw LightPlanError.invalidPlan
        }
        return try Self(body: body, subject: subject, desiredOffsetDegrees: desiredOffsetDegrees,
                        instant: instant, constraints: constraints, cameraFraming: cameraFraming)
    }

    private enum CodingKeys: String, CodingKey { case body, subject, desiredOffsetDegrees, instant, constraints, cameraFraming }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(body: values.decode(CelestialBody.self, forKey: .body),
                      subject: values.decode(Coordinate.self, forKey: .subject),
                      desiredOffsetDegrees: values.decode(Double.self, forKey: .desiredOffsetDegrees),
                      instant: values.decode(Date.self, forKey: .instant),
                      constraints: values.decodeIfPresent(OpportunityConstraints.self, forKey: .constraints),
                      cameraFraming: values.decodeIfPresent(CameraFraming.self, forKey: .cameraFraming))
    }
}
