import FamilyControls
import SwiftUI

/// Dünner Wrapper um Apples `FamilyActivityPicker`.
///
/// Der Picker liefert opake Tokens statt Bundle-IDs – die App erfährt nie,
/// welche Apps ausgewählt wurden. Das ist Apples Datenschutzmodell und der
/// Grund, warum die Oberfläche nur "X Apps ausgewählt" anzeigen kann.
struct AppSelectionView: View {
    @Binding var selection: FamilyActivitySelection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Apps auswählen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
    }
}
