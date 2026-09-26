import SwiftUI
import WidgetKit
import LightPlanCore

struct MapPlanRestore: Identifiable {
    let id = UUID()
    let plan: ShootPlan
}

enum PlanningTemplate { case sunset, moon }

@MainActor final class AppState: ObservableObject {
    @Published var place = Place.example
    @Published var basePlace = Place.example
    @Published var selectedDate = Date()
    @Published var selectedInstant = Date()
    @Published var summary: DaySummary?
    @Published var places: [Place] = []
    @Published var plans: [ShootPlan] = []
    @Published var tab = 0
    @Published var busy = false
    @Published var errorKey: String?
    @Published var noticeKey: String?
    @Published var archiveLocked = false
    @Published var openPlanID: UUID?
    @Published var mapPlanRestore: MapPlanRestore?
    @Published var compositionRequest: UUID?
    @Published var compositionTemplate: PlanningTemplate?
    @Published var followingToday = true
    @Published var followingNow = true
    // In-memory applied search settings survive sheets/tabs, without storing new location data.
    var planningSearchMemory = PlanningSearchMemory()
    private var calculation: Task<DaySummary, Error>?
    private var refreshID = UUID()
    private var mapRestorationID = UUID()
    private let repository: ArchiveRepository
    private(set) var isFixture = false

    init() {
        #if DEBUG
        isFixture = ProcessInfo.processInfo.environment["LIGHTPLAN_VISUAL_FIXTURE"] == "1"
        #endif
        var fixtureArchiveID: UUID?
        #if DEBUG
        if isFixture, let value = ProcessInfo.processInfo.environment["LIGHTPLAN_VISUAL_ARCHIVE"] {
            fixtureArchiveID = UUID(uuidString: value)
        }
        #endif
        let directory = isFixture ? FileManager.default.temporaryDirectory.appendingPathComponent("LightPlanVisualFixture").appendingPathComponent(fixtureArchiveID?.uuidString ?? "ephemeral") : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        repository = ArchiveRepository(url: directory.appendingPathComponent("LightPlan/archive-v1.json"))
        do {
            if !isFixture || fixtureArchiveID != nil {
                let saved = try repository.load(); places = saved.places; plans = saved.plans
            }
        } catch { archiveLocked = true; errorKey = "error.archive" }
        if !isFixture, let data = UserDefaults.standard.data(forKey: "basePlace"), let saved = try? JSONDecoder().decode(Place.self, from: data) {
            if (try? saved.validated()) != nil { basePlace = saved; place = saved }
        }
        #if DEBUG
        if isFixture {
            let env = ProcessInfo.processInfo.environment
            UserDefaults.standard.set(env["LIGHTPLAN_VISUAL_LANGUAGE"] ?? "zh-Hans", forKey: "language")
            UserDefaults.standard.set(env["LIGHTPLAN_VISUAL_THEME"] ?? "light", forKey: "appearance")
            UserDefaults.standard.set(true, forKey: "onboardingDone")
            selectedDate = Date(timeIntervalSince1970: 1_789_617_600) // deterministic UTC instant for visual tests
            selectedInstant = Date(timeIntervalSince1970: 1_789_638_590)
            if let text = env["LIGHTPLAN_VISUAL_DAY"], let date = ISO8601DateFormatter().date(from: text),
               (try? LocalDay.validate(date, timeZone: place.timeZone)) != nil {
                selectedDate = date; selectedInstant = date
            }
            followingToday = false; followingNow = false
            tab = Int(env["LIGHTPLAN_VISUAL_TAB"] ?? "0") ?? 0
            place.name = L10n.text("v3.demo.place")
            if fixtureArchiveID == nil {
                if let plan = try? ShootPlan(title: L10n.text("v3.demo.title"), place: place, date: selectedDate, target: .sunset, arrivalLeadMinutes: 45) { plans = [plan] }
                places = [place]
                // Opt-in, DEBUG-only large library for native responsiveness checks.
                // No fixture count reaches production storage or notification scheduling.
                if let raw = env["LIGHTPLAN_VISUAL_LIBRARY_COUNT"], let count = Int(raw), (1...5000).contains(count) {
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = place.timeZone
                    if let future = calendar.date(byAdding: .day, value: 365, to: Date()) {
                        plans = (0..<count).compactMap { index in
                            try? ShootPlan(title: String(format: "M5-%04d", index), place: place, date: future,
                                           target: .sunset, reminderLeadMinutes: nil, collectionName: "M5 library")
                        }
                    }
                }
            }
        }
        #endif
    }

    func refresh() async {
        calculation?.cancel()
        let id = UUID(); refreshID = id; busy = true; summary = nil
        defer {
            if id == refreshID { busy = false; calculation = nil }
        }
        let p = place, d = selectedDate
        let task = Task.detached(priority: .userInitiated) { try DayEngine.calculate(place: p, date: d) }
        calculation = task
        do {
            let value = try await task.value
            // The shared selected day outlives the initiating view/pull-to-refresh.
            // Only a newer refresh supersedes this app-owned calculation; a view
            // cancellation must not leave the current day permanently blank.
            guard id == refreshID else { return }
            summary = value
            if !(value.start..<value.end).contains(selectedInstant) {
                let now = Date()
                selectedInstant = (value.start..<value.end).contains(now) ? now : value.start.addingTimeInterval(value.end.timeIntervalSince(value.start) * 0.7)
            }
        } catch is CancellationError {
        } catch {
            if id == refreshID { errorKey = "error.calculation" }
        }
    }
    func select(_ newPlace: Place, asBase: Bool = false) async {
        invalidateMapRestoration()
        let oldZone = place.timeZone
        if !followingToday {
            do { selectedDate = try LocalDay.relocating(selectedDate, from: oldZone, to: newPlace.timeZone) }
            catch { errorKey = "error.calculation"; return }
        }
        place = newPlace
        if asBase || basePlace.isExample {
            basePlace = newPlace
            if !isFixture, let data = try? JSONEncoder().encode(newPlace) { UserDefaults.standard.set(data, forKey: "basePlace") }
        }
        if followingToday { selectedDate = Date() }
        await refresh()
    }

    /// Move the active planning observer without replacing the user's saved default location.
    /// Used by composition guidance where a suggested stand point is provisional.
    func selectPlanningPlace(_ newPlace: Place) async {
        invalidateMapRestoration()
        let oldZone = place.timeZone
        if !followingToday {
            do { selectedDate = try LocalDay.relocating(selectedDate, from: oldZone, to: newPlace.timeZone) }
            catch { errorKey = "error.calculation"; return }
        }
        place = newPlace
        if followingToday { selectedDate = Date() }
        followingNow = false
        await refresh()
    }

    /// A saved plan already owns its destination civil day; never reinterpret it in the old map zone.
    func showPlanMap(_ plan: ShootPlan) async {
        invalidateMapRestoration()
        let request = mapRestorationID
        let requestedInstant = plan.composition?.instant ?? plan.date
        followingToday = false; followingNow = false
        place = plan.place; selectedDate = plan.date; selectedInstant = requestedInstant
        await refresh()
        // A second plan, location/date change or manual scrub wins over this older request.
        guard !Task.isCancelled, request == mapRestorationID, place == plan.place,
              selectedDate == plan.date, selectedInstant == requestedInstant else { return }
        if let summary, let anchor = Planner.anchorDate(plan: plan, summary: summary) { selectedInstant = anchor }
        mapPlanRestore = MapPlanRestore(plan: plan)
        tab = 1
    }
    private func invalidateMapRestoration() {
        mapRestorationID = UUID(); mapPlanRestore = nil
    }
    func selectDate(_ date: Date) async {
        invalidateMapRestoration()
        followingToday = LocalDay.same(date, Date(), timeZone: place.timeZone)
        followingNow = false; selectedDate = date
        await refresh()
    }
    func showToday() async {
        invalidateMapRestoration()
        followingToday = true; followingNow = true
        selectedDate = Date(); selectedInstant = Date()
        await refresh()
    }
    func beginComposition(template: PlanningTemplate? = nil) {
        invalidateMapRestoration()
        compositionTemplate = template
        compositionRequest = UUID()
        tab = 1
    }
    func tick() async {
        guard !isFixture else { return }
        if followingToday, !LocalDay.same(selectedDate, Date(), timeZone: place.timeZone) {
            selectedDate = Date(); selectedInstant = Date(); await refresh()
        } else if followingNow, let summary, (summary.start..<summary.end).contains(Date()) {
            selectedInstant = Date()
        }
    }
    func save() throws {
        guard !archiveLocked else { throw LightPlanError.storageLocked }
        try persist(Archive(places: places, plans: plans))
    }
    private func persist(_ archive: Archive, allowRecovery: Bool = false) throws {
        do {
            let verified = try repository.write(archive, allowRecovery: allowRecovery)
            // Only publish bytes that have been read back and validated.
            places = verified.places; plans = verified.plans
        } catch ArchiveRepositoryError.rollbackFailed {
            archiveLocked = true
            throw ArchiveRepositoryError.rollbackFailed
        }
    }
    func applyPlanMutation(_ mutation: PlanMutation) throws {
        guard !archiveLocked else { throw LightPlanError.storageLocked }
        try persist(mutation.applying(to: Archive(places: places, plans: plans)))
    }
    @discardableResult
    func reconcileReminders(requestPermission: Bool = false) async -> ReminderReconciliationResult? {
        // Corrupt or temporarily protected storage is not an authoritative empty library.
        guard !archiveLocked else { return nil }
        let snapshot = plans
        return await ReminderService.reconcile(plans: snapshot, language: L10n.language,
            requestPermission: requestPermission, isCurrent: { [weak self] in
                await self?.matchesReminderSnapshot(snapshot) ?? false
            })
    }
    func scheduleReminder(for plan: ShootPlan, summary: DaySummary) async throws -> ReminderResult {
        try await ReminderService.schedule(plan: plan, summary: summary, language: L10n.language,
            isCurrent: { [weak self] in
                await self?.matchesReminderPlan(plan) ?? false
            })
    }
    /// A queued stop/delete must not cancel a newer saved-and-enabled reminder.
    func cancelSavedReminder(planID: UUID) async {
        let expected = plans.first(where: { $0.id == planID })
        guard !archiveLocked,
              expected == nil || expected?.reminderLeadMinutes == nil || expected?.completedAt != nil else { return }
        await ReminderService.cancel(planID: planID, isCurrent: { [weak self] in
            await self?.matchesReminderCancellation(planID, expected: expected) ?? false
        })
    }
    private func matchesReminderCancellation(_ id: UUID, expected: ShootPlan?) -> Bool {
        !archiveLocked && plans.first(where: { $0.id == id }) == expected
    }
    private func matchesReminderSnapshot(_ snapshot: [ShootPlan]) -> Bool { !archiveLocked && plans == snapshot }
    private func matchesReminderPlan(_ plan: ShootPlan) -> Bool {
        !archiveLocked && plans.first(where: { $0.id == plan.id }) == plan
    }
    func favorite() {
        guard !places.contains(where: { $0.coordinate == place.coordinate && $0.timeZoneID == place.timeZoneID }) else { noticeKey = "notice.duplicatePlace"; return }
        let before = places
        // A saved place is a snapshot; deleting or renaming it cannot mutate existing plans.
        var favorite = place
        if places.contains(where: { $0.id == favorite.id }) { favorite.id = UUID() }
        places.append(favorite)
        do { try save(); noticeKey = "notice.saved" } catch { places = before; errorKey = "error.save" }
    }
    func upsert(_ plan: ShootPlan, replacing expected: ShootPlan? = nil) throws {
        try applyPlanMutation(expected.map { .replace(expected: $0, updated: plan) } ?? .insert(plan))
    }
    func add(_ plan: ShootPlan) throws { try upsert(plan) }
    func duplicate(_ plan: ShootPlan) {
        do {
            try applyPlanMutation(.duplicate(plan.id, newID: UUID(), now: Date()))
            noticeKey = "notice.duplicated"
        } catch { errorKey = "error.save" }
    }
    @discardableResult
    func deletePlan(_ plan: ShootPlan) async -> Bool {
        do {
            try applyPlanMutation(.remove(plan.id))
            await cancelSavedReminder(planID: plan.id)
            // Refill a freed reminder slot from the current saved library.
            await reconcileReminders()
            return true
        } catch { errorKey = "error.save"; return false }
    }
    func stopReminder(_ plan: ShootPlan) async {
        do {
            try applyPlanMutation(.disableReminder(plan.id, now: Date()))
            await cancelSavedReminder(planID: plan.id)
            await reconcileReminders()
        } catch { errorKey = "error.save" }
    }
    func deletePlace(_ id: UUID) {
        let before = places; places.removeAll { $0.id == id }
        do { try save() } catch { places = before; errorKey = "error.save" }
    }
    func renamePlace(_ id: UUID, name: String) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        let before = places; places[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do { _ = try places[i].validated(); try save() } catch { places = before; errorKey = "error.save" }
    }
    func movePlaces(from: IndexSet, to: Int) {
        let before = places; places.move(fromOffsets: from, toOffset: to)
        do { try save() } catch { places = before; errorKey = "error.save" }
    }
    func previewImport(_ data: Data) throws -> ImportPreview {
        try ImportPreview(local: Archive(places: places, plans: plans), incoming: Archive.decode(data))
    }
    func previewImportFile(_ url: URL) async throws -> ImportPreview {
        let snapshot = Archive(places: places, plans: plans)
        let worker = Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            return try ImportPreview(local: snapshot, incoming: Archive.decode(ArchiveFileReader.read(url)))
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
    func importArchive(_ preview: ImportPreview, policy: ImportConflictPolicy, enableReminders: Bool) async throws {
        let merged = try preview.merged(with: Archive(places: places, plans: plans), policy: policy, enableImportedReminders: enableReminders)
        // The old file is copied (even if damaged), then the new file is replaced atomically.
        try persist(merged, allowRecovery: archiveLocked)
        archiveLocked = false
        let result = await reconcileReminders(requestPermission: enableReminders)
        noticeKey = result?.needsAttention == true && plans.contains(where: { $0.completedAt == nil && $0.reminderLeadMinutes != nil })
            ? "backup.importedReminderWarning" : "notice.imported"
    }
    func exportedBytes() throws -> Data {
        try archiveLocked ? repository.originalBytes() : Archive(places: places, plans: plans).encoded()
    }
    func exportedArchive() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LightPlan-backup-\(UUID().uuidString).json")
        try exportedBytes().write(to: url, options: .atomic); return url
    }
    func publishWidget() {
        guard let suite = AppConfiguration.sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(place) { suite.set(data, forKey: "widgetPlace") }
        else { suite.removeObject(forKey: "widgetPlace") }
        suite.set(L10n.language, forKey: "widgetLanguage")
        suite.set(UserDefaults.standard.string(forKey: "clockFormat") ?? "system", forKey: "widgetClock")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
