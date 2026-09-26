import SwiftUI
import MapKit
import LightPlanCore

private struct MapPlanEditorSheet: Identifiable {
    let id = UUID()
    let draft: ShootPlan?
}

private struct MapOpportunityRequest: Identifiable {
    let id = UUID()
    let place: Place
    let subject: Coordinate
    let body: CelestialBody
    let offset: Double
    let date: Date
    let configuration: PlanningSearchConfiguration
    var context: PlanningSearchContext {
        PlanningSearchContext(place: place, subject: subject, body: body, offset: offset)
    }
}

/// One persistent Map instance occupies the first HStack slot in both layouts.
/// Width changes alter surrounding panels, not place/date/body/time state.
struct LightMapView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var visual = VisualDayModel()
    @StateObject private var location = LocationService()
    @State private var cameraRegion: MKCoordinateRegion?
    @State private var selectedBody: CelestialBody = .sun
    @AppStorage("mapBaseStyle") private var mapBaseStyle = "satellite"
    @State private var planEditor: MapPlanEditorSheet?
    @State private var restoredPlanID: UUID?
    @State private var showDate = false
    @State private var draftDate = Date()
    @State private var compositionMode = false
    @State private var subjectCoordinate: Coordinate?
    @State private var showSubjectEditor = false
    @State private var showLocationEntry = false
    @State private var showUserLocation = false
    @State private var opportunitySearch: MapOpportunityRequest?
    @State private var framingRequest: FramingPreviewRequest?
    @State private var cameraFraming: CameraFraming?
    @State private var planningTemplate: PlanningTemplate?
    @State private var dailyResult: AlignmentCandidate?
    @State private var dailyResultRequest: AlignmentRequest?
    @State private var dailyGeneration = UUID()
    @State private var compositionBusy = false
    @State private var dailyFailed = false
    @State private var dailyRetry = 0
    private struct DailyTask: Hashable {
        let request: AlignmentRequest?
        let retry: Int
    }
    @State private var chosenAlignment: AlignmentCandidate?
    @State private var chosenRequest: AlignmentRequest?
    @State private var chosenConstraints: OpportunityConstraints?
    @State private var desiredOffsetDegrees = 0.0
    @State private var standDistance = 250.0
    private var showsSatellite: Bool { mapBaseStyle != "standard" }
    private var coordinate: CLLocationCoordinate2D { Self.cl(state.place.coordinate) }
    private var sky: SkyPosition? { try? Astronomy.position(selectedBody, at: state.selectedInstant, coordinate: state.place.coordinate) }
    private var sun: SkyPosition? { try? Astronomy.position(.sun, at: state.selectedInstant, coordinate: state.place.coordinate) }
    private var band: LightBand { Astronomy.lightBand(altitude: sun?.altitude ?? -90) }
    private var suggestedObserver: Coordinate? {
        guard compositionMode, let subjectCoordinate, let dailyAlignment else { return nil }
        return try? CompositionPlanner.recommendedObserver(
            subject: subjectCoordinate,
            bodyAzimuth: dailyAlignment.bodyAzimuth,
            desiredOffsetDegrees: desiredOffsetDegrees,
            distanceMeters: standDistance
        )
    }
    private var dailyRequest: AlignmentRequest? {
        guard compositionMode, let subjectCoordinate, let summary = state.summary,
              summary.place.coordinate == state.place.coordinate,
              summary.place.timeZoneID == state.place.timeZoneID,
              LocalDay.same(summary.start, state.selectedDate, timeZone: state.place.timeZone) else { return nil }
        return AlignmentRequest(body: selectedBody, observer: state.place.coordinate,
                                subject: subjectCoordinate,
                                interval: DateInterval(start: summary.start, end: summary.end),
                                desiredOffsetDegrees: desiredOffsetDegrees)
    }
    private var dailyAlignment: AlignmentCandidate? {
        if let chosenAlignment, chosenRequest == dailyRequest,
           abs(chosenAlignment.instant.timeIntervalSince(state.selectedInstant)) < 1 {
            return chosenAlignment
        }
        return dailyResultRequest == dailyRequest ? dailyResult : nil
    }
    /// The timeline, framing preview and save action use this same absolute instant.
    /// Daily search is a suggestion until the user explicitly taps Show best time.
    private var currentAlignment: AlignmentCandidate? {
        guard let request = dailyRequest,
              (request.interval.start..<request.interval.end).contains(state.selectedInstant) else { return nil }
        return try? CompositionPlanner.evaluate(body: request.body, at: state.selectedInstant,
            observer: request.observer, subject: request.subject, desiredOffsetDegrees: request.desiredOffsetDegrees)
    }
    private var hasChosenAlignment: Bool {
        guard let chosenAlignment, chosenRequest == dailyRequest else { return false }
        return abs(chosenAlignment.instant.timeIntervalSince(state.selectedInstant)) < 1
    }
    private var savedSearchConditions: OpportunityConstraints? {
        guard let chosenAlignment, chosenRequest == dailyRequest,
              abs(chosenAlignment.instant.timeIntervalSince(state.selectedInstant)) < 1 else { return nil }
        return chosenConstraints
    }
    private var templateConditions: OpportunityConstraints? {
        switch (planningTemplate, selectedBody) {
        case (.sunset, .sun): return try? OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...6)
        case (.moon, .moon): return try? OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...20, moonIlluminationRange: 0.8...1)
        default: return nil
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let shortLandscape = geometry.size.width > geometry.size.height && geometry.size.height < 500
            let wide = (geometry.size.width >= 760 || (shortLandscape && geometry.size.width >= 600)) && !typeSize.isAccessibilitySize
            let controlsInSidebar = wide && shortLandscape
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Keep controls outside MapReader's overlay accessibility hierarchy.
                    // Its overlay ancestors can have empty bounds after iPad rotation.
                    ZStack(alignment: .topTrailing) {
                        mapPane
                        if !controlsInSidebar && !typeSize.isAccessibilitySize {
                            topControls.frame(maxWidth: .infinity).padding(14)
                            toolRail.padding(.trailing, 14).padding(.top, 130)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 100)
                    .accessibilityElement(children: .contain)
                    if wide {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if controlsInSidebar {
                                    topControls
                                    HStack(spacing: 10) { toolButtons }
                                }
                                inspector
                            }.padding(20)
                        }
                            .frame(width: min(380, max(290, geometry.size.width * 0.33)))
                            .background(LPTheme.ink).environment(\.colorScheme, .dark)
                    }
                }
                // The inset sits OUTSIDE the map viewport so system legal labels remain visible.
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            if typeSize.isAccessibilitySize {
                                topControls
                                HStack(spacing: 12) { toolButtons }
                            }
                            if let summary = state.summary {
                                let timeLayout = typeSize.isAccessibilitySize
                                    ? AnyLayout(VStackLayout(spacing: 6))
                                    : AnyLayout(HStackLayout())
                                timeLayout {
                                    Button { shift(minutes: -15) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("v3.previousTime")).accessibilityIdentifier("map-previous-time")
                                    Spacer()
                                    Text(L10n.time(state.selectedInstant, zone: state.place.timeZone)).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit().accessibilityIdentifier("selected-time")
                                    Spacer()
                                    Button { shift(minutes: 15) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("v3.nextTime")).accessibilityIdentifier("map-next-time")
                                }
                                SolarTimeline(summary: summary, samples: visual.samples, instant: Binding(get: { state.selectedInstant }, set: { state.followingNow = false; state.selectedInstant = $0 }), compact: true)
                            }
                            if !wide { compactInspector }
                            if state.busy { ProgressView() }
                            if state.summary == nil && !state.busy { Button(L10n.text("common.retry")) { Task { await state.refresh() } } }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                        .padding(.top, 6)
                        .background(LPTheme.ink)
                        .environment(\.colorScheme, .dark)
                    }
                    .onChange(of: compositionMode) { _, active in
                        if active && !wide {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scrollProxy.scrollTo("composition-panel", anchor: .top)
                            }
                        }
                    }
                    .frame(maxHeight: wide ? 150 : min(320, geometry.size.height * 0.57))
                }
            }
            .background(LPTheme.ink)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $planEditor) { route in
            NavigationStack { PlanEditorView(compositionDraft: route.draft) }
        }
        .sheet(isPresented: $showDate) { datePicker }
        .sheet(item: $opportunitySearch) { request in
            OpportunitySearchView(place: request.place, subject: request.subject, body: request.body,
                desiredOffsetDegrees: request.offset, startingDate: request.configuration.startDate,
                initialConstraints: request.configuration.constraints, initialDays: request.configuration.days,
                initialSortByDate: request.configuration.sortByDate,
                onConfigurationChange: { configuration in
                    do {
                        try state.planningSearchMemory.remember(configuration, for: request.context, mapDate: request.date)
                    } catch { state.errorKey = "error.calculation" }
                }) { window, constraints in
                    Task { await applyOpportunity(window.best, constraints: constraints, request: request) }
                }
        }
        .sheet(item: $framingRequest) { request in
            FramingPreviewSheet(request: request) { framing, instant in
                Task { await applyFraming(framing, at: instant, request: request) }
            }
        }
        .sheet(isPresented: $showSubjectEditor) {
            NavigationStack {
                SubjectCoordinateEditor(observer: state.place.coordinate, subject: subjectCoordinate) { coordinate in
                    subjectCoordinate = coordinate
                    chosenAlignment = nil; chosenRequest = nil; opportunitySearch = nil
                }
            }
        }
        .sheet(isPresented: $showLocationEntry) {
            NavigationStack {
                ManualPlaceView(
                    prefilledCoordinate: location.fallbackCoordinate,
                    prefilledName: L10n.text("place.current")
                ) { place in
                    Task { await state.select(place, asBase: true); recenter() }
                }
            }
        }
        .task(id: "\(state.place.id)-\(state.summary?.start.timeIntervalSince1970 ?? 0)") {
            if let summary = state.summary { await visual.load(summary) }
        }
        .task(id: DailyTask(request: dailyRequest, retry: dailyRetry)) { await loadDailyAlignment() }
        .onAppear { recenter() }
        .onDisappear { location.cancel(); showUserLocation = false }
        .onChange(of: location.errorKey) { _, key in
            guard let key else { return }
            if key == "error.timezone", location.fallbackCoordinate != nil {
                showUserLocation = true
                location.startLiveUpdates()
                showLocationEntry = true
            } else {
                state.errorKey = key
            }
        }
        .onChange(of: state.place.id) { _, _ in recenter() }
        .onChange(of: state.mapPlanRestore?.id, initial: true) { _, _ in restorePlan() }
        .onChange(of: state.compositionRequest, initial: true) { _, value in
            guard value != nil else { return }
            planningTemplate = state.compositionTemplate
            chosenAlignment = nil; chosenRequest = nil; chosenConstraints = nil
            if let planningTemplate {
                selectedBody = planningTemplate == .moon ? .moon : .sun; desiredOffsetDegrees = 0
                state.planningSearchMemory.reset(body: selectedBody)
            }
            if !compositionMode { toggleComposition() }
            state.compositionRequest = nil; state.compositionTemplate = nil
        }
    }
    private var mapPane: some View {
        NativePhotoMap(
            place: state.place, region: $cameraRegion, selectedBody: selectedBody,
            satellite: showsSatellite, compositionMode: compositionMode,
            tracks: visibleTracks, goldenSector: goldenSector,
            summary: state.summary, sky: sky,
            subject: compositionMode ? subjectCoordinate : nil,
            suggestedObserver: compositionMode ? suggestedObserver : nil,
            deviceLocation: showUserLocation ? location.currentCoordinate : nil,
            language: L10n.language
        ) { coordinate in
            subjectCoordinate = coordinate
            chosenAlignment = nil; chosenRequest = nil; chosenConstraints = nil
            opportunitySearch = nil
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel(L10n.text("map.accessibility"))
        .accessibilityIdentifier("map-canvas")
    }
    private var topControls: some View {
        VStack(spacing: 9) {
            Button { state.tab = 3 } label: {
                HStack(spacing: 10) { Image(systemName: "magnifyingglass"); Text(state.place.name).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal: false, vertical: true); Spacer(); Image(systemName: "chevron.down").font(.caption.bold()) }.padding(14).lpGlass(radius: 24)
            }.buttonStyle(.plain).accessibilityLabel(L10n.text("place.search"))
                .accessibilityValue(Text(verbatim: state.place.name))
                .accessibilityIdentifier("map-place-search")
            let dateLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout())
            dateLayout {
                Button { draftDate = state.selectedDate; showDate = true } label: {
                    Label(L10n.fullDate(state.selectedDate, zone: state.place.timeZone), systemImage: "calendar").font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 38).lpGlass(radius: 19)
                }.buttonStyle(.plain)
                if !typeSize.isAccessibilitySize { Spacer() }
                Button(L10n.text("time.now")) { Task { await state.showToday() } }.font(.caption.weight(.semibold)).padding(12).lpGlass(radius: 20)
            }
        }
    }
    private var toolRail: some View {
        HStack(spacing: 10) { toolButtons }
    }
    private var toolButtons: some View {
        Group {
            LPCircleButton(
                symbol: showsSatellite ? "map.fill" : "globe.americas.fill",
                label: "v3.map.style", identifier: "map-style"
            ) { mapBaseStyle = showsSatellite ? "standard" : "satellite" }
                .accessibilityValue(Text(L10n.text(showsSatellite ? "map.satellite" : "map.standard")))
            Button(action: requestDeviceLocation) {
                Group {
                    if location.busy { ProgressView() }
                    else { Image(systemName: "location.fill").font(.system(size: 17)) }
                }
                .frame(width: 46, height: 46)
                .lpGlass(radius: 23)
                .contentShape(Circle())
            }
            .buttonStyle(LPPressStyle())
            .disabled(location.busy)
            .accessibilityLabel(L10n.text("place.useCurrent"))
            .accessibilityIdentifier("map-use-current-location")
            .contextMenu {
                Button { recenter() } label: {
                    Label(L10n.text("v3.map.recenter"), systemImage: "scope")
                }.accessibilityIdentifier("map-recenter")
            }
            LPCircleButton(symbol: "star", label: "place.saveCurrent", identifier: "map-favorite") { state.favorite() }
        }
    }
    private func requestDeviceLocation() {
        location.onPlace = { place in
            showUserLocation = true
            location.startLiveUpdates()
            Task {
                await state.select(place, asBase: true)
                recenter()
            }
        }
        location.request()
    }
    private var compactInspector: some View {
        VStack(spacing: 10) {
            compactInspectorHeader
            compactBodyPicker
            compactMoonIllumination
            compactBelowHorizon
            if compositionMode { compositionPanel.id("composition-panel") }
        }
    }

    private var compactInspectorHeader: some View {
        HStack(spacing: 12) {
            compactInspectorArtwork
            VStack(alignment: .leading, spacing: 5) {
                LPPhaseLabel(key: "band." + band.rawValue)
                    .font(.headline)
                if let summary = compactSkySummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            compactCompositionButton
            compactPlanButton
        }
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private var compactInspectorArtwork: some View {
        Image("hero-sunset")
            .resizable()
            .scaledToFill()
            .frame(width: 66, height: 58)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private var compactCompositionButton: some View {
        Button { toggleComposition() } label: {
            Image(systemName: "camera.viewfinder")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(compositionMode ? .purple.opacity(0.34) : .white.opacity(0.1), in: Circle())
                // Keep the whole 44pt control interactive, including the space around the glyph.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("composition.toggle"))
        .accessibilityAddTraits(compositionMode ? .isSelected : [])
        .accessibilityIdentifier("map-composition")
    }

    private var compactPlanButton: some View {
        Button {
            planEditor = MapPlanEditorSheet(draft: nil)
        } label: {
            Image(systemName: "calendar.badge.plus")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.1), in: Circle())
        }
        .accessibilityLabel(L10n.text("plan.create"))
    }

    private var compactBodyPicker: some View {
        Picker(L10n.text("map.body"), selection: $selectedBody) {
            Text(L10n.text("body.sun")).tag(CelestialBody.sun)
            Text(L10n.text("body.moon")).tag(CelestialBody.moon)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var compactMoonIllumination: some View {
        if selectedBody == .moon {
            Text(compactMoonIlluminationText)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var compactBelowHorizon: some View {
        if let sky, sky.altitude < 0 {
            KeyText("map.belowHorizon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var compactSkySummary: String? {
        guard let sky else { return nil }
        return L10n.text("metric.altitude") + " "
            + L10n.number(sky.altitude, decimals: 1) + "° · "
            + L10n.text("metric.azimuth") + " "
            + L10n.number(sky.azimuth) + "°"
    }

    private var compactMoonIlluminationText: String {
        let percentage = Astronomy.moonIllumination(at: state.selectedInstant) * 100
        return L10n.text("moon.illumination") + " " + L10n.number(percentage) + "%"
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 20) {
            KeyText("v3.workbench").font(.title2.bold())
            LPPhotoHero(asset: "hero-sunset", minimumHeight: 185) {
                VStack(alignment: .leading, spacing: 5) { LPPhaseLabel(key: "band." + band.rawValue).font(.title3.bold()); KeyText("v3.art.label").font(.caption2).opacity(0.7) }
            }.clipShape(RoundedRectangle(cornerRadius: 22))
            Picker(L10n.text("map.body"), selection: $selectedBody) { Text(L10n.text("body.sun")).tag(CelestialBody.sun); Text(L10n.text("body.moon")).tag(CelestialBody.moon) }.pickerStyle(.segmented)
            Button { toggleComposition() } label: {
                Label(
                    L10n.text("composition.title"),
                    systemImage: "camera.viewfinder"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(compositionMode ? .purple.opacity(0.28) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(compositionMode ? .isSelected : [])
            .accessibilityIdentifier("map-composition")
            if let sky {
                LPMetric(title: "metric.azimuth", value: L10n.number(sky.azimuth) + "°", icon: "location.north.fill", tint: LPTheme.blue)
                LPMetric(title: "metric.altitude", value: L10n.number(sky.altitude, decimals: 1) + "°", icon: "sun.max.fill")
                if sky.altitude < 0 { KeyText("map.belowHorizon").font(.caption).foregroundStyle(.secondary) }
            }
            if selectedBody == .moon { Text(L10n.text("moon.illumination") + " " + L10n.number(Astronomy.moonIllumination(at: state.selectedInstant) * 100) + "%").font(.callout) }
            if compositionMode { compositionPanel }
            Divider()
            Label(L10n.text("v3.geometryOnly"), systemImage: "info.circle").font(.subheadline)
            KeyText("map.directionNote").font(.caption).foregroundStyle(.secondary)
            Button { planEditor = MapPlanEditorSheet(draft: nil) } label: { Label(L10n.text("plan.create"), systemImage: "calendar.badge.plus").font(.headline).frame(maxWidth: .infinity).padding(15).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(LPPressStyle())
            KeyText("disclaimer.geometry").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private var compositionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("composition.title"), systemImage: "camera.viewfinder").font(.headline)
                Spacer()
                if subjectCoordinate != nil {
                    Button(L10n.text("composition.clear")) {
                        subjectCoordinate = nil
                        dailyResult = nil
                        dailyResultRequest = nil
                        opportunitySearch = nil
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            Button { state.tab = 3 } label: {
                Label(L10n.text("flow.observer") + " · " + state.place.name, systemImage: "mappin")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.plain).accessibilityIdentifier("composition-choose-observer")
            Button { showSubjectEditor = true } label: {
                Label(L10n.text("composition.subject"), systemImage: "number")
            }.buttonStyle(.bordered).accessibilityIdentifier("composition-subject-coordinates")

            if let subjectCoordinate {
                KeyText("flow.chooseTime").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: openOpportunitySearch) {
                    Label(L10n.text("composition.search"), systemImage: "sparkle.magnifyingglass")
                        .font(.headline).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("composition-search")

                if let current = currentAlignment {
                    Text(L10n.text("flow.currentTime") + " · " + L10n.time(state.selectedInstant, zone: state.place.timeZone))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("composition-current-time")
                    if current.altitude < 0 { KeyText("map.belowHorizon").font(.caption).foregroundStyle(.secondary) }
                    Text(state.place.timeZoneID).font(.caption).foregroundStyle(.secondary)
                }
                Button(action: openFraming) {
                    Label(L10n.text("frame.open"), systemImage: "viewfinder")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.bordered).accessibilityIdentifier("composition-preview")
                if let cameraFraming {
                    Text(L10n.focalLength(cameraFraming.focalLength35mm) + " mm · "
                         + L10n.text("frame." + cameraFraming.orientation.rawValue)
                         + " · " + L10n.number(cameraFraming.referenceAltitudeDegrees, decimals: 1) + "°")
                        .font(.caption).accessibilityIdentifier("composition-framing-summary")
                }
                Picker(L10n.text("composition.frame"), selection: $desiredOffsetDegrees) {
                    Text(L10n.text("composition.left")).tag(-10.0)
                    Text(L10n.text("composition.center")).tag(0.0)
                    Text(L10n.text("composition.right")).tag(10.0)
                    if ![-10.0, 0, 10].contains(desiredOffsetDegrees) {
                        Text(L10n.number(desiredOffsetDegrees, decimals: 1) + "°").tag(desiredOffsetDegrees)
                    }
                }
                .pickerStyle(.segmented)


                Button(action: saveCompositionPlan) {
                    Label(L10n.text("composition.savePlan"), systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).disabled(currentAlignment == nil)
                    .accessibilityIdentifier("composition-save-plan")

                if let bearing = Geometry.bearing(from: state.place.coordinate, to: subjectCoordinate) {
                    LabeledContent(L10n.text("composition.subjectBearing"), value: L10n.number(bearing) + "°")
                }

                if compositionBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let dailyAlignment {
                    LabeledContent(L10n.text(chosenAlignment?.instant == dailyAlignment.instant ? "composition.selectedTime" : "composition.bestTime"), value: L10n.time(dailyAlignment.instant, zone: state.place.timeZone))
                    LabeledContent(L10n.text("composition.error"), value: L10n.number(dailyAlignment.absoluteErrorDegrees, decimals: 1) + "°")
                    LabeledContent(L10n.text("composition.altitude"), value: L10n.number(dailyAlignment.altitude, decimals: 1) + "°")
                    HStack {
                        Text(L10n.text("composition.quality." + dailyAlignment.quality.rawValue)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(L10n.text("composition.side." + dailyAlignment.side.rawValue)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(L10n.text("composition.arriveBy") + " · " + L10n.time(dailyAlignment.instant.addingTimeInterval(-30 * 60), zone: state.place.timeZone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("composition-best-time")

                    Button {
                        state.followingNow = false
                        state.selectedInstant = dailyAlignment.instant
                    } label: {
                        Label(L10n.text("composition.showBest"), systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("composition-show-best")

                    Group {
                        Stepper(value: $standDistance, in: 50...1_000, step: 50) {
                            Text(L10n.text("composition.standDistance") + " · " + L10n.number(standDistance) + " m")
                        }

                        if suggestedObserver != nil {
                            Button {
                                Task { await useSuggestedObserver() }
                            } label: {
                                Label(L10n.text("composition.useStand"), systemImage: "figure.walk")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("composition-use-stand")
                        }
                    }
                } else if dailyFailed {
                    KeyText("composition.searchFailed").font(.caption).foregroundStyle(.secondary)
                    Button(L10n.text("common.retry")) { dailyRetry += 1 }
                        .accessibilityIdentifier("composition-retry")
                } else {
                    KeyText(Geometry.bearing(from: state.place.coordinate, to: subjectCoordinate) == nil
                        ? "flow.samePoint" : "composition.noOpportunity")
                        .font(.caption).foregroundStyle(.secondary)
                }

                KeyText("composition.geometryNote").font(.caption2).foregroundStyle(.secondary)
            } else {
                KeyText("composition.tapTarget").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composition-card")
    }

    private func toggleComposition() {
        compositionMode.toggle()
        opportunitySearch = nil
        if compositionMode, state.isFixture, subjectCoordinate == nil {
            subjectCoordinate = try? VisualGeometry.destination(from: state.place.coordinate, bearing: 250, meters: 900)
        }
        if !compositionMode { dailyResult = nil; dailyResultRequest = nil }
    }

    private func loadDailyAlignment() async {
        guard !Task.isCancelled else { return }
        let generation = UUID()
        dailyGeneration = generation
        dailyFailed = false
        guard let request = dailyRequest else {
            dailyResult = nil
            dailyResultRequest = nil
            compositionBusy = false
            return
        }
        compositionBusy = true
        defer { if dailyGeneration == generation { compositionBusy = false } }
        do {
            let result = try await CompositionPlanner.bestAlignment(for: request)
            guard !Task.isCancelled, dailyGeneration == generation, dailyRequest == request else { return }
            dailyResult = result
            dailyResultRequest = request
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled, dailyGeneration == generation {
                dailyResult = nil
                dailyResultRequest = nil
                dailyFailed = true
            }
        }
    }

    private func openOpportunitySearch() {
        guard let subjectCoordinate else { return }
        // Nil is a meaningful saved choice: unrestricted/All. Only a fresh task gets defaults.
        let constraints = hasChosenAlignment ? chosenConstraints : (templateConditions
            ?? (try? OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...15)))
        let context = PlanningSearchContext(place: state.place, subject: subjectCoordinate,
            body: selectedBody, offset: desiredOffsetDegrees)
        let defaults = PlanningSearchConfiguration(startDate: state.selectedDate,
            days: planningTemplate == .moon && selectedBody == .moon ? 30 : 14, constraints: constraints)
        do {
            let configuration = try state.planningSearchMemory.configuration(for: context,
                mapDate: state.selectedDate, defaults: defaults)
            opportunitySearch = MapOpportunityRequest(place: state.place, subject: subjectCoordinate,
                body: selectedBody, offset: desiredOffsetDegrees, date: state.selectedDate, configuration: configuration)
        } catch { state.errorKey = "error.coordinate" }
    }

    private func applyOpportunity(_ candidate: AlignmentCandidate, constraints: OpportunityConstraints?,
                                  request: MapOpportunityRequest) async {
        guard state.place == request.place, subjectCoordinate == request.subject,
              selectedBody == request.body, desiredOffsetDegrees == request.offset else { return }
        await state.selectDate(candidate.instant)
        guard !Task.isCancelled, state.place == request.place, subjectCoordinate == request.subject,
              selectedBody == request.body, desiredOffsetDegrees == request.offset,
              let interval = dailyRequest?.interval,
              (interval.start..<interval.end).contains(candidate.instant) else { return }
        state.followingNow = false
        state.selectedInstant = candidate.instant
        chosenAlignment = candidate; chosenRequest = dailyRequest; chosenConstraints = constraints
        try? state.planningSearchMemory.selectedResult(for: request.context, mapDate: candidate.instant)
    }

    private func openFraming() {
        guard let subjectCoordinate else { return }
        framingRequest = FramingPreviewRequest(place: state.place, subject: subjectCoordinate,
            body: selectedBody, instant: state.selectedInstant, framing: cameraFraming)
    }

    private func applyFraming(_ framing: CameraFraming, at instant: Date, request: FramingPreviewRequest) async {
        guard state.place == request.place, subjectCoordinate == request.subject, selectedBody == request.body else { return }
        let offset = desiredOffsetDegrees
        let retainedConditions = abs(instant.timeIntervalSince(state.selectedInstant)) < 1 ? savedSearchConditions : nil
        await state.selectDate(instant)
        guard !Task.isCancelled, state.place == request.place, subjectCoordinate == request.subject, selectedBody == request.body,
              desiredOffsetDegrees == offset,
              let interval = dailyRequest?.interval,
              (interval.start..<interval.end).contains(instant),
              LocalDay.same(instant, state.selectedDate, timeZone: request.place.timeZone) else { return }
        cameraFraming = framing
        state.followingNow = false; state.selectedInstant = instant
        chosenAlignment = try? CompositionPlanner.evaluate(body: request.body, at: instant,
            observer: request.place.coordinate, subject: request.subject, desiredOffsetDegrees: offset)
        chosenRequest = dailyRequest; chosenConstraints = retainedConditions
    }

    private func saveCompositionPlan() {
        guard let alignment = currentAlignment, let subject = subjectCoordinate else { return }
        do {
            let composition = try CompositionPlan(body: alignment.body, subject: subject,
                desiredOffsetDegrees: alignment.desiredOffsetDegrees, instant: alignment.instant,
                constraints: savedSearchConditions, cameraFraming: cameraFraming)
            let draft = try ShootPlan(title: String((state.place.name + " · " + L10n.text("composition.title")).prefix(100)),
                place: state.place, date: alignment.instant, target: .composition, composition: composition)
            planEditor = MapPlanEditorSheet(draft: draft)
        } catch { state.errorKey = "error.calculation" }
    }

    private func restorePlan() {
        guard let request = state.mapPlanRestore, request.id != restoredPlanID else { return }
        restoredPlanID = request.id
        planningTemplate = nil
        opportunitySearch = nil
        if let saved = request.plan.composition {
            selectedBody = saved.body
            state.planningSearchMemory.reset(body: saved.body)
            subjectCoordinate = saved.subject
            desiredOffsetDegrees = saved.desiredOffsetDegrees
            compositionMode = true
            chosenAlignment = try? CompositionPlanner.evaluate(body: saved.body, at: saved.instant,
                observer: request.plan.place.coordinate, subject: saved.subject, desiredOffsetDegrees: saved.desiredOffsetDegrees)
            chosenRequest = dailyRequest
            chosenConstraints = saved.constraints
            cameraFraming = saved.cameraFraming
        } else {
            selectedBody = .sun
            cameraFraming = nil
            subjectCoordinate = nil
            compositionMode = false
        }
    }

    private func useSuggestedObserver() async {
        guard let suggestedObserver else { return }
        do {
            let place = try Place(
                name: L10n.text("composition.suggestedPlace"),
                coordinate: suggestedObserver,
                timeZoneID: state.place.timeZoneID
            )
            await state.selectPlanningPlace(place)
            recenter()
        } catch {
            state.errorKey = "error.coordinate"
        }
    }

    private var datePicker: some View {
        NavigationStack {
            Form {
                DatePicker(L10n.text("map.date"), selection: $draftDate, in: LocalDay.supportedRange(timeZone: state.place.timeZone), displayedComponents: .date).datePickerStyle(.graphical).environment(\.timeZone, state.place.timeZone).environment(\.calendar, destinationCalendar)
                HStack {
                    Button(L10n.text("tab.today")) { draftDate = Date() }
                    Spacer()
                    Button(L10n.text("date.tomorrow")) { draftDate = destinationCalendar.date(byAdding: .day, value: 1, to: Date()) ?? Date() }
                    Spacer()
                    Button(L10n.text("date.weekend")) { draftDate = destinationCalendar.nextWeekend(startingAfter: Date())?.start ?? Date() }
                }
                Text(state.place.timeZoneID).font(.caption)
                Button(L10n.text("common.ok")) { showDate = false; Task { await state.selectDate(draftDate) } }
            }.navigationTitle(L10n.text("map.date"))
                .toolbar { Button(L10n.text("common.cancel")) { showDate = false } }
        }
    }
    private func recenter() {
        cameraRegion = MKCoordinateRegion(center: coordinate, latitudinalMeters: 3500, longitudinalMeters: 3500)
    }
    private static func cl(_ value: Coordinate) -> CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude) }
    private var destinationCalendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = state.place.timeZone; calendar.locale = L10n.locale; return calendar }
    private func shift(minutes: Int) {
        state.followingNow = false
        guard let s = state.summary else { return }
        let interval = DateInterval(start: s.start, end: s.end)
        state.selectedInstant = VisualGeometry.instant(at: VisualGeometry.fraction(at: state.selectedInstant.addingTimeInterval(Double(minutes) * 60), in: interval), in: interval)
    }
    private var visibleTracks: [[CLLocationCoordinate2D]] {
        let tracks = selectedBody == .sun ? visual.projection?.sunTracks : visual.projection?.moonTracks
        return (tracks ?? []).map { $0.map(Self.cl) }
    }
    private var goldenSector: [CLLocationCoordinate2D] {
        (visual.projection?.goldenSector ?? []).map(Self.cl)
    }
}
