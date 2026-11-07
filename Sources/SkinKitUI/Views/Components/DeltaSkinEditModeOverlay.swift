import CoreGraphics
import Foundation
import SkinKitCore
import SkinKitManager

// MARK: - Edit math (no UI; runs in `swift test` on the host)

/// The two coordinate spaces the editor works in: the skin's mapping space (what `DeltaSkinButton.frame` and
/// `DeltaSkinButtonEdit` use) and the on-screen container the skin is drawn into.
struct DeltaSkinEditGeometry: Equatable {
    var mappingSize: CGSize
    var containerSize: CGSize

    /// `false` when either size is empty, in which case every conversion returns zero.
    var isValid: Bool {
        mappingSize.width > 0 && mappingSize.height > 0 && containerSize.width > 0 && containerSize.height > 0
    }

    /// A screen-space delta (points) in mapping points.
    func mappingDelta(forScreenDelta delta: CGSize) -> CGPoint {
        guard isValid else { return .zero }
        return CGPoint(
            x: delta.width / containerSize.width * mappingSize.width,
            y: delta.height / containerSize.height * mappingSize.height
        )
    }

    /// A frame in mapping points as a rect in the container.
    func screenRect(forMappingRect rect: CGRect) -> CGRect {
        guard isValid else { return .zero }
        let sx = containerSize.width / mappingSize.width
        let sy = containerSize.height / mappingSize.height
        return CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
    }

    // MARK: Clamping

    /// `edit` with its move nudged so the edited frame stays inside the mapping area.
    ///
    /// The frame that has to fit is the one *after* scaling (`edit.applying(to:)`), so a button that grows
    /// near an edge slides back in. A frame larger than the area on an axis is centered on it. The scale is
    /// clamped to `DeltaSkinButtonEdit.scaleRange` first.
    func clamped(_ edit: DeltaSkinButtonEdit, baseFrame: CGRect) -> DeltaSkinButtonEdit {
        var result = edit.normalized
        guard mappingSize.width > 0, mappingSize.height > 0 else { return result }
        let frame = result.applying(to: baseFrame)
        result.dx += Self.shift(lower: frame.minX, upper: frame.maxX, limit: mappingSize.width)
        result.dy += Self.shift(lower: frame.minY, upper: frame.maxY, limit: mappingSize.height)
        return result
    }

    private static func shift(lower: Double, upper: Double, limit: Double) -> Double {
        if upper - lower >= limit { return limit / 2 - (lower + upper) / 2 }
        if lower < 0 { return -lower }
        if upper > limit { return limit - upper }
        return 0
    }

    // MARK: Gestures

    /// `edit` after a drag of `screenTranslation` (screen points) from its current position.
    func dragged(_ edit: DeltaSkinButtonEdit, by screenTranslation: CGSize, baseFrame: CGRect) -> DeltaSkinButtonEdit {
        let delta = mappingDelta(forScreenDelta: screenTranslation)
        var moved = edit
        moved.dx += Double(delta.x)
        moved.dy += Double(delta.y)
        return clamped(moved, baseFrame: baseFrame)
    }

    /// `edit` after a pinch of `magnification` (1 = no change) from its current size.
    ///
    /// The scale is the size the pinch started at times the magnification, clamped to
    /// `DeltaSkinButtonEdit.scaleRange`. A non-finite or non-positive magnification changes nothing.
    func pinched(_ edit: DeltaSkinButtonEdit, by magnification: Double, baseFrame: CGRect) -> DeltaSkinButtonEdit {
        guard magnification.isFinite, magnification > 0 else { return clamped(edit, baseFrame: baseFrame) }
        var scaled = edit
        scaled.scale = edit.scale * magnification
        return clamped(scaled, baseFrame: baseFrame)
    }
}

/// What the edit overlay is doing for one skin and one trait: the committed edits, the selected button,
/// and the saves. The overlay is a thin view over this, so the behavior is testable without UI.
///
/// The store is not observable, so the session keeps its own copy of the trait's edits (loaded once,
/// updated on every save) and the view redraws from that.
@MainActor
final class DeltaSkinEditSession: ObservableObject {
    let store: DeltaSkinLayoutEdits
    let skinIdentifier: String
    let traitKey: String

    /// The committed edit per button id; identity edits are absent.
    @Published private(set) var edits: [String: DeltaSkinButtonEdit]

    /// The button the last tap selected ("Reset this button" acts on it).
    @Published private(set) var selectedButtonId: String?

    /// The last save error, kept for tests; also logged.
    private(set) var lastSaveError: Error?

    init(store: DeltaSkinLayoutEdits, skinIdentifier: String, traitKey: String) {
        self.store = store
        self.skinIdentifier = skinIdentifier
        self.traitKey = traitKey
        edits = store.edits(skinIdentifier: skinIdentifier, traitKey: traitKey)
    }

    /// Re-reads the trait's edits from the store (after something else changed them).
    func reload() {
        edits = store.edits(skinIdentifier: skinIdentifier, traitKey: traitKey)
    }

    func edit(for buttonId: String) -> DeltaSkinButtonEdit { edits[buttonId] ?? .identity }

    /// `true` when this trait has any edit ("Reset all" is offered).
    var hasEdits: Bool { !edits.isEmpty }

    /// `true` when the selected button has an edit ("Reset this button" is offered).
    var selectedHasEdit: Bool { selectedButtonId.map { edits[$0] != nil } ?? false }

    // MARK: Selection

    func select(_ buttonId: String?) { selectedButtonId = buttonId }

    // MARK: Live preview (nothing saved)

    /// The edit to draw while a drag and/or a pinch is in progress.
    func liveEdit(
        for buttonId: String,
        baseFrame: CGRect,
        translation: CGSize,
        magnification: Double,
        geometry: DeltaSkinEditGeometry
    ) -> DeltaSkinButtonEdit {
        var edit = geometry.pinched(self.edit(for: buttonId), by: magnification, baseFrame: baseFrame)
        if translation != .zero { edit = geometry.dragged(edit, by: translation, baseFrame: baseFrame) }
        return edit
    }

    // MARK: Commits (saved)

    /// Saves a finished drag.
    func commitDrag(_ buttonId: String, translation: CGSize, baseFrame: CGRect, geometry: DeltaSkinEditGeometry) {
        save(geometry.dragged(edit(for: buttonId), by: translation, baseFrame: baseFrame), for: buttonId)
    }

    /// Saves a finished pinch.
    func commitPinch(_ buttonId: String, magnification: Double, baseFrame: CGRect, geometry: DeltaSkinEditGeometry) {
        save(geometry.pinched(edit(for: buttonId), by: magnification, baseFrame: baseFrame), for: buttonId)
    }

    // MARK: Resets

    /// Removes the selected button's edit.
    func resetSelected() {
        guard let selectedButtonId else { return }
        save(.identity, for: selectedButtonId)
    }

    /// Removes every edit on this trait (the layout on screen). Other orientations and display types keep theirs.
    func resetAllInTrait() {
        do {
            try store.resetTrait(skinIdentifier: skinIdentifier, traitKey: traitKey)
            lastSaveError = nil
            edits = [:]
        } catch {
            lastSaveError = error
            WLOG("DeltaSkinEditSession: could not reset edits for \(skinIdentifier) \(traitKey): \(error)")
        }
    }

    private func save(_ edit: DeltaSkinButtonEdit, for buttonId: String) {
        let normalized = edit.normalized
        do {
            try store.setEdit(normalized, forButton: buttonId, skinIdentifier: skinIdentifier, traitKey: traitKey)
            lastSaveError = nil
            if normalized.isIdentity { edits.removeValue(forKey: buttonId) } else { edits[buttonId] = normalized }
        } catch {
            lastSaveError = error
            WLOG("DeltaSkinEditSession: could not save edit for \(buttonId) in \(skinIdentifier): \(error)")
        }
    }
}

#if canImport(UIKit)
import SkinCatalogKit
import SwiftUI

// MARK: - Edit-mode overlay

/// An overlay rendered on top of `DeltaSkinView` while the player edits the controls.
///
/// Every button gets a highlight and can be dragged to move it, pinched to resize it (0.5x to 2x), and
/// tapped to select it. A bar at the top offers "Reset this button" (when the selected button has an edit),
/// "Reset all" and "Done". Screens have no handles.
///
/// ## Saving
/// Use ``init(skin:traits:mappingSize:containerSize:layoutEdits:onEditsChanged:onDone:)``. Each finished
/// gesture is written to the `DeltaSkinLayoutEdits` you pass, under `traits.layoutEditKey`
/// (`<device>.<displayType>.<orientation>`), so a change made in portrait does not touch landscape. "Reset all"
/// clears the layout on screen (that trait) only; ``DeltaSkinOptionsView`` has the reset for the whole skin.
/// Pass the same `DeltaSkinLayoutEdits` instance to everything that reads or writes edits: it caches.
///
/// The overlay does not draw the buttons. The skin view underneath has to read the same
/// `DeltaSkinLayoutEdits` (move and scale) to show the result; `onEditsChanged` fires after every save so the
/// host can redraw it.
///
/// The older ``init(skin:traits:mappingSize:containerSize:buttonOffsets:onOffsetChanged:)`` is kept so existing
/// call sites compile. It moves buttons only, through `DeltaSkinButtonOffsets`, with no bar.
///
/// ## tvOS
/// `DragGesture` and `MagnifyGesture` do not exist there. The overlay draws the highlights and the bar (its
/// buttons work with the focus engine) but cannot move or resize anything.
public struct DeltaSkinEditModeOverlay: View {

    let skin: any DeltaSkinRenderable
    let traits: DeltaSkinTraits
    let mappingSize: CGSize
    let containerSize: CGSize

    private let storage: Storage

    private enum Storage {
        case legacy(buttonOffsets: DeltaSkinButtonOffsets, onOffsetChanged: (String, CGPoint) -> Void)
        case layoutEdits(store: DeltaSkinLayoutEdits, onEditsChanged: (() -> Void)?, onDone: (() -> Void)?)
    }

    /// Edits that persist through `DeltaSkinLayoutEdits`, per orientation, with move, pinch and the reset bar.
    ///
    /// - Parameters:
    ///   - layoutEdits: The store to read and write. Share one instance with the skin view.
    ///   - onEditsChanged: Called after every saved gesture or reset, on the main actor.
    ///   - onDone: Called when the player taps "Done". The host leaves edit mode (`isEditMode = false`).
    public init(
        skin: any DeltaSkinRenderable,
        traits: DeltaSkinTraits,
        mappingSize: CGSize,
        containerSize: CGSize,
        layoutEdits: DeltaSkinLayoutEdits,
        onEditsChanged: (() -> Void)? = nil,
        onDone: (() -> Void)? = nil
    ) {
        self.skin = skin
        self.traits = traits
        self.mappingSize = mappingSize
        self.containerSize = containerSize
        storage = .layoutEdits(store: layoutEdits, onEditsChanged: onEditsChanged, onDone: onDone)
    }

    /// The original drag-only overlay, saving through `DeltaSkinButtonOffsets`. Prefer the
    /// `layoutEdits:` initializer.
    public init(
        skin: any DeltaSkinRenderable,
        traits: DeltaSkinTraits,
        mappingSize: CGSize,
        containerSize: CGSize,
        buttonOffsets: DeltaSkinButtonOffsets,
        onOffsetChanged: @escaping (String, CGPoint) -> Void
    ) {
        self.skin = skin
        self.traits = traits
        self.mappingSize = mappingSize
        self.containerSize = containerSize
        storage = .legacy(buttonOffsets: buttonOffsets, onOffsetChanged: onOffsetChanged)
    }

    public var body: some View {
        switch storage {
        case let .legacy(buttonOffsets, onOffsetChanged):
            DeltaSkinLegacyEditHandles(
                skin: skin,
                traits: traits,
                mappingSize: mappingSize,
                containerSize: containerSize,
                buttonOffsets: buttonOffsets,
                onOffsetChanged: onOffsetChanged
            )
        case let .layoutEdits(store, onEditsChanged, onDone):
            DeltaSkinLayoutEditCanvas(
                skin: skin,
                traits: traits,
                geometry: DeltaSkinEditGeometry(mappingSize: mappingSize, containerSize: containerSize),
                store: store,
                onEditsChanged: onEditsChanged,
                onDone: onDone
            )
            // A different orientation or display type is a different set of edits.
            .id(traits.layoutEditKey)
        }
    }
}

// MARK: - Layout-edits canvas

private struct DeltaSkinLayoutEditCanvas: View {
    let skin: any DeltaSkinRenderable
    let traits: DeltaSkinTraits
    let geometry: DeltaSkinEditGeometry
    let onEditsChanged: (() -> Void)?
    let onDone: (() -> Void)?

    @StateObject private var session: DeltaSkinEditSession
    @State private var liveTranslations: [String: CGSize] = [:]
    @State private var liveMagnifications: [String: Double] = [:]
    @State private var confirmsResetAll = false

    init(
        skin: any DeltaSkinRenderable,
        traits: DeltaSkinTraits,
        geometry: DeltaSkinEditGeometry,
        store: DeltaSkinLayoutEdits,
        onEditsChanged: (() -> Void)?,
        onDone: (() -> Void)?
    ) {
        self.skin = skin
        self.traits = traits
        self.geometry = geometry
        self.onEditsChanged = onEditsChanged
        self.onDone = onDone
        _session = StateObject(wrappedValue: DeltaSkinEditSession(
            store: store, skinIdentifier: skin.identifier, traitKey: traits.layoutEditKey
        ))
    }

    var body: some View {
        ZStack {
            // Dim the game so it is clear the layout is being edited.
            Color.black.opacity(0.35)
                .allowsHitTesting(false)

            if let buttons = skin.buttons(for: traits) {
                ForEach(buttons, id: \.id) { button in
                    handle(for: button)
                }
            }

            VStack {
                editBar
                Spacer()
            }
        }
        .onAppear { session.reload() }
    }

    // MARK: Per-button handle

    @ViewBuilder
    private func handle(for button: DeltaSkinButton) -> some View {
        let live = session.liveEdit(
            for: button.id,
            baseFrame: button.frame,
            translation: liveTranslations[button.id] ?? .zero,
            magnification: liveMagnifications[button.id] ?? 1,
            geometry: geometry
        )
        let rect = geometry.screenRect(forMappingRect: live.applying(to: button.frame))
        let isSelected = session.selectedButtonId == button.id
        // Tiny buttons still get a finger-sized target, centered on the button.
        let target = CGSize(width: max(rect.width, 44), height: max(rect.height, 44))

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.yellow : Color.white.opacity(0.8), lineWidth: isSelected ? 3 : 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(isSelected ? 0.3 : 0.15)))
                .frame(width: rect.width, height: rect.height)

            Image(systemName: "move.3d")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(4)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
        .frame(width: target.width, height: target.height)
        .position(x: rect.midX, y: rect.midY)
        .modifier(EditGestures(
            isSelected: isSelected,
            select: { session.select(button.id) },
            dragChanged: { liveTranslations[button.id] = $0 },
            dragEnded: { translation in
                session.commitDrag(button.id, translation: translation, baseFrame: button.frame, geometry: geometry)
                liveTranslations.removeValue(forKey: button.id)
                onEditsChanged?()
            },
            pinchChanged: { liveMagnifications[button.id] = $0 },
            pinchEnded: { magnification in
                session.commitPinch(button.id, magnification: magnification, baseFrame: button.frame, geometry: geometry)
                liveMagnifications.removeValue(forKey: button.id)
                onEditsChanged?()
            }
        ))
        .accessibilityLabel("\(button.id) button")
        .accessibilityHint("Drag to move, pinch to resize")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Bar

    private var editBar: some View {
        HStack(spacing: 10) {
            if session.selectedHasEdit {
                Button {
                    session.resetSelected()
                    onEditsChanged?()
                } label: {
                    Label("Reset this button", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(EditBarButtonStyle(tint: .orange))
            }

            if session.hasEdits {
                Button {
                    confirmsResetAll = true
                } label: {
                    Label("Reset all", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(EditBarButtonStyle(tint: .red))
            }

            Spacer(minLength: 0)

            Button {
                onDone?()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(EditBarButtonStyle(tint: .green))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .confirmationDialog("Reset every control on this layout?", isPresented: $confirmsResetAll, titleVisibility: .visible) {
            Button("Reset all", role: .destructive) {
                session.resetAllInTrait()
                liveTranslations.removeAll()
                liveMagnifications.removeAll()
                onEditsChanged?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only this orientation is reset.")
        }
    }
}

private struct EditBarButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tint.opacity(configuration.isPressed ? 0.6 : 0.85))
            .clipShape(Capsule())
    }
}

/// Tap to select, drag to move, pinch to resize. Compiled out on tvOS, where none of those gestures exist.
private struct EditGestures: ViewModifier {
    let isSelected: Bool
    let select: () -> Void
    let dragChanged: (CGSize) -> Void
    let dragEnded: (CGSize) -> Void
    let pinchChanged: (Double) -> Void
    let pinchEnded: (Double) -> Void

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.allowsHitTesting(false)
        #else
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isSelected { select() }
                        dragChanged(value.translation)
                    }
                    .onEnded { dragEnded($0.translation) }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !isSelected { select() }
                        pinchChanged(Double(value.magnification))
                    }
                    .onEnded { pinchEnded(Double($0.magnification)) }
            )
        #endif
    }
}

// MARK: - Legacy drag handles (DeltaSkinButtonOffsets)

private struct DeltaSkinLegacyEditHandles: View {

    let skin: any DeltaSkinRenderable
    let traits: DeltaSkinTraits
    let mappingSize: CGSize
    let containerSize: CGSize
    let buttonOffsets: DeltaSkinButtonOffsets
    let onOffsetChanged: (String, CGPoint) -> Void

    /// Currently dragging button id → accumulated drag translation in screen points.
    @State private var dragTranslations: [String: CGSize] = [:]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .allowsHitTesting(false)

            if let buttons = skin.buttons(for: traits) {
                ForEach(buttons, id: \.id) { button in
                    editHandle(for: button)
                }
            }
        }
    }

    @ViewBuilder
    private func editHandle(for button: DeltaSkinButton) -> some View {
        let savedOffset = buttonOffsets.offset(for: button.id, skinIdentifier: skin.identifier)
        let dragOffset = dragTranslations[button.id] ?? .zero
        let liveNormalizedOffset = mappingSpaceDelta(fromScreenDelta: dragOffset)
        let totalOffset = CGPoint(x: savedOffset.x + liveNormalizedOffset.x, y: savedOffset.y + liveNormalizedOffset.y)
        let liveFrame = screenFrame(for: button, savedOffset: totalOffset)

        Group {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.15)))
                .frame(width: liveFrame.width, height: liveFrame.height)
                .position(x: liveFrame.midX, y: liveFrame.midY)
                .allowsHitTesting(false)

            dragHandleView(for: button, savedOffset: savedOffset, liveFrame: liveFrame)
        }
    }

    @ViewBuilder
    private func dragHandleView(for button: DeltaSkinButton, savedOffset: CGPoint, liveFrame: CGRect) -> some View {
        let handle = Image(systemName: "move.3d")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .padding(4)
            .background(Color.black.opacity(0.6))
            .clipShape(Circle())
            .position(x: liveFrame.midX, y: liveFrame.midY)
        #if os(tvOS)
        handle.allowsHitTesting(false)
        #else
        handle.gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    dragTranslations[button.id] = value.translation
                }
                .onEnded { value in
                    let delta = mappingSpaceDelta(fromScreenDelta: value.translation)
                    let rawOffset = CGPoint(x: savedOffset.x + delta.x, y: savedOffset.y + delta.y)
                    let clampedMinX = max(0, min(mappingSize.width - button.frame.width, button.frame.minX + rawOffset.x))
                    let clampedMinY = max(0, min(mappingSize.height - button.frame.height, button.frame.minY + rawOffset.y))
                    onOffsetChanged(button.id, CGPoint(x: clampedMinX - button.frame.minX, y: clampedMinY - button.frame.minY))
                    dragTranslations.removeValue(forKey: button.id)
                }
        )
        #endif
    }

    private func screenFrame(for button: DeltaSkinButton, savedOffset: CGPoint) -> CGRect {
        DeltaSkinEditGeometry(mappingSize: mappingSize, containerSize: containerSize).screenRect(
            forMappingRect: CGRect(
                x: button.frame.minX + savedOffset.x,
                y: button.frame.minY + savedOffset.y,
                width: button.frame.width,
                height: button.frame.height
            )
        )
    }

    private func mappingSpaceDelta(fromScreenDelta delta: CGSize) -> CGPoint {
        DeltaSkinEditGeometry(mappingSize: mappingSize, containerSize: containerSize).mappingDelta(forScreenDelta: delta)
    }
}

// MARK: - "Done" floating button (legacy)

/// Shown only while the layout editor is open (it is entered from the pause menu or the
/// three-finger hold): a "Done" pill that leaves edit mode and a "Reset" link.
///
/// Belongs to the drag-only `DeltaSkinButtonOffsets` overlay. The `layoutEdits:` overlay has its own bar.
public struct DeltaSkinEditModeToolbar: View {
    @Binding var isEditMode: Bool
    let skinIdentifier: String
    let buttonOffsets: DeltaSkinButtonOffsets
    let hasCustomOffsets: Bool

    public init(isEditMode: Binding<Bool>, skinIdentifier: String, buttonOffsets: DeltaSkinButtonOffsets, hasCustomOffsets: Bool) {
        self._isEditMode = isEditMode
        self.skinIdentifier = skinIdentifier
        self.buttonOffsets = buttonOffsets
        self.hasCustomOffsets = hasCustomOffsets
    }

    public var body: some View {
        VStack(spacing: 8) {
            Button {
                isEditMode = false
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.85))
                    .clipShape(Capsule())
            }

            // Reset button — only when there are custom offsets
            if hasCustomOffsets {
                Button {
                    buttonOffsets.resetOffsets(for: skinIdentifier)
                } label: {
                    Label("Reset to Default", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.65))
                        .clipShape(Capsule())
                }
            }
        }
    }
}
#endif
