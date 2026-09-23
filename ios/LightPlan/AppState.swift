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
        followingToday = false; followingNow = false
        place = plan.place; selectedDate = plan.date
        await refresh()
        if let summary, let anchor = Planner.anchorDate(plan: plan, summary: summary) { selectedInstant = anchor }
        mapPlanRestore = MapPlanRestore(plan: plan)
        tab = 1
    }
    func selectDate(_ date: Date) async {
        followingToday = LocalDay.same(date, Date(), timeZone: place.timeZone)
        followingNow = false; selectedDate = date
        await refresh()
    }
    func showToday() async {
        followingToday = true; followingNow = true
        selectedDate = Date(); selectedInstant = Date()
        await refresh()
    }
    func beginComposition(template: PlanningTemplate? = nil) {
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
        try repository.write(Archive(places: places, plans: plans))
        try? protectStorage()
    }
    private func protectStorage() throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: repository.url.path)
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
    func upsert(_ plan: ShootPlan) throws {
        _ = try plan.validated()
        let before = plans
        if let i = plans.firstIndex(where: { $0.id == plan.id }) { plans[i] = plan } else { plans.append(plan) }
        do { try save() } catch { plans = before; throw error }
    }
    func add(_ plan: ShootPlan) throws { try upsert(plan) }
    func duplicate(_ plan: ShootPlan) {
        do {
            var copy = plan; copy.id = UUID(); copy.createdAt = Date(); copy.updatedAt = Date(); copy.reminderLeadMinutes = nil; copy.completedAt = nil
            try upsert(copy); noticeKey = "notice.duplicated"
        } catch { errorKey = "error.save" }
    }
    func deletePlan(_ plan: ShootPlan) async {
        let before = plans; plans.removeAll { $0.id == plan.id }
        do { try save(); await ReminderService.cancel(planID: plan.id) } catch { plans = before; errorKey = "error.save" }
    }
    func stopReminder(_ plan: ShootPlan) async {
        do { var copy = plan; copy.reminderLeadMinutes = nil; copy.updatedAt = Date(); try upsert(copy); await ReminderService.cancel(planID: copy.id) }
        catch { errorKey = "error.save" }
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
    func importArchive(_ preview: ImportPreview, policy: ImportConflictPolicy, enableReminders: Bool) async throws {
        let merged = try preview.merged(with: Archive(places: places, plans: plans), policy: policy, enableImportedReminders: enableReminders)
        // The old file is copied (even if damaged), then the new file is replaced atomically.
        try repository.write(merged, allowRecovery: archiveLocked)
        places = merged.places; plans = merged.plans; archiveLocked = false
        try? protectStorage()
        await ReminderService.reconcile(plans: plans, language: L10n.language, requestPermission: enableReminders)
        noticeKey = "notice.imported"
    }
    func exportedBytes() throws -> Data {
        try archiveLocked ? repository.originalBytes() : Archive(places: places, plans: plans).encoded()
    }
    func exportedArchive() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LightPlan-backup.json")
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
