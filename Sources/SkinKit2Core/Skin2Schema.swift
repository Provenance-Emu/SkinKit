import Foundation

/// The JSON Schema of `skin.json` (draft 2020-12), built from the same constants and enums the decoder uses so
/// the two can't drift silently. `docs/schema/skin-2.0.schema.json` is this value written out
/// (`SKIN2_RECORD=1 xcrun swift test --filter SkinKit2CoreTests` regenerates it; a test fails when it is stale).
///
/// The schema describes the authored file: any scalar, colour, length, shape or paint may instead be a `$token`
/// or `@param` reference, and a node may be a part instance (`use`). What it can't say (the referenced token
/// exists, `maxScale ≥ minScale`, ids are unique, `requires` matches the content) the validator checks.
/// Unknown keys are allowed everywhere, as readers ignore them.
public enum Skin2Schema {
    public static let id = "https://emuskins.com/schema/skin-2.0.schema.json"

    /// Every keyword the schema uses. The tests' validator implements exactly these.
    public static let keywords: Set<String> = [
        "$schema", "$id", "$defs", "$ref", "title", "description", "type", "const", "enum", "pattern", "minLength",
        "maxLength", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "properties", "required",
        "additionalProperties", "propertyNames", "minProperties", "maxProperties", "items", "prefixItems",
        "minItems", "maxItems", "anyOf", "oneOf", "not",
    ]

    /// The schema file's bytes: sorted keys, two-space indent, trailing newline.
    public static func encoded() throws -> Data {
        var data = try document.data(pretty: true)
        data.append(0x0A)
        return data
    }

    public static var document: Skin2JSON {
        var defs: [String: Skin2JSON] = [:]

        defs["reference"] = [
            "description": "A $token or @partParameter reference, replaced before the value is read.",
            "type": "string", "pattern": .string(Skin2Preprocessor.referencePattern),
        ]
        defs["color"] = any([["type": "string", "pattern": .string(Skin2Color.pattern)], ref("reference")],
                            description: "#RRGGBB or #RRGGBBAA (sRGB)")
        defs["unit"] = tok(num(min: 0, max: 1))
        defs["unitPoint"] = ["type": "array", "prefixItems": [tok(num()), tok(num())], "minItems": 2, "maxItems": 2]

        // Lengths: level n allows n nested operators, so the schema enforces the depth limit as the decoder does.
        defs["lengthValue"] = any([
            num(),
            ["type": "string", "pattern": .string(Skin2Length.percentPattern)],
            single("pt", tok(num())), single("frac", tok(num())),
            single("safe", tok(enumOf(Skin2Edge.allCases.map(\.rawValue)))),
            ref("reference"),
        ])
        var previous = "lengthValue"
        for level in 1...Skin2Length.maxDepth {
            let name = level == Skin2Length.maxDepth ? "length" : "length\(level)"
            let items: Skin2JSON = ["type": "array", "items": ref(previous), "minItems": 2]
            defs[name] = any([ref("lengthValue"), single("max", items), single("min", items), single("sum", items)],
                             description: level == Skin2Length.maxDepth
                                ? "Points at reference scale (number), \"N%\" of the parent, {pt}, {frac}, {safe: edge} (offset and inset only), or {max|min|sum: [lengths]} nested at most \(Skin2Length.maxDepth) deep."
                                : nil)
            previous = name
        }
        defs["lengthOrNull"] = any([ref("length"), ["type": "null"]])
        let edges = Skin2Edge.allCases.map(\.rawValue)
        defs["edgeLengths"] = any([
            ref("length"),
            obj(Dictionary(uniqueKeysWithValues: edges.map { ($0, ref("length")) }),
                extra: ["anyOf": .array(edges.map { ["required": [.string($0)]] })]),
        ])
        defs["sizeLengths"] = obj(["width": ref("lengthOrNull"), "height": ref("lengthOrNull")])

        // Layout and conditions
        defs["area"] = tok(["type": "string", "pattern": .string("^(parent|canvas|safeArea|screen|#\(Skin2Area.idBody))$")])
        defs["anchor"] = obj([
            "x": nullable(tok(enumOf(Skin2HAnchor.allCases.map(\.rawValue)))),
            "y": nullable(tok(enumOf(Skin2VAnchor.allCases.map(\.rawValue)))),
            "to": nullable(ref("area")),
        ])
        defs["layout"] = obj([
            "frame": nullable(["type": "array", "items": ref("length"), "minItems": 4, "maxItems": 4]),
            "inset": nullable(ref("edgeLengths")),
            "size": nullable(ref("sizeLengths")),
            "aspect": nullable(tok(num(exclusiveMin: 0))),
            "minSize": nullable(ref("sizeLengths")),
            "maxSize": nullable(ref("sizeLengths")),
            "anchor": nullable(ref("anchor")),
            "offset": nullable(obj(["x": ref("lengthOrNull"), "y": ref("lengthOrNull")])),
            "span": nullable(obj(["columns": tok(int(min: 1)), "rows": tok(int(min: 1))])),
        ])
        let conditionProps: [String: Skin2JSON] = [
            "orientation": tok(enumOf(Skin2Orientation.allCases.map(\.rawValue))),
            "device": tok(enumOf(Skin2Device.allCases.map(\.rawValue))),
            "displayType": tok(enumOf(Skin2DisplayType.allCases.map(\.rawValue))),
            "flag": tok(["type": "string"]), "minWidth": tok(num()), "minHeight": tok(num()),
            "theme": tok(["type": "string"]), "variant": tok(["type": "string"]),
        ]
        defs["condition"] = obj(conditionProps)
        defs["visibility"] = any([tok(["type": "boolean"]), ref("condition")])
        let patchProps: [String: Skin2JSON] = [
            "layout": nullable(ref("layout")), "visible": nullable(ref("visibility")), "opacity": nullable(ref("unit")),
            "fills": ["type": "array", "items": ref("paint")], "strokes": ["type": "array", "items": ref("stroke")],
            "text": tok(["type": "string"]),
        ]
        defs["when"] = obj(conditionProps.merging(patchProps) { a, _ in a })
        defs["statePatch"] = obj(patchProps.merging(["target": tok(["type": "string", "pattern": .string(Skin2Patch.targetPattern)])]) { a, _ in a },
                                 required: ["target"])
        defs["state"] = obj(["scale": tok(num(exclusiveMin: 0)), "opacity": ref("unit"),
                             "patch": ["type": "array", "items": ref("statePatch")]])

        // Paint
        defs["stop"] = ["type": "array", "prefixItems": [ref("color"), ref("unit"), ref("unit")], "minItems": 2, "maxItems": 3,
                        "description": "[colour, at] or [colour, opacity, at]"]
        let stops: Skin2JSON = ["type": "array", "items": ref("stop"), "minItems": 2]
        let paintProps: [String: Skin2JSON] = [
            "color": ref("color"), "opacity": ref("unit"), "start": ref("unitPoint"), "end": ref("unitPoint"),
            "center": ref("unitPoint"), "radius": tok(num(exclusiveMin: 0)), "startAngle": tok(num()), "stops": stops,
            "src": tok(["type": "string"]), "scale": tok(num(exclusiveMin: 0)),
            "mode": tok(enumOf(Skin2ImageMode.allCases.map(\.rawValue))),
        ]
        func paint(_ type: Skin2PaintType, _ required: [String], extra: [String: Skin2JSON] = [:]) -> Skin2JSON {
            var props = paintProps
            props["type"] = ["const": .string(type.rawValue)]
            for (k, v) in extra { props[k] = v }
            return obj(props, required: ["type"] + required)
        }
        defs["paint"] = any([
            paint(.solid, ["color"]),
            paint(.linear, ["start", "end", "stops"]),
            paint(.radial, ["center", "radius", "stops"]),
            paint(.angular, ["center", "stops"]),
            paint(.image, ["src"], extra: ["mode": tok(enumOf(["tile", "fit", "fill"]))]),
            ref("reference"),
        ])
        defs["stroke"] = obj([
            "color": ref("color"), "opacity": ref("unit"), "width": ref("length"),
            "align": tok(enumOf(Skin2StrokeAlign.allCases.map(\.rawValue))),
            "dash": ["type": "array", "items": ref("length")],
            "cap": tok(enumOf(Skin2LineCap.allCases.map(\.rawValue))),
            "join": tok(enumOf(Skin2LineJoin.allCases.map(\.rawValue))),
        ], required: ["color", "width"])
        let effectProps: [String: Skin2JSON] = [
            "color": ref("color"), "opacity": ref("unit"), "radius": ref("length"),
            "offset": ["type": "array", "items": ref("length"), "minItems": 2, "maxItems": 2],
            "spread": ref("length"), "inner": tok(["type": "boolean"]),
            "mode": tok(enumOf(Skin2BlendMode.allCases.map(\.rawValue))), "name": tok(["type": "string"]),
            "params": ["type": "object"],
        ]
        func effect(_ type: Skin2EffectType, _ required: [String]) -> Skin2JSON {
            obj(effectProps.merging(["type": ["const": .string(type.rawValue)]]) { a, _ in a }, required: ["type"] + required)
        }
        defs["effect"] = any([effect(.shadow, ["color"]), effect(.blur, ["radius"]), effect(.blend, ["mode"]), effect(.ci, ["name"])])
        defs["material"] = obj(["name": tok(enumOf(Skin2MaterialName.allCases.map(\.rawValue))), "intensity": ref("unit"),
                                "params": ["type": "object"]], required: ["name"])
        defs["font"] = obj(["family": tok(["type": "string"]), "size": ref("length"),
                            "weight": tok(enumOf(Skin2FontWeight.allCases.map(\.rawValue)))], required: ["size"])

        // Shapes
        let shapeProps: [String: Skin2JSON] = [
            "cornerRadius": ref("length"),
            "corners": ["type": "array", "items": ref("length"), "minItems": 4, "maxItems": 4],
            "sides": tok(int(min: 3)), "rotation": tok(num()), "points": tok(int(min: 3)), "innerRatio": ref("unit"),
            "startAngle": tok(num()), "endAngle": tok(num()), "inner": ref("unit"),
            "from": ref("unitPoint"), "to": ref("unitPoint"),
            "armRatio": ref("unit"), "bulge": ref("unit"), "taper": tok(num(min: 0, exclusiveMax: 0.5)),
            "d": tok(["type": "string", "maxLength": .number(Double(Skin2Shape.maxPathBytes))]),
            "box": ["type": "array", "prefixItems": [tok(num()), tok(num()), tok(num(exclusiveMin: 0)), tok(num(exclusiveMin: 0))],
                    "minItems": 4, "maxItems": 4],
        ]
        func shape(_ kinds: [String], _ required: [String]) -> Skin2JSON {
            let kind: Skin2JSON = kinds.count == 1 ? ["const": .string(kinds[0])] : enumOf(kinds)
            return obj(shapeProps.merging(["kind": kind]) { a, _ in a }, required: ["kind"] + required)
        }
        defs["shape"] = any([
            shape(["rect", "squircle", "ellipse", "circle", "capsule", "cross", "kidney", "trapezoid"], []),
            shape(["polygon"], ["sides"]), shape(["star"], ["points"]), shape(["arc"], ["startAngle", "endAngle"]),
            shape(["line"], ["from", "to"]), shape(["path"], ["d", "box"]),
            ref("reference"),
        ])

        // Controls
        defs["input"] = any([
            ["type": "string"],
            obj(["up": tok(["type": "string"]), "down": tok(["type": "string"]), "left": tok(["type": "string"]), "right": tok(["type": "string"])],
                required: ["up", "down", "left", "right"]),
        ])
        defs["stack"] = obj(["axis": tok(enumOf(Skin2StackAxis.allCases.map(\.rawValue))), "spacing": ref("length"),
                             "align": tok(enumOf(Skin2Align.allCases.map(\.rawValue))),
                             "distribute": tok(enumOf(Skin2Distribute.allCases.map(\.rawValue)))], required: ["axis"])
        defs["grid"] = obj(["columns": tok(int(min: 1)),
                            "spacing": any([ref("length"), obj(["x": ref("length"), "y": ref("length")],
                                                               extra: ["anyOf": [["required": ["x"]], ["required": ["y"]]]])]),
                            "align": tok(enumOf(Skin2Align.allCases.map(\.rawValue)))], required: ["columns"])
        defs["repeat"] = obj(["count": tok(int(min: 1, max: Skin2Repeat.maxCount)),
                              "offset": obj(["x": ref("length"), "y": ref("length")]), "rotate": tok(num()),
                              "scale": tok(num(exclusiveMin: 0)), "pivot": tok(enumOf(Skin2RepeatPivot.allCases.map(\.rawValue)))],
                             required: ["count"])

        // Nodes
        let idSchema = tok(["type": "string", "pattern": .string(Skin2Node.idPattern)])
        let common: [String: Skin2JSON] = [
            "id": idSchema, "layout": ref("layout"), "when": ["type": "array", "items": ref("when")],
            "visible": ref("visibility"), "opacity": ref("unit"), "effects": ["type": "array", "items": ref("effect")],
            "repeat": ref("repeat"), "role": tok(enumOf(Skin2ArtRole.allCases.map(\.rawValue))),
        ]
        let children: Skin2JSON = ["type": "array", "items": ref("node")]
        func node(_ type: Skin2NodeType, _ props: [String: Skin2JSON], required: [String] = [], extra: [String: Skin2JSON] = [:]) -> Skin2JSON {
            obj(common.merging(props) { _, b in b }.merging(["type": ["const": .string(type.rawValue)]]) { _, b in b },
                required: ["type"] + required, extra: extra)
        }
        defs["group"] = node(.group, ["children": children, "stack": ref("stack"), "grid": ref("grid")],
                             extra: ["not": ["required": ["stack", "grid"]]])
        defs["shapeNode"] = node(.shape, ["shape": ref("shape"), "fills": ["type": "array", "items": ref("paint")],
                                          "strokes": ["type": "array", "items": ref("stroke")], "material": ref("material")],
                                 required: ["shape"])
        defs["imageNode"] = node(.image, ["src": tok(["type": "string"]), "mode": tok(enumOf(Skin2ImageMode.allCases.map(\.rawValue))),
                                          "tint": ref("color")], required: ["src"])
        defs["textNode"] = node(.text, ["text": tok(["type": "string"]), "font": ref("font"), "color": ref("color"),
                                        "align": tok(enumOf(Skin2TextAlign.allCases.map(\.rawValue))), "fit": tok(["type": "boolean"])],
                                required: ["text"])
        defs["controlNode"] = node(.control, [
            "kind": tok(enumOf(Skin2ControlKind.allCases.map(\.rawValue))), "input": ref("input"),
            "inputs": ["type": "array", "items": tok(["type": "string"])],
            "click": tok(["type": "string"]),
            "hit": obj(["extend": ref("edgeLengths")]), "travel": ref("length"),
            "states": ["type": "object", "propertyNames": enumOf(Skin2State.names.sorted()), "additionalProperties": ref("state")],
            "haptic": obj(["style": tok(["type": "string"]), "intensity": ref("unit")]), "children": children,
        ], required: ["kind"])
        defs["screenNode"] = node(.screen, [
            "aspect": tok(num(exclusiveMin: 0)), "role": tok(enumOf(Skin2ScreenRole.allCases.map(\.rawValue))),
            "filters": ["type": "array", "items": obj(["name": tok(["type": "string"]), "params": ["type": "object"]], required: ["name"])],
            "placement": tok(enumOf(Skin2ScreenPlacement.allCases.map(\.rawValue))),
        ])
        defs["partInstance"] = obj([
            "use": ["type": "string", "pattern": .string(Skin2Preprocessor.partNamePattern)], "with": ["type": "object"],
            "id": idSchema, "layout": ref("layout"), "when": ["type": "array", "items": ref("when")], "visible": ref("visibility"),
        ], required: ["use"], extra: [
            "propertyNames": enumOf((["use", "with"] + Skin2Preprocessor.instanceKeys.sorted())),
            "description": "A part placed here: the part's node with `with` as its arguments and these keys merged over it.",
        ])
        defs["node"] = ["oneOf": [ref("group"), ref("shapeNode"), ref("imageNode"), ref("textNode"), ref("controlNode"),
                                  ref("screenNode"), ref("partInstance")]]

        // Document-level maps
        defs["token"] = any([
            ["type": "string", "pattern": .string(Skin2Color.pattern)], num(),
            single("color", ["type": "string", "pattern": .string(Skin2Color.pattern)]),
            single("length", ref("length")), single("number", num()), single("string", ["type": "string"]),
        ], description: "A colour, a number, or a typed token {color|length|number|string: value}.")
        defs["part"] = obj([
            "params": ["type": "object", "propertyNames": ["pattern": .string(Skin2Preprocessor.tokenNamePattern)],
                       "additionalProperties": obj(["type": enumOf(Skin2ParamType.allCases.map(\.rawValue)), "default": [:]], required: ["type"])],
            "node": ref("node"),
        ], required: ["node"])
        defs["variant"] = obj([
            "label": ["type": "string"],
            "match": obj(["md5": strings, "crc": strings, "filename": strings, "title": strings, "any": ["type": "boolean"]]),
            "toggle": ["type": "boolean"],
            "patch": ["type": "array", "items": obj(["target": ["type": "string", "pattern": .string(Skin2Variant.Patch.targetPattern)]],
                                                     required: ["target"])],
        ])

        let tokenName: Skin2JSON = ["pattern": .string(Skin2Preprocessor.tokenNamePattern)]
        let root: [String: Skin2JSON] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": .string(id),
            "title": "Skin format 2.0 (skin.json)",
            "description": "A declarative controller skin: a tree of groups, shapes, images, text, controls and screens with layout rules, tokens, parts, themes and variants. See docs/specs/2026-11-03-skin-format-2-design.md.",
            "type": "object",
            "required": ["formatVersion", "identifier", "name", "gameTypes", "reference", "root"],
            "properties": [
                "formatVersion": ["type": "string", "pattern": .string(Skin2Document.formatVersionPattern)],
                "requires": strings,
                "identifier": ["type": "string"],
                "name": ["type": "string"],
                "author": ["type": "string"],
                "gameTypes": ["type": "array", "items": ["type": "string"], "minItems": 1],
                "reference": obj(["shortSide": num(exclusiveMin: 0), "minScale": num(exclusiveMin: 0), "maxScale": num(exclusiveMin: 0)],
                                 required: ["shortSide", "minScale", "maxScale"]),
                "tokens": ["type": "object", "propertyNames": tokenName, "additionalProperties": ref("token")],
                "themes": ["type": "object", "additionalProperties": ["type": "object", "propertyNames": tokenName,
                                                                      "additionalProperties": ref("token")]],
                "parts": ["type": "object", "propertyNames": ["pattern": .string(Skin2Preprocessor.partNamePattern)],
                          "additionalProperties": ref("part")],
                "variants": ["type": "object", "additionalProperties": ref("variant")],
                "screens": strings,
                "bake": obj(["traits": ["type": "array", "items": enumOf(Skin2TraitSet.familyNames)]]),
                "root": any([ref("group"), ref("partInstance")]),
            ],
            "$defs": .object(defs),
        ]
        return .object(root)
    }

    // MARK: Builders

    static let strings: Skin2JSON = ["type": "array", "items": ["type": "string"]]

    static func ref(_ name: String) -> Skin2JSON { ["$ref": .string("#/$defs/\(name)")] }

    static func tok(_ s: Skin2JSON) -> Skin2JSON { ["anyOf": [s, ref("reference")]] }

    static func nullable(_ s: Skin2JSON) -> Skin2JSON { ["anyOf": [s, ["type": "null"]]] }

    static func any(_ items: [Skin2JSON], description: String? = nil) -> Skin2JSON {
        var o: [String: Skin2JSON] = ["anyOf": .array(items)]
        if let description { o["description"] = .string(description) }
        return .object(o)
    }

    static func enumOf(_ values: [String]) -> Skin2JSON { ["enum": .array(values.map { .string($0) })] }

    static func num(min: Double? = nil, max: Double? = nil, exclusiveMin: Double? = nil, exclusiveMax: Double? = nil) -> Skin2JSON {
        var o: [String: Skin2JSON] = ["type": "number"]
        if let min { o["minimum"] = .number(min) }
        if let max { o["maximum"] = .number(max) }
        if let exclusiveMin { o["exclusiveMinimum"] = .number(exclusiveMin) }
        if let exclusiveMax { o["exclusiveMaximum"] = .number(exclusiveMax) }
        return .object(o)
    }

    static func int(min: Int? = nil, max: Int? = nil) -> Skin2JSON {
        var o: [String: Skin2JSON] = ["type": "integer"]
        if let min { o["minimum"] = .number(Double(min)) }
        if let max { o["maximum"] = .number(Double(max)) }
        return .object(o)
    }

    static func obj(_ props: [String: Skin2JSON], required: [String] = [], extra: [String: Skin2JSON] = [:]) -> Skin2JSON {
        var o: [String: Skin2JSON] = ["type": "object", "properties": .object(props)]
        if !required.isEmpty { o["required"] = .array(required.map { .string($0) }) }
        for (k, v) in extra { o[k] = v }
        return .object(o)
    }

    /// An object with exactly this one key.
    static func single(_ key: String, _ value: Skin2JSON) -> Skin2JSON {
        obj([key: value], required: [key], extra: ["maxProperties": 1])
    }
}
