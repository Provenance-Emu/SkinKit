import Foundation
import SkinKitCore
import ZIPFoundation

// The logic behind SkinKitUI's "Send to RetroArch" sheet. It lives here, not in SkinKitUI, so it has no UIKit and
// its tests run on the macOS host: the report the sheet shows, the destination text, the
// `provenance://skins/retroarch` route and the state machine that runs the exporter.

// MARK: - Text

/// The words the sheet shows (spec §4). One place so the sheet, the README promise and the tests agree.
public enum RetroArchSendText {
    /// Where to save the folder in the Files picker.
    public static let destination = "On My iPhone › RetroArch › RetroArch › overlays"

    public static let destinationHint = "Choose \(destination), then tap Save. The picker opens at the last place you used, so next time it is just Save."

    /// The three menu taps that turn the overlay on once it is in `overlays`.
    public static let menuTaps: [String] = [
        "In RetroArch open Settings › On-Screen Overlay.",
        "Tap Overlay Preset and browse to <name>/<name>.cfg.",
        "Turn Display Overlay on. To keep it for one game, use Quick Menu › Overrides › Save Game Overrides.",
    ]

    /// `menuTaps` with the folder name filled in.
    public static func menuTaps(folderName: String) -> [String] {
        menuTaps.map { $0.replacingOccurrences(of: "<name>", with: folderName) }
    }
}

// MARK: - Report

/// What the sheet tells the player about a conversion: what became an overlay, and what did not.
public struct RetroArchSendReport: Equatable, Sendable {

    /// An input the skin has that RetroArch cannot be given.
    public struct Unmapped: Equatable, Sendable {
        /// Where in the skin it was, e.g. `portrait / edgeToEdge`.
        public var location: String
        public var input: String
        public var reason: String
    }

    /// Folder (and `.cfg`) base name.
    public var folderName: String
    /// Input-map system key, e.g. `gba`.
    public var system: String
    /// The core whose default binding the buttons follow, when the input map says.
    public var assumes: String?
    /// How many RetroArch overlays the preset holds (landscape, portrait, and the alternates).
    public var overlayCount: Int
    /// Layouts used and layouts skipped, as sentences.
    public var warnings: [String]
    public var unmapped: [Unmapped]

    public var hasIssues: Bool { !warnings.isEmpty || !unmapped.isEmpty }

    public init(conversion: RetroArchConversion, inputMap: RetroArchInputMap? = nil) {
        folderName = conversion.name
        system = conversion.system
        assumes = inputMap?.assumes(system: conversion.system)
        overlayCount = conversion.layouts.count
        var lines = conversion.notes
        for skipped in conversion.skipped {
            lines.append("\(skipped.overlayName) (\(skipped.displayType)) was left out: \(skipped.reason)")
        }
        var seen = Set<String>()
        warnings = lines.filter { seen.insert($0).inserted }
        unmapped = conversion.unconvertible.map { Unmapped(location: $0.location, input: $0.input, reason: $0.reason) }
    }

    /// The unconverted inputs grouped by token, with every place each one appeared, in order of first appearance.
    /// A skin repeats `touchScreen` in every layout; the sheet shows it once.
    public var unmappedByInput: [(input: String, reason: String, locations: [String])] {
        var order: [String] = []
        var grouped: [String: (reason: String, locations: [String])] = [:]
        for item in unmapped {
            if grouped[item.input] == nil {
                order.append(item.input)
                grouped[item.input] = (item.reason, [])
            }
            if !grouped[item.input]!.locations.contains(item.location) { grouped[item.input]!.locations.append(item.location) }
        }
        return order.map { (input: $0, reason: grouped[$0]!.reason, locations: grouped[$0]!.locations) }
    }
}

// MARK: - Availability

/// Whether the sheet is offered for a skin: the input map has a row for its game type.
public enum RetroArchSendAvailability {
    private static let map = try? RetroArchInputMap.bundled()

    /// True when the input map has a row for the skin's `gameTypeIdentifier` (`jaguar` has none until the file gets one).
    public static func isSupported(gameTypeIdentifier: String?, inputMap: RetroArchInputMap? = nil) -> Bool {
        guard let map = inputMap ?? Self.map else { return false }
        let system = map.system(forGameTypeIdentifier: gameTypeIdentifier)
        return map.systems[system] != nil
    }

    public static func isSupported(skin: some DeltaSkinProtocol, inputMap: RetroArchInputMap? = nil) -> Bool {
        isSupported(gameTypeIdentifier: RetroArchSkinInfo(skin: skin).gameTypeIdentifier, inputMap: inputMap)
    }
}

// MARK: - Route

/// The `provenance://skins/retroarch?skin=<identifier>` deep link (spec §3 and §4).
///
/// The app's URL handler asks `parse(_:)`; a non-nil result means "open the Send to RetroArch sheet for this skin".
/// A link without `skin` opens the sheet's "pick a skin" message.
public enum RetroArchSendRoute {
    public static let scheme = "provenance"
    public static let host = "skins"
    public static let path = "/retroarch"
    public static let skinParameter = "skin"

    public struct Route: Equatable, Sendable {
        /// The skin's `identifier`, when the link names one.
        public var skinIdentifier: String?
    }

    /// The route a URL stands for, or nil when it is some other link.
    public static func parse(_ url: URL) -> Route? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else { return nil }
        var pathPart = url.path
        while pathPart.count > 1, pathPart.hasSuffix("/") { pathPart.removeLast() }
        guard pathPart.lowercased() == path else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let id = items.first { $0.name == skinParameter }?.value
        return Route(skinIdentifier: (id?.isEmpty ?? true) ? nil : id)
    }

    /// The link for a skin (the website's "Send to RetroArch" inside the app builds the same URL).
    public static func url(forSkinIdentifier identifier: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        if let identifier, !identifier.isEmpty { components.queryItems = [URLQueryItem(name: skinParameter, value: identifier)] }
        return components.url!
    }
}

// MARK: - Result

/// A finished export in a form that can cross actors: where the folder is, and the report to show.
public struct RetroArchSendResult: Equatable, Sendable {
    public var folder: URL
    public var report: RetroArchSendReport

    public init(folder: URL, report: RetroArchSendReport) {
        self.folder = folder
        self.report = report
    }

    public init(export: RetroArchOverlayExporter.Export, inputMap: RetroArchInputMap? = nil) {
        self.init(folder: export.folder, report: RetroArchSendReport(conversion: export.conversion, inputMap: inputMap))
    }
}

// MARK: - Model

/// Runs the exporter off the main actor and holds what the sheet shows.
@MainActor
public final class RetroArchSendModel: ObservableObject {

    public enum State: Equatable {
        case idle
        case exporting
        case ready(RetroArchSendResult)
        case failed(String)
    }

    /// Does the conversion and writes the folder. Runs on a background task.
    public typealias Exporter = @Sendable () throws -> RetroArchSendResult

    @Published public private(set) var state: State = .idle

    private let exporter: Exporter
    private var archiveURL: URL?
    /// Bumped by every `start()` and `cleanUp()`. A run whose ticket is stale when it finishes deletes its own output.
    private var generation = 0

    public init(exporter: @escaping Exporter) {
        self.exporter = exporter
    }

    /// Runs the export once; later calls do nothing until `reset()`.
    public func start() async {
        guard state == .idle else { return }
        state = .exporting
        generation &+= 1
        let ticket = generation
        let exporter = self.exporter
        let outcome: Result<RetroArchSendResult, Error> = await Task.detached(priority: .userInitiated) {
            Result { try exporter() }
        }.value
        guard ticket == generation, state == .exporting else {
            // cleanUp() or reset() ran while the export was in flight: nothing will show
            // or delete this folder, so drop it here.
            if case .success(let result) = outcome { Self.removeScratch(for: result.folder) }
            return
        }
        switch outcome {
        case .success(let result): state = .ready(result)
        case .failure(let error): state = .failed(Self.message(for: error))
        }
    }

    /// The folder for the document picker, when the export is done.
    public var folder: URL? {
        if case .ready(let result) = state { return result.folder }
        return nil
    }

    /// `<name>.zip` of the folder, for the share sheet. Made on first use and kept until `cleanUp()`.
    public func shareArchive() throws -> URL {
        if let archiveURL, FileManager.default.fileExists(atPath: archiveURL.path) { return archiveURL }
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        let url = try RetroArchSendArchive.zip(folder: folder)
        archiveURL = url
        return url
    }

    /// Forgets the result so `start()` can run again, and deletes the files.
    public func reset() {
        cleanUp()
        state = .idle
    }

    /// Deletes the temporary folder and archive. Call when the sheet closes.
    /// An export still in flight is invalidated: it deletes its folder when it finishes instead of publishing it.
    public func cleanUp() {
        generation &+= 1
        if state == .exporting { state = .idle }
        if let folder { Self.removeScratch(for: folder) }
        archiveURL = nil
    }

    // MARK: Helpers

    /// Removes the `SkinKitRetroArch-<uuid>` directory an export was written into, and nothing else.
    nonisolated static func removeScratch(for folder: URL) {
        let root = folder.deletingLastPathComponent()
        guard root.lastPathComponent.hasPrefix("SkinKitRetroArch-") else { return }
        try? FileManager.default.removeItem(at: root)
    }

    nonisolated static func message(for error: Error) -> String {
        switch error {
        case RetroArchExportError.nothingToConvert(let notes):
            let why = notes.isEmpty ? "" : " " + notes.joined(separator: " ")
            return "This skin has no layout that can become a RetroArch overlay." + why
        case RetroArchExportError.unreadableSkin:
            return "The skin file could not be read."
        case RetroArchExportError.missingAsset(let name):
            return "The skin names artwork it does not contain: \(name)."
        case RetroArchExportError.unsafeFolderName(let name):
            return "The skin's name (\(name)) cannot be used as a folder name."
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Archive

/// Zips an overlay folder for the share sheet.
public enum RetroArchSendArchive {
    /// Writes `<folder name>.zip` next to `folder`, with the folder itself as the archive's top entry so unzipping
    /// in Files gives `<name>/<name>.cfg` (the shape the Move recipe expects).
    public static func zip(folder: URL) throws -> URL {
        let url = folder.deletingLastPathComponent().appendingPathComponent("\(folder.lastPathComponent).zip")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.zipItem(at: folder, to: url, shouldKeepParent: true)
        return url
    }
}
