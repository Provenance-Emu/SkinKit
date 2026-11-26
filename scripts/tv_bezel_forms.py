#!/usr/bin/env python3
"""Writes the portrait and widescreen forms of a built-in TV into its skin document.

A TV's document (Sources/SkinKitBezels/Resources/TVBezels/<id>.skin.json) is drawn for a
landscape room with a 4:3 tube. This adds `when` entries so the same document also draws:

- portrait: the set at the top of a tall canvas, standing on a hi-fi console that runs down
  to the bottom (`console-*` nodes, portrait only): brushed metal, a trim strip and a
  perforated speaker grille, dark and even enough for the touch controls to float over;
- wide (flag `tv.wide`), landscape: the tube and cabinet widened to 16:9 at the same height;
- wide, portrait: the tube and cabinet shortened to 16:9 at the same width.

It expects the structure the room TVs share: a `room-band` group (skirting, floor) and a
1920x1080 `set` group holding the stand, the cabinet and one `tube` screen node. Entries it
wrote before are replaced, so it can be run again after the artwork changes.

    python3 scripts/tv_bezel_forms.py flat-tube-tv [--no-wide]
"""
import argparse
import json
import pathlib

FOLDER = pathlib.Path(__file__).resolve().parent.parent / "Sources/SkinKitBezels/Resources/TVBezels"
WIDE_FLAG = "tv.wide"
SET_WIDTH = 1920
CENTER_X = SET_WIDTH / 2
WIDE_ASPECT = 16 / 9
# How far the set sits below the top of a portrait canvas: the cabinet's top edge clears a
# phone's status bar.
PORTRAIT_TOP = 60
# Taller than any portrait canvas, so what is carried down reaches the bottom.
PORTRAIT_FLOOR_HEIGHT = 6000
# Ids of the nodes this script adds for the console under the TV in portrait.
CONSOLE_PREFIX = "console-"
# The grille's holes: `GRILLE_COUNT` rows of `GRILLE_COUNT` (the format's most per repeat),
# in two sets, the second shifted half a step both ways.
GRILLE_COUNT = 64
GRILLE_STEP_X = 22
GRILLE_STEP_Y = 44
GRILLE_HOLE = 11
# From this canvas width the documents show the cabinet with its speakers.
SPEAKERS_MIN_WIDTH = 1568
# The canvas width from which a widened cabinet with speakers, and its stand, still fit.
WIDE_SPEAKERS_MIN_WIDTH = 1920
PORTRAIT = {"orientation": "portrait"}
LANDSCAPE_WIDE = {"orientation": "landscape", "flag": WIDE_FLAG}
PORTRAIT_WIDE = {"orientation": "portrait", "flag": WIDE_FLAG}
MARK = "form"


def is_ours(entry):
    return entry.get("orientation") is not None


def frame_of(node, min_width=None):
    """The node's frame, or the one its `minWidth` entry gives."""
    if min_width is not None:
        for entry in node.get("when", []):
            if not is_ours(entry) and entry.get("minWidth") == min_width and "frame" in entry.get("layout", {}):
                return entry["layout"]["frame"]
    return node["layout"]["frame"]


def widened(frame, delta):
    x, y, width, height = frame
    if x < CENTER_X < x + width:
        return [x - delta, y, width + 2 * delta, height]
    return [x + delta if x >= CENTER_X else x - delta, y, width, height]


def shortened(frame, tube, delta):
    x, y, width, height = frame
    tube_bottom = tube[1] + tube[3]
    if y >= tube_bottom - 1:
        return [x, y - delta, width, height]
    if y + height > tube[1]:
        return [x, y, width, height - delta]
    return frame


def rect(node_id, frame, fills, radius=0, **more):
    shape = {"kind": "rect", "cornerRadius": radius} if radius else {"kind": "rect"}
    return {"type": "shape", "id": node_id, "layout": {"frame": frame}, "shape": shape, "fills": fills, **more}


def vertical(*stops):
    return {"type": "linear", "start": [0.5, 0], "end": [0.5, 1], "stops": [list(stop) for stop in stops]}


def horizontal(*stops):
    return {"type": "linear", "start": [0, 0.5], "end": [1, 0.5], "stops": [list(stop) for stop in stops]}


def holes(node_id, x, y):
    row = {"type": "shape", "id": f"{node_id}-hole", "layout": {"frame": [0, 0, GRILLE_HOLE, GRILLE_HOLE]},
           "shape": {"kind": "ellipse"},
           "fills": [vertical(("#050506", 0), ("#16171A", 1))],
           "repeat": {"count": GRILLE_COUNT, "offset": {"x": GRILLE_STEP_X, "y": 0}}}
    return {"type": "group", "id": node_id,
            "layout": {"frame": [x, y, GRILLE_COUNT * GRILLE_STEP_X, GRILLE_HOLE]},
            "repeat": {"count": GRILLE_COUNT, "offset": {"x": 0, "y": GRILLE_STEP_Y}},
            "children": [row]}


def console(top, left, width):
    """The console the set stands on in portrait, from `top` (the stand's bottom) down."""
    grille_left = CENTER_X - GRILLE_COUNT * GRILLE_STEP_X / 2
    grille_top = top + 150
    brushed = horizontal(("#22242A", 0), ("#34373E", 0.18), ("#24262B", 0.36), ("#3A3D45", 0.55),
                         ("#25272C", 0.74), ("#33363D", 0.9), ("#202227", 1))
    chrome = vertical(("#F2F4F6", 0), ("#B9BEC5", 0.35), ("#7C828B", 0.6), ("#D3D7DC", 1))
    nodes = [
        rect("console-body", [left, top, width, PORTRAIT_FLOOR_HEIGHT], [brushed]),
        # Light from above falls off down the front.
        rect("console-falloff", [left, top, width, 2400],
             [vertical(("#000000", 0.0, 0), ("#000000", 0.5, 1))]),
        rect("console-deep", [left, top + 2400, width, PORTRAIT_FLOOR_HEIGHT], [{"type": "solid", "color": "#000000", "opacity": 0.5}]),
        rect("console-lip", [left, top, width, 14], [chrome],
             effects=[{"type": "shadow", "color": "#000000", "opacity": 0.7, "radius": 18, "offset": [0, 10]}]),
        rect("console-groove", [left, top + 96, width, 4], [{"type": "solid", "color": "#000000", "opacity": 0.55}]),
        rect("console-groove-light", [left, top + 100, width, 2], [{"type": "solid", "color": "#FFFFFF", "opacity": 0.08}]),
        rect("console-plate", [CENTER_X - 150, top + 40, 300, 34], [chrome], radius=6,
             strokes=[{"color": "#4B5058", "width": 1.5, "align": "outer", "opacity": 0.9}]),
        {"type": "text", "id": "console-plate-text", "layout": {"frame": [CENTER_X - 150, top + 46, 300, 22]},
         "text": "HI-FI  STEREO  SYSTEM", "font": {"size": 15, "weight": "semibold"}, "color": "#3A3E45", "align": "center"},
        holes("console-holes-a", grille_left, grille_top),
        holes("console-holes-b", grille_left + GRILLE_STEP_X / 2, grille_top + GRILLE_STEP_Y / 2),
    ]
    for node in nodes:
        node["visible"] = dict(PORTRAIT)
    return nodes


def add(node, condition, patch):
    node.setdefault("when", []).append({**condition, **patch})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bezel")
    parser.add_argument("--no-wide", action="store_true", help="portrait only: keep the 4:3 tube")
    args = parser.parse_args()
    path = FOLDER / f"{args.bezel}.skin.json"
    document = json.loads(path.read_text())
    groups = {node["id"]: node for node in document["root"]["children"]}
    band, tv = groups["room-band"], groups["set"]
    tv["children"] = [node for node in tv["children"] if not node["id"].startswith(CONSOLE_PREFIX)]
    nodes = band["children"] + tv["children"]
    for node in [band, tv] + nodes:
        node["when"] = [entry for entry in node.get("when", []) if not is_ours(entry)]
        if not node["when"]:
            del node["when"]

    tube = next(node for node in tv["children"] if node["type"] == "screen")["layout"]["frame"]
    cabinet = next(node for node in tv["children"] if node["id"] == "cabinet")
    slim = frame_of(cabinet)
    cabinet_left, cabinet_right = slim[0], slim[0] + slim[2]
    wide_delta = round((tube[3] * WIDE_ASPECT - tube[2]) / 2)
    short_delta = round(tube[3] - tube[2] / WIDE_ASPECT)

    # Portrait: the set and the room's band hang from the top, and the floor runs on down.
    top = {"layout": {"anchor": {"y": "top"}, "offset": {"y": PORTRAIT_TOP}}}
    add(band, PORTRAIT, top)
    add(tv, PORTRAIT, top)
    floor = next(node for node in band["children"] if node["id"] == "floor")
    stand = next(node for node in tv["children"] if node["id"] == "stand-side")["layout"]["frame"]
    tv["children"][:0] = console(stand[1] + stand[3], stand[0], stand[2])
    nodes = band["children"] + tv["children"]

    if not args.no_wide:
        for node in tv["children"]:
            if node["id"].startswith(CONSOLE_PREFIX):
                continue
            frame = node["layout"]["frame"]
            inside = frame[0] >= cabinet_left and frame[0] + frame[2] <= cabinet_right
            speakers = "visible" in node and node["visible"].get("minWidth") == SPEAKERS_MIN_WIDTH
            if inside:
                add(node, LANDSCAPE_WIDE, {"layout": {"frame": widened(frame, wide_delta)}})
            if node is cabinet or node["id"].startswith("cabinet"):
                # With room for it, the speaker cabinet widens too.
                full = frame_of(node, SPEAKERS_MIN_WIDTH)
                add(node, {**LANDSCAPE_WIDE, "minWidth": WIDE_SPEAKERS_MIN_WIDTH},
                    {"layout": {"frame": widened(full, wide_delta)}})
            elif speakers:
                add(node, LANDSCAPE_WIDE,
                    {"visible": {"minWidth": WIDE_SPEAKERS_MIN_WIDTH}, "layout": {"frame": widened(frame, wide_delta)}})
            elif not inside and frame[0] < CENTER_X < frame[0] + frame[2] and frame[2] > slim[2]:
                # The stand, wider than the cabinet: it grows with the speaker cabinet.
                add(node, {**LANDSCAPE_WIDE, "minWidth": WIDE_SPEAKERS_MIN_WIDTH},
                    {"layout": {"frame": widened(frame, wide_delta)}})
        for node in nodes:
            frame = node["layout"]["frame"]
            shorter = shortened(frame, tube, short_delta)
            if shorter != frame:
                add(node, PORTRAIT_WIDE, {"layout": {"frame": shorter}})

    path.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
    print(f"{args.bezel}: tube {tube}, wide +{wide_delta} each side, portrait wide -{short_delta} tall")


if __name__ == "__main__":
    main()
