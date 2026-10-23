#if canImport(UIKit)
import SkinKitCore
import SkinKitManager
import SkinCatalogKit
import SwiftUI

/// A segmented control for selecting a named visual theme variant for a skin.
/// Hidden automatically when the skin has no themes.
public struct DeltaSkinThemePickerView: View {
    let skin: any DeltaSkinRenderable
    @State private var selectedId: String?
    let preferences: DeltaSkinPreferences

    public init(skin: any DeltaSkinRenderable, preferences: DeltaSkinPreferences = .shared) {
        self.skin = skin
        self.preferences = preferences
    }

    public var body: some View {
        if skin.availableThemes.isEmpty {
            EmptyView()
        } else {
            Picker("Theme", selection: $selectedId) {
                Text("Default").tag(Optional<String>.none)
                ForEach(skin.availableThemes) { theme in
                    Text(theme.name).tag(Optional(theme.id))
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onAppear {
                selectedId = preferences.selectedThemeId(for: skin.identifier)
            }
            .onChange(of: selectedId) { newId in
                preferences.setSelectedThemeId(newId, for: skin.identifier)
            }
        }
    }
}
#endif
