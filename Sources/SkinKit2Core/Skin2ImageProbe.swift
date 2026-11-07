import Foundation

/// Reads an image's pixel size from its header, without decoding it or any image framework, so the validator's
/// image limits (section 11) run the same on every platform. PNG, JPEG and GIF; PDF and SVG are vectors with no
/// pixel size.
public enum Skin2ImageProbe {
    public struct PixelSize: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public init(width: Int, height: Int) { self.width = width; self.height = height }
    }

    public static func isVector(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "pdf" || ext == "svg"
    }

    public static func pixelSize(of data: Data) -> PixelSize? {
        let b = [UInt8](data.prefix(64 * 1024))
        if b.count >= 24, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47,
           b[12] == 0x49, b[13] == 0x48, b[14] == 0x44, b[15] == 0x52 { // PNG: signature, then the IHDR chunk
            return sized(be32(b, 16), be32(b, 20))
        }
        if b.count >= 10, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { // GIF: logical screen, little endian
            return sized(Int(b[6]) | Int(b[7]) << 8, Int(b[8]) | Int(b[9]) << 8)
        }
        if b.count >= 4, b[0] == 0xFF, b[1] == 0xD8 { return jpeg(b) }
        return nil
    }

    private static func sized(_ w: Int, _ h: Int) -> PixelSize? { w > 0 && h > 0 ? PixelSize(width: w, height: h) : nil }

    private static func be32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }

    /// Walks the marker segments to the first start-of-frame.
    private static func jpeg(_ b: [UInt8]) -> PixelSize? {
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let marker = b[i + 1]
            if marker == 0xFF { i += 1; continue }
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            let isFrame = (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if isFrame {
                return sized(Int(b[i + 7]) << 8 | Int(b[i + 8]), Int(b[i + 5]) << 8 | Int(b[i + 6]))
            }
            if length < 2 { return nil }
            i += 2 + length
        }
        return nil
    }
}
