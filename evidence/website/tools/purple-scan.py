#!/usr/bin/env python3
"""Scan screenshots for lavender / purple pixel clusters.

A pixel counts as lavender/purple when its HSV hue sits in the violet band
(default 260-285 deg) with saturation above the threshold (default 0.08) and
value above 0.05. `--strict` uses those defaults; `--relaxed` widens the band
(255-295 deg, saturation > 0.03) to catch faint lavender washes.

Usage:
  python3 evidence/website/tools/purple-scan.py [--strict|--relaxed] [--json] <png> ...
"""
import colorsys
import json
import sys
from pathlib import Path

from PIL import Image

CELL = 40
PRESETS = {
    "strict": {"hue_min": 260.0, "hue_max": 285.0, "sat_min": 0.08},
    "relaxed": {"hue_min": 255.0, "hue_max": 295.0, "sat_min": 0.03},
}


def scan(path, hue_min, hue_max, sat_min):
    image = Image.open(path).convert("RGB")
    width, height = image.size
    pixels = image.load()
    hits = 0
    cells = {}
    for y in range(height):
        for x in range(width):
            r, g, b = pixels[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            hue = h * 360.0
            if hue_min <= hue <= hue_max and s > sat_min and v > 0.05:
                hits += 1
                key = (x // CELL * CELL, y // CELL * CELL)
                cells[key] = cells.get(key, 0) + 1
    total = width * height
    hot = [{"x": cx, "y": cy, "pixels": n}
           for (cx, cy), n in sorted(cells.items(), key=lambda kv: -kv[1])[:5]]
    return {
        "file": str(path), "width": width, "height": height,
        "total_pixels": total, "purple_pixels": hits,
        "ratio": round(hits / total, 6),
        "percent": round(hits / total * 100, 4),
        "hue_band": [hue_min, hue_max], "sat_min": sat_min,
        "hot_cells": hot,
    }


def main(argv):
    as_json = "--json" in argv
    preset = "relaxed" if "--relaxed" in argv else "strict"
    cfg = PRESETS[preset]
    paths = [Path(a) for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__.strip())
        return 2
    results = [scan(p, **cfg) for p in paths]
    if as_json:
        print(json.dumps({"preset": preset, "results": results}, indent=2))
    else:
        for r in results:
            print(f"{r['file']}: {r['purple_pixels']}/{r['total_pixels']} px = {r['percent']}% "
                  f"[{preset}: hue {r['hue_band'][0]:.0f}-{r['hue_band'][1]:.0f}, sat>{r['sat_min']}] "
                  f"hot={r['hot_cells']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
