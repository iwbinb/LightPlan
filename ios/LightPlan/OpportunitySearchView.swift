import SwiftUI
import LightPlanCore

private enum WindowSearchPreset: String, CaseIterable {
    case low, twilight, all, custom

    var constraints: OpportunityConstraints? {
        switch self {
        case .low: return try? OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...15)
        case .twilight: return try? OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...30, solarAltitudeRange: -6...6)
        case .all, .custom: return nil
        }
    }
    var title: String { L10n.text(self == .custom ? "search.custom" : "opportunity." + rawValue) }

    static func matching(_ constraints: OpportunityConstraints?) -> Self {
        if constraints == nil { return .all }
        if constraints == Self.low.constraints { return .low }
        if constraints == Self.twilight.constraints { return .twilight }
        return .custom
    }
}

private typealias WindowSearchConfiguration = PlanningSearchConfiguration

private struct WindowSearchOptionsRoute: Identifiable {
    let id = UUID()
    let configuration: WindowSearchConfiguration
}

private enum WindowSearchOrder: String, CaseIterable {
    case match, date
    var title: String { L10n.text(self == .match ? "search.byMatch" : "search.byDate") }
}

/// Owns an immutable observer/subject snapshot. Editing the search form only changes a
/// draft; applying it cancels the previous worker and publishes results for the new request.
struct OpportunitySearchView: View {
    let place: Place
    let subject: Coordinate
    let celestialBody: CelestialBody
    let desiredOffsetDegrees: Double
    let onSelect: @MainActor (OpportunityWindow, OpportunityConstraints?) -> Void
    let onConfigurationChange: @MainActor (PlanningSearchConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var configuration: WindowSearchConfiguration
    @State private var options: WindowSearchOptionsRoute?
    private var order: WindowSearchOrder { configuration.sortByDate ? .date : .match }
    private var searchConfiguration: WindowSearchConfiguration { configuration.calculationInput }
    @State private var result: OpportunityWindowSearchResult?
    @State private var loadedConfiguration: WindowSearchConfiguration?
    @State private var busy = true
    @State private var failed = false
    @State private var generation = UUID()
    @State private var retry = 0
    @State private var paused = false

    init(place: Place, subject: Coordinate, body: CelestialBody, desiredOffsetDegrees: Double,
         startingDate: Date,
         initialConstraints: OpportunityConstraints? = try? OpportunityConstraints(maximumErrorDegrees: 3, altitudeRange: 0...15), initialDays: Int = 14, initialSortByDate: Bool = false,
         onConfigurationChange: @escaping @MainActor (PlanningSearchConfiguration) -> Void = { _ in },
         onSelect: @escaping @MainActor (OpportunityWindow, OpportunityConstraints?) -> Void) {
        self.place = place
        self.subject = subject
        self.celestialBody = body
        self.desiredOffsetDegrees = desiredOffsetDegrees
        self.onSelect = onSelect
        self.onConfigurationChange = onConfigurationChange
        _configuration = State(initialValue: WindowSearchConfiguration(startDate: startingDate, days: min(90, max(1, initialDays)),
            constraints: initialConstraints, sortByDate: initialSortByDate))
    }

    private struct RequestIdentity: Hashable {
        let configuration: WindowSearchConfiguration
        let retry: Int
        let paused: Bool
    }
    private var requestIdentity: RequestIdentity { RequestIdentity(configuration: searchConfiguration, retry: retry, paused: paused) }
    private var preset: WindowSearchPreset { .matching(configuration.constraints) }
    private var currentResult: OpportunityWindowSearchResult? {
        loadedConfiguration == searchConfiguration ? result : nil
    }
    private var visibleWindows: [OpportunityWindow] {
        guard let windows = currentResult?.windows else { return [] }
        if order == .date { return windows.sorted { $0.interval.start < $1.interval.start } }
        return windows
    }

    var body: some View {
        NavigationStack {
            List {
                Section { searchHeader }
                if busy || loadedConfiguration != searchConfiguration {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(L10n.text("flow.searching"))
                            .accessibilityIdentifier("opportunity-search-busy")
                        Button(L10n.text("flow.stopSearch")) { paused = true }
                            .buttonStyle(.bordered).controlSize(.large)
                            .accessibilityIdentifier("opportunity-stop-search")
                    }.padding(.vertical, 8)
                } else if paused {
                    VStack(alignment: .leading, spacing: 12) {
                        KeyText("flow.searchStopped").accessibilityIdentifier("opportunity-search-stopped")
                        Button(L10n.text("flow.resumeSearch")) { paused = false }
                            .buttonStyle(.bordered).controlSize(.large)
                            .accessibilityIdentifier("opportunity-resume-search")
                    }
                } else if failed {
                    VStack(alignment: .leading, spacing: 12) {
                        KeyText("composition.searchFailed")
                        Button(L10n.text("common.retry")) { retry += 1 }
                            .buttonStyle(.bordered).controlSize(.large)
                            .accessibilityIdentifier("opportunity-retry")
                        changeConditionsButton
                    }
                } else if let result = currentResult {
                    Section { resultSummary(result) }
                    if result.windows.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            ContentUnavailableView(L10n.text("composition.noOpportunity"),
                                systemImage: "camera.viewfinder", description: Text(L10n.text("search.empty")))
                                .accessibilityIdentifier("opportunity-empty")
                            changeConditionsButton
                            if configuration.constraints != nil {
                                Button(L10n.text("flow.clearConditions")) { configuration.constraints = nil }
                                    .buttonStyle(.bordered).controlSize(.large)
                                    .accessibilityIdentifier("opportunity-clear-conditions")
                            }
                        }
                    } else {
                        Section { sortPicker }
                        Section {
                            ForEach(visibleWindows) { window in
                                Button {
                                    guard loadedConfiguration == searchConfiguration else { return }
                                    onSelect(window, configuration.constraints)
                                    dismiss()
                                } label: {
                                    OpportunityWindowRow(window: window, zone: place.timeZone)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("composition-opportunity")
                            }
                        } footer: {
                            KeyText("search.windowEdgeNote")
                        }
                    }
                }
            }
            .navigationTitle(L10n.text("composition.opportunities"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.close")) { dismiss() }
                        .accessibilityIdentifier("opportunity-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { options = WindowSearchOptionsRoute(configuration: configuration) } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel(L10n.text("search.options"))
                    .accessibilityIdentifier("opportunity-options")
                }
            }
            .sheet(item: $options) { route in
                OpportunitySearchOptions(configuration: route.configuration, place: place,
                    celestialBody: celestialBody) { configuration = $0 }
            }
            .task(id: requestIdentity) { await load() }
            .onChange(of: configuration, initial: true) { old, value in
                if old.calculationInput != value.calculationInput { paused = false }
                onConfigurationChange(value)
            }
            .onDisappear { generation = UUID() }
        }
    }

    private var changeConditionsButton: some View {
        Button(L10n.text("flow.changeConditions")) {
            options = WindowSearchOptionsRoute(configuration: configuration)
        }
        // Explicit styles prevent a List row from activating its sibling actions.
        .buttonStyle(.bordered).controlSize(.large)
        .accessibilityIdentifier("opportunity-change-conditions")
    }

    @ViewBuilder private var sortPicker: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                KeyText("search.sort").font(.headline)
                ForEach(WindowSearchOrder.allCases, id: \.self) { value in
                    Button { configuration.sortByDate = value == .date } label: {
                        HStack(alignment: .top) {
                            Text(value.title).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            if order == value { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(order == value ? .isSelected : [])
                }
            }.accessibilityIdentifier("opportunity-sort")
        } else {
            Picker(L10n.text("search.sort"), selection: Binding(get: { order }, set: { configuration.sortByDate = $0 == .date })) {
                ForEach(WindowSearchOrder.allCases, id: \.self) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("opportunity-sort")
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            presetPicker
            if preset == .all {
                KeyText("search.allNote").font(.caption).foregroundStyle(.secondary)
            } else if let conditions = configuration.constraints {
                Text(L10n.conditions(conditions)).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("opportunity-conditions-summary")
            }
            Text(place.name + " · " + place.timeZoneID).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            KeyText("search.geometryNote").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var presetPicker: some View {
        if typeSize.isAccessibilitySize {
            Picker(L10n.text("opportunity.conditions"), selection: Binding(get: { preset }, set: { value in
                if value != .custom { configuration.constraints = value.constraints }
            })) {
                ForEach(WindowSearchPreset.allCases.filter { $0 != .custom || preset == .custom }, id: \.self) { value in
                    Text(value.title).tag(value)
                }
            }.pickerStyle(.menu).accessibilityIdentifier("opportunity-filter")
        } else {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WindowSearchPreset.allCases.filter { $0 != .custom || preset == .custom }, id: \.self) { value in
                        Button {
                            guard value != .custom else { return }
                            configuration.constraints = value.constraints
                        } label: {
                            Text(value.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .background(preset == value ? LPTheme.accent : LPTheme.surface, in: Capsule())
                                .foregroundStyle(preset == value ? Color.white : Color.primary)
                                .overlay(Capsule().stroke(.primary.opacity(preset == value ? 0 : 0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(preset == value ? .isSelected : [])
                        .accessibilityIdentifier("opportunity-preset-" + value.rawValue)
                        .id(value.rawValue)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("opportunity-filter")
            .task(id: preset) {
                // A custom chip can be inserted by the same state update. Let its layout
                // exist before bringing the full selected label into the visible strip.
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(preset.rawValue, anchor: .center)
            }
        }
        }
    }

    private func resultSummary(_ value: OpportunityWindowSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.fullDate(value.interval.start, zone: place.timeZone) + " – " +
                 L10n.fullDate(value.interval.end.addingTimeInterval(-0.001), zone: place.timeZone))
                .font(.headline).accessibilityIdentifier("opportunity-searched-range")
            Text(L10n.text("search.searchedDays") + ": " + L10n.number(Double(value.dayCount)))
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("opportunity-searched-days")
            if value.dayCount < configuration.days {
                KeyText("search.rangeLimit").font(.caption).foregroundStyle(.secondary)
            }
            if value.isTruncated {
                KeyText("search.truncated").font(.caption).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    @MainActor private func load() async {
        guard !Task.isCancelled else { return }
        let token = UUID()
        generation = token
        let request = searchConfiguration
        if paused {
            busy = false; failed = false; result = nil; loadedConfiguration = request
            return
        }
        busy = true
        failed = false
        result = nil
        loadedConfiguration = nil
        do {
            let constraints = try request.constraints ?? OpportunityConstraints()
            let value = try await CompositionPlanner.opportunityWindowsAsync(body: celestialBody,
                place: place, subject: subject, starting: request.startDate, days: request.days,
                desiredOffsetDegrees: desiredOffsetDegrees, limit: 60, constraints: constraints)
            guard !Task.isCancelled, generation == token, request == searchConfiguration else { return }
            result = value
            loadedConfiguration = request
            busy = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == token, request == searchConfiguration else { return }
            loadedConfiguration = request
            failed = true
            busy = false
        }
    }
}

private struct OpportunityWindowRow: View {
    let window: OpportunityWindow
    let zone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.fullDate(window.best.instant, zone: zone)).font(.headline)
            VStack(alignment: .leading, spacing: 3) {
                KeyText("search.bestTime").font(.subheadline)
                Text(L10n.time(window.best.instant, zone: zone)).font(.headline).monospacedDigit()
                    .accessibilityIdentifier("composition-opportunity-time")
            }
            Text(windowLabel).font(.subheadline)
            Text(durationLabel)
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("opportunity-window-duration")
            Text(qualityLabel).font(.caption).foregroundStyle(.secondary)
            if window.best.body == .moon {
                Text(moonLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var windowLabel: String {
        L10n.text("search.window") + ": " + boundary(window.interval.start) + " – " + boundary(window.interval.end)
    }

    private var durationLabel: String { L10n.text("search.duration") + ": " + duration }

    private var qualityLabel: String {
        let quality = L10n.text("composition.quality." + window.best.quality.rawValue)
        let error = L10n.number(window.best.absoluteErrorDegrees, decimals: 1)
        let altitude = L10n.number(window.best.altitude, decimals: 1)
        return quality + " · Δ " + error + "° · " + L10n.text("composition.altitude") + " " + altitude + "°"
    }

    private var moonLabel: String {
        L10n.text("moon.illumination") + ": " + L10n.number(window.moonIllumination * 100) + "%"
    }

    private func boundary(_ value: Date) -> String {
        let day = LocalDay.same(value, window.best.instant, timeZone: zone) ? "" : L10n.fullDate(value, zone: zone) + " "
        let clock: String
        if window.interval.duration < 120 {
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = zone
            let style = UserDefaults.standard.string(forKey: "clockFormat") ?? "system"
            formatter.setLocalizedDateFormatFromTemplate(style == "24h" ? "HHmmss" : (style == "12h" ? "hmmssa" : "jmmss"))
            clock = formatter.string(from: value)
        } else {
            clock = L10n.time(value, zone: zone)
        }
        return day + clock + " (" + L10n.utcOffset(at: value, zone: zone) + ")"
    }

    private var duration: String {
        if window.interval.duration < 60 {
            let formatter = MeasurementFormatter()
            formatter.locale = L10n.locale
            formatter.unitOptions = .providedUnit
            formatter.unitStyle = .medium
            formatter.numberFormatter.maximumFractionDigits = 1
            return formatter.string(from: Measurement(value: window.interval.duration, unit: UnitDuration.seconds))
        }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = L10n.locale
        formatter.calendar = calendar
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: window.interval.duration) ?? L10n.number(window.interval.duration / 60)
    }
}

private enum OpportunitySolarOption: String, CaseIterable {
    case any, golden, twilight, existing
    var title: String { L10n.text(self == .existing ? "search.custom" : "search." + rawValue) }
    var range: ClosedRange<Double>? {
        switch self {
        case .any, .existing: nil
        case .golden: -4...6
        case .twilight: -6...0
        }
    }
    static func matching(_ range: ClosedRange<Double>?) -> Self {
        if range == nil { return .any }
        if range == Self.golden.range { return .golden }
        if range == Self.twilight.range { return .twilight }
        return .existing
    }
}

private enum OpportunityMoonOption: String, CaseIterable {
    case any, brightMoon, darkMoon, existing
    var title: String { L10n.text(self == .existing ? "search.custom" : "search." + rawValue) }
    var range: ClosedRange<Double>? {
        switch self {
        case .any, .existing: nil
        case .brightMoon: 0.8...1
        case .darkMoon: 0...0.2
        }
    }
    static func matching(_ range: ClosedRange<Double>?) -> Self {
        if range == nil { return .any }
        if range == Self.brightMoon.range { return .brightMoon }
        if range == Self.darkMoon.range { return .darkMoon }
        return .existing
    }
}

private struct OpportunitySearchOptions: View {
    let configuration: WindowSearchConfiguration
    let place: Place
    let celestialBody: CelestialBody
    let onApply: (WindowSearchConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date
    @State private var days: Int
    @State private var limitedError: Bool
    @State private var maximumError: Double
    @State private var minimumAltitude: Double
    @State private var maximumAltitude: Double
    @State private var solar: OpportunitySolarOption
    @State private var moon: OpportunityMoonOption

    init(configuration: WindowSearchConfiguration, place: Place, celestialBody: CelestialBody,
         onApply: @escaping (WindowSearchConfiguration) -> Void) {
        self.configuration = configuration
        self.place = place
        self.celestialBody = celestialBody
        self.onApply = onApply
        _startDate = State(initialValue: configuration.startDate)
        _days = State(initialValue: configuration.days)
        let filters = configuration.constraints
        _limitedError = State(initialValue: (filters?.maximumErrorDegrees ?? 180) < 180)
        _maximumError = State(initialValue: filters?.maximumErrorDegrees ?? 3)
        _minimumAltitude = State(initialValue: filters?.altitudeRange.lowerBound ?? -1)
        _maximumAltitude = State(initialValue: filters?.altitudeRange.upperBound ?? 90)
        _solar = State(initialValue: .matching(filters?.solarAltitudeRange))
        _moon = State(initialValue: .matching(filters?.moonIlluminationRange))
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = place.timeZone
        value.locale = L10n.locale
        return value
    }
    private var constraints: OpportunityConstraints? {
        guard minimumAltitude < maximumAltitude else { return nil }
        return try? OpportunityConstraints(maximumErrorDegrees: limitedError ? maximumError : 180,
            altitudeRange: minimumAltitude...maximumAltitude,
            solarAltitudeRange: solar == .existing ? configuration.constraints?.solarAltitudeRange : solar.range,
            moonIlluminationRange: moon == .existing ? configuration.constraints?.moonIlluminationRange : moon.range)
    }
    private var isValid: Bool {
        guard constraints != nil else { return false }
        return (try? LocalDay.validate(startDate, timeZone: place.timeZone)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                geometrySection
                lightSection
                Section { KeyText("search.geometryNote").font(.caption).foregroundStyle(.secondary) }
                if !isValid { KeyText("search.invalid").foregroundStyle(.red) }
            }
            .environment(\.calendar, calendar)
            .environment(\.timeZone, place.timeZone)
            .environment(\.locale, L10n.locale)
            .navigationTitle(L10n.text("search.options"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("search.apply"), action: apply).disabled(!isValid)
                        .accessibilityIdentifier("opportunity-apply-options")
                }
            }
        }
    }

    private var dateSection: some View {
        Section(L10n.text("search.range")) {
            DatePicker(L10n.text("search.startDate"), selection: $startDate,
                in: LocalDay.supportedRange(timeZone: place.timeZone), displayedComponents: .date)
                .accessibilityIdentifier("opportunity-start-date")
            Picker(L10n.text("search.days"), selection: $days) {
                ForEach(Array(Set([14, 30, 60, 90, days])).sorted(), id: \.self) { value in
                    Text(L10n.number(Double(value))).tag(value)
                }
            }.accessibilityIdentifier("opportunity-days-presets")
            Stepper(value: $days, in: 1...90) {
                Text(L10n.text("search.days") + ": " + L10n.number(Double(days)))
            }.accessibilityIdentifier("opportunity-days-stepper")
            Text(place.timeZoneID).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var geometrySection: some View {
        Section(L10n.text("opportunity.conditions")) {
            Toggle(L10n.text("search.errorLimit"), isOn: $limitedError)
                .accessibilityIdentifier("opportunity-limit-error")
            if limitedError {
                Stepper(value: $maximumError, in: min(0.1, maximumError)...max(15, maximumError), step: 0.1) {
                    Text("Δ ≤ " + L10n.number(maximumError, decimals: 1) + "°")
                }.accessibilityIdentifier("opportunity-maximum-error")
            }
            // Retain valid imported bounds outside the normal editor range until the user
            // changes them. Date-only edits must not silently tighten a saved condition.
            Stepper(value: $minimumAltitude,
                in: min(-6, minimumAltitude)...max(minimumAltitude, min(89.9, maximumAltitude - 0.1)), step: 1) {
                Text(L10n.text("search.lowerAltitude") + ": " + L10n.number(minimumAltitude, decimals: 1) + "°")
            }.accessibilityIdentifier("opportunity-minimum-altitude")
            Stepper(value: $maximumAltitude,
                in: min(maximumAltitude, max(-5.9, minimumAltitude + 0.1))...max(90, maximumAltitude), step: 1) {
                Text(L10n.text("search.upperAltitude") + ": " + L10n.number(maximumAltitude, decimals: 1) + "°")
            }.accessibilityIdentifier("opportunity-maximum-altitude")
        }
    }

    private var lightSection: some View {
        Section {
            Picker(L10n.text("search.solarAltitude"), selection: $solar) {
                ForEach(OpportunitySolarOption.allCases.filter { $0 != .existing || configuration.constraints?.solarAltitudeRange != nil }, id: \.self) {
                    Text($0.title).tag($0)
                }
            }.accessibilityIdentifier("opportunity-solar-condition")
            if celestialBody == .moon {
                Picker(L10n.text("moon.illumination"), selection: $moon) {
                    ForEach(OpportunityMoonOption.allCases.filter { $0 != .existing || configuration.constraints?.moonIlluminationRange != nil }, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }.accessibilityIdentifier("opportunity-moon-condition")
            }
            if let constraints {
                Text(L10n.conditions(constraints)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func apply() {
        guard isValid, let constraints else { return }
        let unrestricted = try? OpportunityConstraints()
        onApply(WindowSearchConfiguration(startDate: startDate, days: days,
                                           constraints: constraints == unrestricted ? nil : constraints, sortByDate: configuration.sortByDate))
        dismiss()
    }
}
