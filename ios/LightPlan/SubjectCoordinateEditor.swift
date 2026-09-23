import SwiftUI
import LightPlanCore

/// Coordinate entry is also a nonvisual alternative to selecting a pin on the map.
struct SubjectCoordinateEditor: View {
    let observer: Coordinate
    let subject: Coordinate?
    var onSave: (Coordinate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var invalid = false
    private enum Field: Hashable { case latitude, longitude }
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section(L10n.text("place.latitude")) {
            TextField(L10n.text("place.latitude"), text: $latitude)
                .keyboardType(.numbersAndPunctuation).accessibilityIdentifier("subject-latitude")
                .focused($focusedField, equals: .latitude).submitLabel(.next)
                .onSubmit { focusedField = .longitude }
            }
            Section(L10n.text("place.longitude")) {
            TextField(L10n.text("place.longitude"), text: $longitude)
                .keyboardType(.numbersAndPunctuation).accessibilityIdentifier("subject-longitude")
                .focused($focusedField, equals: .longitude).submitLabel(.done)
                .onSubmit { focusedField = nil }
            }
            if invalid { KeyText("error.coordinate").foregroundStyle(.red) }
            Button(L10n.text("common.use"), action: save).accessibilityIdentifier("subject-save")
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(L10n.text("composition.subject"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L10n.text("common.cancel")) { dismiss() } }
            ToolbarItemGroup(placement: .keyboard) {
                Button { focusedField = .latitude } label: { Image(systemName: "arrow.up") }
                    .accessibilityLabel(L10n.text("place.latitude"))
                Button { focusedField = .longitude } label: { Image(systemName: "arrow.down") }
                    .accessibilityLabel(L10n.text("place.longitude")).accessibilityIdentifier("subject-next-field")
                Spacer()
                Button { focusedField = nil } label: { Image(systemName: "keyboard.chevron.compact.down") }
                    .accessibilityLabel(L10n.text("keyboard.dismiss")).accessibilityIdentifier("subject-dismiss-keyboard")
            }
        }
        .onAppear {
            if let subject { latitude = String(subject.latitude); longitude = String(subject.longitude) }
        }
    }

    private func save() {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              let coordinate = try? Coordinate(latitude: lat, longitude: lon),
              Geometry.bearing(from: observer, to: coordinate) != nil else { invalid = true; return }
        onSave(coordinate); dismiss()
    }
}
