import Foundation
import SkinKit2Core
import ZIPFoundation

extension Skin2Baker {
    /// Reads a source document and its adjacent assets from a directory.
    public static func bake(sourceURL: URL, hitOverlapPolicy: Skin2Validator.HitOverlapPolicy = .reject) throws -> [Skin2BakedBundle] {
        let source = sourceURL.standardizedFileURL
        let root = source.deletingLastPathComponent()
        let assetRoot = root.appendingPathComponent("assets", isDirectory: true)
        var assets: [String: Data] = [:]
        let fm = FileManager.default
        if let entries = fm.enumerator(at: assetRoot, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            for case let url as URL in entries {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    entries.skipDescendants()
                } else if values.isRegularFile == true {
                    let name = String(url.path.dropFirst(root.path.count + 1))
                    assets[name] = try Data(contentsOf: url)
                }
            }
        }
        return try bake(source: Data(contentsOf: source), assets: assets, hitOverlapPolicy: hitOverlapPolicy)
    }

    /// Reads the format 2 source and assets from an installed archive or directory package.
    public static func bake(bundleURL: URL, sourcePath: String = "skin.json") throws -> [Skin2BakedBundle] {
        let components = sourcePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !sourcePath.contains("\\"), !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw Skin2BakeError.invalidSource([sourcePath])
        }
        if (try bundleURL.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
            return try bake(sourceURL: bundleURL.appendingPathComponent(sourcePath))
        }
        let archive = try Archive(url: bundleURL, accessMode: .read)
        guard let entry = archive[sourcePath], entry.type == .file,
              entry.uncompressedSize <= Skin2Document.maxFileBytes else { throw Skin2BakeError.invalidSource([sourcePath]) }
        func data(for entry: Entry) throws -> Data {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            return data
        }
        var assets: [String: Data] = [:]
        var total: UInt64 = 0
        for entry in archive where entry.type == .file && entry.path.hasPrefix("assets/") {
            let limit: UInt64 = 64 * 1024 * 1024
            guard entry.uncompressedSize <= limit - total else { throw Skin2BakeError.artwork("Assets exceed 64 MiB") }
            total += entry.uncompressedSize
            assets[entry.path] = try data(for: entry)
        }
        return try bake(source: data(for: entry), assets: assets)
    }

    /// Writes classic ZIP archives into a new or existing directory, without replacing existing skins.
    public static func write(_ bundles: [Skin2BakedBundle], to output: URL) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let destinations = bundles.indices.map { output.appendingPathComponent("skin-\($0 + 1).deltaskin") }
        for destination in destinations where fm.fileExists(atPath: destination.path) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: destination])
        }

        var written: [URL] = []
        do {
            for (bundle, destination) in zip(bundles, destinations) {
                let temporary = output.appendingPathComponent(".\(UUID().uuidString).zip")
                defer { try? fm.removeItem(at: temporary) }
                let archive = try Archive(url: temporary, accessMode: .create)
                for (name, data) in bundle.files.sorted(by: { $0.key < $1.key }) {
                    try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count),
                                         modificationDate: Date(timeIntervalSince1970: 315532800),
                                         compressionMethod: .deflate) { position, size in
                        let start = Int(position)
                        return data.subdata(in: start..<(start + size))
                    }
                }
                try fm.moveItem(at: temporary, to: destination)
                written.append(destination)
            }
            return written
        } catch {
            for url in written { try? fm.removeItem(at: url) }
            throw error
        }
    }
}
