import Foundation

public enum PlanLibraryFilter: String, CaseIterable, Sendable {
    case all, upcoming, completed, past
}

public struct PlanLibraryEntry: Identifiable, Sendable {
    public var id: UUID { plan.id }
    public let plan: ShootPlan
    public let destinationDay: DateInterval
    /// Always exact for composition plans; resolved for ordinary plans on the current destination day.
    public let anchor: Date?
    public let isPast: Bool
    public let hasNoEventToday: Bool
    /// Today's ordinary plan has not had its event calculated yet. Unknown is
    /// distinct from an absent event, a past event and a future event.
    public let needsTimeResolution: Bool

    public var collectionName: String? {
        let trimmed = plan.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct PlanLibraryGroup: Identifiable, Sendable {
    public var id: String { name.map { "collection:" + $0 } ?? "unfiled" }
    public let name: String?
    public let entries: [PlanLibraryEntry]
}

/// Destination civil days determine day boundaries. Only ordinary plans for the
/// current destination day need astronomy to distinguish an upcoming event from
/// one that has passed. Historical/future archives therefore remain inexpensive.
public enum PlanLibrary {
    public static func entries(plans: [ShootPlan], now: Date, resolveToday: Bool = true) throws -> [PlanLibraryEntry] {
        guard now.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        guard plans.count <= 10_000 else { throw LightPlanError.tooManyItems }
        var cache = PlanLibraryTimeCache(capacity: 10_000)
        return try plans.map { plan in
            try Task.checkCancellation()
            _ = try plan.validated()
            let day = try LocalDay.interval(containing: plan.date, timeZone: plan.place.timeZone)
            return try cache.entry(plan: plan, day: day, now: now, allowCalculation: resolveToday)
        }
    }

    public static func filtered(_ entries: [PlanLibraryEntry], query: String = "",
                                filter: PlanLibraryFilter = .all, locale: Locale = .current) -> [PlanLibraryEntry] {
        filtered(entries, query: query, filter: filter, locale: locale, checkpoint: {})
    }

    /// The synchronous API retains its original semantics. This implementation also
    /// accepts a cooperative checkpoint for off-main, latest-request-only UI work.
    static func filtered(_ entries: [PlanLibraryEntry], query: String,
                         filter: PlanLibraryFilter, locale: Locale,
                         checkpoint: () throws -> Void) rethrows -> [PlanLibraryEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        struct SortRow {
            let entry: PlanLibraryEntry
            let category: Int
            let date: Date
            let completed: Date
            let targetRank: Int
            let identifier: String
        }
        let ranks: [PlanTarget: Int] = [.goldenMorning: 0, .sunrise: 1, .goldenEvening: 2,
                                       .sunset: 3, .blueEvening: 4, .composition: 5]
        var rows: [SortRow] = []
        rows.reserveCapacity(entries.count)
        for entry in entries {
            try checkpoint()
            let completed = entry.plan.completedAt != nil
            let matchesStatus: Bool
            switch filter {
            case .all: matchesStatus = true
            case .upcoming: matchesStatus = !completed && !entry.needsTimeResolution && !entry.isPast && !entry.hasNoEventToday
            case .completed: matchesStatus = completed
            case .past: matchesStatus = !completed && !entry.needsTimeResolution && entry.isPast
            }
            guard matchesStatus else { continue }
            // Empty searches don't allocate/rebuild a haystack for every plan.
            if !words.isEmpty {
                let haystack = [entry.plan.title, entry.plan.place.name, entry.plan.notes ?? "", entry.collectionName ?? ""].joined(separator: " ")
                guard words.allSatisfy({ haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil }) else { continue }
            }
            // Expensive UUID conversion and sort-key construction happen once per
            // row rather than on both sides of every comparison. Ordering is unchanged.
            rows.append(SortRow(entry: entry, category: completed ? 2 : (entry.isPast ? 1 : 0),
                date: entry.anchor ?? entry.destinationDay.start, completed: entry.plan.completedAt ?? .distantPast,
                targetRank: ranks[entry.plan.target] ?? 0, identifier: entry.id.uuidString))
        }
        try rows.sort { lhs, rhs in
            try checkpoint()
            if filter == .completed, lhs.completed != rhs.completed { return lhs.completed > rhs.completed }
            if filter == .all, lhs.category != rhs.category { return lhs.category < rhs.category }
            if lhs.date != rhs.date { return filter == .past ? lhs.date > rhs.date : lhs.date < rhs.date }
            if lhs.targetRank != rhs.targetRank { return lhs.targetRank < rhs.targetRank }
            return lhs.identifier < rhs.identifier
        }
        return rows.map(\.entry)
    }

    /// Filtering, sorting and grouping run outside the caller's actor. Cancellation
    /// reaches the worker and no partial/stale groups are published by this API.
    public static func groupsAsync(_ entries: [PlanLibraryEntry], query: String = "",
                                   filter: PlanLibraryFilter = .all,
                                   locale: Locale = .current) async throws -> [PlanLibraryGroup] {
        guard entries.count <= 10_000 else { throw LightPlanError.tooManyItems }
        return try await CompositionPlanner.runCancellable {
            let result = try filtered(entries, query: query, filter: filter, locale: locale,
                                      checkpoint: { try Task.checkCancellation() })
            return try groups(result, checkpoint: { try Task.checkCancellation() })
        }
    }

    public static func groups(_ entries: [PlanLibraryEntry]) -> [PlanLibraryGroup] {
        groups(entries, checkpoint: {})
    }

    static func groups(_ entries: [PlanLibraryEntry], checkpoint: () throws -> Void) rethrows -> [PlanLibraryGroup] {
        var order: [String?] = [], grouped: [String: [PlanLibraryEntry]] = [:]
        for entry in entries {
            try checkpoint()
            let name = entry.collectionName
            let key = name.map { "collection:" + $0 } ?? "unfiled"
            if grouped[key] == nil { order.append(name) }
            grouped[key, default: []].append(entry)
        }
        // Preserve the chronological/status ordering established by `filtered`;
        // a project's first relevant plan determines its position in the library.
        return order.map { name in
            PlanLibraryGroup(name: name, entries: grouped[name.map { "collection:" + $0 } ?? "unfiled"] ?? [])
        }
    }
}

/// Retained by the plan-library view between minute ticks and list mutations.
/// It stores only event anchors/no-event results, not full astronomy tracks. The
/// bounded FIFO cache can hold the archive's 10,000 distinct place/day keys.
public actor PlanLibraryTimeResolver {
    private var cache: PlanLibraryTimeCache

    public init(capacity: Int = 10_000) {
        cache = PlanLibraryTimeCache(capacity: capacity)
    }

    /// Publish all plans without calculating any missing day. Cached answers are
    /// applied immediately; otherwise today's ordinary plans explicitly remain unknown.
    public func prepare(plans: [ShootPlan], now: Date) throws -> [PlanLibraryEntry] {
        let values = try PlanLibrary.entries(plans: plans, now: now, resolveToday: false)
        return try values.map {
            try Task.checkCancellation()
            return try cache.entry(plan: $0.plan, day: $0.destinationDay, now: now, allowCalculation: false)
        }
    }

    /// The caller sends small batches so results can be displayed incrementally.
    /// Cooperative checks also stop a cancelled request inside DayEngine sampling.
    public func resolve(_ entries: [PlanLibraryEntry], now: Date) throws -> [PlanLibraryEntry] {
        guard now.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        guard entries.count <= 128 else { throw LightPlanError.tooManyItems }
        return try entries.map {
            try Task.checkCancellation()
            return try cache.entry(plan: $0.plan, day: $0.destinationDay, now: now, allowCalculation: true)
        }
    }

    // Independent tests assert that refreshes/target changes really hit the cache.
    var calculationCount: Int { cache.calculationCount }
    var cachedDayCount: Int { cache.days.count }
}

private struct PlanLibraryTimeCache: Sendable {
    struct Key: Hashable, Sendable {
        let coordinate: Coordinate
        let timeZoneID: String
        let start: Date
    }
    let capacity: Int
    // Presence of a day with no entry for a target explicitly means no event.
    var days: [Key: [PlanTarget: Date]] = [:]
    private var order: [Key] = []
    private var nextEviction = 0
    private(set) var calculationCount = 0

    init(capacity: Int) { self.capacity = min(10_000, max(1, capacity)) }

    mutating func entry(plan: ShootPlan, day: DateInterval, now: Date,
                        allowCalculation: Bool) throws -> PlanLibraryEntry {
        let today = (day.start..<day.end).contains(now)
        var anchor = plan.composition?.instant
        var noEvent = false, pending = false
        if plan.composition == nil, today {
            let key = Key(coordinate: plan.place.coordinate, timeZoneID: plan.place.timeZoneID, start: day.start)
            if days[key] == nil, allowCalculation {
                try Task.checkCancellation()
                let summary = try DayEngine.calculate(place: plan.place, date: plan.date)
                try Task.checkCancellation()
                var targets: [PlanTarget: Date] = [:]
                for target in PlanTarget.solarTargets {
                    if let kind = Planner.anchorKind(target), let event = summary.first(kind) { targets[target] = event.date }
                }
                if order.count < capacity { order.append(key) }
                else {
                    days.removeValue(forKey: order[nextEviction])
                    order[nextEviction] = key
                    nextEviction = (nextEviction + 1) % capacity
                }
                days[key] = targets
                calculationCount += 1
            }
            if let targets = days[key] { anchor = targets[plan.target]; noEvent = anchor == nil }
            else { pending = true }
        }
        return PlanLibraryEntry(plan: plan, destinationDay: day, anchor: anchor,
            isPast: anchor.map { $0 <= now } ?? (day.end <= now), hasNoEventToday: noEvent,
            needsTimeResolution: pending)
    }
}
