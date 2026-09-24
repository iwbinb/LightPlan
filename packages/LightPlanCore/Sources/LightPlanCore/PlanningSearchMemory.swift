import Foundation

/// Applied search inputs, not search results. Sorting never changes the calculation request.
public struct PlanningSearchConfiguration: Hashable, Sendable {
    public var startDate: Date
    public var days: Int
    public var constraints: OpportunityConstraints?
    public var sortByDate: Bool

    public init(startDate: Date, days: Int = 14, constraints: OpportunityConstraints?, sortByDate: Bool = false) {
        self.startDate = startDate; self.days = days
        self.constraints = constraints; self.sortByDate = sortByDate
    }

    public var calculationInput: Self {
        var value = self; value.sortByDate = false; return value
    }

    public func validated(timeZone: TimeZone) throws -> Self {
        try LocalDay.validate(startDate, timeZone: timeZone)
        guard (1...90).contains(days) else { throw LightPlanError.invalidNumber }
        if let constraints { _ = try constraints.validated() }
        return self
    }
}

/// A map snapshot excludes place names/IDs, which do not change the geometry.
public struct PlanningSearchContext: Hashable, Sendable {
    public let observer: Coordinate
    public let subject: Coordinate
    public let timeZoneID: String
    public let body: CelestialBody
    public let offset: Double

    public init(place: Place, subject: Coordinate, body: CelestialBody, offset: Double) {
        self.observer = place.coordinate; self.subject = subject
        self.timeZoneID = place.timeZoneID; self.body = body; self.offset = offset
    }
}

/// Session-only memory, bounded to one entry per body. No coordinates are written
/// to preferences, archives or logs. A result is always recalculated for its request.
public struct PlanningSearchMemory: Sendable {
    private struct Entry: Sendable {
        let context: PlanningSearchContext
        var mapDate: Date
        let configuration: PlanningSearchConfiguration
    }
    private var entries: [CelestialBody: Entry] = [:]
    public init() {}

    public func configuration(for context: PlanningSearchContext, mapDate: Date,
                              defaults: PlanningSearchConfiguration) throws -> PlanningSearchConfiguration {
        let zone = try timeZone(for: context, date: mapDate)
        guard let entry = entries[context.body] else { return try defaults.validated(timeZone: zone) }
        var value = entry.configuration
        // A deliberate new map day/location/subject starts a new range but retains
        // this body's applied filters, duration and order. Never reuse old results.
        if entry.context != context || !LocalDay.same(entry.mapDate, mapDate, timeZone: zone) {
            value.startDate = mapDate
        }
        return try value.validated(timeZone: zone)
    }

    public mutating func remember(_ configuration: PlanningSearchConfiguration,
                                  for context: PlanningSearchContext, mapDate: Date) throws {
        let zone = try timeZone(for: context, date: mapDate)
        let checked = try configuration.validated(timeZone: zone)
        entries[context.body] = Entry(context: context, mapDate: mapDate, configuration: checked)
    }

    /// Picking a window moves the map, not the previously requested search range.
    public mutating func selectedResult(for context: PlanningSearchContext, mapDate: Date) throws {
        _ = try timeZone(for: context, date: mapDate)
        guard entries[context.body]?.context == context else { return }
        entries[context.body]?.mapDate = mapDate
    }

    /// Explicit templates and saved plans take precedence over remembered settings.
    public mutating func reset(body: CelestialBody) { entries.removeValue(forKey: body) }

    private func timeZone(for context: PlanningSearchContext, date: Date) throws -> TimeZone {
        guard let zone = TimeZone(identifier: context.timeZoneID) else { throw LightPlanError.invalidTimeZone }
        guard context.offset.isFinite, (-180...180).contains(context.offset),
              Geometry.bearing(from: context.observer, to: context.subject) != nil else { throw LightPlanError.invalidPlan }
        try LocalDay.validate(date, timeZone: zone)
        return zone
    }
}
