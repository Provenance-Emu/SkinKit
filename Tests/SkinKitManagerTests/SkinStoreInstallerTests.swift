import Combine
import Foundation
import SkinCatalogKit
import Testing
@testable import SkinKitManager

/// A store preset, as an app wires it: its policy, where it records installs, and an entry that
/// installs on one of its shelves.
struct StorePreset: CustomStringConvertible, Sendable {
    let name: String
    let policy: SkinStorePolicy
    let appName: String
    /// The shelf `installableEntry` lands on.
    let section: SkinStoreSection
    let installableSystemCode: String
    /// A new record over fresh storage, and a cleanup for it. `reopen` is a second record over the
    /// same storage.
    let makeRecord: @Sendable () throws -> (record: SkinStoreInstalledRecord, reopen: () -> SkinStoreInstalledRecord, cleanup: () -> Void)

    var description: String { name }

    func installableEntry(id: String = "17b481d711267028", name: String = "Smash T.V.") throws -> SkinCatalogEntry {
        try TestSupport.entry(
            id: id, name: name, systems: [installableSystemCode],
            url: "https://deltastyles.com/files/skins/611/\(id).manicskin"
        )
    }

    func zipEntry() throws -> SkinCatalogEntry {
        try TestSupport.entry(id: "594892ecc4054694", systems: [installableSystemCode], url: "https://deltastyles.com/files/skins/652/panel.zip")
    }

    /// iFly: arcade shelf (MAME), record in `UserDefaults`.
    static let iFly = StorePreset(
        name: "iFly", policy: .iFly, appName: "iFly", section: .arcade, installableSystemCode: "mame",
        makeRecord: {
            let (defaults, cleanup) = TestSupport.makeDefaults()
            return (SkinStoreInstalledRecord.iFly(defaults: defaults), { SkinStoreInstalledRecord.iFly(defaults: defaults) }, cleanup)
        }
    )

    /// iCube: GameCube shelf, record in `store.json`.
    static let iCube = StorePreset(
        name: "iCube", policy: .iCube, appName: "iCube", section: .gameCube, installableSystemCode: "gamecube",
        makeRecord: {
            let root = try TestSupport.makeScratch("StorePreset-iCube")
            return (
                SkinStoreInstalledRecord.iCube(rootURL: root),
                { SkinStoreInstalledRecord.iCube(rootURL: root) },
                { try? FileManager.default.removeItem(at: root) }
            )
        }
    )

    static let all = [StorePreset.iFly, .iCube]
}

/// The installer's state machine, with the network and the importer stubbed. Ported from iFly's
/// and iCube's `SkinStoreInstallerTests`, which were the same tests over different records; each
/// runs once per preset.
@Suite("SkinStoreInstaller")
@MainActor
struct SkinStoreInstallerTests {

    private func makeInstaller(
        _ preset: StorePreset,
        record: SkinStoreInstalledRecord,
        downloader: FakeDownloader = FakeDownloader(),
        describeError: @escaping (Error) -> String = { $0.localizedDescription },
        installStep: @escaping SkinStoreInstaller.InstallStep
    ) -> SkinStoreInstaller {
        SkinStoreInstaller(
            policy: preset.policy, downloader: downloader, record: record,
            appName: preset.appName, describeError: describeError, installStep: installStep
        )
    }

    @Test("A successful install records the catalog id", arguments: StorePreset.all)
    func successfulInstallRecordsTheCatalogId(preset: StorePreset) async throws {
        let (record, reopen, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        var seen: [(file: String, section: SkinStoreSection, fileExists: Bool)] = []
        let installer = makeInstaller(preset, record: record) { file, section in
            seen.append((file.lastPathComponent, section, FileManager.default.fileExists(atPath: file.path)))
            return .installed(identifier: "com.hzn.smashtv")
        }
        let skin = try preset.installableEntry()
        #expect(installer.state(for: skin) == .idle)

        await installer.install(skin)

        #expect(installer.state(for: skin) == .installed)
        #expect(seen.count == 1)
        #expect(seen.first?.file == "17b481d711267028.manicskin", "named <entry id>.<ext>")
        #expect(seen.first?.section == preset.section)
        #expect(seen.first?.fileExists == true)
        #expect(reopen().load() == ["17b481d711267028": "com.hzn.smashtv"])
    }

    @Test("Installed state survives a new installer", arguments: StorePreset.all)
    func installedStateSurvivesANewInstaller(preset: StorePreset) async throws {
        let (record, reopen, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let first = makeInstaller(preset, record: record) { _, _ in .installed(identifier: "x") }
        let skin = try preset.installableEntry()
        await first.install(skin)

        let second = makeInstaller(preset, record: reopen()) { _, _ in
            Issue.record("must not install")
            return .installed(identifier: "x")
        }
        #expect(second.state(for: skin) == .installed)
    }

    @Test("An already-installed skin is recorded as installed", arguments: StorePreset.all)
    func alreadyInstalledSkinIsRecordedAsInstalled(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = makeInstaller(preset, record: record) { _, _ in
            .alreadyInstalled(identifier: "com.starvingartist.dc.dreamsicle-white")
        }
        let dreamsicle = try preset.installableEntry(id: "3957312ad9e7c59e", name: "Dreamsicle")
        await installer.install(dreamsicle)
        #expect(installer.state(for: dreamsicle) == .installed)
        #expect(installer.installedIds.contains("3957312ad9e7c59e"))
        #expect(record.load()["3957312ad9e7c59e"] == "com.starvingartist.dc.dreamsicle-white")
    }

    @Test("A download failure surfaces its message and installs nothing", arguments: StorePreset.all)
    func downloadFailureSurfacesMessage(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = makeInstaller(
            preset, record: record,
            downloader: FakeDownloader(error: URLSessionSkinStoreDownloader.HTTPStatusError(statusCode: 404))
        ) { _, _ in
            Issue.record("install must not run after a failed download")
            return .installed(identifier: "x")
        }
        let skin = try preset.installableEntry()
        await installer.install(skin)
        #expect(installer.state(for: skin) == .failed(message: "The skin's host answered with HTTP 404."))
        #expect(!installer.installedIds.contains(skin.id))
        #expect(record.load().isEmpty)
    }

    @Test("An install-step failure surfaces its message", arguments: StorePreset.all)
    func installStepFailureSurfacesMessage(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = makeInstaller(preset, record: record) { file, _ in
            throw SkinStoreInstaller.InstallError.unreadableAfterInstall(file.lastPathComponent, app: preset.appName)
        }
        let skin = try preset.installableEntry()
        await installer.install(skin)
        guard case let .failed(message) = installer.state(for: skin) else {
            Issue.record("expected failed, got \(installer.state(for: skin))")
            return
        }
        #expect(message == "17b481d711267028.manicskin downloaded, but \(preset.appName) couldn't read it as a skin.")
        #expect(record.load().isEmpty)
    }

    @Test("The app's error describer turns a failure into the message (iCube's SkinImportError.describe)")
    func errorDescriberIsUsed() async throws {
        struct ImportFailure: Error {}
        let preset = StorePreset.iCube
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = makeInstaller(
            preset, record: record,
            describeError: { $0 is ImportFailure ? "That file isn't a skin archive." : $0.localizedDescription }
        ) { _, _ in throw ImportFailure() }
        let skin = try preset.installableEntry()
        await installer.install(skin)
        #expect(installer.state(for: skin) == .failed(message: "That file isn't a skin archive."))
    }

    @Test("States pass through downloading and installing", arguments: StorePreset.all)
    func statesPassThroughDownloadingAndInstalling(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        var observed: [SkinStoreInstallState] = []
        let installer = makeInstaller(preset, record: record) { _, _ in .installed(identifier: "x") }
        let skin = try preset.installableEntry()
        let cancellable = installer.$states.sink { states in
            if let state = states[skin.id] {
                observed.append(state)
            }
        }
        defer { cancellable.cancel() }

        await installer.install(skin)

        #expect(observed.first == .downloading(progress: 0))
        #expect(observed.contains(.installing))
        #expect(observed.last == .installed)
    }

    @Test("Cancellation returns to idle", arguments: StorePreset.all)
    func cancellationReturnsToIdle(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = makeInstaller(preset, record: record, downloader: FakeDownloader(error: CancellationError())) { _, _ in
            .installed(identifier: "x")
        }
        let skin = try preset.installableEntry()
        await installer.install(skin)
        #expect(installer.state(for: skin) == .idle)
        #expect(record.load().isEmpty)
    }

    @Test("An entry the policy hides fails without downloading", arguments: StorePreset.all)
    func hiddenEntryFailsWithoutDownloading(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = makeInstaller(preset, record: record, downloader: FakeDownloader(error: URLError(.badURL))) { _, _ in
            .installed(identifier: "x")
        }
        let zip = try preset.zipEntry()
        await installer.install(zip)
        #expect(installer.state(for: zip) == .failed(message: "\(zip.name) isn't a skin \(preset.appName) can install."))
    }

    @Test("The not-installable message can be replaced wholesale (a localized app)")
    func notInstallableMessageOverride() async throws {
        let preset = StorePreset.iCube
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        let installer = SkinStoreInstaller(
            policy: preset.policy, record: record,
            notInstallableMessage: { "« \($0) »" },
            installStep: { _, _ in .installed(identifier: "x") }
        )
        let zip = try preset.zipEntry()
        await installer.install(zip)
        #expect(installer.state(for: zip) == .failed(message: "« \(zip.name) »"))
    }

    @Test("The temporary download folder is removed", arguments: StorePreset.all)
    func temporaryDownloadFolderIsRemoved(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        var downloadedTo: URL?
        let installer = makeInstaller(preset, record: record) { file, _ in
            downloadedTo = file
            return .installed(identifier: "x")
        }
        await installer.install(try preset.installableEntry())
        let folder = try #require(downloadedTo).deletingLastPathComponent()
        #expect(folder.lastPathComponent.hasPrefix("SkinStore-"))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("Reconcile forgets deleted skins", arguments: StorePreset.all)
    func reconcileForgetsDeletedSkins(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        record.markInstalled(catalogId: "kept", skinIdentifier: "skin.kept")
        record.markInstalled(catalogId: "deleted", skinIdentifier: "skin.deleted")
        let installer = makeInstaller(preset, record: record) { _, _ in .installed(identifier: "x") }
        #expect(installer.installedIds == ["kept", "deleted"])

        installer.reconcileInstalled(with: ["skin.kept", "something.else"])

        #expect(installer.installedIds == ["kept"])
        #expect(record.load() == ["kept": "skin.kept"])
    }

    @Test("Starting an install twice runs one install", arguments: StorePreset.all)
    func startAndCancel(preset: StorePreset) async throws {
        let (record, _, cleanup) = try preset.makeRecord()
        defer { cleanup() }
        var steps = 0
        let installer = makeInstaller(preset, record: record) { _, _ in
            steps += 1
            return .installed(identifier: "x")
        }
        let skin = try preset.installableEntry()
        installer.startInstall(skin)
        installer.startInstall(skin)
        for _ in 0..<500 where installer.state(for: skin) != .installed {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(installer.state(for: skin) == .installed)
        #expect(steps == 1)
    }

    @Test("InstallResult exposes the identifier either way")
    func installResultIdentifier() {
        #expect(SkinStoreInstaller.InstallResult.installed(identifier: "a").identifier == "a")
        #expect(SkinStoreInstaller.InstallResult.alreadyInstalled(identifier: "b").identifier == "b")
    }

    @Test("InstallError wording names the app")
    func installErrorWording() {
        #expect(SkinStoreInstaller.InstallError.notInstallable("X").localizedDescription == "X isn't a skin this app can install.")
        #expect(SkinStoreInstaller.InstallError.notInstallable("X", app: "iFly").localizedDescription == "X isn't a skin iFly can install.")
        #expect(SkinStoreInstaller.InstallError.unreadableAfterInstall("X", app: "iFly").localizedDescription == "X downloaded, but iFly couldn't read it as a skin.")
    }

    @Test("SkinStoreInstallState.isBusy")
    func isBusy() {
        #expect(SkinStoreInstallState.downloading(progress: 0.5).isBusy)
        #expect(SkinStoreInstallState.installing.isBusy)
        #expect(!SkinStoreInstallState.idle.isBusy)
        #expect(!SkinStoreInstallState.installed.isBusy)
        #expect(!SkinStoreInstallState.failed(message: "x").isBusy)
    }
}
