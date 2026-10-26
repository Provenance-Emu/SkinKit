import CoreGraphics
import Foundation

/// Applies `DeltaSkin.DecodingOptions` to a raw `info.json`: strips comments and rewrites the JSON tree so the
/// strict model decoders accept it. Not used at all for empty options.
///
/// The rules come from iCube's own decoder; see `DeltaSkin.DecodingOptions` for what each one does.
enum DeltaSkinInfoPreparer {
    typealias Options = DeltaSkin.DecodingOptions

    private static let displayKeys = ["standard", "edgeToEdge", "splitView", "stageManager", "externalDisplay", "mini", "pro13", "dedicated"]
    private static let directions = ["up", "down", "left", "right"]
    private static let extendedGameCubeAliases: Set<String> = ["gcn", "nintendogamecube"]

    // MARK: - Entry

    /// The JSON to hand to the model decoder.
    static func prepare(_ data: Data, options: Options) throws -> Data {
        let text = options.contains(.stripsComments) ? try stripComments(data) : data
        guard options.rewritesJSON else { return text }

        guard let object = try? JSONSerialization.jsonObject(with: text), var root = object as? [String: Any] else {
            throw DeltaSkinError.invalidInfoFile
        }
        let rules = Rules(options)

        if options.contains(.canonicalGameTypes) {
            try requireCanonicalGameType(root["gameTypeIdentifier"])
        }
        if rules.drops {
            for (key, type) in rootExtras where root[key] != nil && !decodes(type, root[key]) {
                root[key] = nil
            }
        }

        if let value = root["representations"], !(value is NSNull) {
            guard let devices = value as? [String: Any] else { throw DeltaSkinError.invalidInfoFile }
            let cleaned = try cleanDevices(devices, rules)
            if rules.drops, cleaned.isEmpty { throw DeltaSkinInfoError.noUsableRepresentation }
            root["representations"] = cleaned
        } else if rules.drops {
            throw DeltaSkinInfoError.noUsableRepresentation
        }

        // `-1e999` parses to -infinity, and writing a non-finite number back raises an Objective-C exception
        // that `try` cannot catch. `limitsFrames` removes them; this keeps the other rules from crashing on one.
        guard JSONSerialization.isValidJSONObject(root) else { throw DeltaSkinError.invalidInfoFile }
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// Removes `//` comments (whole-line or trailing) without touching `//` inside a string, such as a URL.
    static func stripComments(_ data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else { throw DeltaSkinError.invalidInfoFile }
        let stripped = text.components(separatedBy: .newlines).map { line -> String in
            var inString = false
            var escaped = false
            var previous: Character?
            for index in line.indices {
                let character = line[index]
                if inString {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        inString = false
                    }
                } else if character == "\"" {
                    inString = true
                } else if character == "/", previous == "/" {
                    return String(line[..<line.index(before: index)])
                }
                previous = character
            }
            return line
        }
        return Data(stripped.joined(separator: "\n").utf8)
    }

    // MARK: - Rules

    private struct Rules {
        let drops: Bool
        let limits: Bool
        let inherits: Bool
        let completeDirections: Bool
        let keepsAssets: Bool

        init(_ options: Options) {
            drops = options.contains(.dropsInvalidElements)
            limits = options.contains(.limitsFrames)
            inherits = options.contains(.inheritsEdges)
            completeDirections = options.contains(.requiresCompleteDirections)
            keepsAssets = options.contains(.keepsItemAssets)
        }

        /// A finite number within the limit, when limits are on.
        func isSane(_ value: CGFloat) -> Bool {
            !limits || (value.isFinite && abs(value) <= Options.maxFrameMagnitude)
        }

        func isSane(_ size: CGSize) -> Bool {
            !limits || (isSane(size.width) && isSane(size.height) && size.width >= 0 && size.height >= 0)
        }

        func isSane(_ rect: CGRect) -> Bool {
            isSane(rect.origin.x) && isSane(rect.origin.y) && isSane(rect.size)
        }
    }

    /// Extras the model reads with `decodeIfPresent`; under `dropsInvalidElements` a bad one is removed.
    private static let rootExtras: [(String, any Decodable.Type)] = [
        ("keyboardOverlay", KeyboardOverlayConfig.self), ("themes", [DeltaSkin.Theme].self),
        ("gameOverrides", [String: [String: DeltaSkin.DeviceRepresentations]].self),
        ("debug", Bool.self), ("caseController", Bool.self),
    ]
    private static let representationExtras: [(String, any Decodable.Type)] = [("backgroundAnimation", DeltaSkinBackgroundAnimation.self)]
    private static let itemExtras: [(String, any Decodable.Type)] = [("haptic", DeltaSkinHaptic.self), ("states", DeltaSkinButtonStates.self)]
    private static let screenExtras: [(String, any Decodable.Type)] = [
        ("filters", [DeltaSkin.FilterInfo].self), ("placement", DeltaSkinScreenPlacement.self), ("maintainAspectRatio", Bool.self),
    ]

    // MARK: - Game type

    private static func requireCanonicalGameType(_ value: Any?) throws {
        guard let raw = value as? String else { return } // the model reports a missing or mistyped key itself
        let suffix = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: ".").last.map(String.init) ?? ""
        let hasSeparator = suffix.contains("-") || suffix.contains("_") || suffix.contains(" ")
        if hasSeparator || extendedGameCubeAliases.contains(suffix) {
            throw DeltaSkinInfoError.unsupportedGameType(raw)
        }
    }

    // MARK: - Tree

    /// `devices` → display types → orientations → representations. Anything that is not a dictionary where one is
    /// expected is invalid. Device and display keys the model does not read are left alone.
    private static func cleanDevices(_ devices: [String: Any], _ rules: Rules) throws -> [String: Any] {
        var result = devices
        let known = Set(DeltaSkinDevice.allCases.map(\.rawValue))
        for (deviceKey, deviceValue) in devices where known.contains(deviceKey) {
            guard var device = deviceValue as? [String: Any] else {
                if rules.drops { result[deviceKey] = nil; continue }
                throw DeltaSkinError.invalidInfoFile
            }
            for displayKey in displayKeys {
                guard let displayValue = device[displayKey] else { continue }
                guard var display = displayValue as? [String: Any] else {
                    if rules.drops { device[displayKey] = nil; continue }
                    throw DeltaSkinError.invalidInfoFile
                }
                for (orientationKey, representation) in display {
                    if let cleaned = try cleanRepresentation(representation, rules) {
                        display[orientationKey] = cleaned
                    } else if rules.drops {
                        display[orientationKey] = nil
                    } else {
                        throw DeltaSkinError.invalidInfoFile
                    }
                }
                device[displayKey] = display.isEmpty ? nil : display
            }
            // A device left with no display type has nothing to offer.
            result[deviceKey] = device.keys.contains(where: displayKeys.contains) ? device : nil
        }
        return result
    }

    /// A representation with its items and screens cleaned, or nil when it must be dropped.
    private static func cleanRepresentation(_ value: Any, _ rules: Rules) throws -> [String: Any]? {
        guard var node = value as? [String: Any], let mapping = size(node["mappingSize"]),
              rules.isSane(mapping), !rules.limits || (mapping.width > 0 && mapping.height > 0) else { return nil }
        node["mappingSize"] = ["width": Double(mapping.width), "height": Double(mapping.height)]

        var repEdges = EdgeSides()
        switch edges(node["extendedEdges"], rules) {
        case .invalid: return nil
        case let .value(sides):
            if let sides {
                repEdges = sides
                if rules.inherits { node["extendedEdges"] = sides.node(over: EdgeSides()) }
            }
        }
        if let translucent = node["translucent"], !(translucent is NSNull), !isBool(translucent) { return nil }
        if let assets = node["assets"], !(assets is NSNull) {
            guard let dictionary = assets as? [String: Any],
                  ["resizable", "small", "medium", "large"].allSatisfy({ isOptionalString(dictionary[$0]) }) else { return nil }
        }
        if let frame = node["gameScreenFrame"], rect(frame, rules) == nil { node["gameScreenFrame"] = nil }
        if rules.drops {
            for (key, type) in representationExtras where node[key] != nil && !decodes(type, node[key]) { node[key] = nil }
        }

        if let rawItems = node["items"], !(rawItems is NSNull) {
            guard let list = rawItems as? [Any] else { return nil }
            var items: [[String: Any]] = []
            for element in list {
                if let item = cleanItem(element, inheriting: repEdges, rules) {
                    items.append(item)
                } else if !rules.drops {
                    throw DeltaSkinError.invalidInfoFile
                }
            }
            node["items"] = items
        }
        if let rawScreens = node["screens"], !(rawScreens is NSNull) {
            guard let list = rawScreens as? [Any] else { return nil }
            var screens: [[String: Any]] = []
            for element in list {
                if let screen = cleanScreen(element, rules) {
                    screens.append(screen)
                } else if !rules.drops {
                    throw DeltaSkinError.invalidInfoFile
                }
            }
            node["screens"] = screens
        }
        return node
    }

    private static func cleanItem(_ value: Any, inheriting rep: EdgeSides, _ rules: Rules) -> [String: Any]? {
        guard var node = value as? [String: Any], let inputs = cleanInputs(node["inputs"], rules),
              let frame = rect(node["frame"], rules) else { return nil }
        node["inputs"] = inputs
        node["frame"] = frameNode(frame)

        switch edges(node["extendedEdges"], rules) {
        case .invalid: return nil
        case let .value(sides):
            if rules.inherits {
                node["extendedEdges"] = (sides ?? EdgeSides()).node(over: rep)
            } else if let sides {
                node["extendedEdges"] = sides.node(over: EdgeSides())
            }
        }
        if let stick = node["thumbstick"], !(stick is NSNull) {
            guard let dictionary = stick as? [String: Any], let name = dictionary["name"] as? String,
                  let stickSize = size(dictionary), rules.isSane(stickSize) else { return nil }
            node["thumbstick"] = ["name": name, "width": Double(stickSize.width), "height": Double(stickSize.height)] as [String: Any]
        }
        if rules.keepsAssets, let asset = node["asset"], !(asset is NSNull) {
            guard let dictionary = asset as? [String: Any], isOptionalString(dictionary["normal"]) else { return nil }
            node["asset"] = (dictionary["normal"] as? String).map { ["normal": $0] } ?? [:]
        }
        if rules.drops {
            for (key, type) in itemExtras where node[key] != nil && !decodes(type, node[key]) { node[key] = nil }
        }
        return node
    }

    /// Screens keep every key; only the frames are validated and rewritten to the dictionary form the model reads.
    private static func cleanScreen(_ value: Any, _ rules: Rules) -> [String: Any]? {
        guard var node = value as? [String: Any] else { return nil }
        for key in ["outputFrame", "inputFrame"] {
            guard let frame = node[key], !(frame is NSNull) else { continue }
            guard let parsed = rect(frame, rules) else { return nil }
            node[key] = frameNode(parsed)
        }
        if rules.drops {
            for (key, type) in screenExtras where node[key] != nil && !decodes(type, node[key]) { node[key] = nil }
        }
        return node
    }

    /// `["a", "b"]`, or a directional dictionary (complete, when required).
    private static func cleanInputs(_ value: Any?, _ rules: Rules) -> Any? {
        if let names = value as? [Any] {
            let strings = names.compactMap { $0 as? String }
            return strings.count == names.count ? strings : nil
        }
        guard let dictionary = value as? [String: Any] else { return nil }
        if rules.completeDirections {
            var result: [String: String] = [:]
            for direction in directions {
                guard let name = dictionary[direction] as? String else { return nil }
                result[direction] = name
            }
            return result
        }
        let strings = dictionary.compactMapValues { $0 as? String }
        return strings.count == dictionary.count ? strings : nil
    }

    // MARK: - Values

    private enum Parsed<Value> {
        case value(Value)
        case invalid
    }

    private struct EdgeSides {
        var top: CGFloat?
        var left: CGFloat?
        var bottom: CGFloat?
        var right: CGFloat?

        /// All four sides, an absent one taken from `base`, then 0.
        func node(over base: EdgeSides) -> [String: Double] {
            ["top": Double(top ?? base.top ?? 0), "left": Double(left ?? base.left ?? 0),
             "bottom": Double(bottom ?? base.bottom ?? 0), "right": Double(right ?? base.right ?? 0)]
        }
    }

    /// Edge insets where any side may be absent (or null). A present side that is not a sane number invalidates the value.
    private static func edges(_ value: Any?, _ rules: Rules) -> Parsed<EdgeSides?> {
        guard let value, !(value is NSNull) else { return .value(nil) }
        guard let raw = value as? [String: Any] else { return .invalid }
        var sides = EdgeSides()
        let keys: [(String, WritableKeyPath<EdgeSides, CGFloat?>)] = [
            ("top", \.top), ("left", \.left), ("bottom", \.bottom), ("right", \.right),
        ]
        for (key, path) in keys {
            guard let side = raw[key], !(side is NSNull) else { continue }
            guard let amount = number(side), rules.isSane(amount) else { return .invalid }
            sides[keyPath: path] = amount
        }
        return .value(sides)
    }

    private static func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func isOptionalString(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return true }
        return value is String
    }

    /// A JSON number (not a boolean).
    private static func number(_ value: Any?) -> CGFloat? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return CGFloat(number.doubleValue)
    }

    private static func size(_ value: Any?) -> CGSize? {
        guard let raw = value as? [String: Any], let width = number(raw["width"]), let height = number(raw["height"]) else { return nil }
        return CGSize(width: width, height: height)
    }

    /// A frame as the `{x, y, width, height}` dictionary, or the `[x, y, width, height]` array some skins use.
    private static func rect(_ value: Any?, _ rules: Rules) -> CGRect? {
        let rect: CGRect
        if let list = value as? [Any] {
            let numbers = list.compactMap(number)
            guard list.count == 4, numbers.count == 4 else { return nil }
            rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        } else if let raw = value as? [String: Any] {
            guard let x = number(raw["x"]), let y = number(raw["y"]),
                  let width = number(raw["width"]), let height = number(raw["height"]) else { return nil }
            rect = CGRect(x: x, y: y, width: width, height: height)
        } else {
            return nil
        }
        return rules.isSane(rect) ? rect : nil
    }

    private static func frameNode(_ rect: CGRect) -> [String: Double] {
        ["x": Double(rect.origin.x), "y": Double(rect.origin.y), "width": Double(rect.width), "height": Double(rect.height)]
    }

    // MARK: - Trial decoding

    private struct Wrapper<Value: Decodable>: Decodable {
        let value: Value
    }

    /// Whether `value` decodes as `type`, using the model's own decoder.
    private static func decodes(_ type: any Decodable.Type, _ value: Any?) -> Bool {
        guard let value else { return true }
        let wrapped: [String: Any] = ["value": value]
        guard JSONSerialization.isValidJSONObject(wrapped), let data = try? JSONSerialization.data(withJSONObject: wrapped) else {
            return false
        }
        func attempt<T: Decodable>(_: T.Type) -> Bool {
            (try? JSONDecoder().decode(Wrapper<T>.self, from: data)) != nil
        }
        return attempt(type)
    }
}
