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
        var base: [(Date, Double)] = []
        var time = start
        while time < end {
            try Task.checkCancellation()
            base.append((time, try Astronomy.position(body, at: time, coordinate: coordinate).altitude))
            time = min(end, time.addingTimeInterval(step))
        }
        base.append((end, try Astronomy.position(body, at: end, coordinate: coordinate).altitude))
        // Refine local extrema before searching crossings. A very short polar daylight interval
        // can have two roots within one sample cell, which a sign-only grid would miss.
        var extrema: [(Date, Double)] = []
        if base.count >= 3 {
            for i in 1..<(base.count - 1) {
                let left = base[i - 1].1, middle = base[i].1, right = base[i + 1].1
                let maximum = middle >= left && middle >= right
                let minimum = middle <= left && middle <= right
                guard maximum || minimum else { continue }
                var lo = base[i - 1].0, hi = base[i + 1].0
                for _ in 0..<32 {
                    if hi.timeIntervalSince(lo) < 0.02 { break }
                    let a = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 3)
                    let b = hi.addingTimeInterval(-hi.timeIntervalSince(lo) / 3)
                    let fa = try Astronomy.position(body, at: a, coordinate: coordinate).altitude
                    let fb = try Astronomy.position(body, at: b, coordinate: coordinate).altitude
                    if (fa < fb) == maximum { lo = a } else { hi = b }
                }
                let peak = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                extrema.append((peak, try Astronomy.position(body, at: peak, coordinate: coordinate).altitude))
            }
        }
        return (base + extrema).sorted { $0.0 < $1.0 }
    }

    /// A nil threshold means upper limb plus a standard 34-arcminute horizon refraction.
    static func crossings(body: CelestialBody, samples: [(Date, Double)], coordinate: Coordinate,
                          threshold: Double?, rising: LightEventKind, setting: LightEventKind) throws -> [LightEvent] {
        guard let end = samples.last?.0 else { return [] }
        func limit(_ date: Date) -> Double { threshold ?? Astronomy.horizonThreshold(body, at: date) }
        var output: [LightEvent] = []
        for (left, right) in zip(samples, samples.dropFirst()) {
            let a = left.1 - limit(left.0), b = right.1 - limit(right.0)
            guard (a <= 0 && b > 0) || (a >= 0 && b < 0) else { continue }
            let isRising = b > a
            var lo = left.0, hi = right.0
            for _ in 0..<25 {
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
