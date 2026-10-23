import Foundation

/// Manages storage of DeltaSkin files
///
/// Stores under Application Support, not under `DeltaSkinManager`'s directory (Documents), and
/// nothing in Provenance's skin code calls it. Moved as it was; the two are not unified.
public final class DeltaSkinStorage: DeltaSkinStorageProtocol {
    public static let shared = DeltaSkinStorage()

    private let fileManager = FileManager.default

    /// Where skins are stored. `nil` means `<Application Support>/DeltaSkins`.
    private let directoryOverride: URL?

    /// - Parameter directory: the folder to store in; defaults to `<Application Support>/DeltaSkins`.
    public init(directory: URL? = nil) {
        directoryOverride = directory
    }

    /// Get the directory where skins are stored
    public func skinsDirectory() throws -> URL {
        let skinsDir: URL
        if let directoryOverride {
            skinsDir = directoryOverride
        } else {
            let appSupport = try fileManager.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
            skinsDir = appSupport.appendingPathComponent("DeltaSkins", isDirectory: true)
        }
        if !fileManager.fileExists(atPath: skinsDir.path) {
            try fileManager.createDirectory(at: skinsDir,
                                         withIntermediateDirectories: true)
        }
        return skinsDir
    }

    public func saveSkin(_ data: Data, withIdentifier identifier: String) async throws -> URL {
        let directory = try skinsDirectory()
        let fileURL = directory.appendingPathComponent("\(identifier).deltaskin")

        try data.write(to: fileURL)
        return fileURL
    }

    public func deleteSkin(withIdentifier identifier: String) async throws {
        if let url = url(forSkinIdentifier: identifier) {
            try fileManager.removeItem(at: url)
        }
    }

    public func url(forSkinIdentifier identifier: String) -> URL? {
        guard let directory = try? skinsDirectory() else { return nil }
        let urls = [
            directory.appendingPathComponent("\(identifier).deltaskin"),
            directory.appendingPathComponent("\(identifier).manicskin")
        ]
        return urls.first {
            fileManager.fileExists(atPath: $0.path)
        }
    }
}
