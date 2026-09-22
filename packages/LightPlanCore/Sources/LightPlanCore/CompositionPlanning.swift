import Foundation

public enum AlignmentQuality: String, Sendable, Equatable {
    case exact, strong, workable, loose
}

public enum FrameSide: String, Sendable, Equatable {
    case left, centered, right
}

/// A single time where a celestial body is evaluated against the camera-to-subject bearing.
///
/// Offsets use the photographer's frame convention:
/// - 0°: body directly behind/in line with the subject.
/// - negative: body appears to the left of the subject.
/// - positive: body appears to the right of the subject.
public struct AlignmentCandidate: Identifiable, Sendable {
    public let body: CelestialBody
    public let instant: Date
    public let subjectBearing: Double
    public let bodyAzimuth: Double
    public let altitude: Double
    public let desiredOffsetDegrees: Double
    public let actualOffsetDegrees: Double
    public let errorDegrees: Double

    public var id: String {
        body.rawValue + ":" + String(Int(instant.timeIntervalSince1970)) + ":" + String(Int(desiredOffsetDegrees * 10))
    }

    public var absoluteErrorDegrees: Double { abs(errorDegrees) }

    public var quality: AlignmentQuality {
        switch absoluteErrorDegrees {
        case ...1: return .exact
        case ...3: return .strong
        case ...6: return .workable
        default: return .loose
        }
    }

    public var side: FrameSide {
        if actualOffsetDegrees < -1 { return .left }
        if actualOffsetDegrees > 1 { return .right }
        return .centered
    }
}

/// Pure composition geometry. It has no MapKit or UI dependency and can be reused by
/// future AR/terrain modules without changing the saved app model.
public enum CompositionPlanner {
    /// Signed shortest angular difference from target to actual, in -180...180.
    public static func signedDifference(target: Double, actual: Double) -> Double {
        guard target.isFinite, actual.isFinite else { return 0 }
        let value = Astronomy.normalize(actual - target + 180) - 180
        return value == -180 ? 180 : value
    }

    public static func evaluate(
        body: CelestialBody,
        at instant: Date,
        observer: Coordinate,
        subject: Coordinate,
        desiredOffsetDegrees: Double = 0
    ) throws -> AlignmentCandidate? {
        guard desiredOffsetDegrees.isFinite, (-90...90).contains(desiredOffsetDegrees),
              let bearing = Geometry.bearing(from: observer, to: subject) else { return nil }
        let sky = try Astronomy.position(body, at: instant, coordinate: observer)
        let actualOffset = signedDifference(target: bearing, actual: sky.azimuth)
        let error = signedDifference(target: desiredOffsetDegrees, actual: actualOffset)
        return AlignmentCandidate(
            body: body,
            instant: instant,
            subjectBearing: bearing,
            bodyAzimuth: sky.azimuth,
            altitude: sky.altitude,
            desiredOffsetDegrees: desiredOffsetDegrees,
            actualOffsetDegrees: actualOffset,
            errorDegrees: error
        )
    }

    /// Finds the visible instant with the smallest azimuth error inside one civil-day interval.
    ///
    /// A five-minute coarse pass is refined to seconds around the best sample. The default
    /// minimum altitude includes bodies on the apparent horizon but excludes deep-below-horizon
    /// mathematical alignments that are not useful for photography.
    public static func bestAlignment(
        body: CelestialBody,
        observer: Coordinate,
        subject: Coordinate,
        interval: DateInterval,
        desiredOffsetDegrees: Double = 0,
        minimumAltitude: Double = -1,
        coarseStep: TimeInterval = 300
    ) throws -> AlignmentCandidate? {
        guard interval.duration > 0,
              desiredOffsetDegrees.isFinite, (-90...90).contains(desiredOffsetDegrees),
              minimumAltitude.isFinite,
              coarseStep.isFinite, coarseStep >= 30, coarseStep <= 3600,
              Geometry.bearing(from: observer, to: subject) != nil else { return nil }

        func candidate(_ instant: Date) throws -> AlignmentCandidate? {
            guard let value = try evaluate(
                body: body,
                at: instant,
                observer: observer,
                subject: subject,
                desiredOffsetDegrees: desiredOffsetDegrees
            ), value.altitude >= minimumAltitude else { return nil }
            return value
        }

        func better(_ lhs: AlignmentCandidate, than rhs: AlignmentCandidate?) -> Bool {
            guard let rhs else { return true }
            if abs(lhs.absoluteErrorDegrees - rhs.absoluteErrorDegrees) > 1e-9 {
                return lhs.absoluteErrorDegrees < rhs.absoluteErrorDegrees
            }
            // Prefer the higher visible body when two instants have effectively equal alignment.
            if abs(lhs.altitude - rhs.altitude) > 1e-9 { return lhs.altitude > rhs.altitude }
            return lhs.instant < rhs.instant
        }

        var best: AlignmentCandidate?
        var time = interval.start
        let last = interval.end.addingTimeInterval(-1)
        while time <= last {
            try Task.checkCancellation()
            if let value = try candidate(time), better(value, than: best) { best = value }
            time = time.addingTimeInterval(coarseStep)
        }
        if let value = try candidate(last), better(value, than: best) { best = value }
        guard let coarseBest = best else { return nil }

        let refineStart = max(interval.start, coarseBest.instant.addingTimeInterval(-coarseStep))
        let refineEnd = min(last, coarseBest.instant.addingTimeInterval(coarseStep))
        time = refineStart
        while time <= refineEnd {
            try Task.checkCancellation()
            if let value = try candidate(time), better(value, than: best) { best = value }
            time = time.addingTimeInterval(15)
        }

        guard let refined = best else { return nil }
        let finalStart = max(interval.start, refined.instant.addingTimeInterval(-15))
        let finalEnd = min(last, refined.instant.addingTimeInterval(15))
        time = finalStart
        while time <= finalEnd {
            if let value = try candidate(time), better(value, than: best) { best = value }
            time = time.addingTimeInterval(1)
        }
        return best
    }

    /// Returns the best daily opportunities, sorted by alignment quality.
    public static func opportunities(
        body: CelestialBody,
        place: Place,
        subject: Coordinate,
        starting startDate: Date,
        days: Int = 14,
        desiredOffsetDegrees: Double = 0,
        minimumAltitude: Double = -1,
        limit: Int = 7
    ) throws -> [AlignmentCandidate] {
        guard (1...31).contains(days), (1...31).contains(limit) else { throw LightPlanError.invalidNumber }
        try LocalDay.validate(startDate, timeZone: place.timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        var values: [AlignmentCandidate] = []

        for offset in 0..<days {
            try Task.checkCancellation()
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { break }
            do { try LocalDay.validate(date, timeZone: place.timeZone) }
            catch LightPlanError.invalidDate { break }
            let interval = try LocalDay.interval(containing: date, timeZone: place.timeZone)
            if let candidate = try bestAlignment(
                body: body,
                observer: place.coordinate,
                subject: subject,
                interval: interval,
                desiredOffsetDegrees: desiredOffsetDegrees,
                minimumAltitude: minimumAltitude
            ) {
                values.append(candidate)
            }
        }

        return Array(values.sorted {
            if abs($0.absoluteErrorDegrees - $1.absoluteErrorDegrees) > 1e-9 {
                return $0.absoluteErrorDegrees < $1.absoluteErrorDegrees
            }
            return $0.instant < $1.instant
        }.prefix(limit))
    }

    /// Computes a suggested observer point around a subject for a known body azimuth.
    ///
    /// This is geometric guidance on a level map, not a route/safety/accessibility claim.
    public static func recommendedObserver(
        subject: Coordinate,
        bodyAzimuth: Double,
        desiredOffsetDegrees: Double = 0,
        distanceMeters: Double
    ) throws -> Coordinate {
        guard bodyAzimuth.isFinite,
              desiredOffsetDegrees.isFinite, (-90...90).contains(desiredOffsetDegrees),
              distanceMeters.isFinite, (10...10_000).contains(distanceMeters) else {
            throw LightPlanError.invalidNumber
        }
        let desiredSubjectBearing = Astronomy.normalize(bodyAzimuth - desiredOffsetDegrees)
        return try VisualGeometry.destination(
            from: subject,
            bearing: Astronomy.normalize(desiredSubjectBearing + 180),
            meters: distanceMeters
        )
    }
}
