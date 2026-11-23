import Foundation

/// Adopt beside `DeltaSkinInputHandling` to take a format 2 skin's semantic inputs: the dotted names of
/// `Skin2SemanticInputs` (`arcade.coin1`, `console.reset`), which are not controller buttons.
///
/// A skin only shows such a control while the app lists `input.<name>` in the capabilities it gives the skin
/// view, so the app decides per core and per game which ones exist. They are never sent to `buttonPressed`.
public protocol DeltaSkinSemanticInputHandling: AnyObject {
    /// A semantic control went down (`pressed` true) or came up.
    func semanticInput(_ name: String, pressed: Bool)
}
