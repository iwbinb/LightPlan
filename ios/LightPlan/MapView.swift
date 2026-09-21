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
    var openPaywall: () -> Void
    private var coordinate: CLLocationCoordinate2D { Self.cl(state.place.coordinate) }
    private var sky: SkyPosition? { try? Astronomy.position(selectedBody, at: state.selectedInstant, coordinate: state.place.coordinate) }
    private var sun: SkyPosition? { try? Astronomy.position(.sun, at: state.selectedInstant, coordinate: state.place.coordinate) }
    private var band: LightBand { Astronomy.lightBand(altitude: sun?.altitude ?? -90) }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760 && !typeSize.isAccessibilitySize
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    mapPane
                        .overlay(alignment: .top) { topControls.padding(14) }
                        .overlay(alignment: .topTrailing) { toolRail.padding(.trailing, 14).padding(.top, 130) }
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 100)
                        .accessibilityIdentifier("map-canvas")
                    if wide {
                        ScrollView { inspector.padding(20) }
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
        .task(id: "\(state.place.id)-\(state.summary?.start.timeIntervalSince1970 ?? 0)") {
            if let summary = state.summary { await visual.load(summary) }
        }
        .onAppear { recenter() }
        .onChange(of: state.place.id) { _, _ in recenter() }
        .accessibilityIdentifier("screen-map")
    }
    private var mapPane: some View {
        Map(position: $camera) {
            if selectedBody == .sun, !goldenSector.isEmpty {
                MapPolygon(coordinates: goldenSector).foregroundStyle(LPTheme.gold.opacity(0.17))
            }
            ForEach(Array(visibleTracks.enumerated()), id: \.offset) { _, track in
                MapPolyline(coordinates: track).stroke(selectedBody == .sun ? LPTheme.gold.opacity(0.7) : LPTheme.blue.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
            }
            if let rise = state.summary?.first(selectedBody == .sun ? .sunrise : .moonrise), let endpoint = endpoint(rise.azimuth) {
                MapPolyline(coordinates: [coordinate, endpoint]).stroke(LPTheme.gold.opacity(0.65), lineWidth: 1.5)
                Annotation(L10n.text(rise.kind.key), coordinate: endpoint) { eventBadge(rise, color: LPTheme.gold) }
            }
            if let set = state.summary?.first(selectedBody == .sun ? .sunset : .moonset), let endpoint = endpoint(set.azimuth) {
                MapPolyline(coordinates: [coordinate, endpoint]).stroke(LPTheme.sunset.opacity(0.75), lineWidth: 1.5)
                Annotation(L10n.text(set.kind.key), coordinate: endpoint) { eventBadge(set, color: LPTheme.sunset) }
            }
            if let sky, let endpoint = endpoint(sky.azimuth) {
                MapPolyline(coordinates: [coordinate, endpoint]).stroke(selectedBody == .sun ? LPTheme.gold : LPTheme.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: sky.altitude < 0 ? [7, 5] : []))
                Annotation(L10n.text("body." + selectedBody.rawValue), coordinate: endpoint) {
                    Image(systemName: selectedBody == .sun ? "sun.max.fill" : "moon.fill").font(.title2)
                        .foregroundStyle(selectedBody == .sun ? LPTheme.gold : LPTheme.blue)
                        .padding(9).background(LPTheme.ink.opacity(0.85), in: Circle()).overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                }
            }
            Annotation(state.place.name, coordinate: coordinate) {
                ZStack { Circle().fill(LPTheme.blue.opacity(0.2)).frame(width: 38, height: 38); Circle().fill(LPTheme.blue).frame(width: 17, height: 17).overlay(Circle().stroke(.white, lineWidth: 3)) }
            }
        }
        .mapStyle(imagery ? .imagery(elevation: .flat) : .standard(elevation: .flat))
        .mapControls { MapCompass(); MapScaleView() }
        .accessibilityLabel(L10n.text("map.accessibility"))
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
        VStack(spacing: 10) {
            LPCircleButton(symbol: imagery ? "map" : "globe", label: "v3.map.style") { imagery.toggle() }
            LPCircleButton(symbol: "location.fill", label: "v3.map.recenter") { recenter() }
            LPCircleButton(symbol: "star", label: "place.saveCurrent") { state.requestPremium(unlocked: purchases.unlocked) { state.favorite() } }
        }
    }
    private var compactInspector: some View {
        VStack(spacing: 10) {
            compactInspectorHeader
            compactBodyPicker
            compactMoonIllumination
            compactBelowHorizon
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
            if let sky {
                LPMetric(title: "metric.azimuth", value: L10n.number(sky.azimuth) + "°", icon: "location.north.fill", tint: LPTheme.blue)
                LPMetric(title: "metric.altitude", value: L10n.number(sky.altitude, decimals: 1) + "°", icon: "sun.max.fill")
                if sky.altitude < 0 { KeyText("map.belowHorizon").font(.caption).foregroundStyle(.secondary) }
            }
            if selectedBody == .moon { Text(L10n.text("moon.illumination") + " " + L10n.number(Astronomy.moonIllumination(at: state.selectedInstant) * 100) + "%").font(.callout) }
            Divider()
            Label(L10n.text("v3.geometryOnly"), systemImage: "info.circle").font(.subheadline)
            KeyText("map.directionNote").font(.caption).foregroundStyle(.secondary)
            Button { state.requestPremium(unlocked: purchases.unlocked) { showPlan = true } } label: { Label(L10n.text("plan.create"), systemImage: "calendar.badge.plus").font(.headline).frame(maxWidth: .infinity).padding(15).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(LPPressStyle())
            KeyText("disclaimer.geometry").font(.caption).foregroundStyle(.secondary)
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
