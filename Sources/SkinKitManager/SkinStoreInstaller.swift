import Combine
import Foundation
import SkinCatalogKit

/// Downloads and installs skins from the store, publishing per-entry state for
/// SwiftUI.
///
/// Flow per entry: download to `<tmp>/SkinStore-<uuid>/<entry id>.<ext>` →
/// the app's install step (import into its skin library, retargeted by shelf where the
/// policy says so) → record the catalog id. Files are always fetched from the entry's
/// `downloadURL`; the apps never re-host them.
///
/// Moved from iFly (`SkinStoreInstaller`) and iCube (`SkinStoreInstaller`), which were the same
/// state machine around different install steps. The step, the policy, the record and the wording of
/// the app's messages are injected; there is no `shared` and no default step, because both default
/// steps were app code (iFly's `SkinImporter` + managers, iCube's `SkinLibrary.importSkin`).
@MainActor
public final class SkinStoreInstaller: ObservableObject {

    /// What the install step did with a downloaded file.
    public enum InstallResult: Sendable, Equatable {
        /// A new skin file was written; carries its identifier.
        case installed(identifier: String)
        /// A skin with the identifier this install would produce is already
        /// loaded (the store's Dreamsicle is the bundled one), so nothing was
        /// copied — a second file with the same id makes the picker ambiguous.
        case alreadyInstalled(identifier: String)

        /// The installed skin's identifier either way.
        public var identifier: String {
            switch self {
            case let .installed(identifier), let .alreadyInstalled(identifier): return identifier
            }
        }
    }

    /// Turns a downloaded file into an installed skin. Injected, so tests and each app supply theirs.
    ///
    /// iFly's step was already `async throws`; iCube's was synchronous and returned its
    /// `InstalledSkin` (wrap it as `.installed(identifier: skin.id)`).
    public typealias InstallStep = @MainActor (_ file: URL, _ section: SkinStoreSection) async throws -> InstallResult

    public enum InstallError: LocalizedError {
        /// The policy hides this entry (a `.zip`, an extensionless link).
        case notInstallable(String, app: String = "this app")
        /// The importer wrote the file but the skin loader rejected it, so it
        /// would never show in a picker. The file is removed again.
        case unreadableAfterInstall(String, app: String = "this app")

        public var errorDescription: String? {
            switch self {
            case let .notInstallable(name, app):
                return "\(name) isn't a skin \(app) can install."
            case let .unreadableAfterInstall(name, app):
                return "\(name) downloaded, but \(app) couldn't read it as a skin."
            }
        }
    }

    private static let temporaryFolderPrefix = "SkinStore-"

    /// Transient state for entries touched this session. Read through
    /// `state(for:)`, which also folds in `installedIds`.
    @Published public private(set) var states: [String: SkinStoreInstallState] = [:]
    /// Catalog ids installed from the store (persisted).
    @Published public private(set) var installedIds: Set<String>

    private let policy: SkinStorePolicy
    private let downloader: any SkinStoreDownloading
    private let record: SkinStoreInstalledRecord
    private let installStep: InstallStep
    private let appName: String
    private let notInstallableMessage: ((String) -> String)?
    private let describeError: (Error) -> String
    private var tasks: [String: Task<Void, Never>] = [:]

    /// - Parameters:
    ///   - policy: which entries install and what their downloads are called (`.iFly`, `.iCube`, or your own).
    ///   - downloader: fetches the file; tests pass a fake.
    ///   - record: where installed catalog ids persist (`.iFly(defaults:)`, `.iCube(rootURL:)`).
    ///   - appName: used in the "isn't a skin ... can install" message ("iFly", "iCube").
    ///   - notInstallableMessage: replaces that message wholesale, for an app that localizes it.
    ///     Receives the entry's name.
    ///   - describeError: turns a failure into the text shown in `.failed(message:)`. The default is
    ///     `localizedDescription`; iCube passes `SkinImportError.describe`.
    ///   - installStep: see `InstallStep`.
    public init(
        policy: SkinStorePolicy,
        downloader: any SkinStoreDownloading = URLSessionSkinStoreDownloader(),
        record: SkinStoreInstalledRecord,
        appName: String = "this app",
        notInstallableMessage: ((String) -> String)? = nil,
        describeError: @escaping (Error) -> String = { $0.localizedDescription },
        installStep: @escaping InstallStep
    ) {
        self.policy = policy
        self.downloader = downloader
        self.record = record
        self.appName = appName
        self.notInstallableMessage = notInstallableMessage
        self.describeError = describeError
        self.installStep = installStep
        installedIds = Set(record.load().keys)
    }

    // MARK: - State

    public func state(for entry: SkinCatalogEntry) -> SkinStoreInstallState {
        if let state = states[entry.id], state != .idle {
            return state
        }
        return installedIds.contains(entry.id) ? .installed : .idle
    }

    /// Forget store installs whose skin is no longer loaded (the user deleted
    /// it), so the store offers it again. Pass every loaded skin identifier.
    public func reconcileInstalled(with loadedIdentifiers: Set<String>) {
        let gone = Set(record.load().filter { !loadedIdentifiers.contains($0.value) }.keys)
        guard !gone.isEmpty else { return }
        record.remove(catalogIds: gone)
        installedIds.subtract(gone)
        for id in gone where states[id] == .installed {
            states[id] = nil
        }
        ILOG("Skin store: \(gone.count) installed skin(s) no longer present")
    }

    // MARK: - Install

    /// Start installing `entry` in the background. A second call while one is
    /// running is ignored.
    public func startInstall(_ entry: SkinCatalogEntry) {
        guard tasks[entry.id] == nil else { return }
        tasks[entry.id] = Task { [weak self] in
            await self?.install(entry)
            self?.tasks[entry.id] = nil
        }
    }

    /// Cancel a running install; the entry returns to idle.
    public func cancelInstall(_ entry: SkinCatalogEntry) {
        tasks[entry.id]?.cancel()
    }

    /// Download and install `entry`, updating `states` along the way.
    public func install(_ entry: SkinCatalogEntry) async {
        if states[entry.id]?.isBusy == true {
            return
        }
        guard let section = policy.section(for: entry),
              let fileName = policy.downloadFileName(for: entry)
        else {
            let message = notInstallableMessage?(entry.name)
                ?? InstallError.notInstallable(entry.name, app: appName).localizedDescription
            states[entry.id] = .failed(message: message)
            return
        }

        states[entry.id] = .downloading(progress: 0)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.temporaryFolderPrefix + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(fileName)

        do {
            let id = entry.id
            try await downloader.download(from: entry.downloadURL, to: file) { [weak self] fraction in
                Task { @MainActor in
                    self?.applyProgress(fraction, for: id)
                }
            }
            try Task.checkCancellation()

            states[entry.id] = .installing
            let result = try await installStep(file, section)

            let identifier = result.identifier
            record.markInstalled(catalogId: entry.id, skinIdentifier: identifier)
            installedIds.insert(entry.id)
            states[entry.id] = .installed
            ILOG(
                "Skin store installed '\(entry.name)' [\(section.id)] as \(identifier)"
                    + (result == .alreadyInstalled(identifier: identifier) ? " (already present)" : "")
            )
        } catch {
            if Self.isCancellation(error) || Task.isCancelled {
                states[entry.id] = .idle
                return
            }
            let message = describeError(error)
            states[entry.id] = .failed(message: message)
            WLOG("Skin store install of '\(entry.name)' failed: \(message)")
        }
    }

    // MARK: - Private

    /// Progress hops arrive asynchronously and can land after the state moved
    /// on; only a still-downloading entry takes them.
    private func applyProgress(_ fraction: Double, for id: String) {
        guard case .downloading = states[id] else { return }
        states[id] = .downloading(progress: fraction)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }
}
