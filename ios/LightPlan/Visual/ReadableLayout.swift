import SwiftUI

/// Keep the standard two-column presentation at normal sizes. Accessibility text
/// gets the full available line width instead of narrow, competing label columns.
struct LPReadableMetricStyle: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                configuration.label.fixedSize(horizontal: false, vertical: true)
                configuration.content.foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline) {
                configuration.label
                Spacer(minLength: 12)
                configuration.content.foregroundStyle(.secondary)
            }
        }
    }
}

/// Inline navigation bars cannot display long translated headings at AX sizes.
/// The full heading lives in scrollable content without reducing the user's font.
struct LPExpandedSheetTitle: View {
    let key: String
    let identifier: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            KeyText(key).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier(identifier)
        }
    }
}
