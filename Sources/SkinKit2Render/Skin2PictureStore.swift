#if canImport(Combine)
import Combine
import CoreGraphics
import Foundation

/// The pictures an app supplies for a skin's accessory screens (a memory unit's LCD), by source name (`vmu.p1`).
///
/// The app owns the store and hands it to the skin view. It sets a finished image at any resolution whenever the
/// picture changes, and nil when there is none (the unit is unplugged, the game has drawn nothing yet). The view
/// shows each picture in a layer of its own, so a new picture does not redraw the skin. SkinKit never reads a
/// picture from a core.
@MainActor
public final class Skin2PictureStore: ObservableObject {
    private var images: [String: CGImage] = [:]
    private let deliveredSubject = CurrentValueSubject<Set<String>, Never>([])

    /// Sends a source's name after its picture was set, changed or cleared.
    public let didChange = PassthroughSubject<String, Never>()

    public init() {}

    /// Sets the picture for `source`; nil means there is none now. Setting the image already there does nothing.
    public func set(_ image: CGImage?, for source: String) {
        guard images[source] !== image else { return }
        objectWillChange.send()
        images[source] = image
        didChange.send(source)
        let now = Set(images.keys)
        if now != deliveredSubject.value { deliveredSubject.send(now) }
    }

    public func image(for source: String) -> CGImage? { images[source] }

    /// The sources that have a picture now.
    public var delivered: Set<String> { deliveredSubject.value }

    /// `delivered` now, then again each time the set of sources changes (not when a picture is replaced).
    public var deliveredChanges: AnyPublisher<Set<String>, Never> { deliveredSubject.eraseToAnyPublisher() }
}
#endif
