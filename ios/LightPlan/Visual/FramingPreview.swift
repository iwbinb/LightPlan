import SwiftUI
import LightPlanCore

struct FramingPreviewRequest: Identifiable {
    let id = UUID()
    let place: Place
    let subject: Coordinate
    let body: CelestialBody
    let instant: Date
    let framing: CameraFraming?
}

struct FramingPreviewSheet: View {
    let request: FramingPreviewRequest
    var allowsTimeEditing = true
    var onApply: (CameraFraming, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var focalLength: String
    @State private var referenceAngle: String
    @State private var orientation: FrameOrientation
    @State private var instant: Date
    private enum Field { case focalLength, referenceAngle }
    @FocusState private var focusedField: Field?

    init(request: FramingPreviewRequest, allowsTimeEditing: Bool = true, onApply: @escaping (CameraFraming, Date) -> Void) {
        self.request = request; self.allowsTimeEditing = allowsTimeEditing; self.onApply = onApply
        _focalLength = State(initialValue: String(request.framing?.focalLength35mm ?? 50))
        _referenceAngle = State(initialValue: String(request.framing?.referenceAltitudeDegrees ?? 0))
        _orientation = State(initialValue: request.framing?.orientation ?? .landscape)
        _instant = State(initialValue: request.instant)
    }

    private var framing: CameraFraming? {
        guard let focal = Double(focalLength.replacingOccurrences(of: ",", with: ".")),
              let angle = Double(referenceAngle.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return try? CameraFraming(focalLength35mm: focal, orientation: orientation, referenceAltitudeDegrees: angle)
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = request.place.timeZone; return value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LPExpandedSheetTitle(key: "frame.title", identifier: "frame-full-title")
                    if let framing {
                        FramingDiagram(framing: framing, place: request.place, subject: request.subject,
                                       celestialBody: request.body, instant: instant)
                    } else { KeyText("frame.invalid").foregroundStyle(.red) }
                    LPCard {
                        VStack(alignment: .leading, spacing: 14) {
                            KeyText("frame.focalLength").font(.headline)
                            HStack {
                                TextField(L10n.text("frame.focalLength"), text: $focalLength)
                                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .focalLength).accessibilityIdentifier("frame-focal-length")
                                Text(verbatim: "mm")
                            }
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach([24, 50, 85, 135, 200, 400], id: \.self) { value in
                                        Button { focalLength = String(value); focusedField = nil } label: {
                                            Text(verbatim: "\(value) mm")
                                        }.buttonStyle(.bordered).accessibilityIdentifier("frame-focal-\(value)")
                                    }
                                }
                            }
                            KeyText("frame.focalHint").font(.caption).foregroundStyle(.secondary)
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 8) {
                                    KeyText("frame.orientation").font(.headline)
                                        .accessibilityIdentifier("frame-orientation")
                                    ForEach([FrameOrientation.landscape, .portrait], id: \.self) { value in
                                        Button { orientation = value; focusedField = nil } label: {
                                            HStack {
                                                Text(L10n.text("frame." + value.rawValue))
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Spacer(minLength: 8)
                                                if orientation == value { Image(systemName: "checkmark").accessibilityHidden(true) }
                                            }.frame(maxWidth: .infinity, minHeight: 44)
                                        }.buttonStyle(.bordered)
                                            .accessibilityAddTraits(orientation == value ? .isSelected : [])
                                            .accessibilityIdentifier("frame-orientation-" + value.rawValue)
                                    }
                                }
                            } else {
                                Picker(L10n.text("frame.orientation"), selection: $orientation) {
                                    Text(L10n.text("frame.landscape")).tag(FrameOrientation.landscape)
                                    Text(L10n.text("frame.portrait")).tag(FrameOrientation.portrait)
                                }.pickerStyle(.segmented).accessibilityIdentifier("frame-orientation")
                            }
                            KeyText("frame.referenceAltitude").font(.headline)
                            HStack {
                                TextField(L10n.text("frame.referenceAltitude"), text: $referenceAngle)
                                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .referenceAngle).accessibilityIdentifier("frame-reference-angle")
                                Text(verbatim: "°")
                            }
                            Slider(value: Binding(get: {
                                min(60, max(-30, Double(referenceAngle.replacingOccurrences(of: ",", with: ".")) ?? 0))
                            }, set: { referenceAngle = String($0); focusedField = nil }), in: -30...60, step: 0.5)
                                .accessibilityLabel(L10n.text("frame.referenceAltitude"))
                                .accessibilityIdentifier("frame-reference-slider")
                            KeyText("frame.referenceHint").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LPCard {
                        VStack(alignment: .leading, spacing: 10) {
                            KeyText("frame.atSelectedTime").font(.headline)
                            Text(L10n.time(instant, zone: request.place.timeZone)).font(.title2.monospacedDigit())
                                .accessibilityIdentifier("frame-selected-time")
                            if allowsTimeEditing, let interval = try? LocalDay.interval(containing: request.instant, timeZone: request.place.timeZone) {
                                DatePicker(L10n.text("frame.atSelectedTime"), selection: $instant,
                                           in: interval.start...interval.end.addingTimeInterval(-1), displayedComponents: .hourAndMinute)
                                    .environment(\.timeZone, request.place.timeZone).environment(\.calendar, calendar)
                                    .accessibilityIdentifier("frame-time")
                                Slider(value: Binding(get: { instant.timeIntervalSince1970 },
                                                      set: { instant = Date(timeIntervalSince1970: $0) }),
                                       in: interval.start.timeIntervalSince1970...interval.end.addingTimeInterval(-1).timeIntervalSince1970)
                                    .accessibilityLabel(L10n.text("map.timeSlider"))
                            }
                            Text(L10n.fullDate(instant, zone: request.place.timeZone) + " · " + request.place.timeZoneID
                                 + " · " + L10n.utcOffset(at: instant, zone: request.place.timeZone)).font(.caption)
                        }
                    }
                    KeyText("frame.modelNote").font(.footnote).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(LPTheme.canvas).scrollDismissesKeyboard(.interactively)
                .navigationTitle(typeSize.isAccessibilitySize ? "" : L10n.text("frame.title"))
                .presentationBackground(LPTheme.canvas)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("common.cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            if let framing { onApply(framing, instant); dismiss() }
                        } label: { Image(systemName: "checkmark").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel(L10n.text("frame.apply"))
                        .disabled(framing == nil).accessibilityIdentifier("frame-apply")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Button { focusedField = .focalLength } label: { Image(systemName: "arrow.up") }
                            .accessibilityLabel(L10n.text("frame.focalLength"))
                        Button { focusedField = .referenceAngle } label: { Image(systemName: "arrow.down") }
                            .accessibilityLabel(L10n.text("frame.referenceAltitude"))
                        Spacer()
                        Button { focusedField = nil } label: { Image(systemName: "keyboard.chevron.compact.down") }
                            .accessibilityLabel(L10n.text("keyboard.dismiss"))
                    }
                }
        }
    }
}

/// A geometric diagram, never a synthetic photograph or camera/terrain view.
struct FramingDiagram: View {
    let framing: CameraFraming
    let place: Place
    let subject: Coordinate
    let celestialBody: CelestialBody
    let instant: Date
    var compact = false

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let projection = try? framing.project(body: celestialBody, at: instant, observer: place.coordinate, subject: subject) {
                Canvas { context, size in
                    let w = size.width, h = size.height
                    var grid = Path()
                    for fraction in [1.0 / 3, 2.0 / 3] {
                        grid.move(to: CGPoint(x: w * fraction, y: 0)); grid.addLine(to: CGPoint(x: w * fraction, y: h))
                        grid.move(to: CGPoint(x: 0, y: h * fraction)); grid.addLine(to: CGPoint(x: w, y: h * fraction))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.14)), lineWidth: 1)
                    if let horizon = try? framing.project(bodyAzimuthDegrees: projection.cameraBearingDegrees,
                        bodyAltitudeDegrees: 0, angularDiameterDegrees: 0.0001,
                        cameraBearingDegrees: projection.cameraBearingDegrees).bodyNormalizedCenter,
                       (0...1).contains(horizon.y) {
                        var line = Path(); line.move(to: CGPoint(x: 0, y: h * horizon.y)); line.addLine(to: CGPoint(x: w, y: h * horizon.y))
                        context.stroke(line, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                    if let first = projection.bodyOutline.first {
                        var disc = Path(); disc.move(to: CGPoint(x: first.x * w, y: first.y * h))
                        for point in projection.bodyOutline.dropFirst() { disc.addLine(to: CGPoint(x: point.x * w, y: point.y * h)) }
                        disc.closeSubpath()
                        context.fill(disc, with: .color(celestialBody == .sun ? LPTheme.gold : .white))
                    }
                    var cross = Path()
                    for sign in [-1.0, 1.0] {
                        cross.move(to: CGPoint(x: w / 2 + sign * 5, y: h / 2)); cross.addLine(to: CGPoint(x: w / 2 + sign * 12, y: h / 2))
                        cross.move(to: CGPoint(x: w / 2, y: h / 2 + sign * 5)); cross.addLine(to: CGPoint(x: w / 2, y: h / 2 + sign * 12))
                    }
                    context.stroke(cross, with: .color(LPTheme.blue), lineWidth: 1.5)
                }
                .background(LPTheme.ink)
                .clipped()
                .overlay(Rectangle().stroke(.secondary.opacity(0.35), lineWidth: 1))
                .accessibilityLabel(L10n.text("frame.title"))
                .accessibilityValue(L10n.text("frame." + projection.visibility.rawValue))
                .accessibilityIdentifier("framing-diagram")
                .aspectRatio(framing.frameAspectRatio, contentMode: .fit)
                .frame(maxHeight: compact ? 260 : 390)
                .frame(maxWidth: .infinity, alignment: .center)
                Text(L10n.text("frame." + projection.visibility.rawValue)).font(.headline)
                    .accessibilityIdentifier("frame-visibility")
                KeyText("frame.legend").font(.caption).foregroundStyle(.secondary)
                LabeledContent(L10n.text("frame.focalLength"), value: L10n.focalLength(framing.focalLength35mm) + " mm")
                    .accessibilityIdentifier("frame-focal-summary")
                LabeledContent(L10n.text("frame.referenceAltitude"), value: L10n.number(framing.referenceAltitudeDegrees, decimals: 1) + "°")
                    .accessibilityIdentifier("frame-angle-summary")
                if !compact {
                    LabeledContent(L10n.text("composition.altitude"), value: L10n.number(projection.bodyAltitudeDegrees, decimals: 1) + "°")
                    LabeledContent(L10n.text("frame.horizontalFoV"), value: L10n.number(framing.horizontalFieldOfViewDegrees, decimals: 1) + "°")
                    LabeledContent(L10n.text("frame.verticalFoV"), value: L10n.number(framing.verticalFieldOfViewDegrees, decimals: 1) + "°")
                    LabeledContent(L10n.text("frame.angularSize"), value: L10n.number(projection.angularDiameterDegrees, decimals: 3) + "°")
                }
            } else { KeyText("error.calculation").foregroundStyle(.secondary) }
        }
    }

    var body: some View { bodyView.labeledContentStyle(LPReadableMetricStyle()) }
}
