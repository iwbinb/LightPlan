import Foundation

/// Pure, testable presentation geometry shared by the native map and timeline.
/// Angles are true-north clockwise. These projected rays are not terrain shadows.
public enum VisualGeometry {
    public static func fraction(at instant: Date, in interval: DateInterval) -> Double {
        guard interval.duration > 0, instant.timeIntervalSince1970.isFinite else { return 0 }
        return min(1, max(0, instant.timeIntervalSince(interval.start) / interval.duration))
    }
    public static func instant(at fraction: Double, in interval: DateInterval) -> Date {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return interval.start.addingTimeInterval(min(max(0, interval.duration - 1), interval.duration * f))
    }
    public static func shortestAngle(from: Double, to: Double, fraction: Double) -> Double {
        guard from.isFinite, to.isFinite, fraction.isFinite else { return 0 }
        let delta = Astronomy.normalize(to - from + 180) - 180
        return Astronomy.normalize(from + delta * min(1, max(0, fraction)))
    }
    public static func destination(from coordinate: Coordinate, bearing: Double, meters: Double) throws -> Coordinate {
        guard bearing.isFinite, meters.isFinite, meters >= 0 else { throw LightPlanError.invalidNumber }
        let r = Double.pi / 180, phi = coordinate.latitude * r, lambda = coordinate.longitude * r
        let theta = bearing * r, distance = meters / 6_371_000
        let lat = asin(min(1, max(-1, sin(phi) * cos(distance) + cos(phi) * sin(distance) * cos(theta))))
        let lon = lambda + atan2(sin(theta) * sin(distance) * cos(phi), cos(distance) - sin(phi) * sin(lat))
        return try Coordinate(latitude: lat / r, longitude: Astronomy.normalize(lon / r + 180) - 180)
    }
}

public struct LightSample: Sendable, Identifiable {
    public var id: TimeInterval { instant.timeIntervalSince1970 }
    public let instant: Date
    public let sun: SkyPosition
    public let moon: SkyPosition
}
public enum VisualSampler {
    /// Off-main-thread caller; bounded sampling independent of frame/drag rate.
    public static func samples(for summary: DaySummary, count: Int = 289) throws -> [LightSample] {
        guard (2...1441).contains(count) else { throw LightPlanError.invalidNumber }
        let interval = DateInterval(start: summary.start, end: summary.end)
        return try (0..<count).map { i in
            let instant = VisualGeometry.instant(at: Double(i) / Double(count - 1), in: interval)
            return LightSample(instant: instant,
                sun: try Astronomy.position(.sun, at: instant, coordinate: summary.place.coordinate),
                moon: try Astronomy.position(.moon, at: instant, coordinate: summary.place.coordinate))
        }
    }
}

public struct MapProjection: Sendable {
    public let sunTracks: [[Coordinate]]
    public let moonTracks: [[Coordinate]]
    public let goldenSector: [Coordinate]
    public static func make(summary: DaySummary, samples: [LightSample], meters: Double = 1050) throws -> MapProjection {
        let origin = summary.place.coordinate
        func tracks(_ body: CelestialBody) throws -> [[Coordinate]] {
            var result: [[Coordinate]] = []; var segment: [Coordinate] = []
            for sample in samples {
                let sky = body == .sun ? sample.sun : sample.moon
                if sky.altitude >= 0 {
                    segment.append(try VisualGeometry.destination(from: origin, bearing: sky.azimuth, meters: meters))
                } else if !segment.isEmpty {
                    if segment.count > 1 { result.append(segment) }; segment = []
                }
            }
            if segment.count > 1 { result.append(segment) }
            return result
        }
        var sector: [Coordinate] = []
        if let window = summary.windows.last(where: { $0.band == .golden }) {
            let duration = window.end.timeIntervalSince(window.start)
            // Exact interval endpoints prevent the golden wedge disappearing between coarse samples.
            let boundary = try (0...24).map { i -> Coordinate in
                let time = window.start.addingTimeInterval(duration * Double(i) / 24)
                let sun = try Astronomy.position(.sun, at: time, coordinate: origin)
                return try VisualGeometry.destination(from: origin, bearing: sun.azimuth, meters: meters)
            }
            sector = [origin] + boundary + [origin]
        }
        return try MapProjection(sunTracks: tracks(.sun), moonTracks: tracks(.moon), goldenSector: sector)
    }
}
