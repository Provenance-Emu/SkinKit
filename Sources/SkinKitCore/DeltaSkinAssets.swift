import Foundation
import ZIPFoundation

public extension DeltaSkinProtocol {
    /// Load asset data from either directory or archive
    func loadAssetData(_ filename: String) throws -> Data {
        DLOG("Loading asset: \(filename)")

        let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        if isDirectory {
            // Load from directory
            let assetURL = fileURL.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: assetURL) else {
                ELOG("Failed to load asset from directory: \(filename)")
                throw DeltaSkinError.missingAsset
            }
            return data
        } else {
            // Load from archive. info.json names are often the file stem while the zip
            // entry lives in a folder or differs only by case.
            guard let archive = try? Archive(url: fileURL, accessMode: .read, pathEncoding: nil),
                  let assetEntry = archive.entry(matchingAssetNamed: filename),
                  let data = archive.extractData(assetEntry) else {
                ELOG("Failed to extract asset from archive: \(filename)")
                throw DeltaSkinError.missingAsset
            }
            return data
        }
    }
}
