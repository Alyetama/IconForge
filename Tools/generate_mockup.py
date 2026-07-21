#!/usr/bin/env python3
"""Regenerate docs/mockup.svg from the icons in docs/examples.

Usage:  python3 Tools/generate_mockup.py

The mockup is a drawing of the IconForge window, so it has to be kept in step
with ContentView by hand. Icons are embedded as base64 rather than linked,
because an SVG loaded through <img> cannot fetch external files and a relative
path renders blank in the README.

Each icon is embedded once at ICON_BLOB_PX and reused at every size through
<use> and a transform, which keeps the file to four blobs rather than fifteen.
"""
import base64
import math
import pathlib
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
EXAMPLES = REPO / "docs" / "examples"
OUT = REPO / "docs" / "mockup.svg"

# The hero is drawn at 178pt and renders on retina at roughly twice that.
HERO_BLOB_PX = 384
ICON_BLOB_PX = 128

W, H = 1240, 960
WIN = (60, 60, 1120, 840)          # x, y, w, h
PANE_X, PANE_R = 452, 1180         # preview pane bounds
PANE_MID = (PANE_X + PANE_R) // 2  # 816
FIELD_X, FIELD_W = 92, 328

# name on disk, label under the gallery tile, blob size
ICONS = [
    ("dupefind", "DupeFind", HERO_BLOB_PX),
    ("mongo", "Mongo", ICON_BLOB_PX),
    ("tusk", "Tusk", ICON_BLOB_PX),
    ("iconforge-full", "IconForge", ICON_BLOB_PX),
]


def blob(name: str, pixels: int) -> str:
    """Downscale one example to `pixels` and return it as a data URI."""
    source = EXAMPLES / f"{name}.png"
    if not source.exists():
        sys.exit(f"missing {source}")
    with tempfile.TemporaryDirectory() as tmp:
        scaled = pathlib.Path(tmp) / "scaled.png"
        subprocess.run(["sips", "-Z", str(pixels), str(source), "--out", str(scaled)],
                       check=True, capture_output=True)
        data = scaled.read_bytes()
    return "data:image/png;base64," + base64.b64encode(data).decode()


def use(icon: str, x: float, y: float, side: float, clip: str | None = None) -> str:
    """Place an embedded icon at `side` points, optionally clipped."""
    scale = side / 100
    element = f'<use href="#ic-{icon}" transform="translate({x} {y}) scale({scale:.5f})"/>'
    return f'<g clip-path="url(#{clip})">{element}</g>' if clip else element


def rounded_clip(cid: str, x: float, y: float, side: float, radius: float) -> str:
    return f'<clipPath id="{cid}"><rect x="{x}" y="{y}" width="{side}" height="{side}" rx="{radius}"/></clipPath>'


def field(x: int, y: int, w: int, h: int = 30) -> str:
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="#22262e" stroke="#333844"/>'


def button(x: int, y: int, w: int, h: int = 28) -> str:
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="7" fill="#252932" stroke="#343a46"/>'


def chevron(x: int, y: int) -> str:
    """The up/down pair macOS puts inside a menu picker."""
    return (f'<path d="M{x} {y} l4 -5 l4 5 M{x} {y + 6} l4 5 l4 -5" '
            f'stroke="#8b929c" stroke-width="1.3" fill="none" stroke-linecap="round"/>')


def label(x: int, y: int, text: str, hint: str = "") -> str:
    tail = f' <tspan fill="#6e7580" font-size="11">{hint}</tspan>' if hint else ""
    return f'<text x="{x}" y="{y}" fill="#a8b0bb" font-size="12">{text}{tail}</text>'


def value(x: int, y: int, text: str, size: float = 13, fill: str = "#e8eaef") -> str:
    return f'<text x="{x}" y="{y}" fill="{fill}" font-size="{size}">{text}</text>'


def centred(x: int, y: int, text: str, size: float = 12.5, fill: str = "#dfe3ea", weight: str = "") -> str:
    bold = f' font-weight="{weight}"' if weight else ""
    return (f'<text x="{x}" y="{y}" fill="{fill}" font-size="{size}"{bold} '
            f'text-anchor="middle">{text}</text>')


def segmented(x: int, y: int, w: int, cells: list[str], selected: int, h: int = 28) -> str:
    """A macOS segmented control, the selected cell filled."""
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="#22262e" stroke="#333844"/>']
    cell = w / len(cells)
    for index, text in enumerate(cells):
        left = x + cell * index
        if index == selected:
            out.append(f'<rect x="{left + 2}" y="{y + 2}" width="{cell - 4}" height="{h - 4}" '
                       f'rx="4.5" fill="#3a4150"/>')
        if index:
            out.append(f'<line x1="{left}" y1="{y + 6}" x2="{left}" y2="{y + h - 6}" stroke="#333844"/>')
        ink = "#f2f4f8" if index == selected else "#9aa1ad"
        out.append(centred(int(left + cell / 2), y + h // 2 + 5, text, 12, ink))
    return "".join(out)


def build() -> str:
    hero = "dupefind"
    parts: list[str] = []
    add = parts.append

    add(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
        f'font-family="-apple-system, BlinkMacSystemFont, \'SF Pro Text\', \'Helvetica Neue\', Arial, sans-serif">')

    # ---- defs -------------------------------------------------------------
    add("<defs>")
    add('<linearGradient id="pageBg" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#0d1016"/><stop offset="1" stop-color="#05070b"/></linearGradient>')
    add('<linearGradient id="accent" x1="0" y1="0" x2="1" y2="0">'
        '<stop offset="0" stop-color="#ff9a3d"/><stop offset="1" stop-color="#ff5f6d"/></linearGradient>')
    add('<linearGradient id="lightCard" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#fafafa"/><stop offset="1" stop-color="#e0e0e0"/></linearGradient>')
    add('<linearGradient id="darkCard" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#333333"/><stop offset="1" stop-color="#141414"/></linearGradient>')
    add('<filter id="iconShadow" x="-30%" y="-30%" width="160%" height="160%">'
        '<feDropShadow dx="0" dy="7" stdDeviation="9" flood-color="#000" flood-opacity="0.42"/></filter>')
    add('<filter id="windowShadow" x="-10%" y="-10%" width="120%" height="130%">'
        '<feDropShadow dx="0" dy="26" stdDeviation="30" flood-color="#000" flood-opacity="0.62"/></filter>')

    for name, _, pixels in ICONS:
        add(f'<image id="ic-{name}" href="{blob(name, pixels)}" width="100" height="100"/>')

    add(rounded_clip("heroClipA", 577, 213, 178, 40))
    add(rounded_clip("heroClipB", 877, 213, 178, 40))
    add(rounded_clip("clip32", 700, 482, 32, 7))
    add(rounded_clip("clip16", 756, 490, 16, 3.5))
    for index in range(4):
        add(rounded_clip(f"clipVariant{index}", 682 + index * 72, 570, 52, 11))
        add(rounded_clip(f"clipGallery{index}", 484 + index * 72, 810, 48, 10))
    add("</defs>")

    add(f'<rect width="{W}" height="{H}" fill="url(#pageBg)"/>')

    # ---- window shell -----------------------------------------------------
    wx, wy, ww, wh = WIN
    add(f'<g filter="url(#windowShadow)"><rect x="{wx}" y="{wy}" width="{ww}" height="{wh}" rx="14" fill="#1c1f26"/></g>')
    add(f'<rect x="{wx}" y="{wy}" width="{ww}" height="52" rx="14" fill="#23262e"/>')
    add(f'<rect x="{wx}" y="{wy + 38}" width="{ww}" height="14" fill="#23262e"/>')
    for index, colour in enumerate(["#ff5f57", "#febc2e", "#28c840"]):
        add(f'<circle cx="{84 + index * 20}" cy="86" r="6" fill="{colour}"/>')
    add('<text x="160" y="91" fill="#9aa1ad" font-size="13">IconForge</text>')

    # Settings gear, the app's only toolbar item. Thick ring plus eight stubby
    # teeth: thin radial spokes read as a sun at this size.
    add('<g transform="translate(1140 86)">')
    add('<circle cx="0" cy="0" r="5.4" fill="none" stroke="#9aa1ad" stroke-width="2.4"/>')
    add('<g stroke="#9aa1ad" stroke-width="2.2" stroke-linecap="round">')
    for step in range(8):
        angle = math.radians(step * 45)
        x1, y1 = 6.3 * math.cos(angle), 6.3 * math.sin(angle)
        x2, y2 = 8.5 * math.cos(angle), 8.5 * math.sin(angle)
        add(f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}"/>')
    add("</g>")
    add('<circle cx="0" cy="0" r="2.1" fill="#23262e"/>')
    add("</g>")

    # ---- inspector --------------------------------------------------------
    add(f'<rect x="{wx}" y="112" width="392" height="{wy + wh - 112}" fill="#191c22"/>')
    add(f'<line x1="452" y1="112" x2="452" y2="{wy + wh}" stroke="#2b2f38" stroke-width="1"/>')

    add('<text x="92" y="152" fill="#f2f4f8" font-size="17" font-weight="600">Describe the app</text>')
    add('<text x="92" y="176" fill="#8b929c" font-size="12.5">IconForge writes the prompt, calls your generator,</text>')
    add('<text x="92" y="194" fill="#8b929c" font-size="12.5">and masks the result into a real macOS icon.</text>')

    # The inspector is a single column, so each group is placed against a
    # running cursor rather than hand-computed offsets. GAP is label-top to the
    # previous control's bottom.
    GAP, LABEL_DROP = 25, 10
    y = 222

    def group(text: str, hint: str = "", x: int = FIELD_X) -> int:
        """Emit a field label and return the y the control sits at."""
        add(label(x, y, text, hint))
        return y + LABEL_DROP

    top = group("App name")
    add(field(FIELD_X, top, FIELD_W, 29))
    add(value(104, top + 19, "DupeFind"))
    y = top + 29 + GAP

    top = group("What it does")
    add(field(FIELD_X, top, FIELD_W, 50))
    add(value(104, top + 20, "finds files with identical contents and"))
    add(value(104, top + 39, "clears out the extras"))
    y = top + 50 + GAP

    top = group("Subject", "yours, kept on every roll")
    add(field(FIELD_X, top, FIELD_W, 29))
    add(value(104, top + 19, "a shed snake skin"))
    y = top + 29 + GAP

    top = group("Palette", "optional")
    add(field(FIELD_X, top, FIELD_W, 29))
    swatch = ["#03045E", "#0077B6", "#00B4D8", "#90E0EF", "#CAF0F8"]
    for index, colour in enumerate(swatch):
        add(f'<rect x="{104 + index * 13}" y="{top + 8}" width="13" height="14" fill="{colour}"/>')
    add(f'<rect x="104" y="{top + 8}" width="65" height="14" rx="4" fill="none" stroke="#3a4150"/>')
    add(value(181, top + 20, "Ocean Breeze"))
    add(chevron(404, top + 12))
    y = top + 29 + GAP

    top = group("Style")
    group("Finish", x=252)
    add(field(FIELD_X, top, 150, 28))
    add(value(104, top + 19, "Luxe", 12.5))
    add(chevron(226, top + 11))
    add(field(252, top, 168, 28))
    add(value(264, top + 19, "Apple edge", 12.5))
    add(chevron(404, top + 11))
    y = top + 28 + GAP

    # Generator, which the app draws as a segmented control.
    top = group("Generator", "gemini models, lists its own")
    add(segmented(FIELD_X, top, FIELD_W, ["agy", "codex"], 0))
    y = top + 28 + GAP

    # Model and effort share a row. Effort is dimmed under agy, whose model ids
    # already carry it, which is exactly how the app disables that picker.
    top = group("Model")
    add(field(FIELD_X, top, 196, 28))
    add(value(104, top + 19, "gemini-3.1-pro-high", 12.5))
    add(chevron(272, top + 11))
    add('<g opacity="0.4">')
    add(field(296, top, 76, 28))
    add(value(306, top + 19, "low", 12.5))
    add(chevron(356, top + 11))
    add("</g>")
    add(button(380, top, 30, 28))
    add(f'<path d="M389 {top + 14} a6 6 0 1 1 2 4" stroke="#9aa1ad" stroke-width="1.5" fill="none" stroke-linecap="round"/>')
    add(f'<path d="M388 {top + 8} v5 h5" stroke="#9aa1ad" stroke-width="1.5" fill="none" stroke-linecap="round"/>')
    y = top + 28 + GAP

    top = group("Body size")
    group("Icons per run", x=296)
    add(field(FIELD_X, top, 196, 28))
    add(value(104, top + 19, "Full bleed", 12.5))
    add(chevron(272, top + 11))
    add(segmented(296, top, 124, ["1", "2", "3", "4"], 3))
    y = top + 28 + GAP + 1

    add(f'<rect x="{FIELD_X}" y="{y}" width="{FIELD_W}" height="32" rx="8" fill="url(#accent)"/>')
    add(centred(256, y + 21, "Generate icon", 13.5, "#26140a", "600"))
    y += 42
    for left_text, right_text in [("Reroll", "Export"), ("Reveal", "Clear")]:
        add(button(FIELD_X, y, 158))
        add(centred(171, y + 19, left_text))
        add(button(262, y, 158))
        add(centred(341, y + 19, right_text))
        y += 36

    if y > wy + wh - 8:
        sys.exit(f"inspector overflows the window by {y - (wy + wh - 8)}pt")

    # ---- preview ----------------------------------------------------------
    add(f'<rect x="452" y="112" width="728" height="658" fill="#1b1e25"/>')

    for x, gradient, clip, caption in [(532, "lightCard", "heroClipA", "Light desktop"),
                                       (832, "darkCard", "heroClipB", "Dark desktop")]:
        add(f'<rect x="{x}" y="168" width="268" height="268" rx="18" fill="url(#{gradient})" stroke="#3a3f4a"/>')
        add(f'<g filter="url(#iconShadow)">{use(hero, x + 45, 213, 178, clip)}</g>')
        add(centred(x + 134, 462, caption, 12, "#8b929c"))

    add(use(hero, 700, 482, 32, "clip32"))
    add(centred(716, 528, "32pt", 10, "#8b929c"))
    add(use(hero, 756, 490, 16, "clip16"))
    add(centred(764, 528, "16pt", 10, "#8b929c"))
    add(value(800, 504, "small sizes should still read at a glance", 11.5, "#666d78"))

    # Four at once, with the first one picked.
    add(centred(PANE_MID, 558, "Pick one", 11.5, "#8b929c"))
    for index, (name, caption, _) in enumerate(ICONS):
        x = 682 + index * 72
        if index == 0:
            add(f'<rect x="{x - 7}" y="563" width="66" height="83" rx="9" fill="#2d3644" stroke="#5b8cde" stroke-width="1.5"/>')
        add(use(name, x, 570, 52, f"clipVariant{index}"))
        add(centred(x + 26, 638, caption, 10, "#9aa1ad"))

    # File chips, each with the button that copies its path.
    chips = [("AppIcon.icns", 112), ("icon_1024.png", 118), ("AppIcon.iconset", 128), ("AppIcon.ico", 104)]
    x = 526
    for name, width in chips:
        add(button(x, 652, width, 24))
        add(centred(x + width // 2, 668, name, 11, "#cdd3dc"))
        add(button(x + width + 2, 652, 22, 24))
        # doc-on-doc, the glyph the copy-path button uses
        glyph = x + width + 8
        add(f'<rect x="{glyph + 2}" y="657" width="6.5" height="8.5" rx="1.5" fill="none" stroke="#9aa1ad" stroke-width="1.1"/>')
        add(f'<rect x="{glyph}" y="660" width="6.5" height="8.5" rx="1.5" fill="#252932" stroke="#9aa1ad" stroke-width="1.1"/>')
        x += width + 34

    add(button(PANE_MID - 90, 686, 180, 24))
    add(centred(PANE_MID, 702, "Copy as agent prompt", 11, "#cdd3dc"))

    # Edit bar. The wand holds edit mode on when the bar is empty.
    add(f'<rect x="587" y="720" width="26" height="26" rx="6" fill="#2d3644" stroke="#5b8cde"/>')
    add('<path d="M594 739 l11 -11 M604 725 l1.5 3 l3 1.5 l-3 1.5 l-1.5 3 l-1.5 -3 l-3 -1.5 l3 -1.5 z" '
        'fill="none" stroke="#a9c4ef" stroke-width="1.3" stroke-linejoin="round" stroke-linecap="round"/>')
    add(field(621, 720, 330, 26))
    add(value(633, 737, "optional: also say what to change", 11.5, "#6e7580"))
    add(button(959, 720, 86, 26))
    add(centred(1002, 737, "Edit icon", 11.5))

    # ---- history ----------------------------------------------------------
    add('<line x1="452" y1="770" x2="1180" y2="770" stroke="#2b2f38"/>')
    add(f'<rect x="452" y="770" width="728" height="{wy + wh - 770}" fill="#171a20"/>')
    add(value(484, 796, "Previous rolls", 11.5, "#8b929c"))
    for index, (name, caption, _) in enumerate(ICONS):
        x = 484 + index * 72
        add(use(name, x, 810, 48, f"clipGallery{index}"))
        add(centred(x + 24, 872, caption, 10, "#9aa1ad"))

    add("</svg>")
    return "\n".join(parts) + "\n"


if __name__ == "__main__":
    OUT.write_text(build())
    print(f"wrote {OUT.relative_to(REPO)} ({OUT.stat().st_size // 1024} KB)")
