import SwiftUI
import LightPlanCore

struct TodayView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var visual = VisualDayModel()
    @StateObject private var location = LocationService()
    @State private var manualLocation = false
    @State private var morningLight = false
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LPPhotoHero(minimumHeight: typeSize.isAccessibilitySize ? 440 : 350) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Button { state.tab = 3 } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label(state.place.name, systemImage: "mappin.circle.fill").font(.headline)
                                        Text(L10n.fullDate(state.selectedDate, zone: state.place.timeZone)).font(.subheadline)
                                    }
                                }.buttonStyle(.plain)
                                Spacer()
                                LPCircleButton(symbol: "gearshape", label: "tab.settings") { state.tab = 4 }
                            }
                            Spacer(minLength: 64)
                            KeyText("v3.hero.title").font(.system(.largeTitle, design: .rounded).weight(.bold)).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("screen-today")
                            KeyText("v3.hero.subtitle").font(.subheadline)
                            HStack { Text(state.place.timeZoneID).font(.caption); Spacer(); KeyText("v3.art.label").font(.caption2) }.opacity(0.8)
                        }
                    }
                    VStack(spacing: 16) {
                        if let summary = state.summary {
                            VStack(spacing: 12) {
                            Picker(L10n.text("today.lightWindow"), selection: $morningLight) {
                                Text(L10n.text("today.morning")).tag(true)
                                Text(L10n.text("today.evening")).tag(false)
                            }.pickerStyle(.segmented)
                                .accessibilityIdentifier("today-light-window")
                            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                LPEventTile(title: "event.sunrise", value: time(.sunrise, summary), icon: "sunrise.fill", color: LPTheme.gold)
                                LPEventTile(title: "band.golden", value: morningLight ? range(.goldenMorningStart, .goldenMorningEnd, summary) : range(.goldenEveningStart, .goldenEveningEnd, summary), icon: "sun.max.fill", color: LPTheme.gold)
                                LPEventTile(title: "event.sunset", value: time(.sunset, summary), icon: "sunset.fill", color: LPTheme.sunset)
                                LPEventTile(title: "band.blue", value: morningLight ? range(.blueMorningStart, .goldenMorningStart, summary) : range(.goldenEveningEnd, .blueEveningEnd, summary), icon: "moon.stars.fill", color: LPTheme.blue)
                            }
                            }.padding(14).background(LPTheme.surface, in: RoundedRectangle(cornerRadius: 28))
                                .shadow(color: .black.opacity(0.06), radius: 16, y: 5)
                            LPCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    KeyText("guide.title").font(.headline)
                                    KeyText("guide.steps").font(.subheadline).foregroundStyle(.secondary)
                                    Button { state.tab = 3 } label: { Label(L10n.text("guide.choosePlace"), systemImage: "mappin.and.ellipse") }
                                    Button { state.beginComposition() } label: {
                                        Label(L10n.text("guide.compose"), systemImage: "camera.viewfinder")
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                            .foregroundStyle(.white)
                                            .background(LPTheme.accent, in: RoundedRectangle(cornerRadius: 16))
                                    }.buttonStyle(LPPressStyle()).accessibilityIdentifier("today-start-composition")
                                    Button { state.beginComposition(template: .sunset) } label: {
                                        Label(L10n.text("guide.sunset"), systemImage: "sun.horizon")
                                    }.buttonStyle(.bordered).accessibilityIdentifier("today-template-sunset")
                                    Button { state.beginComposition(template: .moon) } label: {
                                        Label(L10n.text("guide.moon"), systemImage: "moon")
                                    }.buttonStyle(.bordered).accessibilityIdentifier("today-template-moon")
                                    KeyText("guide.taskHint").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            LPCard {
                                VStack(alignment: .leading, spacing: 15) {
                                    HStack { Label { KeyText("today.sunPosition").foregroundStyle(.primary) } icon: { Image(systemName: "sun.max.fill").foregroundStyle(LPTheme.gold) }.font(.headline); Spacer(); Text(L10n.time(state.selectedInstant, zone: state.place.timeZone)).font(.subheadline.weight(.semibold)).monospacedDigit() }
                                    if let sky = try? Astronomy.position(.sun, at: state.selectedInstant, coordinate: state.place.coordinate) {
                                        ViewThatFits(in: .horizontal) {
                                        HStack(alignment: .top, spacing: 22) {
                                            LPMetric(title: "metric.azimuth", value: L10n.number(sky.azimuth) + "°", icon: "location.north.fill", tint: LPTheme.accent)
                                            LPMetric(title: "metric.altitude", value: L10n.number(sky.altitude, decimals: 1) + "°", icon: "arrow.up.right", tint: LPTheme.gold)
                                            Spacer(minLength: 0)
                                        }
                                        VStack(alignment: .leading, spacing: 12) {
                                            LPMetric(title: "metric.azimuth", value: L10n.number(sky.azimuth) + "°", icon: "location.north.fill", tint: LPTheme.accent)
                                            LPMetric(title: "metric.altitude", value: L10n.number(sky.altitude, decimals: 1) + "°", icon: "arrow.up.right", tint: LPTheme.gold)
                                        }
                                        }
                                    }
                                    SolarTimeline(summary: summary, samples: visual.samples, instant: Binding(get: { state.selectedInstant }, set: { state.followingNow = false; state.selectedInstant = $0 }))
                                    KeyText("v3.timeline.hint").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if let horizon = summary.horizonState { LPCard { KeyText("horizon." + horizon) } }
                        } else if state.busy { ProgressView().frame(height: 100) }
                        Button { state.tab = 1 } label: { Label(L10n.text("v3.openWorkspace"), systemImage: "map.fill").font(.headline).frame(maxWidth: .infinity).padding(17).foregroundStyle(.white).background(LPTheme.ink, in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(LPPressStyle())
                        Button { location.onPlace = { p in Task { await state.select(p, asBase: true); await state.showToday() } }; location.request() } label: { Label(L10n.text("place.useCurrent"), systemImage: "location") }.buttonStyle(.bordered)
                        if location.busy { ProgressView() }
                        if let error = location.errorKey {
                            KeyText(error).font(.footnote).foregroundStyle(.red)
                            if location.fallbackCoordinate != nil { Button(L10n.text("place.chooseTimezone")) { manualLocation = true } }
                        }
                        if !state.followingToday || !state.followingNow { Button(L10n.text("time.now")) { Task { await state.showToday() } } }
                        if let summary = state.summary { AllEventsView(summary: summary) }
                        KeyText("disclaimer.geometry").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.horizontal, 16).padding(.top, -24).padding(.bottom, 24)
                }.frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(LPTheme.canvas)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = state.place.timeZone
            morningLight = calendar.component(.hour, from: state.selectedInstant) < 12
        }
        .task(id: "\(state.place.id)-\(state.summary?.start.timeIntervalSince1970 ?? 0)") { if let summary = state.summary { await visual.load(summary) } }
        .refreshable { await state.showToday() }
        .sheet(isPresented: $manualLocation) { NavigationStack { ManualPlaceView(prefilledCoordinate: location.fallbackCoordinate, prefilledName: L10n.text("place.current"), onSelect: { place in Task { await state.select(place, asBase: true); await state.showToday() } }) } }
    }
    private func time(_ kind: LightEventKind, _ summary: DaySummary) -> String { summary.first(kind).map { L10n.time($0.date, zone: state.place.timeZone) } ?? L10n.text("event.none") }
    private func range(_ a: LightEventKind, _ b: LightEventKind, _ summary: DaySummary) -> String {
        guard let start = summary.first(a), let end = summary.first(b) else { return L10n.text("event.none") }
        return L10n.time(start.date, zone: state.place.timeZone) + " – " + L10n.time(end.date, zone: state.place.timeZone)
    }
}
struct LPEventTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(color).frame(width: 38, height: 42)
            VStack(alignment: .leading, spacing: 5) { KeyText(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
        }.padding(11).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
            .accessibilityElement(children: .combine)
    }
}
struct LPMetric: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = LPTheme.gold
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint).frame(width: 34, height: 40)
            VStack(alignment: .leading, spacing: 4) { KeyText(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText()) }
        }.accessibilityElement(children: .combine)
    }
}

struct AllEventsView: View {
    let summary: DaySummary
    var body: some View {
        LPCard {
            DisclosureGroup(L10n.text("today.allEvents")) {
                VStack(spacing: 14) {
                    ForEach(summary.events) { event in
                        HStack(alignment: .top) {
                            KeyText(event.kind.key).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            Text(L10n.time(event.date, zone: summary.place.timeZone)).monospacedDigit()
                        }.font(.subheadline).accessibilityElement(children: .combine)
                    }
                    if summary.events.isEmpty { KeyText("event.none") }
                }.padding(.top, 16)
            }
        }
    }
}
