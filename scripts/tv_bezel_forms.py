#!/usr/bin/env python3
"""Writes the portrait and widescreen forms of the built-in TVs into their skin documents.

A TV's document (Sources/SkinKitBezels/Resources/TVBezels/<id>.skin.json) is drawn for a
landscape room with a 4:3 tube. This adds `when` entries and a few portrait-only nodes so
the same document also draws:

- portrait: the set at the top of a tall canvas, and under it a surface in the TV's own
  material that runs down to the bottom (`console-*` nodes: a hi-fi console, a desk front,
  a carpet), textured but dark and even enough for the touch controls to float over;
- shelf (flag `tv.shelf`), portrait: a small bay in the lower surface, at the right under the
  set, for a second screen the app owns (a Dreamcast VMU). `console-shelf-screen` is where
  that screen goes; an app that has none leaves the flag off and the bay is not drawn;
- wide (flag `tv.wide`), landscape: the tube and cabinet widened to 16:9 at the same height;
- wide, portrait: the tube and cabinet shortened to 16:9 at the same width.

It expects a 1920x1080 `set` group holding the cabinet and one `tube` screen node, and
reads the rest from `TVS` below. Entries and nodes it wrote before are replaced, so run it
again after a TV's artwork changes.

    python3 scripts/tv_bezel_forms.py            # every TV in TVS
    python3 scripts/tv_bezel_forms.py dorm-tv
"""
import json
import math
import pathlib
import sys

FOLDER = pathlib.Path(__file__).resolve().parent.parent / "Sources/SkinKitBezels/Resources/TVBezels"
WIDE_FLAG = "tv.wide"
SET_WIDTH = 1920
CENTER_X = SET_WIDTH / 2
WIDE_ASPECT = 16 / 9
# How far the set sits below the top of a portrait canvas where nothing is in the way.
PORTRAIT_TOP = 60
# The gap kept between the canvas's top safe-area inset (a notch, a Dynamic Island) and the
# top of the set, where that is lower than PORTRAIT_TOP puts it.
SAFE_TOP_GAP = 12
# Taller than any portrait canvas, so what is carried down reaches the bottom.
PORTRAIT_DEPTH = 6000
# The lower surface is wider than any portrait canvas.
CONSOLE_LEFT, CONSOLE_WIDTH = 150, 1620
CONSOLE_PREFIX = "console-"
# The second half of a repeated node this script split in two (see `split_repeats`).
REST_SUFFIX = "-rest"
# The texture: `TEXTURE_COUNT` copies (the format's most per repeat) each way.
TEXTURE_COUNT = 64
HOLE_STEP_X, HOLE_STEP_Y, HOLE_SIZE = 22, 44, 11
SLAT_STEP = 46
# A centre-spanning node at least this much of the tube's width is part of the frame and
# widens with it; a narrower one (a tape slot, a base) keeps its size.
FRAME_SHARE = 0.9
# The bay for the app's second screen: its right edge is inside the narrowest portrait canvas
# (1152 points, the front seat), and its screen is 3:2, the shape of a VMU's.
SHELF_FLAG = "tv.shelf"
SHELF_WIDTH, SHELF_HEIGHT, SHELF_RIM = 300, 208, 12
SHELF_RIGHT = CENTER_X + 1152 / 2 - 40
SHELF_DROP = 128
PORTRAIT = {"orientation": "portrait"}
PORTRAIT_SHELF = {"orientation": "portrait", "flag": SHELF_FLAG}
LANDSCAPE_WIDE = {"orientation": "landscape", "flag": WIDE_FLAG}
PORTRAIT_WIDE = {"orientation": "portrait", "flag": WIDE_FLAG}

# cabinet: the node whose frame bounds the set (its narrow form).
# surface: the node the set stands on; the lower surface starts at its bottom edge.
# top: the node whose top edge must clear the safe area, when that is not the cabinet (a
# cabinet that runs off the top of the canvas names its marquee).
# base: the lower surface's colour. texture: holes, tufts or slats. lip: a trim strip's
# colours along the top, or None. plate: the text of a name plate, or None.
TVS = {
    "flat-tube-tv": {"cabinet": "cabinet", "surface": "stand-side", "base": "#2B2D33", "texture": "holes",
                     "lip": ("#F2F4F6", "#7C828B"), "plate": "HI-FI  STEREO  SYSTEM"},
    "studio-monitor": {"cabinet": "body", "surface": "shelf", "base": "#25272C", "texture": "holes",
                       "lip": ("#6A6F78", "#2E3035"), "plate": None},
    "computer-monitor": {"cabinet": "case", "surface": "desk", "base": "#54432C", "texture": "slats",
                         "lip": None, "plate": None},
    "vga-monitor": {"cabinet": "case", "surface": "desk", "base": "#565A61", "texture": "slats",
                    "lip": None, "plate": None},
    "dorm-tv": {"cabinet": "cabinet", "surface": "desk", "base": "#5E4328", "texture": "slats",
                "lip": None, "plate": None},
    "living-room-tv": {"cabinet": "cabinet", "surface": "carpet", "base": "#2C1E16", "texture": "tufts",
                       "lip": None, "plate": None},
    "candy-cabinet": {"cabinet": "body", "top": "header", "surface": "panel", "base": "#2F3035", "texture": "slats",
                      "lip": ("#F4F4F1", "#C9C9C2"), "plate": None},
}


def mix(color, other, amount):
    a, b = (int(color[i:i + 2], 16) for i in (1, 3, 5)), (int(other[i:i + 2], 16) for i in (1, 3, 5))
    return "#" + "".join(f"{round(x + (y - x) * amount):02X}" for x, y in zip(a, b))


def lighter(color, amount):
    return mix(color, "#FFFFFF", amount)


def darker(color, amount):
    return mix(color, "#000000", amount)


def is_ours(entry):
    return entry.get("orientation") is not None


def wide_variant(node):
    """The node's own entry for a wide canvas (`minWidth` with a frame), if it has one."""
    for entry in node.get("when", []):
        if not is_ours(entry) and "minWidth" in entry and "frame" in entry.get("layout", {}):
            return entry
    return None


def widened(frame, delta, tube_width):
    x, y, width, height = frame
    if x < CENTER_X < x + width:
        if width < tube_width * FRAME_SHARE:
            return frame
        return [x - delta, y, width + 2 * delta, height]
    return [x + delta if x >= CENTER_X else x - delta, y, width, height]


def shortened(frame, tube, delta):
    x, y, width, height = frame
    if y >= tube[1] + tube[3] - 1:
        return [x, y - delta, width, height]
    if y + height > tube[1] + tube[3] / 2:
        return [x, y, width, height - delta]
    return frame


def room_for(min_width, delta):
    """The canvas width from which a node needing `min_width` still fits once widened."""
    return math.ceil((min_width + 2 * delta) / 10) * 10


def rect(node_id, frame, fills, radius=0, **more):
    shape = {"kind": "rect", "cornerRadius": radius} if radius else {"kind": "rect"}
    return {"type": "shape", "id": node_id, "layout": {"frame": frame}, "shape": shape, "fills": fills, **more}


def solid(color, opacity):
    return {"type": "solid", "color": color, "opacity": opacity}


def vertical(*stops):
    return {"type": "linear", "start": [0.5, 0], "end": [0.5, 1], "stops": [list(stop) for stop in stops]}


def horizontal(*stops):
    return {"type": "linear", "start": [0, 0.5], "end": [1, 0.5], "stops": [list(stop) for stop in stops]}


def dots(node_id, x, y, fill):
    """A grid of dots: a row of them, repeated down."""
    dot = {"type": "shape", "id": f"{node_id}-dot", "layout": {"frame": [0, 0, HOLE_SIZE, HOLE_SIZE]},
           "shape": {"kind": "ellipse"}, "fills": [fill],
           "repeat": {"count": TEXTURE_COUNT, "offset": {"x": HOLE_STEP_X, "y": 0}}}
    return {"type": "group", "id": node_id,
            "layout": {"frame": [x, y, TEXTURE_COUNT * HOLE_STEP_X, HOLE_SIZE]},
            "repeat": {"count": TEXTURE_COUNT, "offset": {"x": 0, "y": HOLE_STEP_Y}},
            "children": [dot]}


def texture(kind, base, top):
    left = CENTER_X - TEXTURE_COUNT * HOLE_STEP_X / 2
    if kind == "slats":
        down = {"count": TEXTURE_COUNT, "offset": {"x": 0, "y": SLAT_STEP}}
        return [rect("console-slats", [CONSOLE_LEFT, top, CONSOLE_WIDTH, 3], [solid("#000000", 0.4)], repeat=down),
                rect("console-slats-light", [CONSOLE_LEFT, top + 3, CONSOLE_WIDTH, 2], [solid("#FFFFFF", 0.07)], repeat=down)]
    fill = (vertical((darker(base, 0.85), 0), (darker(base, 0.5), 1)) if kind == "holes"
            else vertical((lighter(base, 0.16), 0), (lighter(base, 0.04), 1)))
    return [dots("console-dots-a", left, top, fill),
            dots("console-dots-b", left + HOLE_STEP_X / 2, top + HOLE_STEP_Y / 2, fill)]


def console(top, tv):
    """The surface under the set in portrait, from `top` down."""
    base, lip, plate = tv["base"], tv["lip"], tv["plate"]
    brushed = horizontal((darker(base, 0.18), 0), (lighter(base, 0.08), 0.18), (darker(base, 0.12), 0.36),
                         (lighter(base, 0.14), 0.55), (darker(base, 0.1), 0.74), (lighter(base, 0.06), 0.9),
                         (darker(base, 0.22), 1))
    nodes = [
        rect("console-body", [CONSOLE_LEFT, top, CONSOLE_WIDTH, PORTRAIT_DEPTH], [brushed]),
        # Light from above falls off down the front.
        rect("console-falloff", [CONSOLE_LEFT, top, CONSOLE_WIDTH, 2400], [vertical(("#000000", 0.0, 0), ("#000000", 0.5, 1))]),
        rect("console-deep", [CONSOLE_LEFT, top + 2400, CONSOLE_WIDTH, PORTRAIT_DEPTH], [solid("#000000", 0.5)]),
        rect("console-shade", [CONSOLE_LEFT, top, CONSOLE_WIDTH, 60], [vertical(("#000000", 0.55, 0), ("#000000", 0.0, 1))]),
        rect("console-groove", [CONSOLE_LEFT, top + 96, CONSOLE_WIDTH, 4], [solid("#000000", 0.55)]),
        rect("console-groove-light", [CONSOLE_LEFT, top + 100, CONSOLE_WIDTH, 2], [solid("#FFFFFF", 0.08)]),
    ]
    if lip:
        nodes.append(rect("console-lip", [CONSOLE_LEFT, top, CONSOLE_WIDTH, 14],
                          [vertical((lip[0], 0), (mix(lip[0], lip[1], 0.5), 0.35), (lip[1], 0.6), (mix(lip[0], lip[1], 0.25), 1))],
                          effects=[{"type": "shadow", "color": "#000000", "opacity": 0.7, "radius": 18, "offset": [0, 10]}]))
    if plate:
        nodes.append(rect("console-plate", [CENTER_X - 150, top + 40, 300, 34],
                          [vertical(("#F2F4F6", 0), ("#B9BEC5", 0.35), ("#7C828B", 0.6), ("#D3D7DC", 1))], radius=6,
                          strokes=[{"color": "#4B5058", "width": 1.5, "align": "outer", "opacity": 0.9}]))
        nodes.append({"type": "text", "id": "console-plate-text", "layout": {"frame": [CENTER_X - 150, top + 46, 300, 22]},
                      "text": plate, "font": {"size": 15, "weight": "semibold"}, "color": "#3A3E45", "align": "center"})
    nodes += texture(tv["texture"], base, top + 150)
    for node in nodes:
        node["visible"] = dict(PORTRAIT)
    return nodes + shelf(top, base)


def shelf(top, base):
    """The bay for the app's second screen, drawn only when the app asks for it."""
    x, y = SHELF_RIGHT - SHELF_WIDTH, top + SHELF_DROP
    inner = [x + SHELF_RIM, y + SHELF_RIM, SHELF_WIDTH - 2 * SHELF_RIM, SHELF_HEIGHT - 2 * SHELF_RIM]
    nodes = [
        rect("console-shelf", [x, y, SHELF_WIDTH, SHELF_HEIGHT],
             [vertical((lighter(base, 0.22), 0), (lighter(base, 0.08), 0.5), (darker(base, 0.25), 1))], radius=16,
             strokes=[{"color": "#000000", "width": 2, "align": "outer", "opacity": 0.6}],
             effects=[{"type": "shadow", "color": "#000000", "opacity": 0.6, "radius": 14, "offset": [0, 8]}]),
        rect("console-shelf-screen", inner, [solid("#0B0C0E", 1)], radius=8,
             strokes=[{"color": "#000000", "width": 2, "align": "inner", "opacity": 0.8}]),
    ]
    for node in nodes:
        node["visible"] = dict(PORTRAIT_SHELF)
    return nodes


def merge_repeats(children):
    """Undoes `split_repeats` from an earlier run."""
    by_id = {node["id"]: node for node in children}
    for node in [node for node in children if node["id"].endswith(REST_SUFFIX)]:
        by_id[node["id"][:-len(REST_SUFFIX)]]["repeat"]["count"] += node["repeat"]["count"]
        children.remove(node)


def split_repeats(children, tube, delta):
    """A node repeated down the cabinet (wood grain, speaker slots) cannot lose copies in a
    `when` entry, so the copies that would hang below the shortened cabinet become a second
    node, hidden in the short form."""
    limit = tube[1] + tube[3] - delta
    for node in list(children):
        step = node.get("repeat", {}).get("offset", {}).get("y", 0)
        if node["id"].startswith(CONSOLE_PREFIX) or step <= 0:
            continue
        x, y, width, height = node["layout"]["frame"]
        count = node["repeat"]["count"]
        if y >= tube[1] + tube[3] - 1 or y + (count - 1) * step + height <= limit:
            continue
        keep = max(1, min(count - 1, int((limit - height - y) // step) + 1))
        rest = json.loads(json.dumps(node))
        rest["id"] += REST_SUFFIX
        rest["layout"]["frame"] = [x, y + keep * step, width, height]
        rest["repeat"]["count"] = count - keep
        for entry in rest.get("when", []):
            if "frame" in entry.get("layout", {}):
                entry["layout"]["frame"][1] += keep * step
        node["repeat"]["count"] = keep
        children.insert(children.index(node) + 1, rest)


def add(node, condition, patch):
    node.setdefault("when", []).append({**condition, **patch})


def write_forms(name, tv):
    path = FOLDER / f"{name}.skin.json"
    document = json.loads(path.read_text())
    groups = {node["id"]: node for node in document["root"]["children"] if node["type"] == "group"}
    band, tv_set = groups.get("room-band"), groups["set"]
    tv_set["children"] = [node for node in tv_set["children"] if not node["id"].startswith(CONSOLE_PREFIX)]
    merge_repeats(tv_set["children"])
    band_nodes = band["children"] if band else []
    for node in [group for group in (band, tv_set) if group] + band_nodes + tv_set["children"]:
        node["when"] = [entry for entry in node.get("when", []) if not is_ours(entry)]
        if not node["when"]:
            del node["when"]

    by_id = {node["id"]: node for node in band_nodes + tv_set["children"]}
    tube = next(node for node in tv_set["children"] if node["type"] == "screen")["layout"]["frame"]
    slim = by_id[tv["cabinet"]]["layout"]["frame"]
    cabinet_left, cabinet_right = slim[0], slim[0] + slim[2]
    wide_delta = round((tube[3] * WIDE_ASPECT - tube[2]) / 2)
    short_delta = round(tube[3] - tube[2] / WIDE_ASPECT)

    split_repeats(tv_set["children"], tube, short_delta)

    # Portrait: the set and the room's band hang from the top, on the lower surface.
    # Under a notch the set moves down until its top edge is clear of it.
    set_top = by_id[tv.get("top", tv["cabinet"])]["layout"]["frame"][1]
    clear = {"sum": [{"safe": "top"}, SAFE_TOP_GAP - set_top]}
    top = {"layout": {"anchor": {"y": "top"}, "offset": {"y": {"max": [PORTRAIT_TOP, clear]}}}}
    for group in (band, tv_set):
        if group:
            add(group, PORTRAIT, top)
    surface = by_id[tv["surface"]]["layout"]["frame"]
    tv_set["children"][:0] = console(surface[1] + surface[3], tv)

    for node in tv_set["children"]:
        if node["id"].startswith(CONSOLE_PREFIX):
            continue
        frame = node["layout"]["frame"]
        variant = wide_variant(node)
        inside = frame[0] >= cabinet_left and frame[0] + frame[2] <= cabinet_right
        min_width = node["visible"].get("minWidth") if isinstance(node.get("visible"), dict) else None
        if min_width is not None:
            # Shown only where there is room (speakers, posters): they move out, and need more room.
            x = frame[0] + wide_delta if frame[0] >= CENTER_X else frame[0] - wide_delta
            add(node, LANDSCAPE_WIDE, {"visible": {"minWidth": room_for(min_width, wide_delta)},
                                       "layout": {"frame": [x] + frame[1:]}})
            continue
        if inside:
            add(node, LANDSCAPE_WIDE, {"layout": {"frame": widened(frame, wide_delta, tube[2])}})
        if variant:
            # Its form for a wide canvas (the cabinet with its speakers) widens too.
            add(node, {**LANDSCAPE_WIDE, "minWidth": room_for(variant["minWidth"], wide_delta)},
                {"layout": {"frame": widened(variant["layout"]["frame"], wide_delta, tube[2])}})
        elif not inside and frame[0] < CENTER_X < frame[0] + frame[2] and frame[2] > slim[2]:
            # A stand wider than the cabinet grows with the widest cabinet.
            widest = max((wide_variant(other)["minWidth"] for other in tv_set["children"] if wide_variant(other)), default=None)
            if widest is not None:
                add(node, {**LANDSCAPE_WIDE, "minWidth": room_for(widest, wide_delta)},
                    {"layout": {"frame": widened(frame, wide_delta, tube[2])}})
    for node in band_nodes + tv_set["children"]:
        frame = node["layout"]["frame"]
        if node["id"].endswith(REST_SUFFIX):
            add(node, PORTRAIT_WIDE, {"visible": False})
            continue
        shorter = shortened(frame, tube, short_delta)
        if shorter != frame:
            add(node, PORTRAIT_WIDE, {"layout": {"frame": shorter}})

    path.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
    print(f"{name}: tube {tube}, wide +{wide_delta} each side, portrait wide -{short_delta} tall")


def main():
    names = sys.argv[1:] or list(TVS)
    for name in names:
        write_forms(name, TVS[name])


if __name__ == "__main__":
    main()
