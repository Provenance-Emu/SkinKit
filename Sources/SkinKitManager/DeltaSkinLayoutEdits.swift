import CoreGraphics
import CryptoKit
import Foundation
import SkinKitCore

// MARK: - Value types

/// One button's player edit: a move and a size multiplier, in mapping points.
///
/// A positive `dx` moves the button right and a positive `dy` moves it down, the same convention
/// `DeltaSkinButtonOffsets` used. `scale` multiplies the button's frame about its center.
public struct DeltaSkinButtonEdit: Codable, Hashable, Sendable {
    /// The scale range the editor allows (pinch is clamped to it).
    public static let scaleRange: ClosedRange<Double> = 0.5...2.0

    /// No change.
    public static let identity = DeltaSkinButtonEdit()

    public var dx: Double
    public var dy: Double
    public var scale: Double

    public init(dx: Double = 0, dy: Double = 0, scale: Double = 1) {
        self.dx = dx
        self.dy = dy
        self.scale = scale
    }

    public init(offset: CGPoint, scale: Double = 1) {
        self.init(dx: Double(offset.x), dy: Double(offset.y), scale: scale)
    }

    /// `true` when the edit changes nothing, so the store does not keep it.
    public var isIdentity: Bool { dx == 0 && dy == 0 && scale == 1 }

    /// The move as a point.
    public var offset: CGPoint { CGPoint(x: dx, y: dy) }

    /// This edit with `scale` clamped to `scaleRange` and non-finite values replaced by the identity's.
    public var normalized: DeltaSkinButtonEdit {
        let safeScale = scale.isFinite ? min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound) : 1
        return DeltaSkinButtonEdit(dx: dx.isFinite ? dx : 0, dy: dy.isFinite ? dy : 0, scale: safeScale)
    }

    /// The frame after the edit: scaled about its center, then moved.
    public func applying(to frame: CGRect) -> CGRect {
        let edit = normalized
        let width = frame.width * edit.scale
        let height = frame.height * edit.scale
        return CGRect(
            x: frame.midX - width / 2 + edit.dx,
            y: frame.midY - height / 2 + edit.dy,
            width: width,
            height: height
        )
    }
}

/// Everything stored for one skin: `{ traitKey: { buttonId: edit } }`.
///
/// This is the on-disk shape of `<skinsDirectory>/edits/<identifier>.json`.
public struct DeltaSkinLayoutEditsDocument: Codable, Equatable, Sendable {
    /// The file format version, for a future migration.
    public static let currentVersion = 1

    public var version: Int
    public var skinIdentifier: String
    /// Trait key (`<device>.<displayType>.<orientation>`) to button id to edit.
    public var traits: [String: [String: DeltaSkinButtonEdit]]

    public init(skinIdentifier: String, traits: [String: [String: DeltaSkinButtonEdit]] = [:]) {
        version = Self.currentVersion
        self.skinIdentifier = skinIdentifier
        self.traits = traits
    }

    public var isEmpty: Bool { traits.values.allSatisfy(\.isEmpty) }
}

// MARK: - Trait keys

public extension DeltaSkinTraits {
    /// The key edits are stored under: `<device>.<displayType>.<orientation>`, for example
    /// `iphone.edgeToEdge.portrait`. It is the same spelling `DeltaSkinExporter` walks in `info.json`.
    var layoutEditKey: String {
        DeltaSkinLayoutEdits.traitKey(device: device, displayType: displayType, orientation: orientation)
    }
}

// MARK: - Store

/// Per-skin, per-trait button edits (move and scale), kept in a JSON file beside the skins.
///
/// Edits are keyed by skin identifier, then trait key (`<device>.<displayType>.<orientation>`),
/// then button id, so a nudge made in portrait leaves landscape alone. Each skin has one file,
/// `<skinsDirectory>/edits/<identifier>.json`. The skin file itself is never touched.
///
/// Reads never fail: a missing or unreadable file is "no edits". Writes throw. Identity edits are
/// not stored, and a file with nothing left in it is deleted. The type is thread-safe.
public final class DeltaSkinLayoutEdits: @unchecked Sendable {

    /// The folder name under the skins directory.
    public static let directoryName = "edits"

    /// Posted after every successful write, on the writing thread. `object` is the store and
    /// `userInfo[skinIdentifierKey]` the skin whose edits changed.
    public static let didChangeNotification = Notification.Name("DeltaSkinLayoutEditsDidChange")

    /// The `userInfo` key of `didChangeNotification` holding the skin identifier.
    public static let skinIdentifierKey = "skinIdentifier"

    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let directoryProvider: () throws -> URL
    private var cache: [String: DeltaSkinLayoutEditsDocument] = [:]

    /// Stores edits under `<storage.skinsDirectory()>/edits/`.
    public init(storage: any DeltaSkinStorageProtocol = DeltaSkinStorage.shared) {
        directoryProvider = {
            try storage.skinsDirectory().appendingPathComponent(Self.directoryName, isDirectory: true)
        }
    }

    /// Stores edits directly in `editsDirectory` (used by tests and by hosts with their own layout).
    public init(editsDirectory: URL) {
        directoryProvider = { editsDirectory }
    }

    // MARK: Keys

    /// `<device>.<displayType>.<orientation>`.
    public static func traitKey(
        device: DeltaSkinDevice,
        displayType: DeltaSkinDisplayType,
        orientation: DeltaSkinOrientation
    ) -> String {
        "\(device.rawValue).\(displayType.rawValue).\(orientation.rawValue)"
    }

    /// The file name for a skin identifier: `<readable>-<digest>.json`.
    ///
    /// `<readable>` is the identifier with characters outside `[A-Za-z0-9._-]` percent-encoded (and a leading dot
    /// encoded), cut to 96 characters, so an identifier can never name a path outside the edits folder.
    /// `<digest>` is the first 16 hex digits of the SHA-256 of the exact identifier, so identifiers that differ only
    /// by case (`com.example.Skin`, `com.example.skin`) get different files on a case-insensitive file system.
    public static func fileName(forSkinIdentifier identifier: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._")
        var name = identifier.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        if name.hasPrefix(".") { name = "%2E" + name.dropFirst() }
        name = String(name.prefix(96))
        let digest = SHA256.hash(data: Data(identifier.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return (name.isEmpty ? "" : name + "-") + digest + ".json"
    }

    /// Where a skin's edits file lives (it may not exist).
    public func fileURL(forSkinIdentifier identifier: String) throws -> URL {
        try directoryProvider().appendingPathComponent(Self.fileName(forSkinIdentifier: identifier))
    }

    // MARK: Reading

    /// The whole record for a skin; empty if there is none.
    public func document(for skinIdentifier: String) -> DeltaSkinLayoutEditsDocument {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked(skinIdentifier)
    }

    /// A button's edit for one trait; `.identity` if none.
    public func edit(forButton buttonId: String, skinIdentifier: String, traitKey: String) -> DeltaSkinButtonEdit {
        document(for: skinIdentifier).traits[traitKey]?[buttonId] ?? .identity
    }

    /// Every button edit for one trait, keyed by button id.
    public func edits(skinIdentifier: String, traitKey: String) -> [String: DeltaSkinButtonEdit] {
        document(for: skinIdentifier).traits[traitKey] ?? [:]
    }

    /// The trait keys that have at least one edit, sorted.
    public func editedTraitKeys(skinIdentifier: String) -> [String] {
        document(for: skinIdentifier).traits.filter { !$0.value.isEmpty }.keys.sorted()
    }

    /// `true` if the skin has any edit, or any on `traitKey` when one is given.
    public func hasEdits(skinIdentifier: String, traitKey: String? = nil) -> Bool {
        let doc = document(for: skinIdentifier)
        if let traitKey { return !(doc.traits[traitKey]?.isEmpty ?? true) }
        return !doc.isEmpty
    }

    /// `frame` with the stored edit for the button applied; `frame` itself when there is none.
    public func editedFrame(
        _ frame: CGRect,
        forButton buttonId: String,
        skinIdentifier: String,
        traitKey: String
    ) -> CGRect {
        edit(forButton: buttonId, skinIdentifier: skinIdentifier, traitKey: traitKey).applying(to: frame)
    }

    // MARK: Writing

    /// Stores a button's edit for one trait. The scale is clamped to `DeltaSkinButtonEdit.scaleRange`;
    /// an identity edit removes the entry.
    public func setEdit(
        _ edit: DeltaSkinButtonEdit,
        forButton buttonId: String,
        skinIdentifier: String,
        traitKey: String
    ) throws {
        try mutate(skinIdentifier) { doc in
            var trait = doc.traits[traitKey] ?? [:]
            let normalized = edit.normalized
            if normalized.isIdentity {
                trait.removeValue(forKey: buttonId)
            } else {
                trait[buttonId] = normalized
            }
            doc.traits[traitKey] = trait
        }
    }

    /// Removes one button's edit for one trait.
    public func resetButton(_ buttonId: String, skinIdentifier: String, traitKey: String) throws {
        try setEdit(.identity, forButton: buttonId, skinIdentifier: skinIdentifier, traitKey: traitKey)
    }

    /// Removes every edit for one trait ("reset this layout").
    public func resetTrait(skinIdentifier: String, traitKey: String) throws {
        try mutate(skinIdentifier) { $0.traits.removeValue(forKey: traitKey) }
    }

    /// Removes every edit for a skin and deletes its file ("reset edits for this skin").
    public func resetAll(skinIdentifier: String) throws {
        try mutate(skinIdentifier) { $0.traits.removeAll() }
    }

    /// Applies offsets from the old trait-less `DeltaSkinButtonOffsets` store to every trait in `traitKeys`.
    ///
    /// A button that already has an edit on a trait keeps it, so running this twice (or after the player
    /// has started editing) never overwrites newer work. Zero offsets are ignored.
    public func importLegacyOffsets(
        _ offsets: [String: CGPoint],
        skinIdentifier: String,
        traitKeys: [String]
    ) throws {
        let moved = offsets.filter { $0.value != .zero }
        guard !moved.isEmpty, !traitKeys.isEmpty else { return }
        try mutate(skinIdentifier) { doc in
            for key in traitKeys {
                var trait = doc.traits[key] ?? [:]
                for (buttonId, offset) in moved where trait[buttonId] == nil {
                    trait[buttonId] = DeltaSkinButtonEdit(offset: offset)
                }
                doc.traits[key] = trait
            }
        }
    }

    // MARK: Persistence

    private func loadLocked(_ skinIdentifier: String) -> DeltaSkinLayoutEditsDocument {
        if let cached = cache[skinIdentifier] { return cached }
        var doc = DeltaSkinLayoutEditsDocument(skinIdentifier: skinIdentifier)
        if let url = try? fileURL(forSkinIdentifier: skinIdentifier),
           let data = try? Data(contentsOf: url) {
            do {
                var decoded = try JSONDecoder().decode(DeltaSkinLayoutEditsDocument.self, from: data)
                guard decoded.skinIdentifier == skinIdentifier else {
                    // Another skin's file (should not happen with digest names); never apply its edits here.
                    WLOG("DeltaSkinLayoutEdits: \(url.lastPathComponent) belongs to \(decoded.skinIdentifier), not \(skinIdentifier)")
                    cache[skinIdentifier] = doc
                    return doc
                }
                decoded.traits = decoded.traits.mapValues { $0.mapValues(\.normalized).filter { !$0.value.isIdentity } }
                    .filter { !$0.value.isEmpty }
                doc = decoded
            } catch {
                WLOG("DeltaSkinLayoutEdits: ignoring unreadable edits for \(skinIdentifier): \(error)")
            }
        }
        cache[skinIdentifier] = doc
        return doc
    }

    private func mutate(_ skinIdentifier: String, _ change: (inout DeltaSkinLayoutEditsDocument) -> Void) throws {
        try write(skinIdentifier, change)
        // Outside the lock, so an observer can read the store straight away.
        NotificationCenter.default.post(
            name: Self.didChangeNotification, object: self, userInfo: [Self.skinIdentifierKey: skinIdentifier]
        )
    }

    private func write(_ skinIdentifier: String, _ change: (inout DeltaSkinLayoutEditsDocument) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var doc = loadLocked(skinIdentifier)
        change(&doc)
        doc.traits = doc.traits.filter { !$0.value.isEmpty }
        let url = try fileURL(forSkinIdentifier: skinIdentifier)
        if doc.isEmpty {
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        } else {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(doc).write(to: url, options: .atomic)
        }
        cache[skinIdentifier] = doc
    }
}
