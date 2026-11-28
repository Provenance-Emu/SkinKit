//
//  TVBezelCanvas.swift
//  SkinKitBezels
//
//  The canvas a built-in TV's room is drawn on: the display's shape, at a seat's distance.
//

import CoreGraphics
import Foundation

/// Where the player sits in front of a built-in TV. A closer seat draws less of the room, so
/// everything in it is larger.
@frozen public enum TVBezelSeat: String, CaseIterable, Sendable {
    case back
    case middle
    case front

    /// The height of the canvas the room is drawn on from this seat, in points. The room is
    /// laid out 1080 points tall; a shorter canvas is a centred crop of it.
    public var canvasHeight: CGFloat {
        switch self {
        case .back: return 1080
        case .middle: return 980
        case .front: return 900
        }
    }

    /// How much of a portrait canvas is kept on each side of the TV's tube from this seat, in
    /// points. A portrait screen is narrow, so the picture gets nearly all of its width: only
    /// the inner edge of the TV's frame shows beside it, and the cabinet's sides are off screen.
    public var portraitTubeMargin: CGFloat {
        switch self {
        case .back: return 28
        case .middle: return 18
        case .front: return 10
        }
    }

    /// The width of the canvas a portrait room is drawn on from this seat when the TV's tube
    /// is not known, in points. `TVBezelCanvas.portraitSize(display:seat:tube:)` draws
    /// closer: prefer it.
    public var portraitCanvasWidth: CGFloat {
        switch self {
        case .back: return 1280
        case .middle: return 1216
        case .front: return 1152
        }
    }
}

public extension TVBezelSeat {
    /// The seat's name in a menu.
    var displayName: String {
        switch self {
        case .back: return String(localized: "Back")
        case .middle: return String(localized: "Middle")
        case .front: return String(localized: "Front")
        }
    }

    /// The next seat towards the TV; from the front it goes round to the back. What one
    /// button that steps through the seats moves to.
    var nextCloser: TVBezelSeat {
        switch self {
        case .back: return .middle
        case .middle: return .front
        case .front: return .back
        }
    }
}

/// The shape of the game picture a TV is drawn for. A TV whose document has a widescreen
/// form (it reads the `TVBezelPictureShape.wideFlag` flag) widens its tube and cabinet for a
/// wide picture; any other TV keeps its 4:3 tube and the picture is fitted inside it.
@frozen public enum TVBezelPictureShape: String, Hashable, Sendable {
    case standard
    case wide

    /// The flag a TV's document reads in a `when` or `visible` condition.
    public static let wideFlag = "tv.wide"

    /// Pictures at least this wide (width over height) are wide: 16:10 and up, so 3:2 and
    /// 4:3 stay in a 4:3 tube.
    public static let wideThreshold: CGFloat = 1.6

    /// How far below `wideThreshold` a ratio may be and still count as wide.
    private static let tolerance: CGFloat = 0.001

    /// The shape of a picture of `aspect` (only the ratio matters).
    public init(aspect: CGSize) {
        let isWide = aspect.height > 0 && aspect.width / aspect.height >= Self.wideThreshold - Self.tolerance
        self = isWide ? .wide : .standard
    }
}

/// The canvas for a display. A TV's document is resolved on it, so the room has the
/// display's proportions and nothing is cropped or barred.
@frozen public enum TVBezelCanvas {
    /// The narrowest and widest canvas (width over height) the built-in TVs lay out for:
    /// 4:3 keeps the widest tube and cabinet on the canvas, 2.4:1 is as far as the wall
    /// details reach.
    public static let ratioRange: ClosedRange<CGFloat> = (4.0 / 3.0)...2.4

    /// How far a display's ratio may be outside `ratioRange` and still count as inside.
    private static let ratioTolerance: CGFloat = 0.001

    /// The canvas for a display of `display` (any unit) seen from `seat`. A display outside
    /// `ratioRange` gets the nearest supported canvas; an empty one the default canvas.
    public static func size(display: CGSize, seat: TVBezelSeat = .back) -> CGSize {
        guard display.width > 0, display.height > 0 else { return TVBezelArtwork.canvas }
        let height = seat.canvasHeight
        let ratio = display.width / display.height
        if ratio < ratioRange.lowerBound { return CGSize(width: height * 4 / 3, height: height) }
        if ratio > ratioRange.upperBound { return CGSize(width: height * 12 / 5, height: height) }
        return CGSize(width: height * display.width / display.height, height: height)
    }

    /// The portrait displays (width over height) a portrait room is drawn for: from a tall
    /// phone to an iPad held upright. Squarer windows get the 4:3 landscape canvas.
    public static let portraitRatioRange: ClosedRange<CGFloat> = 0.4...0.8

    /// The canvas of a portrait room for `display`: `seat.portraitCanvasWidth` wide, with the
    /// display's proportions, so the room is the whole display. `nil` for a display that is
    /// not a portrait shape. Only a TV whose document has a portrait form
    /// (`TVBezel.drawsPortrait`) can be laid out on it.
    public static func portraitSize(display: CGSize, seat: TVBezelSeat = .back) -> CGSize? {
        guard display.width > 0, display.height > 0 else { return nil }
        let ratio = display.width / display.height
        guard portraitRatioRange.contains(ratio) else { return nil }
        let width = seat.portraitCanvasWidth
        return CGSize(width: width, height: (width / ratio).rounded())
    }

    /// How much of a portrait canvas's height the set may take: the rest is the console the
    /// app's touch controls float over.
    public static let portraitSetShare: CGFloat = 0.55
    /// What a set adds to its tube's height on a portrait canvas, in points: the gap above
    /// it and the cabinet above and below the tube.
    static let portraitSetExtraHeight: CGFloat = 260

    /// The canvas of a portrait room for a TV whose tube is `tube` canvas points large: the
    /// tube and `seat.portraitTubeMargin` on each side, with the display's proportions. On a
    /// squarer display (a tablet held upright) that would fill the screen with the set, so
    /// the canvas is widened until the set takes `portraitSetShare` of its height.
    /// `nil` for a display that is not a portrait shape, or no tube.
    public static func portraitSize(display: CGSize, seat: TVBezelSeat = .back, tube: CGSize) -> CGSize? {
        guard display.width > 0, display.height > 0, tube.width > 0, tube.height > 0 else { return nil }
        let ratio = display.width / display.height
        guard portraitRatioRange.contains(ratio) else { return nil }
        let zoomed = tube.width + 2 * seat.portraitTubeMargin
        let roomy = ratio * (tube.height + portraitSetExtraHeight) / portraitSetShare
        let width = max(zoomed, roomy).rounded()
        return CGSize(width: width, height: (width / ratio).rounded())
    }

    /// Whether `display`'s shape is one the canvas can match exactly. When it is not, the
    /// canvas from `size(display:seat:)` has another shape and the app places it itself: it
    /// must keep the scene's tube (`TVBezelScene.tubeRect`) on the display, because plainly
    /// covering a very wide or very narrow display with the clamped canvas crops the tube.
    public static func fitsDisplay(_ display: CGSize) -> Bool {
        guard display.width > 0, display.height > 0 else { return false }
        let ratio = display.width / display.height
        return ratio >= ratioRange.lowerBound - ratioTolerance && ratio <= ratioRange.upperBound + ratioTolerance
    }
}
