import Foundation
import SkinKitCore
import ZIPFoundation

/// One picture the exporter asks its caller to draw.
public struct RetroArchImageRequest: Sendable {
    public typealias Kind = RetroArchConversion.ImagePlan.Kind

    /// File name the PNG is saved under in the preset folder.
    public let file: String
    public let kind: Kind
    /// The skin file the picture comes from, as found in the skin (path inside the archive or folder).
    public let assetName: String
    public let assetData: Data
    /// Lowercased extension of `assetName`: `pdf`, `svg`, `png`.
    public let fileExtension: String
    /// Size to render at, in pixels: 2x the mapping size, long side capped at 2048.
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Pixels per mapping point (`pixelWidth / mappingWidth`).
    public let pixelsPerPoint: Double
    /// The layout size (an overlay) or hitbox size (a thumbstick) in mapping points.
    public let mappingWidth: Double
    public let mappingHeight: Double
    /// Areas, in mapping points, to make transparent: the game screens, unless the layout is translucent.
    public let clearRects: [RetroArchSkinInfo.Rect]
    /// Thumbstick only: the cap's size in mapping points, centered in the `mappingWidth` x `mappingHeight` box.
    public let innerWidth: Double?
    public let innerHeight: Double?
}

public enum RetroArchExportError: Error, Equatable {
    /// The skin has no layout the converter can use; `notes` says why.
    case nothingToConvert(notes: [String])
    /// The skin file or folder could not be read.
    case unreadableSkin(URL)
    /// The skin names artwork that is not in it.
    case missingAsset(String)
    /// The overlay name would not make a folder of its own inside the output folder, so nothing was written or removed.
    case unsafeFolderName(String)
}

/// Writes a skin as a RetroArch overlay folder: `<name>/<name>.cfg`, the PNGs it names, and a `README.txt`.
///
/// The module draws nothing itself. PDF, SVG and PNG rendering lives in the apps (SkinKitUI has it), so the caller
/// passes a closure that turns a request (artwork bytes, a pixel size, areas to clear) into PNG data. That keeps this
/// module free of UIKit and testable on the macOS host.
public enum RetroArchOverlayExporter {

    public struct Export {
        /// The finished `<name>/` folder.
        public let folder: URL
        /// What the converter made, including the unconvertible-input report.
        public let conversion: RetroArchConversion
    }

    /// Pixels per mapping point and the longest side allowed, for PNGs the exporter requests.
    public static let pixelScale = 2.0
    public static let maxPixelLongSide = 2048.0

    /// Converts `skin` and writes the folder inside `parent` (default: a new folder in the temporary directory).
    /// `rasterize` is called once per picture and returns PNG data.
    public static func export(
        skin: some DeltaSkinProtocol,
        options: RetroArchConverter.Options = RetroArchConverter.Options(),
        converter: RetroArchConverter? = nil,
        into parent: URL? = nil,
        rasterize: (RetroArchImageRequest) throws -> Data
    ) throws -> Export {
        let source = try SkinFiles(url: skin.fileURL)
        var options = options
        options.entries = source.entries
        let converter = try converter ?? RetroArchConverter.bundled()
        let conversion = converter.convert(skin: skin, options: options)
        guard !conversion.preset.overlays.isEmpty else {
            throw RetroArchExportError.nothingToConvert(notes: conversion.notes)
        }

        let fm = FileManager.default
        let root = parent ?? fm.temporaryDirectory.appendingPathComponent("SkinKitRetroArch-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(conversion.name, isDirectory: true)
        // The folder is replaced below, so it must be a real child of `root`: never `root` itself or a parent.
        let name = conversion.name
        guard !name.isEmpty, !name.allSatisfy({ $0 == "." }), !name.contains("/"),
              folder.standardizedFileURL.deletingLastPathComponent().path == root.standardizedFileURL.path else {
            throw RetroArchExportError.unsafeFolderName(name)
        }
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        for plan in conversion.images {
            guard let resolved = RetroArchConverter.resolveAsset(source.entries, plan.asset), let data = source.data(for: resolved) else {
                throw RetroArchExportError.missingAsset(plan.asset ?? "(none)")
            }
            let size = plan.pixelSize(scale: pixelScale, maxLongSide: maxPixelLongSide)
            let png = try rasterize(RetroArchImageRequest(
                file: plan.file, kind: plan.kind, assetName: resolved, assetData: data,
                fileExtension: (resolved as NSString).pathExtension.lowercased(),
                pixelWidth: size.width, pixelHeight: size.height,
                pixelsPerPoint: plan.pixelsPerPoint(scale: pixelScale, maxLongSide: maxPixelLongSide),
                mappingWidth: plan.width, mappingHeight: plan.height, clearRects: plan.clearRects,
                innerWidth: plan.innerWidth, innerHeight: plan.innerHeight))
            try png.write(to: folder.appendingPathComponent(plan.file), options: .atomic)
        }
        try Data(conversion.cfg.utf8).write(to: folder.appendingPathComponent("\(conversion.name).cfg"), options: .atomic)
        try Data(conversion.readme.utf8).write(to: folder.appendingPathComponent("README.txt"), options: .atomic)
        return Export(folder: folder, conversion: conversion)
    }

    /// A skin on disk: an archive or an unpacked folder.
    private struct SkinFiles {
        let entries: [String]
        private let read: (String) -> Data?

        init(url: URL) throws {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                let base = url.standardizedFileURL
                var found: [String] = []
                if let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) {
                    let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
                    for case let file as URL in walker {
                        guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                        let path = file.standardizedFileURL.path
                        if path.hasPrefix(prefix) { found.append(String(path.dropFirst(prefix.count))) }
                    }
                }
                entries = found.sorted()
                read = { try? Data(contentsOf: base.appendingPathComponent($0)) }
            } else {
                guard let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil) else {
                    throw RetroArchExportError.unreadableSkin(url)
                }
                entries = archive.map(\.path)
                read = { path in archive[path].flatMap { archive.extractData($0) } }
            }
        }

        func data(for path: String) -> Data? { read(path) }
    }
}
