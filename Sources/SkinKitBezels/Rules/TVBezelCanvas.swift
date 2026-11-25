//
//  TVBezelCanvas.swift
//  SkinKitBezels
//
//  The canvas a built-in TV's room is drawn on: the display's shape, at a seat's distance.
//

import CoreGraphics

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
