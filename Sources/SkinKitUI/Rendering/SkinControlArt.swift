#if canImport(UIKit)
import SkinKitCore
import UIKit

/// The image a skin draws over its background for one control: a button with its own artwork, or a
/// thumbstick cap.
///
/// ``DeltaSkinView`` draws these while a game runs and ``DeltaSkinRenderable/previewImage(for:maxDimension:)``
/// draws them into a skin's preview. Both read them from here, so a preview cannot leave out art
/// the game shows. (Previews drew only the background image from March 2026, when the picker cells
/// stopped hosting a live `DeltaSkinView`, until this type.)
public struct SkinControlArt {
    public let buttonID: String
    /// Where the art is drawn, in the representation's mapping units.
    public let frame: CGRect
    public let normal: UIImage
    /// Shown while the control is pressed. `nil` keeps `normal`.
    public let pressed: UIImage?
    /// The size a thumbstick's raw item declares for its cap. `nil` for a button.
    public let thumbstickSize: CGSize?

    public var isThumbstick: Bool { thumbstickSize != nil }
}

public extension DeltaSkinProtocol {
    /// The raw `items` entry a decoded control came from, matched by frame, in the same representation
    /// the control was decoded from (see `DeltaSkin.rawItems(in:for:)`).
    func rawItem(matching button: DeltaSkinButton, traits: DeltaSkinTraits) -> [String: Any]? {
        DeltaSkin.rawItems(in: jsonRepresentation, for: traits)?.first { item in
            guard let frame = item["frame"] as? [String: Any],
                  let x = frame["x"] as? CGFloat,
                  let y = frame["y"] as? CGFloat,
                  let width = frame["width"] as? CGFloat,
                  let height = frame["height"] as? CGFloat else { return false }
            return CGRect(x: x, y: y, width: width, height: height) == button.frame
        }
    }
}

public extension DeltaSkinRenderable {
    /// Every control with artwork of its own, in item order. For each control the first source that
    /// loads wins: the selected theme's art, the item's `states` (Manic format), then its `asset`.
    func buttonArt(for traits: DeltaSkinTraits) async -> [SkinControlArt] {
        guard let buttons = buttons(for: traits) else { return [] }
        var art: [SkinControlArt] = []
        for (index, button) in buttons.enumerated() {
            if let image = await themedItemImage(forItemAt: index, traits: traits) {
                art.append(SkinControlArt(buttonID: button.id, frame: button.frame, normal: image, pressed: nil,
                                          thumbstickSize: nil))
                continue
            }
            var names: [(String, String?)] = []
            if let normalName = button.states?.normal?.image {
                names.append((normalName, button.states?.pressed?.image))
            }
            if let assetNames = assetNames(for: button, traits: traits) {
                names.append(assetNames)
            }
            for (normalName, pressedName) in names {
                do {
                    let normal = try await loadThumbstickImage(named: normalName)
                    var pressed: UIImage?
                    if let pressedName {
                        do {
                            pressed = try await loadThumbstickImage(named: pressedName)
                        } catch {
                            ELOG("Failed to load pressed image '\(pressedName)' for button \(button.id): \(error)")
                        }
                    }
                    art.append(SkinControlArt(buttonID: button.id, frame: button.frame, normal: normal,
                                              pressed: pressed, thumbstickSize: nil))
                    break
                } catch {
                    ELOG("Failed to load button image '\(normalName)' for \(button.id): \(error)")
                }
            }
        }
        return art
    }

    /// The cap image of one thumbstick control, or `nil` when `button` is not a thumbstick or its
    /// image does not load.
    func thumbstickArt(for button: DeltaSkinButton, traits: DeltaSkinTraits) async -> SkinControlArt? {
        guard let thumbstick = rawItem(matching: button, traits: traits)?["thumbstick"] as? [String: Any],
              let imageName = thumbstick["name"] as? String,
              let width = thumbstick["width"] as? CGFloat,
              let height = thumbstick["height"] as? CGFloat else { return nil }
        do {
            let image = try await loadThumbstickImage(named: imageName)
            return SkinControlArt(buttonID: button.id, frame: button.frame, normal: image, pressed: nil,
                                  thumbstickSize: CGSize(width: width, height: height))
        } catch {
            ELOG("Failed to load thumbstick image '\(imageName)': \(error)")
            return nil
        }
    }

    /// Every thumbstick cap, in item order.
    func thumbstickArt(for traits: DeltaSkinTraits) async -> [SkinControlArt] {
        var art: [SkinControlArt] = []
        for button in buttons(for: traits) ?? [] {
            if let cap = await thumbstickArt(for: button, traits: traits) {
                art.append(cap)
            }
        }
        return art
    }

    /// The skin as it looks in a game with nothing pressed: its background with button art and
    /// thumbstick caps drawn where ``DeltaSkinView`` draws them, no longer than `maxDimension` points
    /// on its longest side.
    ///
    /// A skin with no control art returns its ``thumbnail(for:maxDimension:)`` unchanged, which the
    /// skin keeps on disk.
    func previewImage(for traits: DeltaSkinTraits, maxDimension: CGFloat) async throws -> UIImage {
        let background = try await thumbnail(for: traits, maxDimension: maxDimension)
        guard let mappingSize = mappingSize(for: traits), mappingSize.width > 0, mappingSize.height > 0 else {
            return background
        }
        let art = await buttonArt(for: traits) + thumbstickArt(for: traits)
        guard !art.isEmpty else { return background }
        return SkinControlArt.composite(art, over: background, mappingSize: mappingSize)
    }

    /// `asset.normal` and `asset.pressed` of the raw item `button` came from.
    private func assetNames(for button: DeltaSkinButton, traits: DeltaSkinTraits) -> (String, String?)? {
        guard let asset = rawItem(matching: button, traits: traits)?["asset"] as? [String: Any],
              let normal = asset["normal"] as? String else { return nil }
        return (normal, asset["pressed"] as? String)
    }
}

extension SkinControlArt {
    /// `background` with each piece of art drawn over it at rest. Art frames are in `mappingSize`
    /// units and the background covers the whole mapping, which is how the skin view scales them.
    static func composite(_ art: [SkinControlArt], over background: UIImage, mappingSize: CGSize) -> UIImage {
        let size = background.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = background.scale
        format.opaque = false
        let scaleX = size.width / mappingSize.width
        let scaleY = size.height / mappingSize.height
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            background.draw(in: CGRect(origin: .zero, size: size))
            for piece in art {
                piece.normal.draw(in: CGRect(x: piece.frame.minX * scaleX, y: piece.frame.minY * scaleY,
                                             width: piece.frame.width * scaleX, height: piece.frame.height * scaleY))
            }
        }
    }
}
#endif
