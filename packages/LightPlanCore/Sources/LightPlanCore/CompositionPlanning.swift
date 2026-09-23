import Foundation

public enum AlignmentQuality: String, Sendable, Equatable {
    case exact, strong, workable, loose
}

public enum FrameSide: String, Sendable, Equatable {
    case left, centered, right
}

/// Every input that can change a daily alignment result. Also used as the UI task identity.
public struct AlignmentRequest: Hashable, Sendable {
    public let body: CelestialBody
    public let observer: Coordinate
    public let subject: Coordinate
    public let interval: DateInterval
    public let desiredOffsetDegrees: Double
    public let constraints: OpportunityConstraints?

    public init(body: CelestialBody, observer: Coordinate, subject: Coordinate,
                interval: DateInterval, desiredOffsetDegrees: Double = 0,
                constraints: OpportunityConstraints? = nil) {
        self.body = body
        self.observer = observer
        self.subject = subject
        self.interval = interval
        self.desiredOffsetDegrees = desiredOffsetDegrees
        self.constraints = constraints
    }
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
    /// Keep CPU work off the caller's actor while forwarding cancellation to the worker.
    static func runCancellable<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await operation()
        }
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            worker.cancel()
        }
    }

    public static func bestAlignment(for request: AlignmentRequest) async throws -> AlignmentCandidate? {
        try await runCancellable {
            try bestAlignment(body: request.body, observer: request.observer,
                              subject: request.subject, interval: request.interval,
                              desiredOffsetDegrees: request.desiredOffsetDegrees,
                              constraints: request.constraints)
        }
    }

    public static func opportunitiesAsync(
        body: CelestialBody, place: Place, subject: Coordinate, starting startDate: Date,
        days: Int = 14, desiredOffsetDegrees: Double = 0, minimumAltitude: Double = -1,
        limit: Int = 7, constraints: OpportunityConstraints? = nil
    ) async throws -> [AlignmentCandidate] {
        try await runCancellable {
            try opportunities(body: body, place: place, subject: subject, starting: startDate,
                              days: days, desiredOffsetDegrees: desiredOffsetDegrees,
                              minimumAltitude: minimumAltitude, limit: limit, constraints: constraints)
        }
    }

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

    /// Finds the smallest azimuth error within eligible altitude intervals of one civil day.
    /// `constraints`, when supplied, replaces the legacy `minimumAltitude` cutoff. Without it,
    /// the default permits the geometric center as low as -1° near the apparent horizon.
    /// Altitude extrema and crossings are resolved before alignment minimization so short
    /// visibility/lighting windows cannot disappear between the coarse samples.
    public static func bestAlignment(
        body: CelestialBody,
        observer: Coordinate,
        subject: Coordinate,
        interval: DateInterval,
        desiredOffsetDegrees: Double = 0,
        minimumAltitude: Double = -1,
        coarseStep: TimeInterval = 300,
        constraints: OpportunityConstraints? = nil
    ) throws -> AlignmentCandidate? {
        guard interval.duration.isFinite, interval.duration > 0,
              interval.start.timeIntervalSince1970.isFinite, interval.end.timeIntervalSince1970.isFinite,
              desiredOffsetDegrees.isFinite, (-90...90).contains(desiredOffsetDegrees),
              minimumAltitude.isFinite,
              coarseStep.isFinite, coarseStep >= 30, coarseStep <= 3600,
              Geometry.bearing(from: observer, to: subject) != nil else { return nil }

        let altitudeRange = constraints?.altitudeRange ?? min(minimumAltitude, 90)...90
        if constraints == nil && minimumAltitude > 90 { return nil }
        let eligible = try OpportunitySearch.intervals(body: body, observer: observer, interval: interval,
            altitudeRange: altitudeRange, solarAltitudeRange: constraints?.solarAltitudeRange,
            moonIlluminationRange: constraints?.moonIlluminationRange, step: coarseStep)

        func candidate(_ instant: Date) throws -> AlignmentCandidate? {
            try Task.checkCancellation()
            return try evaluate(
                body: body,
                at: instant,
                observer: observer,
                subject: subject,
                desiredOffsetDegrees: desiredOffsetDegrees
            )
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
        func consider(_ value: AlignmentCandidate) throws {
            guard value.instant < interval.end, altitudeRange.contains(value.altitude),
                  value.absoluteErrorDegrees <= (constraints?.maximumErrorDegrees ?? 180) else { return }
            if let solarRange = constraints?.solarAltitudeRange {
                let solarAltitude = body == .sun ? value.altitude :
                    try Astronomy.position(.sun, at: value.instant, coordinate: observer).altitude
                guard solarRange.contains(solarAltitude) else { return }
            }
            if let phase = constraints?.moonIlluminationRange {
                guard phase.contains(Astronomy.moonIllumination(at: value.instant)) else { return }
            }
            if better(value, than: best) { best = value }
        }
        for span in eligible {
            // Sample both interval edges and just inside each edge: crossing roots carry tiny
            // numerical error, while returned candidates must satisfy the actual constraints.
            let inset = min(0.001, span.duration / 4)
            var times = [span.start, span.start.addingTimeInterval(inset),
                         span.end.addingTimeInterval(-inset), span.end]
            var time = span.start.addingTimeInterval(min(coarseStep, 300))
            while time < span.end {
                times.append(time)
                time = time.addingTimeInterval(min(coarseStep, 300))
            }
            times.sort()
            var samples: [AlignmentCandidate] = []
            for time in times {
                if let value = try candidate(time) { samples.append(value); try consider(value) }
            }
            // Refine every local minimum, rather than only the globally best coarse sample.
            // Separate morning/evening and solar-lighting windows remain independent candidates.
            guard samples.count >= 3 else { continue }
            for index in 1..<(samples.count - 1) {
                let middle = samples[index].absoluteErrorDegrees
                guard middle <= samples[index - 1].absoluteErrorDegrees,
                      middle <= samples[index + 1].absoluteErrorDegrees else { continue }
                var low = samples[index - 1].instant, high = samples[index + 1].instant
                for _ in 0..<40 {
                    try Task.checkCancellation()
                    if high.timeIntervalSince(low) < 0.02 { break }
                    let a = low.addingTimeInterval(high.timeIntervalSince(low) / 3)
                    let b = high.addingTimeInterval(-high.timeIntervalSince(low) / 3)
                    guard let lhs = try candidate(a), let rhs = try candidate(b) else { break }
                    try consider(lhs); try consider(rhs)
                    if lhs.absoluteErrorDegrees < rhs.absoluteErrorDegrees { high = b } else { low = a }
                }
                if let value = try candidate(low.addingTimeInterval(high.timeIntervalSince(low) / 2)) {
                    try consider(value)
                }
            }
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
        limit: Int = 7,
        constraints: OpportunityConstraints? = nil
    ) throws -> [AlignmentCandidate] {
        guard (1...90).contains(days), (1...90).contains(limit) else { throw LightPlanError.invalidNumber }
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
                minimumAltitude: minimumAltitude,
                constraints: constraints
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
        let radians = Double.pi / 180
        let bearing = desiredSubjectBearing * radians, distance = distanceMeters / 6_371_000
        let subjectLatitude = subject.latitude * radians
        // Solve the forward great-circle equation for the unknown observer latitude. Simply
        // walking the opposite bearing from the subject has a different initial bearing back
        // to it, especially near a pole, and therefore does not preserve the requested framing.
        let a = cos(distance), b = sin(distance) * cos(bearing)
        let scale = hypot(a, b), ratio = sin(subjectLatitude) / scale
        guard abs(ratio) <= 1 else { throw LightPlanError.invalidNumber }
        let latitude = asin(ratio) - atan2(b, a)
        guard abs(latitude) <= Double.pi / 2 else { throw LightPlanError.invalidNumber }
        let longitudeDelta = atan2(sin(bearing) * sin(distance) * cos(latitude),
                                   cos(distance) - sin(latitude) * sin(subjectLatitude))
        let observer = try Coordinate(latitude: latitude / radians,
            longitude: Astronomy.normalize(subject.longitude - longitudeDelta / radians + 180) - 180)
        guard let actualBearing = Geometry.bearing(from: observer, to: subject),
              abs(signedDifference(target: desiredSubjectBearing, actual: actualBearing)) < 0.001 else {
            throw LightPlanError.invalidNumber
        }
        return observer
    }
}
