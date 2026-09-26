import Foundation

/// One continuous period satisfying the selected geometric conditions, contained in a
/// single destination civil day. Boundaries use numerical root refinement; they do not
/// promise actual visibility through terrain, buildings, atmosphere or clouds.
public struct OpportunityWindow: Identifiable, Sendable {
    public let interval: DateInterval
    public let best: AlignmentCandidate
    /// The illuminated fraction of the Moon at `best.instant`, including for Sun searches.
    public let moonIllumination: Double

    public var id: String {
        best.body.rawValue + ":" + String(interval.start.timeIntervalSince1970) + ":" +
            String(interval.end.timeIntervalSince1970)
    }
}

public struct OpportunityWindowSearchResult: Sendable {
    public let windows: [OpportunityWindow]
    /// Actual destination civil days examined, including days with no matching window.
    public let dayCount: Int
    /// The full days examined. `end` is the exclusive end of the last searched day.
    public let interval: DateInterval
    /// True when more matching windows exist than the caller's output limit.
    public let isTruncated: Bool
}

extension CompositionPlanner {
    public static func opportunityWindowsAsync(
        body: CelestialBody, place: Place, subject: Coordinate, starting startDate: Date,
        days: Int = 14, desiredOffsetDegrees: Double = 0, limit: Int = 30,
        constraints: OpportunityConstraints
    ) async throws -> OpportunityWindowSearchResult {
        try await runCancellable {
            try opportunityWindows(body: body, place: place, subject: subject, starting: startDate,
                days: days, desiredOffsetDegrees: desiredOffsetDegrees, limit: limit, constraints: constraints)
        }
    }

    /// Searches up to 90 destination calendar days, retaining every separate eligible span
    /// before optimizing inside it. Results are ranked by best alignment, then start time.
    /// The returned range/day count may be shorter at the supported year-2100 boundary.
    /// An equality-only condition has no positive duration and returns no shooting window.
    public static func opportunityWindows(
        body: CelestialBody, place: Place, subject: Coordinate, starting startDate: Date,
        days: Int = 14, desiredOffsetDegrees: Double = 0, limit: Int = 30,
        constraints: OpportunityConstraints
    ) throws -> OpportunityWindowSearchResult {
        guard (1...90).contains(days), (1...360).contains(limit), desiredOffsetDegrees.isFinite,
              (-90...90).contains(desiredOffsetDegrees),
              Geometry.bearing(from: place.coordinate, to: subject) != nil else {
            throw LightPlanError.invalidNumber
        }
        _ = try constraints.validated()
        try LocalDay.validate(startDate, timeZone: place.timeZone)
        try Task.checkCancellation()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        var date = startDate
        var end = try LocalDay.interval(containing: startDate, timeZone: place.timeZone).end
        let start = try LocalDay.interval(containing: startDate, timeZone: place.timeZone).start
        var dayCount = 0
        var values: [OpportunityWindow] = []
        for _ in 0..<days {
            try Task.checkCancellation()
            do { try LocalDay.validate(date, timeZone: place.timeZone) }
            catch LightPlanError.invalidDate { break }
            let day = try LocalDay.interval(containing: date, timeZone: place.timeZone)
            var cache = SearchSkyCache(coordinate: place.coordinate)
            // The full solar ephemeris dominates Sun searches; the cheaper lunar
            // path did not benefit in benchmarks, so it retains direct evaluation.
            let position: ((CelestialBody, Date) throws -> SkyPosition)? = body == .sun ? { body, instant in
                try cache.position(body, at: instant)
            } : nil
            let lighting = try OpportunitySearch.intervals(body: body, observer: place.coordinate,
                interval: day, altitudeRange: constraints.altitudeRange,
                solarAltitudeRange: constraints.solarAltitudeRange,
                moonIlluminationRange: constraints.moonIlluminationRange, step: 300, position: position)
            if !lighting.isEmpty {
                let alignment = try OpportunitySearch.alignmentIntervals(body: body,
                    observer: place.coordinate, subject: subject, interval: day,
                    desiredOffsetDegrees: desiredOffsetDegrees,
                    maximumErrorDegrees: constraints.maximumErrorDegrees, step: 300, position: position)
                for span in try OpportunitySearch.intersect(lighting, alignment) {
                    try Task.checkCancellation()
                    guard let best = try bestAlignment(body: body, observer: place.coordinate,
                        subject: subject, interval: span, desiredOffsetDegrees: desiredOffsetDegrees,
                        constraints: constraints) else { continue }
                    values.append(OpportunityWindow(interval: span, best: best,
                        moonIllumination: Astronomy.moonIllumination(at: best.instant)))
                }
            }
            dayCount += 1
            end = day.end
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        try Task.checkCancellation()
        values.sort {
            if abs($0.best.absoluteErrorDegrees - $1.best.absoluteErrorDegrees) > 1e-9 {
                return $0.best.absoluteErrorDegrees < $1.best.absoluteErrorDegrees
            }
            return $0.interval.start < $1.interval.start
        }
        return OpportunityWindowSearchResult(windows: Array(values.prefix(limit)), dayCount: dayCount,
            interval: DateInterval(start: start, end: end), isTruncated: values.count > limit)
    }
}
