import Foundation

/// Built alongside the Foundation core by benchmark_core.sh; never part of the iOS app.
/// Fixed fixtures and complete result fingerprints make before/after runs comparable.
@main enum CoreBenchmark {
    struct Measurement: Encodable {
        let name: String
        let milliseconds: [Double]
        let medianMilliseconds: Double
        let p95Milliseconds: Double
        let fingerprint: [String]
    }
    struct Report: Encodable {
        let schemaVersion = 1
        let scope = "Release Foundation microbenchmark, not device launch/frame/energy acceptance"
        let measurements: [Measurement]
    }
    static func measure(_ name: String, iterations: Int, operation: () throws -> [String]) throws -> Measurement {
        // Warm up code/data paths without including compilation in the timings.
        let expected = try operation()
        var times: [Double] = []
        for _ in 0..<iterations {
            let start = ContinuousClock.now
            let actual = try operation()
            let duration = start.duration(to: .now).components
            guard actual == expected else { throw LightPlanError.invalidNumber }
            times.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
        }
        FileHandle.standardError.write(Data("Measured \(name): \(times) ms\n".utf8))
        let sorted = times.sorted()
        return Measurement(name: name, milliseconds: times, medianMilliseconds: sorted[sorted.count / 2],
            p95Milliseconds: sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)], fingerprint: expected)
    }
    static func bits(_ values: Double...) -> String { values.map { String($0.bitPattern, radix: 16) }.joined(separator: ":") }
    static func main() throws {
        let iterations = min(20, max(1, Int(CommandLine.arguments.dropFirst().first ?? "5") ?? 5))
        let date = Date(timeIntervalSince1970: 1789632000) // fixed absolute instant, not a local-day increment
        let place = try Place(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Benchmark coast",
            coordinate: Coordinate(latitude: 24.4478, longitude: 118.0679), timeZoneID: "Asia/Shanghai")
        let subject = try Coordinate(latitude: 24.449, longitude: 118.078)
        var results: [Measurement] = []
        for body in [CelestialBody.sun, .moon] {
            let constraints = try OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...20,
                solarAltitudeRange: body == .moon ? -18...6 : nil,
                moonIlluminationRange: body == .moon ? 0.8...1 : nil)
            results.append(try measure("\(body.rawValue)-90-days", iterations: iterations) {
                let result = try CompositionPlanner.opportunityWindows(body: body, place: place, subject: subject,
                    starting: date, days: 90, limit: 60, constraints: constraints)
                return [String(result.dayCount), String(result.isTruncated)] + result.windows.map {
                    bits($0.interval.start.timeIntervalSince1970, $0.interval.end.timeIntervalSince1970,
                         $0.best.instant.timeIntervalSince1970, $0.best.altitude, $0.best.absoluteErrorDegrees, $0.moonIllumination)
                }
            })
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = place.timeZone
        var plans: [ShootPlan] = []
        for index in 0..<5000 {
            guard let day = calendar.date(byAdding: .day, value: 1 + index % 90, to: date),
                  let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 2)) else {
                throw LightPlanError.invalidDate
            }
            plans.append(try ShootPlan(id: id, title: "Coast \(index)", place: place, date: day, target: .sunset,
                reminderLeadMinutes: nil, now: date, notes: index % 2 == 0 ? "Café harbor coast" : "Mountain scouting",
                collectionName: "Project \(index % 20)"))
        }
        let entries = try PlanLibrary.entries(plans: plans, now: date, resolveToday: false)
        for query in ["", "cafe harbor"] {
            results.append(try measure(query.isEmpty ? "library-5000-all" : "library-5000-query", iterations: iterations) {
                let values = PlanLibrary.groups(PlanLibrary.filtered(entries, query: query, locale: Locale(identifier: "en")))
                return values.map { ($0.name ?? "") + ":" + $0.entries.map { $0.id.uuidString }.joined(separator: ",") }
            })
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(Report(measurements: results)))
        FileHandle.standardOutput.write(Data([10]))
    }
}
