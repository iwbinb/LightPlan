import SwiftUI
import MapKit
import UserNotifications
import UniformTypeIdentifiers
import LightPlanCore

struct PlanEditorView: View {
    var planToEdit: ShootPlan? = nil
    var compositionDraft: ShootPlan? = nil
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var collectionName = ""
    @State private var framingDraft: CameraFraming?
    @State private var framingEditor: FramingPreviewRequest?
    @State private var planDate = Date()
    @State private var target: PlanTarget = .sunset
    @State private var compositionBody: CelestialBody = .sun
    @State private var compositionOffset = 0.0
    @State private var composition: CompositionPlan?
    @State private var arrival = 30
    @State private var reminder = 30
    @State private var notifications = true
    @State private var initialized = false
    @State private var busy = false
    @State private var errorKey: String?
    @State private var day: DaySummary?
    @State private var draftPlace: Place?
    @State private var initialInputs: EditorInputs?
    @State private var confirmDiscard = false
    @State private var previewRetry = 0
    @State private var loadedPreview: PreviewRequest?

    private struct EditorInputs: Equatable {
        let title: String
        let notes: String
        let collection: String
        let framing: CameraFraming?
        let date: Date
        let target: PlanTarget
        let body: CelestialBody
        let offset: Double
        let arrival: Int
        let reminder: Int
        let notifications: Bool
    }
    private struct PreviewRequest: Hashable {
        let place: Place
        let date: Date
        let body: CelestialBody
        let offset: Double
        let initialized: Bool
        let retry: Int
    }
    private var inputs: EditorInputs {
        EditorInputs(title: title, notes: notes, collection: collectionName, framing: framingDraft,
            date: planDate, target: target, body: compositionBody, offset: compositionOffset,
            arrival: arrival, reminder: reminder, notifications: notifications)
    }
    private var hasUnsavedChanges: Bool { initialInputs.map { $0 != inputs } ?? false }
    private var place: Place { draftPlace ?? planToEdit?.place ?? compositionDraft?.place ?? state.place }
    private var inputComposition: CompositionPlan? { (planToEdit ?? compositionDraft)?.composition }
    private var isComposition: Bool { inputComposition != nil }
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = place.timeZone; return value }
    private var calculationID: PreviewRequest {
        PreviewRequest(place: place, date: planDate, body: compositionBody,
            offset: compositionOffset, initialized: initialized, retry: previewRetry)
    }
    private var anchor: Date? {
        guard loadedPreview == calculationID else { return nil }
        if isComposition { return composition?.instant }
        return Planner.anchorKind(target).flatMap { day?.first($0)?.date }
    }
    var body: some View {
        Form {
            Section {
                TextField(L10n.text("plan.title"), text: $title).accessibilityIdentifier("plan-title")
                    .onChange(of: title) { _, value in if value.count > 100 { title = String(value.prefix(100)) } }
                Label(place.name, systemImage: "mappin")
                TextField(L10n.text("plan.collectionHint"), text: $collectionName)
                    .accessibilityLabel(L10n.text("plan.collection")).accessibilityIdentifier("plan-collection")
                    .onChange(of: collectionName) { _, value in if value.count > 60 { collectionName = String(value.prefix(60)) } }
                DatePicker(L10n.text("map.date"), selection: $planDate, in: LocalDay.supportedRange(timeZone: place.timeZone), displayedComponents: .date)
                    .environment(\.timeZone, place.timeZone).environment(\.calendar, calendar)
                Text(place.timeZoneID).font(.caption).foregroundStyle(.secondary)
            }
            if let inputComposition {
                Section(L10n.text("composition.title")) {
                    Picker(L10n.text("map.body"), selection: $compositionBody) {
                        ForEach(CelestialBody.allCases, id: \.self) { Text(L10n.text("body." + $0.rawValue)).tag($0) }
                    }.accessibilityIdentifier("plan-composition-body")
                    Picker(L10n.text("composition.frame"), selection: $compositionOffset) {
                        Text(L10n.text("composition.left")).tag(-10.0)
                        Text(L10n.text("composition.center")).tag(0.0)
                        Text(L10n.text("composition.right")).tag(10.0)
                        if ![-10.0, 0, 10].contains(compositionOffset) {
                            Text(L10n.number(compositionOffset, decimals: 1) + "°").tag(compositionOffset)
                        }
                    }
                    LabeledContent(L10n.text("composition.subject"), value: L10n.coordinate(inputComposition.subject))
                    if let constraints = inputComposition.constraints {
                        Text(L10n.conditions(constraints)).font(.caption).foregroundStyle(.secondary)
                    }
                    KeyText("composition.recalculateNote").font(.caption).foregroundStyle(.secondary)
                    if let framingDraft {
                        Text(L10n.focalLength(framingDraft.focalLength35mm) + " mm · " + L10n.text("frame." + framingDraft.orientation.rawValue)
                             + " · " + L10n.number(framingDraft.referenceAltitudeDegrees, decimals: 1) + "°")
                            .accessibilityIdentifier("plan-framing-summary")
                        Button(L10n.text("frame.remove")) { self.framingDraft = nil }
                    }
                    Button(L10n.text("frame.open")) {
                        if let anchor {
                            framingEditor = FramingPreviewRequest(place: place, subject: inputComposition.subject,
                                body: compositionBody, instant: anchor, framing: framingDraft)
                        }
                    }.disabled(anchor == nil).accessibilityIdentifier("plan-edit-framing")
                }
            }
            Section {
                if !isComposition {
                    Picker(L10n.text("plan.target"), selection: $target) {
                        ForEach(PlanTarget.solarTargets, id: \.self) { Text(L10n.text("target." + $0.rawValue)).tag($0) }
                    }
                }
                Stepper(value: $arrival, in: 0...240, step: 5) { Text(L10n.text("plan.arrivalLead") + " " + L10n.number(Double(arrival)) + " " + L10n.text("unit.minutes")) }
                Toggle(L10n.text("plan.remind"), isOn: $notifications).accessibilityIdentifier("plan-reminder-toggle")
                    .disabled(planToEdit?.completedAt != nil)
                if planToEdit?.completedAt != nil { KeyText("library.completedEditNote").font(.caption) }
                if notifications {
                    Stepper(value: $reminder, in: 0...1440, step: 5) { Text(L10n.text("plan.reminderLead") + " " + L10n.number(Double(reminder)) + " " + L10n.text("unit.minutes")) }
                }
                KeyText("plan.arrivalNote").font(.footnote)
            }
            Section(L10n.text("plan.preview")) {
                if loadedPreview == calculationID, day != nil {
                    if let anchor {
                        Label(L10n.time(anchor.addingTimeInterval(-Double(arrival) * 60), zone: place.timeZone), systemImage: "figure.walk")
                        Label {
                            // The time is the accessible value; the camera glyph is decorative.
                            // A Label-level identifier can be inherited by its image on iOS 26.
                            Text(L10n.time(anchor, zone: place.timeZone))
                                .accessibilityIdentifier("plan-anchor-time")
                        } icon: {
                            Image(systemName: isComposition ? "camera.viewfinder" : "sun.horizon.fill")
                                .accessibilityHidden(true)
                        }
                    } else { KeyText(isComposition ? "composition.noOpportunity" : "plan.noEvent").foregroundStyle(.secondary) }
                } else if errorKey == "error.calculation" {
                    KeyText("error.calculation").foregroundStyle(.secondary)
                    Button(L10n.text("common.retry")) { previewRetry += 1 }
                        .accessibilityIdentifier("plan-preview-retry")
                } else { ProgressView() }
            }
            Section(L10n.text("plan.notes")) {
                TextField(L10n.text("plan.notesHint"), text: $notes, axis: .vertical)
                    .lineLimit(3...8).accessibilityIdentifier("plan-notes")
                    .onChange(of: notes) { _, value in
                        if value.count > 2000 { notes = String(value.prefix(2000)) }
                    }
            }
            if let errorKey { KeyText(errorKey).foregroundStyle(.red) }
            Button { Task { await save() } } label: {
                if busy { ProgressView() } else { KeyText("plan.save") }
            }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || anchor == nil)
                .accessibilityIdentifier("plan-save")
        }
        .disabled(busy)
        .interactiveDismissDisabled(busy || hasUnsavedChanges)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(L10n.text(planToEdit == nil ? "plan.create" : "v3.edit"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.cancel")) {
                    if hasUnsavedChanges { confirmDiscard = true } else { dismiss() }
                }.disabled(busy).accessibilityIdentifier("plan-cancel")
            }
        }
        .confirmationDialog(L10n.text("flow.unsavedTitle"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L10n.text("flow.discard"), role: .destructive) { dismiss() }
                .accessibilityIdentifier("plan-discard-changes")
            Button(L10n.text("flow.keepEditing"), role: .cancel) {}
                .accessibilityIdentifier("plan-keep-editing")
        } message: { Text(L10n.text("flow.unsavedBody")) }
        .onAppear {
            guard !initialized else { return }
            draftPlace = planToEdit?.place ?? compositionDraft?.place ?? state.place
            if let plan = planToEdit ?? compositionDraft {
                title = plan.title; notes = plan.notes ?? ""; collectionName = plan.collectionName ?? ""; target = plan.target; arrival = plan.arrivalLeadMinutes
                reminder = plan.reminderLeadMinutes ?? 30; notifications = plan.completedAt == nil && plan.reminderLeadMinutes != nil; planDate = plan.date
                if let saved = plan.composition {
                    compositionBody = saved.body; compositionOffset = saved.desiredOffsetDegrees; composition = saved
                    framingDraft = saved.cameraFraming
                }
            } else { title = String((state.place.name + " · " + L10n.text("target.sunset")).prefix(100)); planDate = state.selectedDate }
            initialInputs = inputs
            initialized = true
        }
        .task(id: calculationID) { await calculatePreview() }
        .sheet(item: $framingEditor) { request in
            FramingPreviewSheet(request: request, allowsTimeEditing: false) { framing, _ in framingDraft = framing }
        }
    }
    private func calculatePreview() async {
        guard initialized, !Task.isCancelled else { return }
        let request = calculationID
        day = nil; composition = nil; loadedPreview = nil; errorKey = nil
        let p = request.place, d = request.date, body = request.body, offset = request.offset, input = inputComposition
        do {
            let worker = Task.detached { try DayEngine.calculate(place: p, date: d) }
            let calculated = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            guard calculationID == request else { return }
            var resolved: CompositionPlan?
            if let input {
                if LocalDay.same(d, input.instant, timeZone: p.timeZone), body == input.body, offset == input.desiredOffsetDegrees {
                    resolved = input
                } else if let value = try await CompositionPlanner.bestAlignment(for: AlignmentRequest(
                    body: body, observer: p.coordinate, subject: input.subject,
                    interval: DateInterval(start: calculated.start, end: calculated.end), desiredOffsetDegrees: offset,
                    constraints: input.constraints)) {
                    resolved = try CompositionPlan(body: body, subject: input.subject, desiredOffsetDegrees: offset,
                                                   instant: value.instant, constraints: input.constraints)
                }
            }
            try Task.checkCancellation()
            guard calculationID == request else { return }
            composition = resolved; day = calculated; loadedPreview = request
        } catch is CancellationError { }
        catch { if !Task.isCancelled, calculationID == request { errorKey = "error.calculation" } }
    }
    private func save() async {
        guard !busy, loadedPreview == calculationID, anchor != nil else { return }
        busy = true; errorKey = nil; defer { busy = false }
        do {
            let savedComposition = try composition.map {
                try CompositionPlan(body: $0.body, subject: $0.subject, desiredOffsetDegrees: $0.desiredOffsetDegrees,
                                    instant: $0.instant, constraints: $0.constraints, cameraFraming: framingDraft)
            }
            var plan = try ShootPlan(id: planToEdit?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), place: place,
                date: composition?.instant ?? planDate, target: isComposition ? .composition : target,
                arrivalLeadMinutes: arrival, reminderLeadMinutes: notifications && planToEdit?.completedAt == nil ? reminder : nil, composition: savedComposition,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                collectionName: collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : collectionName.trimmingCharacters(in: .whitespacesAndNewlines),
                completedAt: planToEdit?.completedAt)
            if let old = planToEdit { plan.createdAt = old.createdAt; plan.updatedAt = Date() }
            let snapshot = plan
            let summary = try await Task.detached { try DayEngine.calculate(place: snapshot.place, date: snapshot.date) }.value
            _ = try Planner.milestones(plan: plan, summary: summary)
            try state.upsert(plan)
            if plan.reminderLeadMinutes != nil {
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
            } else {
                await ReminderService.cancel(planID: plan.id)
                state.noticeKey = "notice.saved"
            }
            dismiss()
        } catch LightPlanError.noEvent { errorKey = "plan.noEvent" }
        catch { errorKey = "error.save" }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var search = PlaceSearch()
    @StateObject private var location = LocationService()
    @State private var query = ""
    @State private var manual = false
    @State private var manualUsesLocation = false
    @State private var selecting = false
    @State private var renaming: Place?
    @State private var renamed = ""
    @State private var deleting: Place?
    @State private var pendingPlace: Place?
    var body: some View {
        List {
            Section {
                HStack {
                    TextField(L10n.text("place.searchPlaceholder"), text: $query).submitLabel(.search).onSubmit { Task { await search.search(query) } }.accessibilityIdentifier("place-search")
                    Button { Task { await search.search(query) } } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("place.search"))
                }
                Button {
                    location.onPlace = { place in
                        Task { await state.select(place, asBase: true); state.tab = 1 }
                    }
                    location.request()
                } label: {
                    HStack {
                        Label(L10n.text("place.useCurrent"), systemImage: "location.fill")
                        Spacer()
                        if location.busy { ProgressView() }
                    }.frame(minHeight: 44)
                }
                .disabled(location.busy || selecting)
                .accessibilityIdentifier("places-use-current-location")
                Button {
                    manualUsesLocation = false
                    search.unresolvedCoordinate = nil; search.unresolvedName = ""
                    manual = true
                } label: { Label(L10n.text("place.manual"), systemImage: "number") }
                    .accessibilityIdentifier("place-manual")
                if search.busy || selecting { ProgressView() }
                if let key = search.errorKey { KeyText(key).foregroundStyle(.secondary) }
                if let key = location.errorKey {
                    KeyText(key).foregroundStyle(.secondary)
                    if location.fallbackCoordinate != nil {
                        Button(L10n.text("place.chooseTimezone")) {
                            manualUsesLocation = true; manual = true
                        }.accessibilityIdentifier("places-location-timezone")
                    }
                }
                ForEach(Array(search.results.enumerated()), id: \.offset) { _, item in
                    Button {
                        choose(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? L10n.text("place.unnamed"))
                            Text([item.placemark.locality, item.placemark.administrativeArea, item.placemark.country].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(selecting)
                }
            } header: { KeyText("place.search") }
            Section(L10n.text("place.favorites")) {
                Button { state.favorite() } label: { Label(L10n.text("place.saveCurrent"), systemImage: "star") }
                if state.places.isEmpty { KeyText("place.empty").foregroundStyle(.secondary) }
                ForEach(state.places) { place in
                    Button { Task { await state.select(place, asBase: true); state.tab = 1 } } label: {
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
            Task { await state.select(place, asBase: true); state.tab = 1 }
        }) {
            NavigationStack {
                ManualPlaceView(
                    prefilledCoordinate: manualUsesLocation ? location.fallbackCoordinate : search.unresolvedCoordinate,
                    prefilledName: manualUsesLocation ? L10n.text("place.current") : search.unresolvedName,
                    onSelect: { pendingPlace = $0 }
                )
            }
        }
        .alert(L10n.text("place.rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L10n.text("place.name"), text: $renamed)
            Button(L10n.text("common.cancel"), role: .cancel) { renaming = nil }
            Button(L10n.text("common.ok")) { if let place = renaming { state.renamePlace(place.id, name: renamed) }; renaming = nil }
        }
        .confirmationDialog(L10n.text("place.deleteConfirm"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(L10n.text("common.delete"), role: .destructive) { if let place = deleting { state.deletePlace(place.id) }; deleting = nil }
        }
        .onDisappear { search.cancel(); location.cancel() }
        .accessibilityIdentifier("screen-places")
    }
    private func choose(_ item: MKMapItem) {
        selecting = true
        Task {
            defer { selecting = false }
            do { let place = try await search.resolve(item); await state.select(place, asBase: true); state.tab = 1 }
            catch {
                manualUsesLocation = false; manual = true
            } // Keep coordinates and require the user to confirm the destination time zone.
        }
    }
}

struct ManualPlaceView: View {
    var prefilledCoordinate: Coordinate? = nil
    var prefilledName: String = ""
    @EnvironmentObject private var state: AppState
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
            Section(L10n.text("settings.notifications")) {
                KeyText(notificationKey)
                LabeledContent(L10n.text("settings.scheduled"), value: L10n.number(Double(pendingCount)))
                    .accessibilityIdentifier("settings-reminder-count")
                    .accessibilityValue(Text(verbatim: String(pendingCount)))
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
                LabeledContent {
                    Text((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0")
                } label: { Text(verbatim: "LightPlan") }
                NavigationLink(L10n.text("help.title")) { InfoPage(kind: .help) }
                NavigationLink(L10n.text("privacy.title")) { InfoPage(kind: .privacy) }
                NavigationLink(L10n.text("legal.title")) { InfoPage(kind: .legal) }
                if let url = AppConfiguration.privacyURL { Link(L10n.text("privacy.policy"), destination: url) }
                if let url = AppConfiguration.supportURL { Link(L10n.text("settings.supportWebsite"), destination: url) }
                if let url = AppConfiguration.contactURL { Link(L10n.text("settings.contact"), destination: url) }
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
                if kind == .legal, let url = Bundle.main.url(forResource: "astronomia-MIT", withExtension: "txt"),
                   let license = try? String(contentsOf: url, encoding: .utf8) {
                    DisclosureGroup {
                        Text(verbatim: license).font(.footnote).textSelection(.enabled)
                    } label: { Text(verbatim: "astronomia · MIT") }
                }
            }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle(L10n.text(prefix + ".title"))
    }
}
