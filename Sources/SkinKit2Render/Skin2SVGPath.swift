import CoreGraphics
import Foundation

/// SVG path data (`shapes.path`): `M L H V C S Q T A Z`, absolute and relative, implicit repeats, compact numbers
/// (`1.5.5`, `-1-2`, `1e-3`) and compact arc flags. The path is built in its own `box` and stretched,
/// non-uniformly, onto the frame. Arcs become cubics (at most 90° each) so both renderers draw the same curve.
/// Malformed data ends the path at the last complete command.
public enum Skin2SVGPath {
    public static func path(_ d: String, box: CGRect, in rect: CGRect) -> CGPath {
        let sx = box.width > 0 ? rect.width / box.width : 1
        let sy = box.height > 0 ? rect.height / box.height : 1
        var t = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: sx, y: sy).translatedBy(x: -box.minX, y: -box.minY)
        let raw = parse(d)
        return raw.copy(using: &t) ?? raw
    }

    /// The path in its own coordinates.
    public static func parse(_ d: String) -> CGPath {
        var s = Scanner(Array(d.utf8))
        let p = CGMutablePath()
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: UInt8 = 0
        var command: UInt8 = 0

        while true {
            s.skipSeparators()
            guard let c = s.peek() else { break }
            if Scanner.isCommand(c) {
                command = c
                s.advance()
            } else if command == 0 || command == UInt8(ascii: "Z") || command == UInt8(ascii: "z") {
                break
            }
            let rel = command >= UInt8(ascii: "a")
            let base = rel ? cur : .zero
            let upper = rel ? command - 32 : command
            func pt() -> CGPoint? {
                guard let x = s.number(), let y = s.number() else { return nil }
                return CGPoint(x: base.x + x, y: base.y + y)
            }
            var ok = true
            switch upper {
            case UInt8(ascii: "M"):
                guard let q = pt() else { ok = false; break }
                p.move(to: q); cur = q; start = q
                // Further pairs after a moveto are linetos.
                command = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "L"):
                guard let q = pt() else { ok = false; break }
                ensureStarted(p, cur); p.addLine(to: q); cur = q
            case UInt8(ascii: "H"):
                guard let x = s.number() else { ok = false; break }
                ensureStarted(p, cur); cur = CGPoint(x: base.x + x, y: cur.y); p.addLine(to: cur)
            case UInt8(ascii: "V"):
                guard let y = s.number() else { ok = false; break }
                ensureStarted(p, cur); cur = CGPoint(x: cur.x, y: base.y + y); p.addLine(to: cur)
            case UInt8(ascii: "C"):
                guard let c1 = pt(), let c2 = pt(), let q = pt() else { ok = false; break }
                ensureStarted(p, cur); p.addCurve(to: q, control1: c1, control2: c2); lastControl = c2; cur = q
            case UInt8(ascii: "S"):
                guard let c2 = pt(), let q = pt() else { ok = false; break }
                let c1 = isCubic(lastCommand) ? reflect(lastControl ?? cur, about: cur) : cur
                ensureStarted(p, cur); p.addCurve(to: q, control1: c1, control2: c2); lastControl = c2; cur = q
            case UInt8(ascii: "Q"):
                guard let c1 = pt(), let q = pt() else { ok = false; break }
                ensureStarted(p, cur); p.addQuadCurve(to: q, control: c1); lastControl = c1; cur = q
            case UInt8(ascii: "T"):
                guard let q = pt() else { ok = false; break }
                let c1 = isQuad(lastCommand) ? reflect(lastControl ?? cur, about: cur) : cur
                ensureStarted(p, cur); p.addQuadCurve(to: q, control: c1); lastControl = c1; cur = q
            case UInt8(ascii: "A"):
                guard let rx = s.number(), let ry = s.number(), let rot = s.number(),
                      let large = s.flag(), let sweep = s.flag(), let q = pt() else { ok = false; break }
                ensureStarted(p, cur)
                addArc(p, from: cur, to: q, rx: abs(rx), ry: abs(ry), rotation: rot, large: large, sweep: sweep)
                cur = q
            case UInt8(ascii: "Z"):
                p.closeSubpath(); cur = start
            default:
                ok = false
            }
            if !ok { break }
            lastCommand = upper
        }
        return p
    }

    private static func ensureStarted(_ p: CGMutablePath, _ cur: CGPoint) {
        if p.isEmpty { p.move(to: cur) }
    }

    private static func isCubic(_ c: UInt8) -> Bool { c == UInt8(ascii: "C") || c == UInt8(ascii: "S") }
    private static func isQuad(_ c: UInt8) -> Bool { c == UInt8(ascii: "Q") || c == UInt8(ascii: "T") }
    private static func reflect(_ p: CGPoint, about c: CGPoint) -> CGPoint { CGPoint(x: 2 * c.x - p.x, y: 2 * c.y - p.y) }

    /// SVG's endpoint arc (implementation notes F.6) as cubic segments of at most 90°.
    static func addArc(_ p: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                       rotation: CGFloat, large: Bool, sweep: Bool) {
        if p0 == p1 { return }
        if rx0 == 0 || ry0 == 0 { p.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        var rx = rx0, ry = ry0
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2
        let cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi } else if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int((abs(delta) / (.pi / 2) - 0.0001).rounded(.up)))
        let step = delta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        func onEllipse(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosP - ry * sin(t) * sinP, y: cy + rx * cos(t) * sinP + ry * sin(t) * cosP)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosP - ry * cos(t) * sinP, y: -rx * sin(t) * sinP + ry * cos(t) * cosP)
        }
        var t = theta1
        for i in 0..<segments {
            let t2 = t + step
            let a = onEllipse(t), b = i == segments - 1 ? p1 : onEllipse(t2)
            let da = derivative(t), db = derivative(t2)
            p.addCurve(to: b, control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                       control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
            t = t2
        }
    }

    /// A byte scanner over path data.
    struct Scanner {
        let bytes: [UInt8]
        var i = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        func peek() -> UInt8? { i < bytes.count ? bytes[i] : nil }
        mutating func advance() { i += 1 }

        static func isCommand(_ c: UInt8) -> Bool { "MmLlHhVvCcSsQqTtAaZz".utf8.contains(c) }
        static func isSeparator(_ c: UInt8) -> Bool { c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C }

        mutating func skipSeparators() { while let c = peek(), Self.isSeparator(c) { i += 1 } }

        /// One number: sign, digits, one decimal point, exponent. `1.5.5` reads as 1.5 then .5.
        mutating func number() -> CGFloat? {
            skipSeparators()
            let startIndex = i
            if let c = peek(), c == UInt8(ascii: "+") || c == UInt8(ascii: "-") { i += 1 }
            var digits = 0, dot = false
            while let c = peek() {
                if c >= 0x30 && c <= 0x39 { digits += 1; i += 1 } else if c == UInt8(ascii: "."), !dot { dot = true; i += 1 } else { break }
            }
            guard digits > 0 else { i = startIndex; return nil }
            if let c = peek(), c == UInt8(ascii: "e") || c == UInt8(ascii: "E") {
                let save = i
                i += 1
                if let s = peek(), s == UInt8(ascii: "+") || s == UInt8(ascii: "-") { i += 1 }
                var expDigits = 0
                while let d = peek(), d >= 0x30 && d <= 0x39 { expDigits += 1; i += 1 }
                if expDigits == 0 { i = save }
            }
            return Double(String(decoding: bytes[startIndex..<i], as: UTF8.self)).map { CGFloat($0) }
        }

        /// An arc flag: a single `0` or `1`, which may run into the next number (`a1 1 0 01 1 1`).
        mutating func flag() -> Bool? {
            skipSeparators()
            guard let c = peek(), c == UInt8(ascii: "0") || c == UInt8(ascii: "1") else { return nil }
            i += 1
            return c == UInt8(ascii: "1")
        }
    }
}
