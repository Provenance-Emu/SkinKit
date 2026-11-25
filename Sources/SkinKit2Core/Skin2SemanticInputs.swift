import Foundation

/// Inputs that are not controller buttons: an arcade cabinet's coin slot, a console's reset switch, a memory
/// unit's own keys. They have dotted names from this closed registry, so a skin and an app agree on what each
/// one is. Controller buttons keep their classic names (`a`, `start`).
///
/// A control with a semantic input is present only while the app has the capability `input.<name>`
/// (`Skin2Capabilities.input`). Momentary inputs arrive at the app's sink as a press and a release under the
/// dotted name. Two-position switches are reserved here and not built yet: they need a control whose drawn
/// position comes from the app.
@frozen public enum Skin2SemanticInputs {
    @frozen public enum Kind: Sendable { case momentary, twoPosition }

    public struct Entry: Sendable {
        public let name: String
        public let kind: Kind
        /// English label, spoken by VoiceOver when the control has none of its own.
        public let label: String
    }

    public static let all: [Entry] = [
        Entry(name: "arcade.coin1", kind: .momentary, label: "Coin 1"),
        Entry(name: "arcade.coin2", kind: .momentary, label: "Coin 2"),
        Entry(name: "arcade.service", kind: .momentary, label: "Service"),
        Entry(name: "arcade.test", kind: .momentary, label: "Test"),
        Entry(name: "console.reset", kind: .momentary, label: "Reset"),
        Entry(name: "console.select", kind: .momentary, label: "Select"),
        Entry(name: "console.difficulty.left", kind: .twoPosition, label: "Left Difficulty"),
        Entry(name: "console.difficulty.right", kind: .twoPosition, label: "Right Difficulty"),
        Entry(name: "console.tvType", kind: .twoPosition, label: "TV Type"),
        Entry(name: "vmu.a", kind: .momentary, label: "Memory Unit A"),
        Entry(name: "vmu.b", kind: .momentary, label: "Memory Unit B"),
        Entry(name: "vmu.mode", kind: .momentary, label: "Memory Unit Mode"),
        Entry(name: "vmu.sleep", kind: .momentary, label: "Memory Unit Sleep"),
        Entry(name: "vmu.up", kind: .momentary, label: "Memory Unit Up"),
        Entry(name: "vmu.down", kind: .momentary, label: "Memory Unit Down"),
        Entry(name: "vmu.left", kind: .momentary, label: "Memory Unit Left"),
        Entry(name: "vmu.right", kind: .momentary, label: "Memory Unit Right"),
    ]

    public static func entry(_ name: String) -> Entry? { all.first { $0.name == name } }

    /// A dotted name is a semantic input; classic input names have no dot.
    public static func isSemantic(_ input: String) -> Bool { input.contains(".") }
}

extension Skin2Node {
    /// The semantic inputs a control sends.
    public var semanticInputs: [String] { type == .control ? inputNames.filter(Skin2SemanticInputs.isSemantic) : [] }
}
