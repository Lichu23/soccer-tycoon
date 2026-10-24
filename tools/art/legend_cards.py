"""Builds the Legend product icons: the card design (white, gold rays, LEGEND chip, gold frame, name
band) from the drawn SVGs, with the drawn player replaced by the real in-game figure.

Renders: tools/art/legend_renders/<id>.jpg, a Studio playtest screenshot of the player's Mannequin
in a ViewportFrame on flat magenta (#FF00FF; green would cut out Brazil's trim), framed like the
chest roulette tiles.

Usage, from the project root:
    python tools/art/legend_cards.py "<folder with legend_<card>.svg>" [id ...]

Writes, for each Legend, square 512x512 PNGs into tools/art/products:
    legend_<id>.png          with the name band (the Developer Product icon)
    legend_<id>_nolabel.png  without it (the Shop card, which shows the name above the picture)
"""

import base64
import io
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RENDERS = ROOT / "tools" / "art" / "legend_renders"
OUT = ROOT / "tools" / "art" / "products"
CHROME = Path("C:/Program Files/Google/Chrome/Application/chrome.exe")

SIZE = 512
BAND_TOP = 400  # the name band: 112px tall at the foot, as in the drawn 512x680 card
# Every render has the same camera, so one scale and place keeps the five bodies the same size
# (scaling each to its outline would shrink the players with big hair).
SCALE = 0.65  # render pixels -> card pixels
HEAD_TOP = 190  # the top of a bald head in the render
CENTRE_X = 767.5  # the figure's middle in the render
HEAD_Y_LABEL = 124  # where that head top sits on the card: hair stays under the LEGEND chip
HEAD_Y_NOLABEL = 164  # lower without the band, so the render's cut edge is below the card

# The Legend id -> the drawn card's file name.
CARDS = {
    "maradona": "legend_maradona",
    "pele": "legend_pele",
    "ronaldinho": "legend_ronaldinho",
    "ronaldo_nazario": "legend_ronaldo",
    "zidane": "legend_zidane",
}


def cut_out(path: Path) -> Image.Image:
    """The figure on transparency: magenta goes, edges lose its tint."""
    image = Image.open(path).convert("RGB")
    out = Image.new("RGBA", image.size)
    src = image.load()
    dst = out.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b = src[x, y]
            key = min(r, b) - g  # how much more magenta than the figure this pixel is
            alpha = 255 if key < 40 else 0 if key > 140 else int(255 * (140 - key) / 100)
            if alpha < 255:
                spill = max(0, key)  # an edge pixel loses the magenta it picked up
                r, b = r - spill, b - spill
            dst[x, y] = (r, g, b, alpha)
    return out


def data_uri(image: Image.Image) -> str:
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode()


def card_svg(source: str, figure: Image.Image, label: bool) -> str:
    lines = source.splitlines()
    defs = "\n".join(lines[1:8])  # <defs> ... </defs>
    rays, glow = lines[9], lines[10]
    # The name is the last white text (a drawn shirt number before it can be white too).
    name = re.findall(r'<text[^>]*fill="#FFFFFF">[^<]*</text>', source)[-1]
    chip = "\n".join(line for line in lines if "LEGEND" in line or 'x="156.0"' in line or 'x="161.5"' in line)

    width, height = figure.width * SCALE, figure.height * SCALE
    left = SIZE / 2 - CENTRE_X * SCALE
    top = (HEAD_Y_LABEL if label else HEAD_Y_NOLABEL) - HEAD_TOP * SCALE
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">',
        defs,
        f'<rect width="{SIZE}" height="{SIZE}" fill="url(#bg)"/>',
        f'<g transform="translate(0,-40)">{rays}{glow}</g>',
        f'<image href="{data_uri(figure)}" x="{left:.1f}" y="{top:.1f}" width="{width:.1f}" height="{height:.1f}"/>',
    ]
    if label:
        y = float(re.search(r' y="([\d.]+)"', name).group(1)) - 568 + BAND_TOP
        parts.append(f'<rect x="0" y="{BAND_TOP}" width="{SIZE}" height="{SIZE - BAND_TOP}" fill="#202638"/>')
        parts.append(re.sub(r' y="[\d.]+"', f' y="{y:.1f}"', name, count=1))
    parts.append(chip)
    parts.append(f'<rect x="12" y="12" width="{SIZE - 24}" height="{SIZE - 24}" rx="22" fill="none" stroke="#E3B23C" stroke-width="6"/>')
    parts.append("</svg>")
    return "\n".join(parts)


def to_png(svg: str, target: Path):
    html = (
        '<!doctype html><html><head><meta charset="utf-8">'
        '<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@700&display=block" rel="stylesheet">'
        "<style>html,body{margin:0;overflow:hidden;background:transparent}svg{display:block}</style>"
        f"</head><body>{svg}</body></html>"
    )
    with tempfile.TemporaryDirectory() as folder:
        page = Path(folder) / "card.html"
        page.write_text(html, encoding="utf-8")
        shot = Path(folder) / "card.png"
        subprocess.run(
            [
                str(CHROME),
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                f"--window-size={SIZE},{SIZE}",
                "--virtual-time-budget=6000",
                "--default-background-color=00000000",
                f"--screenshot={shot}",
                page.as_uri(),
            ],
            check=True,
            capture_output=True,
        )
        Image.open(shot).convert("RGB").crop((0, 0, SIZE, SIZE)).save(target)


def main():
    cards = Path(sys.argv[1])
    ids = sys.argv[2:] or list(CARDS)
    for legend in ids:
        source = (cards / f"{CARDS[legend]}.svg").read_text(encoding="utf-8")
        figure = cut_out(RENDERS / f"{legend}.jpg")
        to_png(card_svg(source, figure, True), OUT / f"legend_{legend}.png")
        to_png(card_svg(source, figure, False), OUT / f"legend_{legend}_nolabel.png")
        print("wrote", legend)


if __name__ == "__main__":
    main()
