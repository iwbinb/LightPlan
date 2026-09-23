import SwiftUI
import WidgetKit
import LightPlanCore

struct LightEntry: TimelineEntry {
    let date: Date
    let place: Place?
    let sunrise: Date?
    let sunset: Date?
    let goldenStart: Date?
    let dayEnd: Date
    let language: String
}
struct LightProvider: TimelineProvider {
    func placeholder(in context: Context) -> LightEntry { empty(at: Date(), language: "system") }
    func getSnapshot(in context: Context, completion: @escaping (LightEntry) -> Void) { completion(make(at: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LightEntry>) -> Void) {
        let now = Date(), first = make(at: now)
        // Precompute a bounded timeline across midnight. A late OS refresh must not present yesterday as today.
        var entries = [first]
        for offset in [3.0, 6, 9, 12] { entries.append(make(at: now.addingTimeInterval(offset * 3600))) }
        if first.dayEnd > now && first.dayEnd < now.addingTimeInterval(12 * 3600) { entries.append(make(at: first.dayEnd)) }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3600))))
    }
    private func empty(at date: Date, language: String) -> LightEntry {
        LightEntry(date: date, place: nil, sunrise: nil, sunset: nil, goldenStart: nil, dayEnd: date.addingTimeInterval(3600), language: language)
    }
    private func make(at date: Date) -> LightEntry {
        let defaults = AppConfiguration.sharedDefaults, language = defaults?.string(forKey: "widgetLanguage") ?? "system"
        guard let data = defaults?.data(forKey: "widgetPlace"), let place = try? JSONDecoder().decode(Place.self, from: data),
              let day = try? DayEngine.calculate(place: place, date: date) else { return empty(at: date, language: language) }
        return LightEntry(date: date, place: place, sunrise: day.first(.sunrise)?.date, sunset: day.first(.sunset)?.date, goldenStart: day.first(.goldenEveningStart)?.date, dayEnd: day.end, language: language)
    }
}
struct LightWidgetView: View {
    let entry: LightEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sunset.fill").foregroundStyle(.orange)
                if let place = entry.place {
                    Text(place.name).font(.headline).lineLimit(2)
                    Text(L10n.fullDate(entry.date, zone: place.timeZone, language: entry.language)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text(L10n.text("event.sunset", language: entry.language)).font(.caption).foregroundStyle(.secondary)
                    time(entry.sunset, zone: place.timeZone).font(.title2.bold()).monospacedDigit()
                    Text(place.timeZoneID).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else { Text(L10n.text("widget.openApp", language: entry.language)).font(.headline) }
            }
            if family == .systemMedium, let place = entry.place {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("event.sunrise", language: entry.language)).font(.caption).foregroundStyle(.secondary)
                    time(entry.sunrise, zone: place.timeZone).font(.headline).monospacedDigit()
                    Text(L10n.text("band.golden", language: entry.language)).font(.caption).foregroundStyle(.secondary)
                    time(entry.goldenStart, zone: place.timeZone).font(.headline).monospacedDigit()
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.background, for: .widget).widgetURL(URL(string: "lightplan://today"))
    }
    @ViewBuilder private func time(_ date: Date?, zone: TimeZone) -> some View {
        if let date { Text(L10n.time(date, zone: zone, language: entry.language)) }
        else { Text(L10n.text("event.none", language: entry.language)) }
    }
}
@main struct LightPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LightPlanSunset", provider: LightProvider()) { LightWidgetView(entry: $0) }
            .configurationDisplayName(Text(verbatim: "LightPlan")).description(L10n.text("widget.description"))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
