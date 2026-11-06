import Foundation

/// `expected/<trait>.layout.json` (9.2): every visible node's resolved frame and hit frame for one environment.
/// The Swift resolver records it; the TypeScript resolver must reproduce it exactly. Frames are rounded to the
/// half point, copy transforms to 4 decimals (matrix) and the half point (translation).
public struct Skin2LayoutRecord: Equatable, Sendable, Codable {
    public struct Canvas: Equatable, Sendable, Codable {
        public var width: Double
        public var height: Double
        public var safeArea: Skin2Insets
    }

    public struct Node: Equatable, Sendable, Codable {
        /// JSON Pointer in the expanded document.
        public var path: String
        public var id: String?
        public var type: Skin2NodeType
        public var kind: Skin2ControlKind?
        public var frame: [Double]
        public var hitFrame: [Double]?
        public var copies: [[Double]]?

        enum CodingKeys: String, CodingKey { case path, id, type, kind, frame, hitFrame, copies }
    }

    public var trait: String?
    public var canvas: Canvas
    public var device: Skin2Device
    public var displayType: Skin2DisplayType
    public var orientation: Skin2Orientation
    public var theme: String?
    public var variant: String?
    public var nodes: [Node]

    public init(_ r: Skin2Resolution, trait: String? = nil) {
        self.trait = trait
        let e = r.environment
        canvas = Canvas(width: e.size.width, height: e.size.height, safeArea: e.safeArea)
        device = e.device
        displayType = e.displayType
        orientation = e.orientation
        theme = r.theme
        variant = r.variant
        nodes = r.nodes.map { n in
            Node(path: n.pointer, id: n.node.id, type: n.node.type, kind: n.node.kind, frame: n.frame.array,
                 hitFrame: n.hitFrame?.array, copies: n.copies.isEmpty ? nil : n.copies.map(\.roundedArray))
        }
    }

    /// Sorted keys, one node per line, a trailing newline: stable bytes that diff well.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var header = try Skin2JSON.parse(encoder.encode(self)).objectValue ?? [:]
        header.removeValue(forKey: "nodes")
        var lines = ["{"]
        for key in header.keys.sorted() {
            lines.append("  \"\(key)\": " + String(decoding: try header[key]!.data(), as: UTF8.self) + ",")
        }
        let nodeLines = try nodes.map { "    " + String(decoding: try Skin2JSON.parse(encoder.encode($0)).data(), as: UTF8.self) }
        lines.append("  \"nodes\": [")
        lines.append(nodeLines.joined(separator: ",\n"))
        lines.append("  ]")
        lines.append("}")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
