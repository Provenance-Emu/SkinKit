import Foundation
import SkinCatalogKit
import SkinKitCore

public extension SkinStorePolicy {
    /// The identifier the installed skin will carry. Used to spot a skin that is already installed
    /// before copying a second file with the same id.
    ///
    /// iFly's `SkinStorePolicy.installedIdentifier(for:target:)` took a `SkinCompatibility.Inspection`
    /// and called `SkinCompatibility.retargetedIdentifier`. That is iFly's code, so it comes in as a
    /// closure.
    ///
    /// - Parameters:
    ///   - identifier: the downloaded skin's own identifier (`inspection.identifier`).
    ///   - target: the retarget id from `retarget(for:isSupportedGameType:)`, or `nil` to install as-is.
    ///   - retargetedIdentifier: the app's rule for the identifier a retargeted skin gets
    ///     (iFly: `SkinCompatibility.retargetedIdentifier(_:target:)`, a per-target suffix).
    func installedIdentifier(
        for identifier: String,
        target: String?,
        retargetedIdentifier: (_ identifier: String, _ target: String) -> String
    ) -> String {
        guard let target else { return identifier }
        return retargetedIdentifier(identifier, target)
    }

    /// `retarget(for:isSupportedGameType:)` for a skin read with SkinKitCore: a skin counts as
    /// supported when its game type is one of `acceptedGameTypes` (iFly: Dreamcast, Naomi, Naomi 2,
    /// Atomiswave).
    func retarget(
        for section: SkinStoreSection,
        skinGameType: DeltaSkinGameType?,
        acceptedGameTypes: Set<DeltaSkinGameType>
    ) -> String? {
        let supported = skinGameType.map(acceptedGameTypes.contains) ?? false
        return retarget(for: section, isSupportedGameType: supported)
    }
}
