"""Draws the Locker room "Light colour" tab icon: a glowing bulb in four colours on a purple tile."""
import math
import sys

from PIL import Image, ImageDraw

OUT = sys.argv[1]
S = 4 * 256
NAVY = (32, 38, 56, 255)


def P(x, y):
    return (x * S, y * S)


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle([P(0.03, 0.03), P(0.97, 0.97)], radius=int(0.2 * S), fill=NAVY)
d.rounded_rectangle([P(0.07, 0.07), P(0.93, 0.93)], radius=int(0.17 * S), fill=(150, 90, 220, 255))
# rays in four colours round the bulb
colours = [(255, 90, 90, 255), (255, 210, 70, 255), (90, 220, 130, 255), (110, 190, 255, 255)]
for i in range(8):
    a = -math.pi / 2 + (i - 3.5) * math.pi / 7.5
    x0, y0 = 0.5 + 0.3 * math.cos(a), 0.44 + 0.3 * math.sin(a)
    x1, y1 = 0.5 + 0.4 * math.cos(a), 0.44 + 0.4 * math.sin(a)
    d.line([P(x0, y0), P(x1, y1)], fill=NAVY, width=int(0.075 * S))
    d.line([P(x0, y0), P(x1, y1)], fill=colours[i % 4], width=int(0.04 * S))
# the bulb: a round glass split in four colours, then a base
r = 0.22
box = [P(0.5 - r, 0.44 - r), P(0.5 + r, 0.44 + r)]
d.ellipse([P(0.5 - r - 0.025, 0.44 - r - 0.025), P(0.5 + r + 0.025, 0.44 + r + 0.025)], fill=NAVY)
for i, c in enumerate(colours):
    d.pieslice(box, start=i * 90 - 135, end=i * 90 - 45, fill=c)
d.ellipse([P(0.39, 0.30), P(0.47, 0.38)], fill=(255, 255, 255, 220))
d.rounded_rectangle([P(0.38, 0.66), P(0.62, 0.84)], radius=int(0.04 * S), fill=NAVY)
d.rounded_rectangle([P(0.41, 0.68), P(0.59, 0.73)], radius=int(0.02 * S), fill=(205, 210, 222, 255))
d.rounded_rectangle([P(0.41, 0.76), P(0.59, 0.81)], radius=int(0.02 * S), fill=(205, 210, 222, 255))
img.resize((256, 256), Image.LANCZOS).save(OUT)
print("ok")
