#!/usr/bin/env python3
"""Regenerate Sources/IconForge/PaletteData.swift from a palette JSON export.

Usage:  python3 Tools/generate_palettes.py path/to/palettes.json

The JSON is expected to hold {"palettes": [{"rank": 1, "name": "...",
"colors": ["#RRGGBB", ...]}, ...]}; "name" may be null.
"""
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = REPO / "Sources" / "IconForge" / "PaletteData.swift"
HEX = re.compile(r"[0-9A-F]{6}")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    data = json.loads(pathlib.Path(sys.argv[1]).read_text())
    lines = [
        "// Generated from the Coolors trending feed. Edit the generator, not this file.",
        "",
        "extension PaletteLibrary {",
        "    /// The trending Coolors palettes (coolors.co/palettes/trending).",
        "    static let trending: [ColorPalette] = [",
    ]

    for palette in data["palettes"]:
        hexes = [c.lstrip("#").upper() for c in palette["colors"]]
        if not all(HEX.fullmatch(h) for h in hexes):
            raise ValueError(f"bad colour in palette {palette['rank']}: {hexes}")
        name = palette.get("name")
        name_literal = "nil" if not name else '"%s"' % name.replace('"', '\\"')
        joined = ", ".join('"%s"' % h for h in hexes)
        lines.append(
            "        ColorPalette(rank: %d, name: %s, hexes: [%s])," % (int(palette["rank"]), name_literal, joined)
        )

    lines += ["    ]", "}", ""]
    OUT.write_text("\n".join(lines))
    print(f"wrote {OUT.relative_to(REPO)} with {len(data['palettes'])} palettes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
