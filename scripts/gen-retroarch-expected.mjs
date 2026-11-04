#!/usr/bin/env node
// Regenerates Tests/SkinKitRetroArchTests/Fixtures/expected/ from the JavaScript converter in the
// skins repo (Provenance-Emu/skins, docs/js/skin/retroarch-convert.js; generated from skins#38 at
// 2f4d7e8c8ab085b90fcebb2026c135433d4330a2, which is what main carries).
//
//   node scripts/gen-retroarch-expected.mjs /path/to/skins-checkout
//
// For every case in Fixtures/cases.json it writes <id>.cfg, <id>.README.txt and <id>.json (the rest of the
// converter's result: name, system, device, notes, skipped, unconvertible, images, layouts). The Swift tests
// compare SkinKitRetroArch's output against these files, so the converters stay byte-for-byte aligned.
//
// The input map is NOT read from the skins checkout: the vendored copy under Sources/SkinKitRetroArch/Resources
// is the one both sides must use. skins vendors these fixtures (tests/fixtures/retroarch/skinkit/, with the
// SkinKit commit in SOURCE) and checks its converter against them and its map against this one; after
// regenerating here, re-vendor them there. RetroArchInputMapPinTests pins the map's hash on this side.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const skins = process.argv[2];
if (!skins) { console.error("usage: gen-retroarch-expected.mjs <skins checkout>"); process.exit(2); }

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const fixtures = join(root, "Tests", "SkinKitRetroArchTests", "Fixtures");
const RA = await import(pathToFileURL(join(skins, "docs", "js", "skin", "retroarch-convert.js")).href);
const inputMap = JSON.parse(readFileSync(join(root, "Sources", "SkinKitRetroArch", "Resources", "retroarch-input-map.json"), "utf8"));

const cases = JSON.parse(readFileSync(join(fixtures, "cases.json"), "utf8"));
const out = join(fixtures, "expected");
mkdirSync(out, { recursive: true });

const rectOf = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });

for (const c of cases) {
  const info = RA.parseInfo(readFileSync(join(fixtures, "info", `${c.info}.info.json`), "utf8"));
  if (c.tvFromIPadStandardLandscape) info.representations.tv = { standard: { landscape: info.representations.ipad.standard.landscape } };
  const opts = { inputMap };
  for (const k of ["device", "displayType", "screenAspect", "name", "entries"]) if (c[k] !== undefined) opts[k] = c[k];
  const r = RA.convert(info, opts);
  writeFileSync(join(out, `${c.id}.cfg`), r.cfg);
  writeFileSync(join(out, `${c.id}.README.txt`), r.readme);
  const summary = {
    name: r.name,
    system: r.system,
    device: r.device,
    notes: r.notes,
    skipped: r.skipped,
    unconvertible: r.unconvertible,
    descCount: r.descs.length,
    images: r.images.map(i => ({
      file: i.file, kind: i.kind, asset: i.asset, orientation: i.orientation, overlayName: i.overlayName,
      width: i.width, height: i.height,
      innerWidth: i.innerWidth ?? null, innerHeight: i.innerHeight ?? null,
      clearRects: i.clearRects.map(rectOf),
    })),
    layouts: r.layouts.map(l => ({
      orientation: l.orientation, overlayName: l.overlayName, set: l.set, displayType: l.displayType,
      mapping: { width: l.mapping.width, height: l.mapping.height }, asset: l.asset,
      rect: l.rect, translucent: l.translucent, screens: l.screens, items: l.items, descs: l.descs,
    })),
  };
  writeFileSync(join(out, `${c.id}.json`), JSON.stringify(summary, null, 2) + "\n");
}
console.log(`wrote ${cases.length} cases to ${out}`);
