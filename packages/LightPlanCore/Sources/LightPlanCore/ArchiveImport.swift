import Foundation

public enum ImportConflictPolicy: String, CaseIterable, Sendable { case keepLocal, useIncoming, keepBoth }
public enum ImportPreviewError: Error, Equatable, Sendable { case staleLocalData }

public struct ImportPreview: Sendable {
    private let reviewedLocal: Archive
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
        self.reviewedLocal = local
        newPlaces = incoming.places.filter { places[$0.id] == nil }.count
        newPlans = incoming.plans.filter { plans[$0.id] == nil }.count
        conflictingPlaces = incoming.places.filter { places[$0.id] != nil && places[$0.id] != $0 }.count
        conflictingPlans = incoming.plans.filter { plans[$0.id] != nil && plans[$0.id] != $0 }.count
        identicalItems = incoming.places.filter { places[$0.id] == $0 }.count + incoming.plans.filter { plans[$0.id] == $0 }.count
    }
    public func merged(with local: Archive, policy: ImportConflictPolicy, enableImportedReminders: Bool = false) throws -> Archive {
        let local = try Archive.decode(local.encoded())
        guard local == reviewedLocal else { throw ImportPreviewError.staleLocalData }
        var places = local.places, plans = local.plans
        var placeIndices = Dictionary(uniqueKeysWithValues: places.enumerated().map { ($0.element.id, $0.offset) })
        var planIndices = Dictionary(uniqueKeysWithValues: plans.enumerated().map { ($0.element.id, $0.offset) })
        for place in incoming.places {
            if let index = placeIndices[place.id] {
                if policy == .useIncoming { places[index] = place }
                else if policy == .keepBoth, places[index] != place {
                    var copy = place
                    repeat { copy.id = UUID() } while placeIndices[copy.id] != nil
                    placeIndices[copy.id] = places.count; places.append(copy)
                }
            } else { placeIndices[place.id] = places.count; places.append(place) }
        }
        for original in incoming.plans {
            var plan = original
            // Imported reminders never silently activate. This policy is shown in the preview.
            if !enableImportedReminders { plan.reminderLeadMinutes = nil }
            if let index = planIndices[plan.id] {
                if plans[index] == original { continue }
                if policy == .useIncoming { plans[index] = plan }
                else if policy == .keepBoth {
                    repeat { plan.id = UUID() } while planIndices[plan.id] != nil
                    // An imported conflict copy must never create a duplicate reminder.
                    plan.reminderLeadMinutes = nil
                    planIndices[plan.id] = plans.count; plans.append(plan)
                }
            } else { planIndices[plan.id] = plans.count; plans.append(plan) }
        }
        let result = Archive(places: places, plans: plans)
        _ = try result.encoded() // Enforce aggregate byte/item limits before committing any change.
        return result
    }
}
