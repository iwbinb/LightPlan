import SwiftUI
import LightPlanCore

@MainActor final class VisualDayModel: ObservableObject {
    @Published private(set) var samples: [LightSample] = []
    @Published private(set) var failed = false
    @Published private(set) var projection: MapProjection?
    private var request = UUID()
    func load(_ summary: DaySummary) async {
        let id = UUID(); request = id; failed = false
        do {
            let next = try await Task.detached(priority: .userInitiated) {
                let samples = try VisualSampler.samples(for: summary)
                return (samples, try MapProjection.make(summary: summary, samples: samples))
            }.value
            guard request == id, !Task.isCancelled else { return }
            samples = next.0; projection = next.1
        } catch { if request == id { failed = true; samples = []; projection = nil } }
    }
}

struct SolarTimeline: View {
    let summary: DaySummary
    let samples: [LightSample]
    @Binding var instant: Date
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var lastBand: LightBand?
    @State private var hapticToken = 0
    @AppStorage("haptics") private var haptics = true
    private var interval: DateInterval { DateInterval(start: summary.start, end: summary.end) }
    private var fraction: Double { VisualGeometry.fraction(at: instant, in: interval) }
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                Canvas { context, size in
                    let h = size.height
                    let y: (Double) -> Double = { a in (h - 14) * (1 - min(1, max(0, (a + 18) / 108))) + 5 }
                    for window in summary.windows {
                        let start = VisualGeometry.fraction(at: window.start, in: interval)
                        let end = VisualGeometry.fraction(at: window.end, in: interval)
                        let rect = CGRect(x: width * start, y: 0, width: max(1, width * (end - start)), height: h)
                        context.fill(Path(rect), with: .color(color(window.band).opacity(compact ? 0.7 : 0.12)))
                    }
                    if !compact {
                        let horizon = y(0)
                        var baseline = Path(); baseline.move(to: CGPoint(x: 0, y: horizon)); baseline.addLine(to: CGPoint(x: width, y: horizon))
                        context.stroke(baseline, with: .color(.secondary.opacity(0.28)), style: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
                        var curve = Path()
                        for (i, sample) in samples.enumerated() {
                            let point = CGPoint(x: width * VisualGeometry.fraction(at: sample.instant, in: interval), y: y(sample.sun.altitude))
                            if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
                        }
                        context.stroke(curve, with: .linearGradient(Gradient(colors: [LPTheme.blue, LPTheme.gold, LPTheme.sunset, LPTheme.blue]), startPoint: .zero, endPoint: CGPoint(x: width, y: 0)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    var indicator = Path(); indicator.move(to: CGPoint(x: width * fraction, y: 0)); indicator.addLine(to: CGPoint(x: width * fraction, y: h))
                    context.stroke(indicator, with: .color(scheme == .dark ? .white.opacity(0.6) : LPTheme.ink.opacity(0.4)), lineWidth: 1)
                    let altitude = (try? Astronomy.position(.sun, at: instant, coordinate: summary.place.coordinate).altitude) ?? -18
                    let center = CGPoint(x: min(width - 8, max(8, width * fraction)), y: compact ? h / 2 : y(altitude))
                    let dot = Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
                    context.fill(dot, with: .color(.white)); context.stroke(dot, with: .color(LPTheme.gold), lineWidth: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 12))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard width > 0 else { return }
                    // Instant updates while scrubbing; no spring follows the finger.
                    instant = VisualGeometry.instant(at: value.location.x / width, in: interval)
                    let altitude = (try? Astronomy.position(.sun, at: instant, coordinate: summary.place.coordinate).altitude) ?? -90
                    let band = Astronomy.lightBand(altitude: altitude)
                    if haptics, let lastBand, lastBand != band { hapticToken += 1 }
                    lastBand = band
                }.onEnded { _ in lastBand = nil })
            }.frame(height: compact ? 34 : 92)
            HStack(spacing: 0) {
                ForEach(0..<5) { index in
                    let date = VisualGeometry.instant(at: Double(index) / 4, in: interval)
                    Text(L10n.time(date, zone: summary.place.timeZone)).font(.caption2).monospacedDigit()
                    if index < 4 { Spacer(minLength: 0) }
                }
            }.foregroundStyle(.secondary).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(minHeight: compact ? 58 : 120)
        .sensoryFeedback(.selection, trigger: hapticToken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("map.timeSlider"))
        .accessibilityValue(L10n.time(instant, zone: summary.place.timeZone))
        .accessibilityAdjustableAction { direction in
            let change: Double = direction == .increment ? 60 : -60
            instant = VisualGeometry.instant(at: fraction + change / interval.duration, in: interval)
        }
        .accessibilityIdentifier("solar-timeline")
    }
    private func color(_ band: LightBand) -> Color {
        switch band {
        case .golden: return LPTheme.gold
        case .blue: return LPTheme.blue
        case .daylight: return Color(red: 0.96, green: 0.88, blue: 0.64)
        case .night: return LPTheme.ink
        case .astronomical: return Color(red: 0.17, green: 0.23, blue: 0.39)
        case .nautical: return Color(red: 0.30, green: 0.39, blue: 0.63)
        }
    }
}
