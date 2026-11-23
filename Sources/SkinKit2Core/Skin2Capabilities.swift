import Foundation

/// Capability names: what the app and the running game can supply right now (a memory-unit picture, a wired
/// semantic input). The registry is closed, so a skin cannot invent one; the validator rejects other names.
/// Capabilities reach a skin through `Skin2Environment.capabilities` and the `has` condition.
public enum Skin2Capabilities {
    static let picturePrefix = "picture."
    static let inputPrefix = "input."

    /// The pictures an app may supply to an accessory screen, by source name.
    public static let pictureSources: [String] = ["vmu.p1", "vmu.p2", "vmu.p3", "vmu.p4"]

    /// The capability for a picture source: `vmu.p1` → `picture.vmu.p1`.
    public static func picture(_ source: String) -> String { picturePrefix + source }

    /// The capability for a semantic input: `arcade.coin1` → `input.arcade.coin1`.
    public static func input(_ name: String) -> String { inputPrefix + name }

    public static func isKnown(_ capability: String) -> Bool {
        if capability.hasPrefix(picturePrefix) {
            return pictureSources.contains(String(capability.dropFirst(picturePrefix.count)))
        }
        return false
    }
}
