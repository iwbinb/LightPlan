import Foundation

public enum DayEngine {
    /// An entire destination civil day, including DST and offset-boundary days.
    public static func calculate(place: Place, date: Date) throws -> DaySummary {
        try LocalDay.validate(date, timeZone: place.timeZone)
        let interval = try LocalDay.interval(containing: date, timeZone: place.timeZone)
        let sun = try samples(body: .sun, start: interval.start, end: interval.end, coordinate: place.coordinate, step: 60)
        let moon = try samples(body: .moon, start: interval.start, end: interval.end, coordinate: place.coordinate, step: 120)
        let definitions: [(Double, LightEventKind, LightEventKind)] = [
            (-18, .astronomicalDawn, .astronomicalDusk), (-12, .nauticalDawn, .nauticalDusk),
            (-6, .blueMorningStart, .blueEveningEnd), (-4, .goldenMorningStart, .goldenEveningEnd),
            (6, .goldenMorningEnd, .goldenEveningStart)
        ]
        var events: [LightEvent] = []
        for (threshold, rising, setting) in definitions {
            events += try crossings(body: .sun, samples: sun, coordinate: place.coordinate, threshold: threshold, rising: rising, setting: setting)
        }
        events += try crossings(body: .sun, samples: sun, coordinate: place.coordinate, threshold: nil, rising: .sunrise, setting: .sunset)
        events += try crossings(body: .moon, samples: moon, coordinate: place.coordinate, threshold: nil, rising: .moonrise, setting: .moonset)
        events.sort { $0.date < $1.date }
        let excluded: Set<LightEventKind> = [.sunrise, .sunset, .moonrise, .moonset]
        let boundaries = ([interval.start, interval.end] + events.filter { !excluded.contains($0.kind) }.map(\.date)).sorted()
        var windows: [LightWindow] = []
        for (a, b) in zip(boundaries, boundaries.dropFirst()) where b.timeIntervalSince(a) > 0.01 {
            let middle = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            let altitude = try Astronomy.position(.sun, at: middle, coordinate: place.coordinate).altitude
            windows.append(LightWindow(band: Astronomy.lightBand(altitude: altitude), start: a, end: b))
        }
        let residuals = sun.map { $0.1 - Astronomy.horizonThreshold(.sun, at: $0.0) }
        let state: String? = residuals.allSatisfy { $0 > 0 } ? "alwaysAbove" : (residuals.allSatisfy { $0 < 0 } ? "alwaysBelow" : nil)
        return DaySummary(place: place, start: interval.start, end: interval.end, events: events, windows: windows, horizonState: state)
    }

    static func samples(body: CelestialBody, start: Date, end: Date, coordinate: Coordinate, step: TimeInterval) throws -> [(Date, Double)] {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end > start else { throw LightPlanError.invalidDate }
        // An extremum near midnight has no outside grid neighbour. The shared sampler
        // explicitly refines both edge cells as well as interior extrema.
        return try SearchSampling.samples(in: DateInterval(start: start, end: end), step: step,
            tolerance: 0.02, iterations: 32) {
                try Astronomy.position(body, at: $0, coordinate: coordinate).altitude
            }
    }

    /// A nil threshold means upper limb plus a standard 34-arcminute horizon refraction.
    static func crossings(body: CelestialBody, samples: [(Date, Double)], coordinate: Coordinate,
                          threshold: Double?, rising: LightEventKind, setting: LightEventKind) throws -> [LightEvent] {
        guard let end = samples.last?.0 else { return [] }
        func limit(_ date: Date) -> Double { threshold ?? Astronomy.horizonThreshold(body, at: date) }
        var output: [LightEvent] = []
        for (left, right) in zip(samples, samples.dropFirst()) {
            try Task.checkCancellation()
            let a = left.1 - limit(left.0), b = right.1 - limit(right.0)
            guard (a <= 0 && b > 0) || (a >= 0 && b < 0) else { continue }
            let isRising = b > a
            var lo = left.0, hi = right.0
            for _ in 0..<25 {
                try Task.checkCancellation()
                if hi.timeIntervalSince(lo) < 0.1 { break }
                let middle = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                let f = try Astronomy.position(body, at: middle, coordinate: coordinate).altitude - limit(middle)
                if (f > 0) == isRising { hi = middle } else { lo = middle }
            }
            let root = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            guard root < end else { continue }
            if let last = output.last, abs(root.timeIntervalSince(last.date)) < 0.2 { continue }
            let position = try Astronomy.position(body, at: root, coordinate: coordinate)
            output.append(LightEvent(kind: isRising ? rising : setting, date: root, azimuth: position.azimuth))
        }
        return output
    }
}
