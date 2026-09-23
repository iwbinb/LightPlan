import SwiftUI

enum LPTheme {
    static let ink = Color(red: 0.075, green: 0.12, blue: 0.16)
    static let accent = Color(red: 0.07, green: 0.38, blue: 0.69)
    static let gold = Color(red: 1, green: 0.69, blue: 0.18)
    static let sunset = Color(red: 0.98, green: 0.37, blue: 0.21)
    static let blue = Color(red: 0.19, green: 0.57, blue: 0.91)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let radius: CGFloat = 26
}
struct LPCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LPTheme.surface, in: RoundedRectangle(cornerRadius: LPTheme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LPTheme.radius).stroke(.primary.opacity(0.05), lineWidth: 0.5))
    }
}
struct KeyText: View {
    let key: String
    init(_ key: String) { self.key = key }
    @AppStorage("language") private var language = "system"
    var body: some View { Text(L10n.text(key, language: language)) }
}
/// Glass only on controls, never a stack of blur layers behind long-form data.
struct LPGlassSurface: ViewModifier {
    var radius: CGFloat = 22
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(scheme == .dark ? LPTheme.ink : .white, in: RoundedRectangle(cornerRadius: radius))
        } else {
            // Availability is not a claim about a device model. SDK 26+ builds use system glass.
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                legacy(content)
            }
            #else
            legacy(content)
            #endif
        }
    }
    private func legacy(_ content: Content) -> some View {
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.25), lineWidth: 0.5))
    }
}
extension View {
    func lpGlass(radius: CGFloat = 22) -> some View { modifier(LPGlassSurface(radius: radius)) }
}
struct LPPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
struct LPPhotoHero<Content: View>: View {
    var asset: String = "hero-coastal"
    var minimumHeight: CGFloat = 350
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(24).frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .bottomLeading)
            .background {
                GeometryReader { proxy in
                    Image(asset).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                        .overlay(LinearGradient(stops: [.init(color: .black.opacity(0.20), location: 0), .init(color: .clear, location: 0.25), .init(color: .black.opacity(0.78), location: 1)], startPoint: .top, endPoint: .bottom))
                }
                // Scaled images may extend beyond their clipped visual bounds.
                // Decorative pixels must never cover neighbouring controls' taps.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .contain)
    }
}
struct LPCircleButton: View {
    let symbol: String
    let label: String
    let identifier: String?
    var action: () -> Void

    init(symbol: String, label: String, identifier: String? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .lpGlass(radius: 23)
                .contentShape(Circle())
        }
        .buttonStyle(LPPressStyle())
        .accessibilityLabel(L10n.text(label))
        .accessibilityIdentifier(identifier ?? label)
    }
}

struct LPPhaseLabel: View {
    let key: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        KeyText(key).contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: key)
    }
}
