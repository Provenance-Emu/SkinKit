#if canImport(UIKit)
import Foundation
import SkinKit2Core

/// Which of a skin's shelves are open. The skin view owns one, gives the resolver its `flags`
/// (`panel.<name>.open`), and flips a shelf when its handle is touched.
///
/// A shelf starts as the skin's `open` says. Once the player toggles it, the choice is stored per skin identifier
/// and panel name beside the app's other skin choices, and applies the next time that skin is shown. With no
/// identifier nothing is stored.
@MainActor
final class Skin2PanelState: ObservableObject {
    /// The open flags that are on.
    @Published private(set) var flags: Set<String> = []

    private var shelves: [Skin2Panel] = []
    private var skinIdentifier: String?
    private let defaults: UserDefaults

    init(document: Skin2Document, skinIdentifier: String?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        adopt(document: document, skinIdentifier: skinIdentifier)
    }

    static func key(skin: String, panel: String) -> String { "SkinKit.format2.panelOpen.\(skin).\(panel)" }

    /// Reads the shelves of `document` again (a new skin, theme or variant in the same view).
    func adopt(document: Skin2Document, skinIdentifier: String?) {
        var found: [Skin2Panel] = []
        document.root.preorder { if let panel = $0.panel, $0.panelCanBeShelf { found.append(panel) } }
        guard found != shelves || skinIdentifier != self.skinIdentifier else { return }
        shelves = found
        self.skinIdentifier = skinIdentifier
        var open: Set<String> = []
        for shelf in shelves where stored(shelf.name) ?? shelf.open { open.insert(shelf.openFlag) }
        if open != flags { flags = open }
    }

    private func stored(_ panel: String) -> Bool? {
        guard let skinIdentifier else { return nil }
        return defaults.object(forKey: Self.key(skin: skinIdentifier, panel: panel)) as? Bool
    }

    func toggle(_ panel: String) {
        guard let shelf = shelves.first(where: { $0.name == panel }) else { return }
        let open = !flags.contains(shelf.openFlag)
        if open { flags.insert(shelf.openFlag) } else { flags.remove(shelf.openFlag) }
        if let skinIdentifier { defaults.set(open, forKey: Self.key(skin: skinIdentifier, panel: panel)) }
    }
}
#endif
