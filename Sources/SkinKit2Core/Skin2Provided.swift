import Foundation

/// What a resolved skin gives the player itself, so the app can hide its own copy: show the floating memory unit
/// unless `pictures` contains `vmu.p1`.
///
/// It is read from the resolved tree, never from the document, so a declaration alone claims nothing:
///
/// - A **picture** is provided when the app has `picture.<source>` and an accessory screen with that source is
///   present, at least `minimumPicture` in size, inside the canvas and more opaque than `minimumOpacity`.
/// - An **input** (semantic inputs only) is provided when a control that sends it is present with a hit frame of
///   at least `minimumControl` inside the canvas.
/// - A node in a closed shelf counts as it would with the shelf open, as long as the shelf's handle is reachable:
///   the player closed it on purpose and can open it again. A shelf whose handle is off screen provides nothing.
/// - A screen or control marked `"duplicate": true` claims nothing.
///
/// A skin view narrows `pictures` further to the sources the app has actually delivered (`keeping(pictures:)`).
public struct Skin2Provided: Equatable, Sendable {
    /// Picture sources the skin shows (`vmu.p1`).
    public var pictures: Set<String>
    /// Semantic inputs the skin has a control for (`arcade.coin1`).
    public var inputs: Set<String>
    /// The panels that are present, by name, and whether each is open (a fixed panel always is).
    public var panels: [String: Bool]

    public init(pictures: Set<String>, inputs: Set<String>, panels: [String: Bool]) {
        self.pictures = pictures; self.inputs = inputs; self.panels = panels
    }

    public static let none = Skin2Provided(pictures: [], inputs: [], panels: [:])

    /// The smallest frame, in points, a provided picture may have.
    public static let minimumPicture = Skin2Size(width: 48, height: 32)
    /// The smallest hit frame, in points, a provided control or a shelf's handle may have.
    public static let minimumControl = Skin2Size(width: 44, height: 44)
    /// A picture at or below this opacity is not provided.
    public static let minimumOpacity = 0.05

    /// The same report with `pictures` cut down to the sources the app has delivered a picture for.
    public func keeping(pictures delivered: Set<String>) -> Skin2Provided {
        Skin2Provided(pictures: pictures.intersection(delivered), inputs: inputs, panels: panels)
    }

    /// `opened` is the same layout with every reachable closed shelf (`closed`) open; only nodes of those shelves
    /// are read from it.
    init(_ resolution: Skin2Resolution, opened: Skin2Resolution?, closed: Set<String>) {
        self = .none
        for panel in resolution.panels { panels[panel.panel.name] = panel.isOpen }
        collect(resolution.root, opacity: 1, in: resolution.environment, only: nil)
        if let opened { collect(opened.root, opacity: 1, in: opened.environment, only: closed) }
    }

    private static let tolerance = 0.0001

    private static func fits(_ frame: Skin2Rect, minimum: Skin2Size, in canvas: Skin2Rect) -> Bool {
        frame.width >= minimum.width - tolerance && frame.height >= minimum.height - tolerance
            && canvas.outset(Skin2Insets(top: tolerance, left: tolerance, bottom: tolerance, right: tolerance)).contains(frame)
    }

    private mutating func collect(_ r: Skin2ResolvedNode, opacity above: Double, in environment: Skin2Environment, only: Set<String>?) {
        let opacity = above * r.opacity
        let counts = only.map { names in r.panelName.map(names.contains) ?? false } ?? true
        if counts, !r.node.duplicate {
            if r.node.isAccessoryScreen, let source = r.node.source,
               environment.capabilities.contains(Skin2Capabilities.picture(source)), opacity > Self.minimumOpacity,
               Self.fits(r.frame, minimum: Self.minimumPicture, in: environment.canvasRect) {
                pictures.insert(source)
            }
            if let hit = r.hitFrame, Self.fits(hit, minimum: Self.minimumControl, in: environment.canvasRect) {
                inputs.formUnion(r.node.semanticInputs)
            }
        }
        for child in r.children { collect(child, opacity: opacity, in: environment, only: only) }
    }
}
