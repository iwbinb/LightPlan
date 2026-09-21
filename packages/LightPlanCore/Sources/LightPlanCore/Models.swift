import Foundation

public enum LightPlanError: Error, Equatable, Sendable {
    case invalidCoordinate, invalidTimeZone, invalidDate, invalidNumber, unsupportedSchema
    case invalidPlan, noEvent, corruptArchive, tooManyItems, storageLocked
}
public struct Coordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw LightPlanError.invalidCoordinate
        }
        self.latitude = latitude; self.longitude = longitude
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(latitude: c.decode(Double.self, forKey: .latitude), longitude: c.decode(Double.self, forKey: .longitude))
    }
}
public struct Place: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public let coordinate: Coordinate
    public let timeZoneID: String
    public var isExample: Bool
    public init(id: UUID = UUID(), name: String, coordinate: Coordinate, timeZoneID: String, isExample: Bool = false) throws {
        guard TimeZone(identifier: timeZoneID) != nil else { throw LightPlanError.invalidTimeZone }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120 else { throw LightPlanError.invalidPlan }
        self.id = id; self.name = name; self.coordinate = coordinate; self.timeZoneID = timeZoneID; self.isExample = isExample
    }
    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID)! } // immutable identifier validated on init and decode
    public func validated() throws -> Place {
        try Place(id: id, name: name, coordinate: coordinate, timeZoneID: timeZoneID, isExample: isExample)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(UUID.self, forKey: .id), name: c.decode(String.self, forKey: .name),
                      coordinate: c.decode(Coordinate.self, forKey: .coordinate), timeZoneID: c.decode(String.self, forKey: .timeZoneID),
                      isExample: c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false)
    }
    public static let example = try! Place(name: "Gulangyu", coordinate: Coordinate(latitude: 24.4478, longitude: 118.0679), timeZoneID: "Asia/Shanghai", isExample: true)
}
public enum CelestialBody: String, Codable, CaseIterable, Sendable { case sun, moon }
public struct SkyPosition: Codable, Sendable {
    /// Degrees clockwise from true north. Near zenith use angular separation, not azimuth error, for QA.
    public let azimuth: Double
    /// Geometric, unrefracted center altitude. Golden/blue windows use this value.
    public let altitude: Double
    public let apparentAltitude: Double
}
public enum LightEventKind: String, CaseIterable, Codable, Sendable {
    case astronomicalDawn, nauticalDawn, blueMorningStart, goldenMorningStart, sunrise, goldenMorningEnd
    case goldenEveningStart, sunset, goldenEveningEnd, blueEveningEnd, nauticalDusk, astronomicalDusk
    case moonrise, moonset
    public var key: String { "event." + rawValue }
}
public struct LightEvent: Codable, Identifiable, Sendable {
    public var id: String { "\(kind.rawValue):\(Int(date.timeIntervalSince1970))" }
    public let kind: LightEventKind
    public let date: Date
    public let azimuth: Double
}
public enum LightBand: String, Codable, Sendable { case night, astronomical, nautical, blue, golden, daylight }
public struct LightWindow: Codable, Sendable {
    public let band: LightBand
    public let start: Date
    public let end: Date
}
public struct DaySummary: Codable, Sendable {
    public let place: Place
    public let start: Date
    public let end: Date
    public let events: [LightEvent]
    public let windows: [LightWindow]
    /// Nil means no whole-day assertion. No sunrise alone never implies polar night.
    public let horizonState: String?
    public func first(_ kind: LightEventKind) -> LightEvent? { events.first { $0.kind == kind } }
}
public enum LocalDay {
    public static func validate(_ date: Date, timeZone: TimeZone) throws {
        guard date.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard (1900...2100).contains(calendar.component(.year, from: date)) else { throw LightPlanError.invalidDate }
    }
    public static func supportedRange(timeZone: TimeZone) -> ClosedRange<Date> {
        // Constants are checked by tests in extreme time zones.
        let first = try! date(year: 1900, month: 1, day: 1, timeZone: timeZone)
        let last = try! date(year: 2100, month: 12, day: 31, timeZone: timeZone)
        return first...last
    }
    public static func same(_ a: Date, _ b: Date, timeZone: TimeZone) -> Bool {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        return cal.isDate(a, inSameDayAs: b)
    }

    /// Preserve the selected civil date when the map destination changes time zone.
    /// A skipped local date is rejected, never silently normalized into another day.
    public static func relocating(_ value: Date, from source: TimeZone, to destination: TimeZone) throws -> Date {
        try validate(value, timeZone: source)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = source
        let components = calendar.dateComponents([.year, .month, .day], from: value)
        guard let year = components.year, let month = components.month, let day = components.day else { throw LightPlanError.invalidDate }
        return try date(year: year, month: month, day: day, timeZone: destination)
    }

    public static func interval(containing date: Date, timeZone: TimeZone) throws -> DateInterval {
        guard date.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let result = calendar.dateInterval(of: .day, for: date) else { throw LightPlanError.invalidDate }
        return result // 23, 24, 25, and fractional-hour DST days are deliberately preserved.
    }
    public static func date(year: Int, month: Int, day: Int, timeZone: TimeZone) throws -> Date {
        guard (1900...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { throw LightPlanError.invalidDate }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              cal.component(.year, from: d) == year, cal.component(.month, from: d) == month,
              cal.component(.day, from: d) == day else { throw LightPlanError.invalidDate }
        return d
    }
}
