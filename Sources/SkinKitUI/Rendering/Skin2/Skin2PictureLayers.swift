#if canImport(UIKit)
import Combine
import SkinKit2Core
import SkinKit2Render
import SwiftUI
import UIKit

/// One accessory screen's picture, in a layer of its own between the parts of the skin drawn under and over it.
/// It follows the store by itself, so a new picture changes this layer and nothing else.
struct Skin2PictureLayerView: UIViewRepresentable {
    let store: Skin2PictureStore
    let source: String
    let sampling: Skin2Sampling

    func makeUIView(context: Context) -> Skin2PictureUIView {
        let view = Skin2PictureUIView()
        view.bind(store: store, source: source, sampling: sampling)
        return view
    }

    func updateUIView(_ view: Skin2PictureUIView, context: Context) {
        view.bind(store: store, source: source, sampling: sampling)
    }
}

final class Skin2PictureUIView: UIView {
    private weak var store: Skin2PictureStore?
    private var source = ""
    private var subscription: AnyCancellable?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        layer.contentsGravity = .resize
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func bind(store: Skin2PictureStore, source: String, sampling: Skin2Sampling) {
        let filter: CALayerContentsFilter = sampling == .nearest ? .nearest : .linear
        layer.magnificationFilter = filter
        layer.minificationFilter = sampling == .nearest ? .nearest : .trilinear
        if store !== self.store || source != self.source {
            self.store = store
            self.source = source
            subscription = store.didChange.filter { $0 == source }.sink { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let image = store?.image(for: source)
        // Assigning the same image again would still commit a transaction.
        if (layer.contents as AnyObject?) !== image {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = image
            CATransaction.commit()
        }
    }
}
#endif
