import SwiftUI
import MapKit
import LightPlanCore

/// One persistent Map instance occupies the first HStack slot in both layouts.
/// Width changes alter surrounding panels, not place/date/body/time state.
struct LightMapView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var visual = VisualDayModel()
    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedBody: CelestialBody = .sun
    @State private var imagery = true
    @State private var showPlan = false
    @State private var showDate = false
    @State private var draftDate = Date()
    @State private var compositionMode = false
    @State private var subjectCoordinate: Coordinate?
    @State private var dailyAlignment: AlignmentCandidate?
    @State private var compositionBusy = false
    @State private var showOpportunities = false
    @State private var opportunities: [AlignmentCandidate] = []
    @State private var opportunityBusy = false
    @State private var desiredOffsetDegrees = 0.0
    @State private var standDistance = 250.0
    var openPaywall: () -> Void
    private var coordinate: CLLocationCoordinate2D { Self.cl(state.place.coordinate) }
    private var sky: SkyPosition? { try? Astronomy.position(selectedBody, at: state.selectedInstant, coordinate: state.place.coordinate) }
    private var sun: SkyPosition? { try? Astronomy.position(.sun, at: state.selectedInstant, coordinate: state.place.coordinate) }
    private var band: LightBand { Astronomy.lightBand(altitude: sun?.altitude ?? -90) }
    private var subjectCL: CLLocationCoordinate2D? { subjectCoordinate.map(Self.cl) }
    private var suggestedObserver: Coordinate? {
        guard purchases.unlocked, compositionMode, let subjectCoordinate, let dailyAlignment else { return nil }
        return try? CompositionPlanner.recommendedObserver(
            subject: subjectCoordinate,
            bodyAzimuth: dailyAlignment.bodyAzimuth,
            desiredOffsetDegrees: desiredOffsetDegrees,
            distanceMeters: standDistance
        )
    }
    private var compositionRefreshID: String {
        [
            compositionMode ? "1" : "0",
            selectedBody.rawValue,
            String(subjectCoordinate?.latitude ?? 999),
            String(subjectCoordinate?.longitude ?? 999),
            String(state.summary?.start.timeIntervalSince1970 ?? 0),
            String(desiredOffsetDegrees)
        ].joined(separator: "|")
    }
    var body: some View {
        GeometryReader { geometry in
            let shortLandscape = geometry.size.width > geometry.size.height && geometry.size.height < 500
            let wide = (geometry.size.width >= 760 || (shortLandscape && geometry.size.width >= 600)) && !typeSize.isAccessibilitySize
            let controlsInSidebar = wide && shortLandscape
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    mapPane
                        .overlay(alignment: .top) {
                            if !controlsInSidebar { topControls.padding(14) }
                        }
                        .overlay(alignment: .topTrailing) {
                            if !controlsInSidebar { toolRail.padding(.trailing, 14).padding(.top, 130) }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 100)
                        .accessibilityIdentifier("map-canvas")
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
                            .accessibilityIdentifier("wide-inspector")
                    }
                }
                // The inset sits OUTSIDE the map viewport so system legal labels remain visible.
                ScrollView { VStack(spacing: 10) {
                    if let summary = state.summary {
                        HStack {
                            Button { shift(minutes: -15) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("v3.previousTime"))
                            Spacer()
                            Text(L10n.time(state.selectedInstant, zone: state.place.timeZone)).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit().accessibilityIdentifier("selected-time")
                            Spacer()
                            Button { shift(minutes: 15) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel(L10n.text("v3.nextTime"))
                        }
                        SolarTimeline(summary: summary, samples: visual.samples, instant: Binding(get: { state.selectedInstant }, set: { state.followingNow = false; state.selectedInstant = $0 }), compact: true)
                    }
                    if !wide { compactInspector }
                    if state.busy { ProgressView() }
                    if state.summary == nil && !state.busy { Button(L10n.text("common.retry")) { Task { await state.refresh() } } }
                }.padding(.horizontal, 18).padding(.bottom, 14).padding(.top, 6)
                    .background(LPTheme.ink).environment(\.colorScheme, .dark)
                }.frame(maxHeight: wide ? 150 : min(320, geometry.size.height * 0.57))
            }
            .background(LPTheme.ink)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPlan) { NavigationStack { PlanEditorView() } }
        .sheet(isPresented: $showDate) { datePicker }
        .sheet(isPresented: $showOpportunities) { opportunitySheet }
        .task(id: "\(state.place.id)-\(state.summary?.start.timeIntervalSince1970 ?? 0)") {
            if let summary = state.summary { await visual.load(summary) }
        }
        .task(id: compositionRefreshID) { await loadDailyAlignment() }
        .onAppear { recenter() }
        .onChange(of: state.place.id) { _, _ in recenter() }
        .accessibilityIdentifier("screen-map")
    }
    private var mapPane: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if selectedBody == .sun, !goldenSector.isEmpty {
                    MapPolygon(coordinates: goldenSector).foregroundStyle(LPTheme.gold.opacity(0.17))
                }
                ForEach(Array(visibleTracks.enumerated()), id: \.offset) { _, track in
                    MapPolyline(coordinates: track).stroke(selectedBody == .sun ? LPTheme.gold.opacity(0.7) : LPTheme.blue.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                }
                if let rise = state.summary?.first(selectedBody == .sun ? .sunrise : .moonrise), let endpoint = endpoint(rise.azimuth) {
                    MapPolyline(coordinates: [coordinate, endpoint]).stroke(LPTheme.gold.opacity(0.65), lineWidth: 1.5)
                    Annotation(L10n.text(rise.kind.key), coordinate: endpoint, anchor: .bottom) { eventBadge(rise, color: LPTheme.gold) }
                        .annotationTitles(.hidden)
                }
                if let set = state.summary?.first(selectedBody == .sun ? .sunset : .moonset), let endpoint = endpoint(set.azimuth) {
                    MapPolyline(coordinates: [coordinate, endpoint]).stroke(LPTheme.sunset.opacity(0.75), lineWidth: 1.5)
                    Annotation(L10n.text(set.kind.key), coordinate: endpoint, anchor: .bottom) { eventBadge(set, color: LPTheme.sunset) }
                        .annotationTitles(.hidden)
                }
                if let sky, let endpoint = endpoint(sky.azimuth) {
                    MapPolyline(coordinates: [coordinate, endpoint]).stroke(selectedBody == .sun ? LPTheme.gold : LPTheme.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: sky.altitude < 0 ? [7, 5] : []))
                    Annotation(L10n.text("body." + selectedBody.rawValue), coordinate: endpoint, anchor: .top) {
                        Image(systemName: selectedBody == .sun ? "sun.max.fill" : "moon.fill").font(.title2)
                            .foregroundStyle(selectedBody == .sun ? LPTheme.gold : LPTheme.blue)
                            .padding(9).background(LPTheme.ink.opacity(0.85), in: Circle()).overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                    }
                }
                if compositionMode, let subjectCL {
                    MapPolyline(coordinates: [coordinate, subjectCL])
                        .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5]))
                    Annotation(L10n.text("composition.subject"), coordinate: subjectCL, anchor: .bottom) {
                        Image(systemName: "scope")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.purple.opacity(0.92), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                    }
                    .annotationTitles(.hidden)
                }
                if compositionMode, let suggestedObserver, let subjectCL {
                    let suggestedCL = Self.cl(suggestedObserver)
                    MapPolyline(coordinates: [suggestedCL, subjectCL])
                        .stroke(.green.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 4]))
                    Annotation(L10n.text("composition.suggestedStand"), coordinate: suggestedCL, anchor: .bottom) {
                        Image(systemName: "camera.fill")
                            .font(.headline)
                            .foregroundStyle(LPTheme.ink)
                            .padding(10)
                            .background(.green, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
                    }
                    .annotationTitles(.hidden)
                }
                Annotation(state.place.name, coordinate: coordinate) {
                    ZStack { Circle().fill(LPTheme.blue.opacity(0.2)).frame(width: 38, height: 38); Circle().fill(LPTheme.blue).frame(width: 17, height: 17).overlay(Circle().stroke(.white, lineWidth: 3)) }
                }
            }
            .mapStyle(imagery ? .imagery(elevation: .flat) : .standard(elevation: .flat))
            .mapControls { MapCompass(); MapScaleView() }
            .accessibilityLabel(L10n.text("map.accessibility"))
            .accessibilityIdentifier("map-canvas")
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    guard compositionMode,
                          let value = proxy.convert(event.location, from: .local),
                          let coordinate = try? Coordinate(latitude: value.latitude, longitude: value.longitude) else { return }
                    subjectCoordinate = coordinate
                    opportunities = []
                }
            )
        }
    }
    private var topControls: some View {
        VStack(spacing: 9) {
            Button { state.tab = 3 } label: {
                HStack(spacing: 10) { Image(systemName: "magnifyingglass"); Text(state.place.name).font(.headline).lineLimit(2); Spacer(); Image(systemName: "chevron.down").font(.caption.bold()) }.padding(14).lpGlass(radius: 24)
            }.buttonStyle(.plain).accessibilityLabel(L10n.text("place.search"))
            HStack {
                Button { state.requestPremium(unlocked: purchases.unlocked) { draftDate = state.selectedDate; showDate = true } } label: {
                    Label(L10n.fullDate(state.selectedDate, zone: state.place.timeZone), systemImage: "calendar").font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 38).lpGlass(radius: 19)
                }.buttonStyle(.plain)
                Spacer()
                Button(L10n.text("time.now")) { Task { await state.showToday(unlocked: purchases.unlocked) } }.font(.caption.weight(.semibold)).padding(12).lpGlass(radius: 20)
            }
        }
    }
    private var toolRail: some View {
        VStack(spacing: 10) { toolButtons }
    }
    private var toolButtons: some View {
        Group {
            LPCircleButton(symbol: imagery ? "map" : "globe", label: "v3.map.style", identifier: "map-style") { imagery.toggle() }
            LPCircleButton(symbol: "location.fill", label: "v3.map.recenter", identifier: "map-recenter") { recenter() }
            LPCircleButton(symbol: "star", label: "place.saveCurrent", identifier: "map-favorite") { state.requestPremium(unlocked: purchases.unlocked) { state.favorite() } }
        }
    }
    private var compactInspector: some View {
        VStack(spacing: 10) {
            compactInspectorHeader
            compactBodyPicker
            compactMoonIllumination
            compactBelowHorizon
            if compositionMode { compositionPanel }
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
            Image(systemName: compositionMode ? "camera.viewfinder" : "camera.viewfinder")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(compositionMode ? .purple.opacity(0.34) : .white.opacity(0.1), in: Circle())
        }
        .accessibilityLabel(L10n.text("composition.toggle"))
        .accessibilityIdentifier("map-composition")
    }

    private var compactPlanButton: some View {
        Button {
            state.requestPremium(unlocked: purchases.unlocked) {
                showPlan = true
            }
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
            Button { state.requestPremium(unlocked: purchases.unlocked) { showPlan = true } } label: { Label(L10n.text("plan.create"), systemImage: "calendar.badge.plus").font(.headline).frame(maxWidth: .infinity).padding(15).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(LPPressStyle())
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
                        dailyAlignment = nil
                        opportunities = []
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if let subjectCoordinate {
                Picker(L10n.text("composition.frame"), selection: $desiredOffsetDegrees) {
                    Text(L10n.text("composition.left")).tag(-10.0)
                    Text(L10n.text("composition.center")).tag(0.0)
                    Text(L10n.text("composition.right")).tag(10.0)
                }
                .pickerStyle(.segmented)

                if let bearing = Geometry.bearing(from: state.place.coordinate, to: subjectCoordinate) {
                    LabeledContent(L10n.text("composition.subjectBearing"), value: L10n.number(bearing) + "°")
                }

                if compositionBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let dailyAlignment {
                    LabeledContent(L10n.text("composition.bestTime"), value: L10n.time(dailyAlignment.instant, zone: state.place.timeZone))
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

                    if purchases.unlocked {
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
                } else {
                    KeyText("composition.noOpportunity").font(.caption).foregroundStyle(.secondary)
                }

                Button {
                    state.requestPremium(unlocked: purchases.unlocked) {
                        showOpportunities = true
                    }
                } label: {
                    Label(L10n.text("composition.search"), systemImage: "sparkle.magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("composition-search")

                if !purchases.unlocked {
                    KeyText("composition.premiumHint").font(.caption2).foregroundStyle(.secondary)
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

    private var opportunitySheet: some View {
        NavigationStack {
            Group {
                if opportunityBusy {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if opportunities.isEmpty {
                    ContentUnavailableView(
                        L10n.text("composition.noOpportunity"),
                        systemImage: "camera.viewfinder",
                        description: Text(L10n.text("composition.geometryNote"))
                    )
                } else {
                    List(opportunities) { candidate in
                        Button {
                            showOpportunities = false
                            Task { await applyOpportunity(candidate) }
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(L10n.fullDate(candidate.instant, zone: state.place.timeZone)).font(.headline)
                                    Spacer()
                                    Text(L10n.time(candidate.instant, zone: state.place.timeZone)).font(.headline).monospacedDigit()
                                }
                                HStack {
                                    Text(L10n.text("composition.quality." + candidate.quality.rawValue))
                                    Spacer()
                                    Text("Δ " + L10n.number(candidate.absoluteErrorDegrees, decimals: 1) + "°")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                Text(L10n.text("composition.altitude") + " " + L10n.number(candidate.altitude, decimals: 1) + "° · " + L10n.text("composition.side." + candidate.side.rawValue))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(L10n.text("composition.opportunities"))
            .toolbar { Button(L10n.text("common.close")) { showOpportunities = false } }
            .task(id: compositionOpportunityID) { await loadOpportunities() }
        }
    }

    private var compositionOpportunityID: String {
        [
            selectedBody.rawValue,
            String(subjectCoordinate?.latitude ?? 999),
            String(subjectCoordinate?.longitude ?? 999),
            String(state.selectedDate.timeIntervalSince1970),
            String(desiredOffsetDegrees)
        ].joined(separator: "|")
    }

    private func toggleComposition() {
        compositionMode.toggle()
        opportunities = []
        if compositionMode, state.isFixture, subjectCoordinate == nil {
            subjectCoordinate = try? VisualGeometry.destination(from: state.place.coordinate, bearing: 250, meters: 900)
        }
        if !compositionMode { dailyAlignment = nil }
    }

    private func loadDailyAlignment() async {
        guard compositionMode, let subjectCoordinate, let summary = state.summary else {
            dailyAlignment = nil
            compositionBusy = false
            return
        }
        compositionBusy = true
        let body = selectedBody
        let observer = state.place.coordinate
        let offset = desiredOffsetDegrees
        let interval = DateInterval(start: summary.start, end: summary.end)
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try CompositionPlanner.bestAlignment(
                    body: body,
                    observer: observer,
                    subject: subjectCoordinate,
                    interval: interval,
                    desiredOffsetDegrees: offset
                )
            }.value
            guard !Task.isCancelled else { return }
            dailyAlignment = result
        } catch {
            if !Task.isCancelled { dailyAlignment = nil }
        }
        compositionBusy = false
    }

    private func loadOpportunities() async {
        guard let subjectCoordinate else {
            opportunities = []
            opportunityBusy = false
            return
        }
        opportunityBusy = true
        let body = selectedBody
        let place = state.place
        let start = state.selectedDate
        let offset = desiredOffsetDegrees
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try CompositionPlanner.opportunities(
                    body: body,
                    place: place,
                    subject: subjectCoordinate,
                    starting: start,
                    days: 14,
                    desiredOffsetDegrees: offset,
                    limit: 7
                )
            }.value
            guard !Task.isCancelled else { return }
            opportunities = result
        } catch {
            if !Task.isCancelled {
                opportunities = []
                state.errorKey = "composition.searchFailed"
            }
        }
        opportunityBusy = false
    }

    private func applyOpportunity(_ candidate: AlignmentCandidate) async {
        await state.selectDate(candidate.instant)
        state.followingNow = false
        state.selectedInstant = candidate.instant
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
        camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 3500, longitudinalMeters: 3500))
    }
    private func endpoint(_ bearing: Double, meters: Double = 1050) -> CLLocationCoordinate2D? {
        (try? VisualGeometry.destination(from: state.place.coordinate, bearing: bearing, meters: meters)).map(Self.cl)
    }
    private static func cl(_ value: Coordinate) -> CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude) }
    private var destinationCalendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = state.place.timeZone; calendar.locale = L10n.locale; return calendar }
    private func shift(minutes: Int) {
        state.followingNow = false
        guard let s = state.summary else { return }
        let interval = DateInterval(start: s.start, end: s.end)
        state.selectedInstant = VisualGeometry.instant(at: VisualGeometry.fraction(at: state.selectedInstant.addingTimeInterval(Double(minutes) * 60), in: interval), in: interval)
    }
    private func eventBadge(_ event: LightEvent, color: Color) -> some View {
        VStack(spacing: 2) { KeyText(event.kind.key).font(.caption2.weight(.semibold)); Text(L10n.time(event.date, zone: state.place.timeZone)).font(.caption.weight(.semibold)).monospacedDigit() }
            .foregroundStyle(LPTheme.ink).padding(8).background(color, in: RoundedRectangle(cornerRadius: 11)).shadow(color: .black.opacity(0.15), radius: 5, y: 3)
    }
    private var visibleTracks: [[CLLocationCoordinate2D]] {
        let tracks = selectedBody == .sun ? visual.projection?.sunTracks : visual.projection?.moonTracks
        return (tracks ?? []).map { $0.map(Self.cl) }
    }
    private var goldenSector: [CLLocationCoordinate2D] {
        (visual.projection?.goldenSector ?? []).map(Self.cl)
    }
}
