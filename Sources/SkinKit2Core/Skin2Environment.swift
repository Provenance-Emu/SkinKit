import Foundation

/// What a skin is resolved for: the canvas, its safe area and the traits conditions read (4.1, 4.6).
public struct Skin2Environment: Equatable, Hashable, Sendable {
    public var size: Skin2Size
    public var safeArea: Skin2Insets
    /// Given explicitly because classic trait sets don't always match the canvas shape (iPad split view
    /// landscape is 639×834).
    public var orientation: Skin2Orientation
    public var device: Skin2Device
    public var displayType: Skin2DisplayType
    /// App flags that are on (`microphone`, `keypadShown`, `altToggled`).
    public var flags: Set<String>

    public init(size: Skin2Size, safeArea: Skin2Insets = .zero, orientation: Skin2Orientation? = nil,
                device: Skin2Device = .iphone, displayType: Skin2DisplayType = .edgeToEdge, flags: Set<String> = []) {
        self.size = size
        self.safeArea = safeArea
        self.orientation = orientation ?? (size.height >= size.width ? .portrait : .landscape)
        self.device = device
        self.displayType = displayType
        self.flags = flags
    }

    public var canvasRect: Skin2Rect { Skin2Rect(size: size) }
    public var safeRect: Skin2Rect { canvasRect.inset(safeArea) }
}

/// The classic trait sets the baker writes (8.1). The validator resolves every one a skin bakes to check hit
/// frames; `layout.json` fixtures are recorded per trait set.
public struct Skin2TraitSet: Equatable, Hashable, Sendable {
    public var device: Skin2Device
    public var displayType: Skin2DisplayType
    public var orientation: Skin2Orientation
    public var size: Skin2Size
    public var safeArea: Skin2Insets

    /// `iphone-edgeToEdge-portrait`, the name the baker gives the PDF.
    public var name: String { "\(device.rawValue)-\(displayType.rawValue)-\(orientation.rawValue)" }
    /// `iphone.edgeToEdge`, the form `bake.traits` uses.
    public var family: String { "\(device.rawValue).\(displayType.rawValue)" }

    public var environment: Skin2Environment {
        Skin2Environment(size: size, safeArea: safeArea, orientation: orientation, device: device, displayType: displayType)
    }

    static func t(_ d: Skin2Device, _ t: Skin2DisplayType, _ o: Skin2Orientation, _ w: Double, _ h: Double,
                  _ top: Double, _ left: Double, _ bottom: Double, _ right: Double) -> Skin2TraitSet {
        Skin2TraitSet(device: d, displayType: t, orientation: o, size: Skin2Size(width: w, height: h),
                      safeArea: Skin2Insets(top: top, left: left, bottom: bottom, right: right))
    }

    /// Section 8.1, in table order.
    public static let all: [Skin2TraitSet] = [
        t(.iphone, .standard, .portrait, 414, 736, 0, 0, 0, 0),
        t(.iphone, .standard, .landscape, 736, 414, 0, 0, 0, 0),
        t(.iphone, .edgeToEdge, .portrait, 393, 852, 59, 0, 34, 0),
        t(.iphone, .edgeToEdge, .landscape, 852, 393, 0, 59, 21, 59),
        t(.ipad, .standard, .portrait, 834, 1194, 24, 0, 20, 0),
        t(.ipad, .standard, .landscape, 1194, 834, 24, 0, 20, 0),
        t(.ipad, .splitView, .portrait, 639, 1194, 24, 0, 20, 0),
        t(.ipad, .splitView, .landscape, 639, 834, 24, 0, 20, 0),
        t(.tv, .standard, .landscape, 1920, 1080, 60, 80, 60, 80),
    ]

    public static let familyNames: [String] = {
        var seen: [String] = []
        for t in all where !seen.contains(t.family) { seen.append(t.family) }
        return seen
    }()

    /// The families every skin bakes: the base representations must be a complete classic skin.
    public static let requiredFamilies = ["iphone.standard", "iphone.edgeToEdge"]

    public static func family(named name: String) -> [Skin2TraitSet]? {
        let sets = all.filter { $0.family == name }
        return sets.isEmpty ? nil : sets
    }

    /// The trait sets a skin bakes to: `bake.traits`, or all of them.
    public static func sets(for document: Skin2Document) -> [Skin2TraitSet] {
        guard let families = document.bake?.traits else { return all }
        return all.filter { families.contains($0.family) }
    }
}
