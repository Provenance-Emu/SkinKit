//
//  BezelSettingsStore.swift
//  SkinKitBezels
//
//  Where the player's TV choices are stored.
//

import Foundation

/// The player's TV choices. Each app stores them its own way: Provenance in its `Defaults`
/// keys, an app with nothing of its own in `UserDefaultsBezelSettings`.
///
/// An implementation posts `Notification.Name.bezelSettingsDidChange` on the main queue after
/// any value changes, whoever changed it, so open views can re-read.
public protocol BezelSettingsStore: AnyObject, Sendable {
    /// The TV for every game: a `TVBezel` id, `ExternalDisplayBezelRules.noBezelID` for none
    /// or `automaticBezelID`, which is what a player who never chose has.
    var chosenBezel: String { get set }
    /// With a TV chosen, prefer the TV that lists the game's system.
    var matchesSystem: Bool { get set }
    /// The picture lights the room; `nil` until the player sets it (it then goes by the device).
    var lightsRoom: Bool? { get set }
    /// Look for artwork made for each game.
    var showsGameArtwork: Bool { get set }
    var bezelProjectStyle: BezelProjectStyle { get set }
    /// TVs pinned to single games: the app's game key to a `TVBezel` id (`noBezelID` for none).
    var pinnedBezels: [String: String] { get set }
}

public extension Notification.Name {
    /// Posted on the main queue when a `BezelSettingsStore` value changed.
    static let bezelSettingsDidChange = Notification.Name("SkinKitBezelSettingsDidChangeNotification")
}

public extension BezelSettingsStore {
    /// The TV pinned to `game`: `nil` for none pinned, `noBezelID` for no TV.
    func pinnedBezel(forGame game: String?) -> String? {
        game.flatMap { pinnedBezels[$0] }
    }

    /// Posts `bezelSettingsDidChange` on the main queue.
    func notifyChanged() {
        DispatchQueue.main.async { [weak self] in
            NotificationCenter.default.post(name: .bezelSettingsDidChange, object: self)
        }
    }
}

/// The choices in a `UserDefaults` suite, under keys with a prefix of the app's own.
public final class UserDefaultsBezelSettings: BezelSettingsStore, @unchecked Sendable {

    private enum Key: String {
        case chosenBezel, matchesSystem, lightsRoom, showsGameArtwork, bezelProjectStyle, pinnedBezels
    }

    private let defaults: UserDefaults
    private let prefix: String

    /// - Parameter prefix: put before every key, such as `iFly.bezel.`.
    public init(defaults: UserDefaults = .standard, prefix: String = "bezel.") {
        self.defaults = defaults
        self.prefix = prefix
    }

    private func key(_ key: Key) -> String { prefix + key.rawValue }

    private func set(_ value: Any?, _ key: Key) {
        defaults.set(value, forKey: self.key(key))
        notifyChanged()
    }

    public var chosenBezel: String {
        get { defaults.string(forKey: key(.chosenBezel)) ?? ExternalDisplayBezelRules.automaticBezelID }
        set { set(newValue, .chosenBezel) }
    }

    public var matchesSystem: Bool {
        get { defaults.object(forKey: key(.matchesSystem)) as? Bool ?? true }
        set { set(newValue, .matchesSystem) }
    }

    public var lightsRoom: Bool? {
        get { defaults.object(forKey: key(.lightsRoom)) as? Bool }
        set { set(newValue, .lightsRoom) }
    }

    public var showsGameArtwork: Bool {
        get { defaults.bool(forKey: key(.showsGameArtwork)) }
        set { set(newValue, .showsGameArtwork) }
    }

    public var bezelProjectStyle: BezelProjectStyle {
        get { defaults.string(forKey: key(.bezelProjectStyle)).flatMap(BezelProjectStyle.init(rawValue:)) ?? .gameArt }
        set { set(newValue.rawValue, .bezelProjectStyle) }
    }

    public var pinnedBezels: [String: String] {
        get { defaults.dictionary(forKey: key(.pinnedBezels)) as? [String: String] ?? [:] }
        set { set(newValue, .pinnedBezels) }
    }
}
