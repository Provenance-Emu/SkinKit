import CoreGraphics
import CoreText
import Foundation
import SkinKit2Core

/// Text as glyph outlines (section 9.3): CoreText shapes the line (kerning, no hinting), then each glyph's outline
/// from `CTFontCreatePathForGlyph` is filled as a path, so text is a shape and the TypeScript renderer
/// (opentype.js) can match it from the same font file.
///
/// The default face is Outfit (SIL OFL 1.1), bundled as `Resources/Fonts/Outfit-Regular.ttf` and `-Bold.ttf`; the
/// skins repo ships the same files. `regular` and `medium` use Regular, `semibold` and `bold` use Bold.
public enum Skin2Text {
    /// The outline of `text` laid out in `frame`: one line, vertically centred on the font's ascent and descent,
    /// aligned by `align`. `size` is in canvas points. With `fit`, the size shrinks (to 60 % at most) until the
    /// line fits the frame's width.
    public static func path(_ text: String, font: CGFont, size: CGFloat, align: Skin2TextAlign, fit: Bool, in frame: CGRect) -> CGPath {
        var pointSize = size
        var line = makeLine(text, font: font, size: pointSize)
        if fit {
            let width = CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil))
            if width > frame.width, width > 0 {
                pointSize = size * max(0.6, frame.width / width)
                line = makeLine(text, font: font, size: pointSize)
            }
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line.line, &ascent, &descent, nil))
        let x: CGFloat
        switch align {
        case .leading: x = frame.minX
        case .center: x = frame.midX - width / 2
        case .trailing: x = frame.maxX - width
        }
        let baseline = frame.midY + (ascent - descent) / 2
        let out = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line.line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? line.font
            for (g, pos) in zip(glyphs, positions) {
                // Glyph outlines are y-up; flip them onto the y-down canvas at the baseline.
                var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x + pos.x, ty: baseline - pos.y)
                if let gp = CTFontCreatePathForGlyph(runFont, g, &t) { out.addPath(gp) }
            }
        }
        return out
    }

    private static func makeLine(_ text: String, font: CGFont, size: CGFloat) -> (line: CTLine, font: CTFont) {
        let ct = CTFontCreateWithGraphicsFont(font, size, nil, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: ct]
        let string = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        return (CTLineCreateWithAttributedString(string), ct)
    }

    /// The bundled default face for a weight.
    public static func defaultFont(_ weight: Skin2FontWeight) -> CGFont? {
        switch weight {
        case .regular, .medium: return regular
        case .semibold, .bold: return bold
        }
    }

    /// A font from the bytes of a TrueType or OpenType file (`assets/fonts/<family>`).
    public static func font(data: Data) -> CGFont? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGFont(provider)
    }

    private static func bundled(_ name: String) -> CGFont? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf"),
              let data = try? Data(contentsOf: url) else { return nil }
        return font(data: data)
    }

    nonisolated(unsafe) private static let regular = bundled("Outfit-Regular")
    nonisolated(unsafe) private static let bold = bundled("Outfit-Bold")
}
