#if canImport(UIKit)
import CoreGraphics
import SkinKitCore
import SkinKitManager

public extension DeltaSkinLayoutEdits {
    /// The trait keys `skin` has buttons for: every device, display type and orientation (with and without the
    /// alt representations) whose `buttons(for:)` is not empty.
    static func traitKeys(for skin: any DeltaSkinRenderable) -> [String] {
        var keys = Set<String>()
        forEachButtonTrait(of: skin) { traits, _ in keys.insert(traits.layoutEditKey) }
        return keys.sorted()
    }

    /// Moves a skin's offsets from the old trait-less `DeltaSkinButtonOffsets` store into this one, once.
    ///
    /// The old store applied one offset to every orientation, so each offset is copied to every trait the skin has
    /// buttons for. Every stored offset moves, including one for a button that only a `gameOverrides` layout has
    /// (such layouts share their base trait's key). A button that already has an edit on a trait keeps it.
    /// The old offsets are cleared afterwards, so this does nothing on later calls; if the write fails they stay,
    /// and the next call tries again.
    @MainActor
    func migrateLegacyOffsets(from offsets: DeltaSkinButtonOffsets, skin: any DeltaSkinRenderable) {
        guard offsets.hasCustomOffsets(for: skin.identifier) else { return }
        let keys = Self.traitKeys(for: skin)
        let moved = offsets.allOffsets(for: skin.identifier)
        do {
            try importLegacyOffsets(moved, skinIdentifier: skin.identifier, traitKeys: keys)
            offsets.resetOffsets(for: skin.identifier)
            ILOG("DeltaSkinLayoutEdits: moved \(moved.count) legacy offset(s) for \(skin.identifier) to \(keys.count) trait(s)")
        } catch {
            WLOG("DeltaSkinLayoutEdits: could not move legacy offsets for \(skin.identifier): \(error)")
        }
    }

    private static func forEachButtonTrait(
        of skin: any DeltaSkinRenderable,
        _ body: (DeltaSkinTraits, [DeltaSkinButton]) -> Void
    ) {
        for device in DeltaSkinDevice.allCases {
            for displayType in DeltaSkinDisplayType.allCases {
                for orientation in DeltaSkinOrientation.allCases {
                    for alt in [false, true] {
                        let traits = DeltaSkinTraits(
                            device: device, displayType: displayType, orientation: orientation,
                            usesAltRepresentations: alt
                        )
                        if let buttons = skin.buttons(for: traits), !buttons.isEmpty { body(traits, buttons) }
                    }
                }
            }
        }
    }
}
#endif
