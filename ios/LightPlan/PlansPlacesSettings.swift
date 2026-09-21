import SwiftUI
import MapKit
import UserNotifications
import UniformTypeIdentifiers
import LightPlanCore

struct PlanEditorView: View {
    var planToEdit: ShootPlan? = nil
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var planDate = Date()
    @State private var target: PlanTarget = .sunset
    @State private var arrival = 30
    @State private var reminder = 30
    @State private var notifications = true
    @State private var initialized = false
    @State private var busy = false
    @State private var errorKey: String?
    @State private var day: DaySummary?
    private var place: Place { planToEdit?.place ?? state.place }
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = place.timeZone; return value }
    var body: some View {
        Form {
            Section {
                TextField(L10n.text("plan.title"), text: $title).accessibilityIdentifier("plan-title")
                    .onChange(of: title) { _, value in if value.count > 100 { title = String(value.prefix(100)) } }
                Label(place.name, systemImage: "mappin")
                DatePicker(L10n.text("map.date"), selection: $planDate, in: LocalDay.supportedRange(timeZone: place.timeZone), displayedComponents: .date)
                    .environment(\.timeZone, place.timeZone).environment(\.calendar, calendar)
                Text(place.timeZoneID).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker(L10n.text("plan.target"), selection: $target) { ForEach(PlanTarget.allCases, id: \.self) { Text(L10n.text("target." + $0.rawValue)).tag($0) } }
                Stepper(value: $arrival, in: 0...240, step: 5) { Text(L10n.text("plan.arrivalLead") + " " + L10n.number(Double(arrival)) + " " + L10n.text("unit.minutes")) }
                Toggle(L10n.text("plan.remind"), isOn: $notifications)
                if notifications {
                    Stepper(value: $reminder, in: 0...1440, step: 5) { Text(L10n.text("plan.reminderLead") + " " + L10n.number(Double(reminder)) + " " + L10n.text("unit.minutes")) }
                }
                KeyText("plan.arrivalNote").font(.footnote)
            }
            Section(L10n.text("plan.preview")) {
                if let day {
                    if let event = day.first(Planner.anchorKind(target)) {
                        Label(L10n.time(event.date.addingTimeInterval(-Double(arrival) * 60), zone: place.timeZone), systemImage: "figure.walk")
                        Label(L10n.time(event.date, zone: place.timeZone), systemImage: "sun.horizon.fill")
                    } else { KeyText("plan.noEvent").foregroundStyle(.secondary) }
                } else { ProgressView() }
            }
            if let errorKey { KeyText(errorKey).foregroundStyle(.red) }
            Button { Task { await save() } } label: {
                if busy { ProgressView() } else { KeyText("plan.save") }
            }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || day?.first(Planner.anchorKind(target)) == nil)
                .accessibilityIdentifier("plan-save")
        }
        .navigationTitle(L10n.text(planToEdit == nil ? "plan.create" : "v3.edit"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("common.cancel")) { dismiss() } } }
        .onAppear {
            guard !initialized else { return }; initialized = true
            if let plan = planToEdit {
                title = plan.title; target = plan.target; arrival = plan.arrivalLeadMinutes
                reminder = plan.reminderLeadMinutes ?? 30; notifications = plan.reminderLeadMinutes != nil; planDate = plan.date
            } else { title = String((state.place.name + " · " + L10n.text("target.sunset")).prefix(100)); planDate = state.selectedDate }
        }
        .task(id: planDate) {
            day = nil; let p = place, d = planDate
            do {
                let calculated = try await Task.detached { try DayEngine.calculate(place: p, date: d) }.value
                guard !Task.isCancelled else { return }; day = calculated
            } catch { if !Task.isCancelled { errorKey = "error.calculation" } }
        }
    }
    private func save() async {
        guard purchases.unlocked else { errorKey = "purchase.required"; return }
        busy = true; errorKey = nil; defer { busy = false }
        do {
            var plan = try ShootPlan(id: planToEdit?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), place: place, date: planDate, target: target, arrivalLeadMinutes: arrival, reminderLeadMinutes: notifications ? reminder : nil)
            if let old = planToEdit { plan.createdAt = old.createdAt; plan.updatedAt = Date() }
            let snapshot = plan
            let summary = try await Task.detached { try DayEngine.calculate(place: snapshot.place, date: snapshot.date) }.value
            _ = try Planner.milestones(plan: plan, summary: summary)
            guard purchases.unlocked else { errorKey = "purchase.required"; return }
            try state.upsert(plan)
            await ReminderService.cancel(planID: plan.id)
            if notifications {
                do {
                    let result = try await ReminderService.schedule(plan: plan, summary: summary, language: L10n.language)
                    switch result {
                    case .scheduled: state.noticeKey = "notice.reminderSaved"
                    case .denied: state.noticeKey = "notice.notificationDenied"
                    case .capacityReached: state.noticeKey = "notice.notificationCapacity"
                    case .noFutureEvent: state.noticeKey = "notice.pastReminder"
                    case .superseded: state.noticeKey = "notice.saved"
                    }
                } catch { state.noticeKey = "notice.savedWithoutReminder" }
            } else { state.noticeKey = "notice.saved" }
            dismiss()
        } catch LightPlanError.noEvent { errorKey = "plan.noEvent" }
        catch { errorKey = "error.save" }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var purchases: PurchaseStore
    @StateObject private var search = PlaceSearch()
    @State private var query = ""
    @State private var manual = false
    @State private var selecting = false
    @State private var renaming: Place?
    @State private var renamed = ""
    @State private var deleting: Place?
    @State private var pendingPlace: Place?
    var openPaywall: () -> Void
    var body: some View {
        List {
            Section {
                HStack {
                    TextField(L10n.text("place.searchPlaceholder"), text: $query).submitLabel(.search).onSubmit { Task { await search.search(query) } }.accessibilityIdentifier("place-search")
                    Button { Task { await search.search(query) } } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("place.search"))
                }
                Button { search.unresolvedCoordinate = nil; manual = true } label: { Label(L10n.text("place.manual"), systemImage: "number") }.accessibilityIdentifier("place-manual")
                if search.busy || selecting { ProgressView() }
                if let key = search.errorKey { KeyText(key).foregroundStyle(.secondary) }
                ForEach(Array(search.results.enumerated()), id: \.offset) { _, item in
                    Button {
                        if purchases.unlocked || state.basePlace.isExample { choose(item) }
                        else { state.requestPremium(unlocked: false) { choose(item) } }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? L10n.text("place.unnamed"))
                            Text([item.placemark.locality, item.placemark.administrativeArea, item.placemark.country].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(selecting)
                }
            } header: { KeyText("place.search") }
            Section(L10n.text("place.favorites")) {
                Button { state.requestPremium(unlocked: purchases.unlocked) { state.favorite() } } label: { Label(L10n.text("place.saveCurrent"), systemImage: "star") }
                if state.places.isEmpty { KeyText("place.empty").foregroundStyle(.secondary) }
                ForEach(state.places) { place in
                    Button { state.requestPremium(unlocked: purchases.unlocked) { Task { await state.select(place); state.tab = 1 } } } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(place.name); Text(place.timeZoneID).font(.caption).foregroundStyle(.secondary) }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleting = place } label: { Label(L10n.text("common.delete"), systemImage: "trash") }
                        Button { renamed = place.name; renaming = place } label: { Label(L10n.text("place.rename"), systemImage: "pencil") }.tint(.blue)
                    }
                }.onMove { state.movePlaces(from: $0, to: $1) }
            }
        }.navigationTitle(L10n.text("tab.places"))
        .toolbar { EditButton() }
        .sheet(isPresented: $manual, onDismiss: {
            guard let place = pendingPlace else { return }; pendingPlace = nil
            state.requestPremium(unlocked: purchases.unlocked || state.basePlace.isExample) {
                Task { await state.select(place, asBase: !purchases.unlocked); state.tab = 1 }
            }
        }) { NavigationStack { ManualPlaceView(prefilledCoordinate: search.unresolvedCoordinate, prefilledName: search.unresolvedName, onSelect: { pendingPlace = $0 }) } }
        .alert(L10n.text("place.rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L10n.text("place.name"), text: $renamed)
            Button(L10n.text("common.cancel"), role: .cancel) { renaming = nil }
            Button(L10n.text("common.ok")) { if let place = renaming { state.renamePlace(place.id, name: renamed) }; renaming = nil }
        }
        .confirmationDialog(L10n.text("place.deleteConfirm"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(L10n.text("common.delete"), role: .destructive) { if let place = deleting { state.deletePlace(place.id) }; deleting = nil }
        }
        .onDisappear { search.cancel() }
        .accessibilityIdentifier("screen-places")
    }
    private func choose(_ item: MKMapItem) {
        selecting = true
        Task {
            defer { selecting = false }
            do { let place = try await search.resolve(item); await state.select(place); state.tab = 1 }
            catch { manual = true } // Keep coordinates and require the user to confirm the destination time zone.
        }
    }
}

struct ManualPlaceView: View {
    var prefilledCoordinate: Coordinate? = nil
    var prefilledName: String = ""
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var zone = ""
    @State private var zonePicker = false
    @State private var problem = false
    @State private var initialized = false
    var onSelect: (Place) -> Void
    var body: some View {
        Form {
            TextField(L10n.text("place.name"), text: $name).accessibilityIdentifier("manual-name")
            TextField(L10n.text("place.latitude"), text: $latitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("manual-latitude")
            TextField(L10n.text("place.longitude"), text: $longitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("manual-longitude")
            Button { zonePicker = true } label: { LabeledContent(L10n.text("place.timezone"), value: zone.isEmpty ? L10n.text("place.chooseTimezone") : zone) }.accessibilityIdentifier("manual-timezone")
            KeyText("place.manualNote").font(.footnote)
            if problem { KeyText("error.coordinate").foregroundStyle(.red) }
            Button(L10n.text("common.use")) { usePlace() }.accessibilityIdentifier("manual-save")
        }.navigationTitle(L10n.text("place.manual"))
        .toolbar { Button(L10n.text("common.cancel")) { dismiss() } }
        .sheet(isPresented: $zonePicker) { TimeZonePicker(selection: $zone) }
        .onAppear {
            guard !initialized else { return }; initialized = true
            name = String(prefilledName.prefix(120))
            if let coordinate = prefilledCoordinate { latitude = String(coordinate.latitude); longitude = String(coordinate.longitude) }
        }
    }
    private func usePlace() {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) else { problem = true; return }
        do {
            let place = try Place(name: name.trimmingCharacters(in: .whitespacesAndNewlines), coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneID: zone)
            onSelect(place); dismiss()
        } catch { problem = true }
    }
}
struct TimeZonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var zones: [String] { TimeZone.knownTimeZoneIdentifiers.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            List(zones, id: \.self) { id in
                Button { selection = id; dismiss() } label: { HStack { Text(id); Spacer(); if id == selection { Image(systemName: "checkmark") } } }
            }.searchable(text: $query).navigationTitle(L10n.text("place.chooseTimezone"))
                .toolbar { Button(L10n.text("common.cancel")) { dismiss() } }
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
private struct ImportSheet: Identifiable { let id = UUID(); let preview: ImportPreview }
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("language") private var language = "system"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("haptics") private var haptics = true
    @AppStorage("clockFormat") private var clockFormat = "system"
    @State private var exporting = false
    @State private var importing = false
    @State private var backup = BackupDocument(data: Data())
    @State private var preview: ImportSheet?
    @State private var notificationKey = "settings.notificationUnknown"
    @State private var pendingCount = 0
    var openPaywall: () -> Void
    var body: some View {
        Form {
            Section {
                Picker(L10n.text("settings.language"), selection: $language) { KeyText("settings.system").tag("system"); ForEach(Array(L10n.supported.enumerated()), id: \.offset) { i, code in Text(L10n.names[i]).tag(code) } }
                Picker(L10n.text("v3.theme"), selection: $appearance) { KeyText("settings.system").tag("system"); KeyText("v3.theme.light").tag("light"); KeyText("v3.theme.dark").tag("dark") }
                Picker(L10n.text("settings.clockFormat"), selection: $clockFormat) {
                    KeyText("settings.system").tag("system"); KeyText("settings.clock12").tag("12h"); KeyText("settings.clock24").tag("24h")
                }
                Toggle(L10n.text("settings.haptics"), isOn: $haptics)
            }
            Section {
                Button(action: openPaywall) { KeyText(purchases.unlocked ? "purchase.unlocked" : "purchase.unlock") }.accessibilityIdentifier("membership").accessibilityValue(purchases.unlocked ? "unlocked" : "locked")
                Button { Task { await purchases.restore() } } label: { KeyText("purchase.restore") }.disabled(purchases.busy)
                if let message = purchases.messageKey { KeyText(message).font(.footnote) }
            }
            Section(L10n.text("settings.notifications")) {
                KeyText(notificationKey)
                LabeledContent(L10n.text("settings.scheduled"), value: L10n.number(Double(pendingCount)))
                Button { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } label: { KeyText("settings.openSystem") }
                KeyText("settings.reminderBudget").font(.footnote).foregroundStyle(.secondary)
            }
            Section(L10n.text("settings.data")) {
                if state.archiveLocked { KeyText("backup.recoveryWarning").foregroundStyle(.red) }
                Button { do { backup = BackupDocument(data: try state.exportedBytes()); exporting = true } catch { state.errorKey = "error.save" } } label: { KeyText("settings.export") }.accessibilityIdentifier("backup-export")
                Button { importing = true } label: { KeyText("backup.import") }.accessibilityIdentifier("backup-import")
                KeyText("settings.localOnly").font(.footnote)
            }
            Section(L10n.text("settings.about")) {
                LabeledContent("LightPlan", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0")
                NavigationLink(L10n.text("help.title")) { InfoPage(kind: .help) }
                NavigationLink(L10n.text("privacy.title")) { InfoPage(kind: .privacy) }
                NavigationLink(L10n.text("legal.title")) { InfoPage(kind: .legal) }
                Link(L10n.text("settings.contact"), destination: URL(string: "mailto:" + AppConfiguration.supportEmail)!)
                KeyText("disclaimer.geometry").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle(L10n.text("tab.settings"))
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "LightPlan-backup") { result in
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError { state.errorKey = "error.save" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? 5_000_001) <= 5_000_000 else { throw LightPlanError.tooManyItems }
                    preview = ImportSheet(preview: try state.previewImport(Data(contentsOf: url)))
                } catch { state.errorKey = "backup.invalid" }
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { state.errorKey = "backup.invalid" }
            }
        }
        .sheet(item: $preview) { sheet in ImportPreviewView(preview: sheet.preview) }
        .task { await notificationStatus() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await notificationStatus() } } }
        .accessibilityIdentifier("screen-settings")
    }
    private func notificationStatus() async {
        let center = UNUserNotificationCenter.current(), status = await center.notificationSettings()
        notificationKey = [.authorized, .provisional, .ephemeral].contains(status.authorizationStatus) ? "settings.notificationAllowed" : "settings.notificationOff"
        pendingCount = await center.pendingNotificationRequests().count
    }
}
struct ImportPreviewView: View {
    let preview: ImportPreview
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var policy: ImportConflictPolicy = .keepLocal
    @State private var enableReminders = false
    @State private var busy = false
    @State private var failed = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L10n.text("backup.newPlaces"), value: L10n.number(Double(preview.newPlaces)))
                    LabeledContent(L10n.text("backup.newPlans"), value: L10n.number(Double(preview.newPlans)))
                    LabeledContent(L10n.text("backup.conflicts"), value: L10n.number(Double(preview.conflictingPlaces + preview.conflictingPlans)))
                    LabeledContent(L10n.text("backup.identical"), value: L10n.number(Double(preview.identicalItems)))
                }
                Section {
                    Picker(L10n.text("backup.conflictPolicy"), selection: $policy) { KeyText("backup.keepLocal").tag(ImportConflictPolicy.keepLocal); KeyText("backup.useIncoming").tag(ImportConflictPolicy.useIncoming) }
                    Toggle(L10n.text("backup.enableReminders"), isOn: $enableReminders)
                    KeyText("backup.explanation").font(.footnote)
                    if state.archiveLocked { KeyText("backup.recoveryWarning").font(.footnote) }
                }
                if failed { KeyText("error.save").foregroundStyle(.red) }
                Button {
                    busy = true
                    Task { do { try await state.importArchive(preview, policy: policy, enableReminders: enableReminders); dismiss() } catch { failed = true }; busy = false }
                } label: { if busy { ProgressView() } else { KeyText("backup.confirm") } }.disabled(busy)
            }.navigationTitle(L10n.text("backup.preview"))
                .toolbar { Button(L10n.text("common.cancel")) { dismiss() }.disabled(busy) }
                .interactiveDismissDisabled(busy)
        }
    }
}
struct InfoPage: View {
    enum Kind { case help, privacy, legal }
    let kind: Kind
    private var prefix: String { switch kind { case .help: return "help"; case .privacy: return "privacy"; case .legal: return "legal" } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(1...4, id: \.self) { index in KeyText(prefix + ".p" + String(index)).fixedSize(horizontal: false, vertical: true) }
            }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle(L10n.text(prefix + ".title"))
    }
}
struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LPPhotoHero(minimumHeight: 230) { KeyText("purchase.title").font(.largeTitle.bold()) }.clipShape(RoundedRectangle(cornerRadius: 28))
                    KeyText("purchase.body").font(.title3)
                    Label(L10n.text("purchase.featureDates"), systemImage: "calendar")
                    Label(L10n.text("purchase.featurePlaces"), systemImage: "map")
                    Label(L10n.text("purchase.featurePlans"), systemImage: "bell")
                    Label(L10n.text("purchase.featureWidget"), systemImage: "rectangle.3.group")
                    KeyText("purchase.oneTime").font(.headline)
                    if purchases.unlocked { KeyText("purchase.unlocked").foregroundStyle(.green) }
                    else {
                        Button { Task { await purchases.purchase() } } label: {
                            HStack {
                                Spacer()
                                if purchases.busy || purchases.loadingProduct { ProgressView() }
                                else { Text(purchases.product.map { L10n.text("purchase.buy") + " · " + $0.displayPrice } ?? L10n.text("purchase.unavailable")) }
                                Spacer()
                            }.padding(12)
                        }.buttonStyle(.borderedProminent).disabled(purchases.product == nil || purchases.busy).accessibilityIdentifier("purchase-buy")
                    }
                    if let key = purchases.messageKey { KeyText(key).font(.footnote) }
                    HStack {
                        Button(L10n.text("purchase.restore")) { Task { await purchases.restore() } }.disabled(purchases.busy).accessibilityIdentifier("purchase-restore")
                        Spacer()
                        Button(L10n.text("common.retry")) { Task { await purchases.loadProduct() } }.disabled(purchases.loadingProduct)
                    }
                    KeyText("purchase.priceNote").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink(L10n.text("privacy.title")) { InfoPage(kind: .privacy) }
                    NavigationLink(L10n.text("legal.title")) { InfoPage(kind: .legal) }
                }.padding(24)
            }.toolbar { Button(L10n.text("common.close")) { dismiss() }.accessibilityIdentifier("paywall-close") }
                .task { if purchases.product == nil { await purchases.loadProduct() } }
        }
    }
}
