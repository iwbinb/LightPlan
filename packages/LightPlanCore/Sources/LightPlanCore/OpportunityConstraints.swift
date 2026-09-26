import Foundation

/// Geometric search conditions, not a prediction of weather, terrain visibility or image quality.
/// Altitudes are the geometric center of the body, in degrees above the horizon.
public struct OpportunityConstraints: Codable, Hashable, Sendable {
    public let maximumErrorDegrees: Double
    public let altitudeRange: ClosedRange<Double>
    public let solarAltitudeRange: ClosedRange<Double>?
    /// Fraction of the Moon illuminated at the actual candidate instant, from 0 to 1.
    public let moonIlluminationRange: ClosedRange<Double>?

    public init(maximumErrorDegrees: Double = 180,
                altitudeRange: ClosedRange<Double> = -1...90,
                solarAltitudeRange: ClosedRange<Double>? = nil,
                moonIlluminationRange: ClosedRange<Double>? = nil) throws {
        func valid(_ range: ClosedRange<Double>) -> Bool {
            range.lowerBound.isFinite && range.upperBound.isFinite &&
            range.lowerBound >= -90 && range.upperBound <= 90 &&
            range.lowerBound < range.upperBound
        }
        guard maximumErrorDegrees.isFinite, (0...180).contains(maximumErrorDegrees),
              valid(altitudeRange), solarAltitudeRange.map(valid) ?? true,
              moonIlluminationRange.map({ range in
                  range.lowerBound.isFinite && range.upperBound.isFinite &&
                  range.lowerBound >= 0 && range.upperBound <= 1 && range.lowerBound <= range.upperBound
              }) ?? true else {
            throw LightPlanError.invalidNumber
        }
        self.maximumErrorDegrees = maximumErrorDegrees
        self.altitudeRange = altitudeRange
        self.solarAltitudeRange = solarAltitudeRange
        self.moonIlluminationRange = moonIlluminationRange
    }

    public func validated() throws -> Self {
        try Self(maximumErrorDegrees: maximumErrorDegrees, altitudeRange: altitudeRange,
                 solarAltitudeRange: solarAltitudeRange, moonIlluminationRange: moonIlluminationRange)
    }

    private enum CodingKeys: String, CodingKey { case maximumErrorDegrees, altitudeRange, solarAltitudeRange, moonIlluminationRange }

    /// Decode bounds individually and validate before constructing a ClosedRange. A malformed
    /// reversed range must throw, never reach ClosedRange's ordering precondition.
    private struct EncodedAltitudeRange: Codable {
        let lowerBound: Double
        let upperBound: Double

        init(_ range: ClosedRange<Double>) {
            lowerBound = range.lowerBound
            upperBound = range.upperBound
        }

        func validated(illumination: Bool = false) throws -> ClosedRange<Double> {
            if illumination {
                guard lowerBound.isFinite, upperBound.isFinite, lowerBound >= 0,
                      upperBound <= 1, lowerBound <= upperBound else { throw LightPlanError.invalidNumber }
                return lowerBound...upperBound
            }
            guard lowerBound.isFinite, upperBound.isFinite, lowerBound >= -90,
                  upperBound <= 90, lowerBound < upperBound else { throw LightPlanError.invalidNumber }
            return lowerBound...upperBound
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let altitude = try values.decode(EncodedAltitudeRange.self, forKey: .altitudeRange).validated()
        let solarAltitude = try values.decodeIfPresent(EncodedAltitudeRange.self, forKey: .solarAltitudeRange)?.validated()
        let illumination = try values.decodeIfPresent(EncodedAltitudeRange.self, forKey: .moonIlluminationRange)?.validated(illumination: true)
        try self.init(maximumErrorDegrees: values.decode(Double.self, forKey: .maximumErrorDegrees),
                      altitudeRange: altitude, solarAltitudeRange: solarAltitude,
                      moonIlluminationRange: illumination)
    }

    public func encode(to encoder: Encoder) throws {
        _ = try validated()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(maximumErrorDegrees, forKey: .maximumErrorDegrees)
        try values.encode(EncodedAltitudeRange(altitudeRange), forKey: .altitudeRange)
        if let solarAltitudeRange {
            try values.encode(EncodedAltitudeRange(solarAltitudeRange), forKey: .solarAltitudeRange)
        }
        if let moonIlluminationRange {
            try values.encode(EncodedAltitudeRange(moonIlluminationRange), forKey: .moonIlluminationRange)
        }
    }
}

/// Splits the search at the actual constraint crossings before minimizing alignment.
/// Sampling locates smooth extrema; refinement retains short near-tangent windows whose
/// coarse endpoints are both outside the allowed range. The root tolerance is numerical,
/// not a guarantee of astronomical-model, terrain or observed timing accuracy.
enum OpportunitySearch {
    static let boundaryTolerance: TimeInterval = 0.0001

    static func intervals(body: CelestialBody, observer: Coordinate, interval: DateInterval,
                          altitudeRange: ClosedRange<Double>, solarAltitudeRange: ClosedRange<Double>?,
                          moonIlluminationRange: ClosedRange<Double>? = nil,
                          step: TimeInterval,
                          position: ((CelestialBody, Date) throws -> SkyPosition)? = nil) throws -> [DateInterval] {
        try SearchSampling.validate(interval: interval, step: step)
        var result = try altitudeIntervals(body: body, observer: observer, interval: interval,
                                           range: altitudeRange, step: step, position: position)
        if let solarAltitudeRange, !result.isEmpty {
            let solar = try altitudeIntervals(body: .sun, observer: observer, interval: interval,
                                               range: solarAltitudeRange, step: step, position: position)
            result = try intersect(result, solar)
        }
        if let moonIlluminationRange, moonIlluminationRange != 0...1, !result.isEmpty {
            // Illumination varies throughout a day. Filtering only its noon/daily-best value
            // would discard valid partial-day windows at a phase cutoff.
            let phase = try scalarIntervals(interval: interval, range: moonIlluminationRange, step: step) {
                Astronomy.moonIllumination(at: $0)
            }
            result = try intersect(result, phase)
        }
        return result
    }

    static func alignmentIntervals(body: CelestialBody, observer: Coordinate, subject: Coordinate,
                                   interval: DateInterval, desiredOffsetDegrees: Double,
                                   maximumErrorDegrees: Double, step: TimeInterval,
                                   position: ((CelestialBody, Date) throws -> SkyPosition)? = nil) throws -> [DateInterval] {
        try SearchSampling.validate(interval: interval, step: step)
        guard maximumErrorDegrees.isFinite, (0...180).contains(maximumErrorDegrees),
              desiredOffsetDegrees.isFinite, (-90...90).contains(desiredOffsetDegrees) else {
            throw LightPlanError.invalidNumber
        }
        if maximumErrorDegrees == 180 { return [interval] }
        guard let bearing = Geometry.bearing(from: observer, to: subject) else { throw LightPlanError.invalidNumber }
        return try scalarIntervals(interval: interval, range: 0...maximumErrorDegrees, step: step) { instant in
            let sky = try position?(body, instant) ?? Astronomy.position(body, at: instant, coordinate: observer)
            return CompositionPlanner.candidate(body: body, at: instant, sky: sky, subjectBearing: bearing,
                                                desiredOffsetDegrees: desiredOffsetDegrees).absoluteErrorDegrees
        }
    }

    static func intersect(_ lhs: [DateInterval], _ rhs: [DateInterval]) throws -> [DateInterval] {
        var result: [DateInterval] = []
        var left = 0, right = 0
        while left < lhs.count, right < rhs.count {
            try Task.checkCancellation()
            let a = lhs[left], b = rhs[right]
            let start = max(a.start, b.start), end = min(a.end, b.end)
            if end > start { result.append(DateInterval(start: start, end: end)) }
            if a.end < b.end { left += 1 } else { right += 1 }
        }
        return result
    }

    private static func altitudeIntervals(body: CelestialBody, observer: Coordinate,
                                          interval: DateInterval, range: ClosedRange<Double>,
                                          step: TimeInterval,
                                          position: ((CelestialBody, Date) throws -> SkyPosition)?) throws -> [DateInterval] {
        if range == -90...90 { return [interval] }
        return try scalarIntervals(interval: interval, range: range, step: step) {
            try (position?(body, $0) ?? Astronomy.position(body, at: $0, coordinate: observer)).altitude
        }
    }

    /// Positive-duration intervals only. A zero-width condition may describe an isolated
    /// instant but has no usable shooting duration, so it produces no window.
    static func scalarIntervals(interval: DateInterval, range: ClosedRange<Double>,
                                step: TimeInterval,
                                value: (Date) throws -> Double) throws -> [DateInterval] {
        // Reject bad steps before capping them; zero/NaN must not become a hang or
        // a misleading empty result. Nonfinite model values are calculation errors.
        try SearchSampling.validate(interval: interval, step: step)
        guard range.lowerBound.isFinite, range.upperBound.isFinite else {
            throw LightPlanError.invalidNumber
        }
        guard range.lowerBound < range.upperBound else { return [] }
        let samples = try SearchSampling.samples(in: interval, step: min(step, 300),
            tolerance: boundaryTolerance, iterations: 48, value: value)
        var boundaries = samples.map(\.0)
        for (left, right) in zip(samples, samples.dropFirst()) {
            try Task.checkCancellation()
            for threshold in [range.lowerBound, range.upperBound] {
                let a = left.1 - threshold, b = right.1 - threshold
                guard (a < 0 && b > 0) || (a > 0 && b < 0) else { continue }
                var low = left.0, high = right.0
                for _ in 0..<40 {
                    try Task.checkCancellation()
                    if high.timeIntervalSince(low) < boundaryTolerance { break }
                    let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                    let residual = try SearchSampling.checkedValue(at: middle, using: value) - threshold
                    if (residual > 0) == (a > 0) { low = middle } else { high = middle }
                }
                boundaries.append(low.addingTimeInterval(high.timeIntervalSince(low) / 2))
            }
        }
        boundaries.sort()
        var result: [DateInterval] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > start {
            try Task.checkCancellation()
            let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            guard range.contains(try SearchSampling.checkedValue(at: middle, using: value)) else { continue }
            if let previous = result.last, previous.end == start {
                result[result.count - 1] = DateInterval(start: previous.start, end: end)
            } else {
                result.append(DateInterval(start: start, end: end))
            }
        }
        return result
    }
}
