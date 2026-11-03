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
    func installCatalogSkin(
        from file: URL,
        entry: SkinCatalogEntry,
        familyIndex: SkinFamilyIndex? = nil
    ) async throws -> (any DeltaSkinProtocol)? {
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
                skinIdentifier: skin.identifier,
                index: familyIndex
            )
            ILOG("SkinKitManager: Wrote catalog sidecar for '\(skin.name)' at \(SkinSystemOverrideRegistry.sidecarURL(for: skin.fileURL).lastPathComponent)")
        } catch {
            WLOG("SkinKitManager: Failed to write catalog sidecar for '\(entry.name)': \(error)")
        }
        return skin
    }

    /// Downloads and installs every entry of a family download plan, one after another (one
    /// request per member file; deltastyles.com rate-limits parallel fetches). A failed member is
    /// reported and the rest still install.
    ///
    /// - Parameters:
    ///   - plan: from `SkinFamily.downloadPlan(memberIds:policy:)`.
    ///   - familyIndex: the whole catalog's index, so each sidecar stores the label the store showed.
    ///   - downloader: fetches each file; tests pass a fake.
    ///   - progress: per entry id, the fraction of that entry's download.
    ///   - tracker: claims each entry while it installs; an entry another install already holds
    ///     is skipped with `SkinCatalogInstallError.alreadyInProgress`.
    /// - Returns: per entry id, the error that stopped it. Empty when everything installed.
    @discardableResult
    func installCatalogPlan(
        _ plan: SkinDownloadPlan,
        familyIndex: SkinFamilyIndex? = nil,
        downloader: any SkinStoreDownloading = URLSessionSkinStoreDownloader(),
        tracker: SkinCatalogInstallTracker? = nil,
        progress: @escaping @Sendable (_ entryId: String, _ fraction: Double) -> Void = { _, _ in }
    ) async -> [String: Error] {
        let claims: SkinCatalogInstallTracker
        if let tracker {
            claims = tracker
        } else {
            claims = await MainActor.run { SkinCatalogInstallTracker.shared }
        }
        var failures: [String: Error] = [:]
        for entry in plan.entries {
            if Task.isCancelled {
                failures[entry.id] = CancellationError()
                continue
            }
            guard await claims.begin(entry.id) else {
                ILOG("SkinKitManager: '\(entry.name)' is already installing; skipped")
                failures[entry.id] = SkinCatalogInstallError.alreadyInProgress(entryId: entry.id)
                continue
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SkinCatalogPlan-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent(entry.preferredLocalDownloadFileName())
            do {
                let id = entry.id
                try await downloader.download(from: entry.downloadURL, to: file) { progress(id, $0) }
                try await installCatalogSkin(from: file, entry: entry, familyIndex: familyIndex)
            } catch {
                WLOG("SkinKitManager: Family install of '\(entry.name)' failed: \(error)")
                failures[entry.id] = error
            }
            await claims.end(entry.id)
        }
        return failures
    }
}
