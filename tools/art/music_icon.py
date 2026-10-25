"""Draws the MUSIC dock tile: two beamed notes on a pink tile, like the other dock tiles (a navy
outline, a darker slab under the face, a lighter rim). With "off" it adds a red slash for muted.

    python tools/art/music_icon.py out.png [off]
"""
import sys

from PIL import Image, ImageDraw

OUT = sys.argv[1]
MUTED = len(sys.argv) > 2 and sys.argv[2] == "off"
S = 4 * 256
NAVY = (32, 38, 56, 255)
FACE = (240, 96, 168, 255)
SLAB = (184, 56, 124, 255)
RIM = (255, 150, 200, 255)
WHITE = (255, 255, 255, 255)
GOLD = (255, 205, 60, 255)
RED = (232, 64, 96, 255)


def P(x, y):
    return (x * S, y * S)


def W(w):
    return int(w * S)


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# The button: navy outline, the darker slab at the bottom, then the face with its lighter rim.
d.rounded_rectangle([P(0.03, 0.03), P(0.97, 0.97)], radius=W(0.2), fill=NAVY)
d.rounded_rectangle([P(0.07, 0.07), P(0.93, 0.93)], radius=W(0.17), fill=SLAB)
d.rounded_rectangle([P(0.07, 0.07), P(0.93, 0.83)], radius=W(0.17), fill=RIM)
d.rounded_rectangle([P(0.1, 0.1), P(0.9, 0.8)], radius=W(0.14), fill=FACE)


def note_shapes(draw, fill, grow):
    """The two beamed notes; `grow` widens every shape for the outline pass."""
    # the heads, tilted ovals drawn as ellipses
    for cx, cy in ((0.29, 0.63), (0.55, 0.57)):
        draw.ellipse([P(cx - 0.1 - grow, cy - 0.075 - grow), P(cx + 0.1 + grow, cy + 0.075 + grow)], fill=fill)
    # the stems
    draw.rectangle([P(0.355 - grow, 0.27 - grow), P(0.395 + grow, 0.63 + grow)], fill=fill)
    draw.rectangle([P(0.615 - grow, 0.21 - grow), P(0.655 + grow, 0.57 + grow)], fill=fill)
    # the beam joining the stems
    draw.polygon(
        [
            P(0.355 - grow, 0.27 - grow),
            P(0.655 + grow, 0.21 - grow),
            P(0.655 + grow, 0.31 + grow),
            P(0.355 - grow, 0.37 + grow),
        ],
        fill=fill,
    )


note_shapes(d, NAVY, 0.03)
note_shapes(d, WHITE, 0.0)

# Two small sound arcs on the right, gold like the bell of the ALERTS tile.
if not MUTED:
    for r in (0.07, 0.13):
        box = [P(0.7 - r, 0.4 - r), P(0.7 + r, 0.4 + r)]
        d.arc(box, start=-50, end=50, fill=NAVY, width=W(0.06))
        d.arc(box, start=-48, end=48, fill=GOLD, width=W(0.03))
else:
    # The red slash across the notes, navy-outlined like the red X of the panels.
    d.line([P(0.2, 0.22), P(0.8, 0.72)], fill=NAVY, width=W(0.12))
    d.line([P(0.2, 0.22), P(0.8, 0.72)], fill=RED, width=W(0.065))

img.resize((256, 256), Image.LANCZOS).save(OUT)
