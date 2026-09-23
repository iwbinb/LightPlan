import Foundation

/// Numerical sampling shared by event and opportunity searches. This only resolves
/// extrema of the supplied smooth function; it does not improve the ephemeris model.
enum SearchSampling {
    typealias Sample = (date: Date, value: Double)

    static func checkedValue(at date: Date, using value: (Date) throws -> Double) throws -> Double {
        try Task.checkCancellation()
        let result = try value(date)
        guard result.isFinite else { throw LightPlanError.invalidNumber }
        return result
    }

    static func validate(interval: DateInterval, step: TimeInterval) throws {
        guard interval.start.timeIntervalSince1970.isFinite,
              interval.end.timeIntervalSince1970.isFinite,
              interval.duration.isFinite, interval.duration > 0 else {
            throw LightPlanError.invalidDate
        }
        guard step.isFinite, step > 0,
              interval.start.addingTimeInterval(step) > interval.start else {
            throw LightPlanError.invalidNumber
        }
        try Task.checkCancellation()
    }

    /// Includes both endpoints and refines extrema inside the first/last cells,
    /// where a three-sample local-extremum detector has no outside neighbour.
    /// All evaluations remain inside the requested interval.
    static func samples(in interval: DateInterval, step: TimeInterval,
                        tolerance: TimeInterval, iterations: Int,
                        value: (Date) throws -> Double) throws -> [Sample] {
        try validate(interval: interval, step: step)
        guard tolerance.isFinite, tolerance > 0, (1...128).contains(iterations) else {
            throw LightPlanError.invalidNumber
        }
        var base: [Sample] = []
        var time = interval.start
        while time < interval.end {
            base.append((time, try checkedValue(at: time, using: value)))
            let next = min(interval.end, time.addingTimeInterval(step))
            guard next > time else { throw LightPlanError.invalidNumber }
            time = next
        }
        base.append((interval.end, try checkedValue(at: interval.end, using: value)))

        var cells: [(start: Date, end: Date, maximum: Bool)] = []
        if base.count >= 3 {
            for index in 1..<(base.count - 1) {
                let left = base[index - 1].value
                let middle = base[index].value
                let right = base[index + 1].value
                if middle >= left && middle >= right && (middle > left || middle > right) {
                    cells.append((base[index - 1].date, base[index + 1].date, true))
                }
                if middle <= left && middle <= right && (middle < left || middle < right) {
                    cells.append((base[index - 1].date, base[index + 1].date, false))
                }
            }
        }
        // Use the actual final grid cell, not end-step when the last cell is short.
        if base.count >= 2 {
            cells.append((base[0].date, base[1].date, true))
            cells.append((base[0].date, base[1].date, false))
            if base.count > 2 {
                cells.append((base[base.count - 2].date, base[base.count - 1].date, true))
                cells.append((base[base.count - 2].date, base[base.count - 1].date, false))
            }
        }

        var result = base
        for cell in cells {
            var low = cell.start, high = cell.end
            for _ in 0..<iterations {
                try Task.checkCancellation()
                let width = high.timeIntervalSince(low)
                if width < tolerance { break }
                let a = low.addingTimeInterval(width / 3)
                let b = high.addingTimeInterval(-width / 3)
                // Date's representable spacing can exceed the numerical tolerance.
                if a <= low || b >= high || a >= b { break }
                let fa = try checkedValue(at: a, using: value)
                let fb = try checkedValue(at: b, using: value)
                if (fa < fb) == cell.maximum { low = a } else { high = b }
            }
            let extremum = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            result.append((extremum, try checkedValue(at: extremum, using: value)))
        }
        result.sort { $0.date < $1.date }
        var unique: [Sample] = []
        for sample in result where unique.last?.date != sample.date { unique.append(sample) }
        return unique
    }
}
