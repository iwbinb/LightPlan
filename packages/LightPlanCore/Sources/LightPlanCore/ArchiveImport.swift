import Foundation

public enum ImportConflictPolicy: String, CaseIterable, Sendable { case keepLocal, useIncoming }
public struct ImportPreview: Sendable {
    public let incoming: Archive
    public let newPlaces: Int
    public let newPlans: Int
    public let conflictingPlaces: Int
    public let conflictingPlans: Int
    public let identicalItems: Int

    public init(local: Archive, incoming: Archive) throws {
        // Archives store timestamps at whole-second precision. Compare the persisted
        // representations so exporting and reimporting an unchanged plan is not a conflict.
        let local = try Archive.decode(local.encoded())
        let incoming = try Archive.decode(incoming.encoded())
        let places = Dictionary(uniqueKeysWithValues: local.places.map { ($0.id, $0) })
        let plans = Dictionary(uniqueKeysWithValues: local.plans.map { ($0.id, $0) })
        self.incoming = incoming
        newPlaces = incoming.places.filter { places[$0.id] == nil }.count
        newPlans = incoming.plans.filter { plans[$0.id] == nil }.count
        conflictingPlaces = incoming.places.filter { places[$0.id] != nil && places[$0.id] != $0 }.count
        conflictingPlans = incoming.plans.filter { plans[$0.id] != nil && plans[$0.id] != $0 }.count
        identicalItems = incoming.places.filter { places[$0.id] == $0 }.count + incoming.plans.filter { plans[$0.id] == $0 }.count
    }
    public func merged(with local: Archive, policy: ImportConflictPolicy, enableImportedReminders: Bool = false) throws -> Archive {
        let local = try Archive.decode(local.encoded())
        var places = local.places, plans = local.plans
        var placeIndices = Dictionary(uniqueKeysWithValues: places.enumerated().map { ($0.element.id, $0.offset) })
        var planIndices = Dictionary(uniqueKeysWithValues: plans.enumerated().map { ($0.element.id, $0.offset) })
        for place in incoming.places {
            if let index = placeIndices[place.id] {
                if policy == .useIncoming { places[index] = place }
            } else { placeIndices[place.id] = places.count; places.append(place) }
        }
        for original in incoming.plans {
            var plan = original
            // Imported reminders never silently activate. This policy is shown in the preview.
            if !enableImportedReminders { plan.reminderLeadMinutes = nil }
            if let index = planIndices[plan.id] {
                if plans[index] == original { continue }
                if policy == .useIncoming { plans[index] = plan }
            } else { planIndices[plan.id] = plans.count; plans.append(plan) }
        }
        let result = Archive(places: places, plans: plans)
        _ = try result.encoded() // Enforce aggregate byte/item limits before committing any change.
        return result
    }
}

/// Atomic, fail-closed repository. No implicit reset on corruption and no destructive migrations.
/// A write is preceded by a durable copy of the previous bytes, including corrupt originals.
public struct ArchiveRepository: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Archive {
        guard FileManager.default.fileExists(atPath: url.path) else { return Archive(places: [], plans: []) }
        return try Archive.decode(Data(contentsOf: url, options: .mappedIfSafe))
    }
    public func write(_ archive: Archive, allowRecovery: Bool = false) throws {
        let data = try archive.encoded()
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let old = try Data(contentsOf: url)
            if !allowRecovery { _ = try Archive.decode(old) }
            if let legacy = try? Archive.decode(old), legacy.schemaVersion < Archive.currentSchemaVersion {
                let migrationBackup = url.deletingLastPathComponent()
                    .appendingPathComponent("archive-schema-\(legacy.schemaVersion)-\(UUID().uuidString).json")
                try old.write(to: migrationBackup, options: .atomic)
            }
            let backup = url.deletingLastPathComponent().appendingPathComponent(allowRecovery ? "recovered-\(UUID().uuidString).json" : "archive-previous.json")
            try old.write(to: backup, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
    public func originalBytes() throws -> Data { try Data(contentsOf: url) }
}
