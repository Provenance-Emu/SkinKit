import Foundation
import SkinCatalogKit
import SkinKitCore

public extension DeltaSkinManager {
    /// Installs a downloaded catalog skin the way Provenance's `SkinCatalogDetailView` did, minus
    /// the download and the view state: import the file, then write the `<stem>.skinmeta` sidecar so
    /// the override registry can map the skin back to the catalog's systems even when its
    /// `info.json` `gameTypeIdentifier` is wrong (the SEGA SG-1000 thumbstick skin).
    ///
    /// Save the download as `entry.preferredLocalDownloadFileName()` first: the on-disk name is how
    /// `matchingInstalledSkin(for:in:)` finds the skin again.
    ///
    /// A sidecar failure is logged and does not fail the install.
    /// - Returns: the installed skin, or `nil` if it could not be matched after the import (then
    ///   no sidecar is written).
    @discardableResult
    func installCatalogSkin(from file: URL, entry: SkinCatalogEntry) async throws -> (any DeltaSkinProtocol)? {
        try await importSkin(from: file)

        let allSkins = try await availableSkins(forceRescan: false)
        guard let skin = matchingInstalledSkin(for: entry, in: allSkins) else {
            WLOG("SkinKitManager: Skipping sidecar write — installed skin not found for '\(entry.name)' (id: \(entry.id))")
            return nil
        }
        do {
            try await overrideRegistry.writeSidecar(
                for: skin.fileURL,
                entry: entry,
                skinIdentifier: skin.identifier
            )
            ILOG("SkinKitManager: Wrote catalog sidecar for '\(skin.name)' at \(SkinSystemOverrideRegistry.sidecarURL(for: skin.fileURL).lastPathComponent)")
        } catch {
            WLOG("SkinKitManager: Failed to write catalog sidecar for '\(entry.name)': \(error)")
        }
        return skin
    }
}
