import Foundation

/// Local to one searched civil day and observer. Lighting and alignment share exact
/// sky samples; no rounding, persisted results or cross-request/global state.
struct SearchSkyCache {
    private struct Key: Hashable { let body: CelestialBody; let instant: Date }
    let coordinate: Coordinate
    let capacity: Int
    private var values: [Key: SkyPosition] = [:]
    var count: Int { values.count }
    private(set) var calculationCount = 0

    init(coordinate: Coordinate, capacity: Int = 4096) {
        self.coordinate = coordinate
        self.capacity = min(4096, max(0, capacity))
    }

    mutating func position(_ body: CelestialBody, at instant: Date) throws -> SkyPosition {
        try Task.checkCancellation()
        guard instant.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        let key = Key(body: body, instant: instant)
        if let sky = values[key] { return sky }
        let sky = try Astronomy.position(body, at: instant, coordinate: coordinate)
        calculationCount += 1
        if values.count < capacity { values[key] = sky }
        return sky
    }
}
