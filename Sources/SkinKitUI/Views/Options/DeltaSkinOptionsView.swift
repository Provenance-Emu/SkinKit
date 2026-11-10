#if canImport(UIKit)
import SkinCatalogKit
import SkinKitCore
import SkinKitManager
import SkinKit2Bake
import SkinKit2Render
import SwiftUI

/// The skin options sheet: theme, alternate layout, which per-game layout applies, edit controls, reset and
/// export, for one skin in one game.
///
/// Present it from a pause menu or an in-game menu, inside the host's own `NavigationStack` and sheet. Create one
/// `DeltaSkinLayoutEdits` and pass it to both this sheet and the skin view, which then draws the edits, offers the
/// move, pinch and reset overlay in edit mode, and redraws after a reset here:
///
/// ```swift
/// DeltaSkinView(skin: skin, traits: traits, inputHandler: handler,
///               isEditMode: $isEditMode, layoutEdits: layoutEdits)
///
/// .sheet(isPresented: $showsSkinOptions) {
///     NavigationStack {
///         DeltaSkinOptionsView(
///             skin: skin,
///             traits: traits,
///             gameId: game.id,
///             gameTitle: game.title,
///             layoutEdits: layoutEdits,                 // the instance the skin view reads
///             onAltRepresentationsChanged: { _ in rebuildTraits() },
///             onEditControls: { showsSkinOptions = false; isEditMode = true },
///             onLayoutEditsReset: { redrawSkin() },
///             onExport: { exportEditedSkin() }          // nil hides the row
///         )
///         .toolbar { Button("Done") { showsSkinOptions = false } }
///     }
/// }
/// ```
///
/// Each row shows only when it applies:
/// - **Theme**: ``DeltaSkinThemePickerView``, when the skin has `themes`. It saves through `preferences` and
///   redraws any skin view already on screen.
/// - **Alternate layout**: when the skin has `altRepresentations` and there is a game to store the choice
///   under (`gameId`, or the game keys in `traits`).
/// - **Layout for: <game>**: read-only, when a `gameOverrides` key matched the game.
/// - **Edit controls**: when `onEditControls` is set. Not offered on tvOS.
/// - **Reset edits for this skin**: with "Edit controls"; disabled until something is edited. Clears every
///   orientation's edits, after a confirmation.
/// - **Export**: when `onExport` is set.
public struct DeltaSkinOptionsView: View {
    let skin: any DeltaSkinRenderable
    let traits: DeltaSkinTraits
    let gameId: String?
    let gameTitle: String?
    let altRepresentationsStore: any DeltaSkinAltRepresentationsStoring
    let preferences: DeltaSkinPreferences
    let layoutEdits: DeltaSkinLayoutEdits
    let exportTitle: String
    let onAltRepresentationsChanged: ((Bool) -> Void)?
    let onEditControls: (() -> Void)?
    let onLayoutEditsReset: (() -> Void)?
    let onExport: (() -> Void)?

    @State private var usesAlt = false
    @State private var hasEdits = false
    @State private var confirmsReset = false
    #if os(iOS)
    @State private var classicExport: ClassicExport?
    @State private var exportingClassic = false
    @State private var exportError: String?
    #endif

    private var format2Source: Skin2SourceInfo? {
        #if os(iOS)
        Skin2SourceInfo(infoJSON: skin.jsonRepresentation)
        #else
        nil
        #endif
    }

    /// - Parameters:
    ///   - skin: The skin in use.
    ///   - traits: The traits it is drawn with, including the game candidates (`gameIdentifiers`) that pick a
    ///     `gameOverrides` layout.
    ///   - gameId: What the game's skin pick is stored under (Provenance passes `PVGame.id`). When `nil`, the
    ///     first of `traits.gameIdentifiers` is used. With neither, the alternate-layout toggle is hidden.
    ///   - gameTitle: The name to show in "Layout for:"; the matched `gameOverrides` key (often a hash) when `nil`.
    ///   - altRepresentationsStore: Where the alternate-layout choice lives. `nil` uses
    ///     `DeltaSkinSelectionManager.shared`, which posts `altRepresentationsChangedNotification`.
    ///   - preferences: Where the theme choice lives.
    ///   - layoutEdits: The edit store the skin view and ``DeltaSkinEditModeOverlay`` use. Share one instance.
    ///   - exportTitle: The export row's title.
    ///   - onAltRepresentationsChanged: Called after the toggle is saved, with the new value. Rebuild the
    ///     traits with `withAltRepresentations(_:)` so the skin redraws.
    ///   - onEditControls: Called when the player taps "Edit controls". Dismiss the sheet and enter edit mode.
    ///   - onLayoutEditsReset: Called after "Reset edits for this skin" cleared the store.
    ///   - onExport: Called when the player taps the export row. The row is hidden when `nil`.
    public init(
        skin: any DeltaSkinRenderable,
        traits: DeltaSkinTraits,
        gameId: String? = nil,
        gameTitle: String? = nil,
        altRepresentationsStore: (any DeltaSkinAltRepresentationsStoring)? = nil,
        preferences: DeltaSkinPreferences = .shared,
        layoutEdits: DeltaSkinLayoutEdits,
        exportTitle: String = "Export as new skin",
        onAltRepresentationsChanged: ((Bool) -> Void)? = nil,
        onEditControls: (() -> Void)? = nil,
        onLayoutEditsReset: (() -> Void)? = nil,
        onExport: (() -> Void)? = nil
    ) {
        self.skin = skin
        self.traits = traits
        self.gameId = gameId
        self.gameTitle = gameTitle
        self.altRepresentationsStore = altRepresentationsStore ?? SelectionManagerAltRepresentationsStore()
        self.preferences = preferences
        self.layoutEdits = layoutEdits
        self.exportTitle = exportTitle
        self.onAltRepresentationsChanged = onAltRepresentationsChanged
        self.onEditControls = onEditControls
        self.onLayoutEditsReset = onLayoutEditsReset
        self.onExport = onExport
    }

    private var model: DeltaSkinOptionsModel {
        DeltaSkinOptionsModel(
            hasThemes: !skin.availableThemes.isEmpty,
            hasAltRepresentations: skin.hasAltRepresentations,
            altGameKeys: altGameKeys,
            matchedOverrideKey: DeltaSkinOptionsModel.matchedOverrideKey(skin: skin, traits: traits),
            gameTitle: gameTitle,
            canEditControls: Self.supportsEditing && onEditControls != nil,
            canExport: onExport != nil,
            hasEdits: hasEdits
        )
    }

    private var altGameKeys: [String] {
        DeltaSkinOptionsModel.altGameKeys(gameId: gameId, traitGameKeys: traits.gameIdentifiers)
    }

    /// The edit gestures need `DragGesture` and `MagnifyGesture`, which tvOS does not have.
    private static var supportsEditing: Bool {
        #if os(tvOS)
        false
        #else
        true
        #endif
    }

    public var body: some View {
        let model = model
        Form {
            Section {
                Text(skin.name)
                    .font(.headline)
            }

            if model.showsThemePicker {
                Section("Theme") {
                    DeltaSkinThemePickerView(skin: skin, preferences: preferences)
                }
            }

            if model.showsAltToggle || model.gameOverrideLine != nil {
                Section("Layout") {
                    if model.showsAltToggle {
                        Toggle("Alternate layout", isOn: altBinding)
                    }
                    if let line = model.gameOverrideLine {
                        Text(line)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.showsEditControls || model.showsExport || format2Source != nil {
                Section("Controls") {
                    if model.showsEditControls {
                        Button {
                            onEditControls?()
                        } label: {
                            Label("Edit controls", systemImage: "hand.draw")
                        }
                        Button(role: .destructive) {
                            confirmsReset = true
                        } label: {
                            Label("Reset edits for this skin", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(!model.resetEnabled)
                    }
                    #if os(iOS)
                    if let source = format2Source {
                        Button {
                            exportClassic(source: source.source)
                        } label: {
                            Label("Export as classic skin", systemImage: "square.and.arrow.up")
                        }
                        .disabled(exportingClassic)
                    }
                    #endif
                    if model.showsExport {
                        Button {
                            onExport?()
                        } label: {
                            Label(exportTitle, systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("Skin options")
        .onAppear(perform: refresh)
        #if os(iOS)
        .sheet(item: $classicExport) { export in
            ShareSheet(activityItems: export.files)
                .onDisappear { try? FileManager.default.removeItem(at: export.directory) }
        }
        .alert("Could not export skin", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        #endif
        .confirmationDialog(
            "Reset every control you moved or resized on this skin?",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Reset edits", role: .destructive, action: resetEdits)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets every orientation.")
        }
    }

    #if os(iOS)
    private struct ClassicExport: Identifiable, Sendable {
        let directory: URL
        let files: [URL]
        var id: URL { directory }
    }

    @MainActor
    private func exportClassic(source: String) {
        let bundle = skin.fileURL
        exportingClassic = true
        Task {
            defer { exportingClassic = false }
            do {
                classicExport = try await Task.detached(priority: .userInitiated) {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    do {
                        let baked = try Skin2Baker.bake(bundleURL: bundle, sourcePath: source)
                        return ClassicExport(directory: directory, files: try Skin2Baker.write(baked, to: directory))
                    } catch {
                        try? FileManager.default.removeItem(at: directory)
                        throw error
                    }
                }.value
            } catch {
                exportError = String(describing: error)
            }
        }
    }
    #endif

    // MARK: Alternate layout

    private var altBinding: Binding<Bool> {
        Binding(
            get: { usesAlt },
            set: { newValue in
                let keys = altGameKeys
                guard let primary = keys.first else { return }
                altRepresentationsStore.setUsesAltRepresentations(
                    newValue,
                    skinIdentifier: skin.identifier,
                    gameId: primary,
                    otherGameKeys: Array(keys.dropFirst())
                )
                usesAlt = newValue
                onAltRepresentationsChanged?(newValue)
            }
        )
    }

    // MARK: State

    private func refresh() {
        let keys = altGameKeys
        usesAlt = keys.isEmpty ? false : altRepresentationsStore.usesAltRepresentations(skinIdentifier: skin.identifier, gameIds: keys)
        hasEdits = layoutEdits.hasEdits(skinIdentifier: skin.identifier)
    }

    private func resetEdits() {
        do {
            try layoutEdits.resetAll(skinIdentifier: skin.identifier)
        } catch {
            WLOG("DeltaSkinOptionsView: could not reset edits for \(skin.identifier): \(error)")
        }
        hasEdits = layoutEdits.hasEdits(skinIdentifier: skin.identifier)
        onLayoutEditsReset?()
    }
}

/// Forwards the alternate-layout choice to `DeltaSkinSelectionManager.shared`, so the change is posted as
/// `altRepresentationsChangedNotification` and a running game re-lays out.
private final class SelectionManagerAltRepresentationsStore: DeltaSkinAltRepresentationsStoring {
    func usesAltRepresentations(skinIdentifier: String, gameIds: [String]) -> Bool {
        DeltaSkinSelectionManager.shared.usesAltRepresentations(skinIdentifier: skinIdentifier, gameIds: gameIds)
    }

    @MainActor
    func setUsesAltRepresentations(_ usesAlt: Bool, skinIdentifier: String, gameId: String, otherGameKeys: [String]) {
        DeltaSkinSelectionManager.shared.setUsesAltRepresentations(
            usesAlt, skinIdentifier: skinIdentifier, gameId: gameId, otherGameKeys: otherGameKeys
        )
    }
}
#endif
