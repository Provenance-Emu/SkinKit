import Foundation

public enum Skin2Severity: String, Codable, Sendable { case error, warning }

/// One validation finding. `pointer` is a JSON Pointer into `skin.json` (for nodes inside parts or variants, into
/// the expanded document, which mirrors the source except that `use` is replaced by the part's node).
public struct Skin2Issue: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var severity: Skin2Severity
    public var pointer: String
    public var message: String

    public init(_ severity: Skin2Severity, _ pointer: String, _ message: String) {
        self.severity = severity; self.pointer = pointer; self.message = message
    }

    public var description: String { "\(severity.rawValue) \(pointer.isEmpty ? "/" : pointer): \(message)" }
}

public struct Skin2ValidationReport: Sendable {
    public var issues: [Skin2Issue]
    /// The base document, when it loaded.
    public var document: Skin2Document?

    public var errors: [Skin2Issue] { issues.filter { $0.severity == .error } }
    public var warnings: [Skin2Issue] { issues.filter { $0.severity == .warning } }
    public var isValid: Bool { errors.isEmpty }
}

/// Validates a `skin.json` (sections 1, 3, 6, 8.1, 11): it loads (schema shape, tokens, parts, every theme and
/// variant), `requires` matches the content, the limits hold, ids and references are sound, inputs fit the
/// control kinds and game types, and on every trait set the skin bakes to, no two hit frames overlap.
public enum Skin2Validator {
    /// The size controls should reach on their short side at unit 1 (a warning).
    public static let minimumControlSide = 44.0

    public static func validate(data: Data, library: [String: Skin2JSON] = [:]) -> Skin2ValidationReport {
        guard data.count <= Skin2Document.maxFileBytes else {
            return Skin2ValidationReport(issues: [Skin2Issue(.error, "", "skin.json is \(data.count) bytes; the limit is \(Skin2Document.maxFileBytes)")])
        }
        let json: Skin2JSON
        do { json = try Skin2JSON.parse(data) } catch {
            return Skin2ValidationReport(issues: [Skin2Issue(.error, "", "not valid JSON: \(error.localizedDescription)")])
        }
        return validate(json: json, library: library)
    }

    public static func validate(json: Skin2JSON, library: [String: Skin2JSON] = [:]) -> Skin2ValidationReport {
        var v = Run()
        let base: Skin2Document
        do { base = try Skin2Document.load(json: json, library: library) } catch let e as Skin2Error {
            return Skin2ValidationReport(issues: [Skin2Issue(.error, e.pointer, e.message)])
        } catch {
            return Skin2ValidationReport(issues: [Skin2Issue(.error, "", "\(error)")])
        }

        var docs: [(label: String, doc: Skin2Document)] = [("", base)]
        for theme in base.themeNames {
            do { docs.append(("theme \(theme)", try Skin2Document.load(json: json, theme: theme, library: library))) } catch let e as Skin2Error {
                v.error(e.pointer, "theme \(theme): \(e.message)")
            } catch {}
        }
        for variant in base.variants.keys.sorted() {
            do { docs.append(("variant \(variant)", try Skin2Document.load(json: json, variant: variant, library: library))) } catch let e as Skin2Error {
                v.error(e.pointer, "variant \(variant): \(e.message)")
            } catch {}
        }

        v.checkDocumentKeys(base, json: json, documents: docs.map(\.doc))
        for (label, doc) in docs where label.isEmpty || label.hasPrefix("variant") {
            v.checkTree(doc, label: label)
        }
        for (label, doc) in docs {
            v.checkLayout(doc, label: label)
        }
        return Skin2ValidationReport(issues: v.issues, document: base)
    }

    struct Run {
        var issues: [Skin2Issue] = []

        mutating func add(_ i: Skin2Issue) { if !issues.contains(i) { issues.append(i) } }
        mutating func error(_ p: String, _ m: String) { add(Skin2Issue(.error, p, m)) }
        mutating func warn(_ p: String, _ m: String) { add(Skin2Issue(.warning, p, m)) }

        // MARK: Document level

        mutating func checkDocumentKeys(_ doc: Skin2Document, json: Skin2JSON, documents: [Skin2Document]) {
            let used = Skin2Features.used(source: json, documents: documents)
            let listed = Set(doc.requires)
            for (i, name) in doc.requires.enumerated() where !Skin2Features.all.contains(name) {
                warn("/requires/\(i)", "\"\(name)\" is not a 2.0 feature name; readers that don't know it fall back to the classic skin")
            }
            for name in used.subtracting(listed).sorted() {
                error("/requires", "the skin uses \(name) but does not list it in requires")
            }
            for (i, name) in doc.requires.enumerated() where Skin2Features.all.contains(name) && !used.contains(name) {
                warn("/requires/\(i)", "requires lists \(name), which the skin does not use")
            }
            if let traits = doc.bake?.traits {
                for family in Skin2TraitSet.requiredFamilies where !traits.contains(family) {
                    error("/bake/traits", "bake.traits must include \(family): the base representations must be a complete classic skin")
                }
            }
            for (i, gt) in doc.gameTypes.enumerated() where Skin2Inputs.inputs(forGameType: gt) == nil {
                warn("/gameTypes/\(i)", "no input table for game type \"\(gt)\"; its inputs are not checked")
            }
            if let screens = doc.screens {
                for (i, id) in screens.enumerated() where doc.node(id: id)?.type != .screen {
                    error("/screens/\(i)", "\"\(id)\" is not the id of a screen node")
                }
            }
        }

        // MARK: Tree

        struct Context {
            var control: Skin2Node?
            var controlPointer: String?
        }

        mutating func checkTree(_ doc: Skin2Document, label: String) {
            let suffix = label.isEmpty ? "" : " (\(label))"
            let count = doc.root.nodeCount
            if count > Skin2Document.maxNodes {
                error("/root", "the skin has \(count) nodes after expanding parts; the limit is \(Skin2Document.maxNodes)\(suffix)")
            }
            var ids: [String: String] = [:]
            var seenScreen = false
            visit(doc.root, pointer: "/root", context: Context(), doc: doc, ids: &ids, seenScreen: &seenScreen, suffix: suffix)
        }

        mutating func visit(_ n: Skin2Node, pointer p: String, context: Context, doc: Skin2Document,
                            ids: inout [String: String], seenScreen: inout Bool, suffix: String) {
            // Anchors are checked before this node's id is recorded: a node can't anchor to itself.
            var layouts: [(Skin2Layout, String)] = n.layout.map { [($0, p + "/layout")] } ?? []
            for (i, w) in n.when.enumerated() { if let l = w.patch.layout { layouts.append((l, "\(p)/when/\(i)/layout")) } }
            for (l, lp) in layouts {
                checkLengths(l, at: lp, suffix: suffix)
                switch l.anchor?.to {
                case .node(let id)?:
                    if ids[id] == nil {
                        error(lp + "/anchor/to", "anchors to #\(id), which is not a node earlier in document order\(suffix)")
                    }
                case .screen?:
                    if !seenScreen { error(lp + "/anchor/to", "anchors to screen, but no screen node comes earlier\(suffix)") }
                default: break
                }
            }

            if let id = n.id {
                if let first = ids[id] {
                    error(p + "/id", "id \"\(id)\" is already used at \(first)\(suffix)")
                } else {
                    ids[id] = p
                }
            }
            if n.type == .screen { seenScreen = true }

            switch n.type {
            case .control: checkControl(n, at: p, doc: doc, suffix: suffix)
            case .screen:
                if n.id == nil { error(p, "a screen needs an id\(suffix)") }
            case .group:
                if (n.stack != nil || n.grid != nil), n.layout?.size != nil, n.layout?.frame == nil, n.layout?.inset == nil {
                    warn(p + "/layout/size", "a stack or grid group takes its size from its children; size is ignored (use frame or inset for a fixed size)\(suffix)")
                }
                if n.stack?.distribute == .spaceBetween, n.layout?.frame == nil, n.layout?.inset == nil {
                    warn(p + "/stack/distribute", "spaceBetween has no room to spread into unless the group has a frame or an inset\(suffix)")
                }
            case .image:
                if let src = n.src, let problem = Self.assetPathProblem(src) { error(p + "/src", problem + suffix) }
            case .text:
                if let family = n.font?.family, family.contains("/") || family.contains("..") || family.contains(":") {
                    error(p + "/font/family", "a font family names a file in assets/fonts/, not a path or URL\(suffix)")
                }
                if let size = n.font?.size, size.usesSafeArea { error(p + "/font/size", "safe is only allowed in offset and inset\(suffix)") }
            case .shape:
                break
            }
            for (i, paint) in n.fills.enumerated() {
                if let src = paint.src, let problem = Self.assetPathProblem(src) { error("\(p)/fills/\(i)/src", problem + suffix) }
            }
            checkPaintLengths(n, at: p, suffix: suffix)

            if n.role == .knob, context.control?.kind != .thumbstick {
                error(p + "/role", "role knob belongs inside a thumbstick control\(suffix)")
            }
            if n.repeat != nil, n.type == .control {
                error(p + "/repeat", "controls can't repeat: hit testing ignores copies\(suffix)")
            }
            if n.type != .group, n.type != .control, n.children.isEmpty == false {
                warn(p + "/children", "only groups and controls have children\(suffix)")
            }

            var inner = context
            if n.type == .control {
                if context.control != nil { error(p, "a control inside a control is art, not a control\(suffix)") }
                inner = Context(control: n, controlPointer: p)
            }
            for (i, child) in n.children.enumerated() {
                visit(child, pointer: "\(p)/children/\(i)", context: inner, doc: doc, ids: &ids, seenScreen: &seenScreen, suffix: suffix)
            }
        }

        static func assetPathProblem(_ src: String) -> String? {
            if src.contains("://") || src.hasPrefix("data:") { return "no remote or inline URLs: src is a path under assets/" }
            if src.hasPrefix("/") || src.split(separator: "/").contains("..") || src.contains("\\") {
                return "src is a relative path under assets/, without .. or a leading /"
            }
            return nil
        }

        mutating func checkLengths(_ l: Skin2Layout, at p: String, suffix: String) {
            var noSafe: [(Skin2Length?, String)] = []
            for (i, f) in (l.frame ?? []).enumerated() { noSafe.append((f, "\(p)/frame/\(i)")) }
            for (name, s) in [("size", l.size), ("minSize", l.minSize), ("maxSize", l.maxSize)] {
                noSafe.append((s?.width, "\(p)/\(name)/width"))
                noSafe.append((s?.height, "\(p)/\(name)/height"))
            }
            for (length, lp) in noSafe where length?.usesSafeArea == true {
                error(lp, "safe is only allowed in offset and inset\(suffix)")
            }
        }

        mutating func checkPaintLengths(_ n: Skin2Node, at p: String, suffix: String) {
            var all: [(Skin2Length?, String)] = [(n.travel, p + "/travel"), (n.stack?.spacing, p + "/stack/spacing"),
                                                 (n.grid?.spacingX, p + "/grid/spacing"), (n.grid?.spacingY, p + "/grid/spacing"),
                                                 (n.repeat?.offset?.x, p + "/repeat/offset/x"), (n.repeat?.offset?.y, p + "/repeat/offset/y"),
                                                 (n.shape?.cornerRadius, p + "/shape/cornerRadius")]
            for l in n.hit?.extend?.all ?? [] { all.append((l, p + "/hit/extend")) }
            for (i, c) in (n.shape?.corners ?? []).enumerated() { all.append((c, "\(p)/shape/corners/\(i)")) }
            for (i, s) in n.strokes.enumerated() {
                all.append((s.width, "\(p)/strokes/\(i)/width"))
                for d in s.dash { all.append((d, "\(p)/strokes/\(i)/dash")) }
            }
            for (i, e) in n.effects.enumerated() {
                all.append((e.radius, "\(p)/effects/\(i)/radius"))
                all.append((e.spread, "\(p)/effects/\(i)/spread"))
                for o in e.offset { all.append((o, "\(p)/effects/\(i)/offset")) }
            }
            for (length, lp) in all where length?.usesSafeArea == true {
                error(lp, "safe is only allowed in offset and inset\(suffix)")
            }
        }

        mutating func checkControl(_ n: Skin2Node, at p: String, doc: Skin2Document, suffix: String) {
            guard let kind = n.kind else { return }
            if n.id == nil { error(p, "a control needs an id\(suffix)") }
            let names = n.inputNames
            if case .directions? = n.input, kind != .dpad {
                error(p + "/input", "only a d-pad takes {up, down, left, right}\(suffix)")
            }
            if kind == .dpad, n.input.map({ if case .directions = $0 { return false } else { return true } }) ?? true {
                error(p + "/input", "a d-pad's input is {\"up\", \"down\", \"left\", \"right\"}\(suffix)")
            }
            if names.isEmpty { error(p, "a control needs input or inputs\(suffix)") }

            switch kind {
            case .touchSurface:
                for name in names where !Skin2Inputs.touchSurface.contains(name) {
                    error(p, "a touch surface takes \(Skin2Inputs.touchSurface.sorted().joined(separator: ", ")), not \"\(name)\"\(suffix)")
                }
            case .action:
                if names.count != 1 { error(p, "an action control fires exactly one app action\(suffix)") }
                for name in names where !Skin2Inputs.actions.contains(name) {
                    error(p, "\"\(name)\" is not an app action (\(Skin2Inputs.actions.sorted().joined(separator: ", ")))\(suffix)")
                }
            case .button, .trigger, .dpad, .thumbstick:
                for gt in doc.gameTypes {
                    guard let system = Skin2Inputs.inputs(forGameType: gt) else { continue }
                    for name in names where !system.contains(name) && !Skin2Inputs.common.contains(name) && !Skin2Inputs.actions.contains(name) {
                        error(p, "\"\(name)\" is not an input of game type \(gt)\(suffix)")
                    }
                }
            }

            // States: names per kind, targets inside this control.
            var inner: [String: Skin2Node] = [:]
            for child in n.children { child.preorder { if let id = $0.id { inner[id] = $0 } } }
            var knobs = 0
            for child in n.children { child.preorder { if $0.role == .knob { knobs += 1 } } }
            if kind == .thumbstick, knobs == 0 { warn(p, "a thumbstick has no role: knob child to move\(suffix)") }
            for (name, state) in n.states.sorted(by: { $0.key < $1.key }) {
                let sp = Skin2Pointer.appending(p + "/states", name)
                if name.hasPrefix("pressed."), kind != .dpad { error(sp, "per-direction states are for d-pads\(suffix)") }
                for (i, patch) in state.patch.enumerated() {
                    guard let (id, copy) = patch.targetID else { continue }
                    let tp = "\(sp)/patch/\(i)/target"
                    guard let target = inner[id] else {
                        error(tp, "#\(id) is not inside this control\(suffix)")
                        continue
                    }
                    if let copy {
                        let count = target.repeat?.count ?? 1
                        if copy >= count { error(tp, "#\(id) has \(count) cop\(count == 1 ? "y" : "ies"); [\(copy)] is out of range\(suffix)") }
                    }
                }
            }
        }

        // MARK: Layout on the bake trait sets

        mutating func checkLayout(_ doc: Skin2Document, label: String) {
            let suffix = label.isEmpty ? "" : ", \(label)"
            var reportedPairs: Set<[String]> = []
            var reportedSmall: Set<String> = []
            for trait in Skin2TraitSet.sets(for: doc) {
                let r = Skin2Resolver.resolve(doc, in: trait.environment)
                for w in r.warnings { error(w.pointer, "\(w.message) (\(trait.name)\(suffix))") }
                let controls = r.controls.filter { $0.node.kind != .touchSurface }
                for (i, a) in controls.enumerated() {
                    guard let ha = a.hitFrame else { continue }
                    for b in controls[(i + 1)...] {
                        guard let hb = b.hitFrame, ha.overlaps(hb) else { continue }
                        let pair = [a.pointer, b.pointer]
                        guard reportedPairs.insert(pair).inserted else { continue }
                        error(a.pointer, "hit frame of #\(a.id ?? "?") overlaps #\(b.id ?? "?") on \(trait.name)\(suffix)")
                    }
                }
                for c in r.controls {
                    let side = min(c.exactFrame.width, c.exactFrame.height) / r.unit
                    if side < minimumControlSide - 0.0001, reportedSmall.insert(c.pointer).inserted {
                        warn(c.pointer, "#\(c.id ?? "?") is \(String(format: "%.1f", side)) pt on its short side at unit 1; controls should be at least \(Int(minimumControlSide)) pt (\(trait.name)\(suffix))")
                    }
                }
            }
        }
    }
}
