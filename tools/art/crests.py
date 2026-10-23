"""Draws the Locker room crest images: flat cartoon shields, 512x512 with a transparent background."""
import math
import os
import sys

from PIL import Image, ImageDraw

OUT = sys.argv[1]
S = 4 * 512  # drawn big, then shrunk for smooth edges
NAVY = (32, 38, 56, 255)
WHITE = (245, 245, 248, 255)
GOLD = (255, 205, 60, 255)


def P(x, y):
    return (x * S, y * S)


def shield_points(inset=0.0):
    pts = []
    top, left, right = 0.08 + inset, 0.12 + inset, 0.88 - inset
    # top edge with a soft dip in the middle
    for i in range(21):
        t = i / 20
        x = left + (right - left) * t
        y = top + 0.035 * math.sin(math.pi * t)
        pts.append(P(x, y))
    # right side straight, then a curve to the point
    pts.append(P(right, 0.50))
    bottom = 0.94 - inset * 1.4
    for i in range(1, 21):
        t = i / 20
        x = right + (0.5 - right) * t
        y = 0.50 + (bottom - 0.50) * math.sin(t * math.pi / 2)
        pts.append(P(x, y))
    for i in range(1, 21):
        t = i / 20
        x = 0.5 + (left - 0.5) * t
        y = bottom - (bottom - 0.50) * (1 - math.cos(t * math.pi / 2))
        pts.append(P(x, y))
    pts.append(P(left, 0.50))
    return pts


def star(d, cx, cy, r, fill, outline=NAVY, width=0.022):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append(P(cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill, outline=outline, width=int(width * S))


def gem(d, cx, cy, w, h, fill, light):
    top = [P(cx - w * 0.35, cy - h * 0.5), P(cx + w * 0.35, cy - h * 0.5), P(cx + w * 0.5, cy - h * 0.2),
           P(cx, cy + h * 0.5), P(cx - w * 0.5, cy - h * 0.2)]
    d.polygon(top, fill=fill, outline=NAVY, width=int(0.022 * S))
    d.polygon([P(cx - w * 0.35, cy - h * 0.5), P(cx - w * 0.05, cy - h * 0.5), P(cx - w * 0.2, cy - h * 0.2),
               P(cx - w * 0.5, cy - h * 0.2)], fill=light)
    d.line([P(cx - w * 0.5, cy - h * 0.2), P(cx + w * 0.5, cy - h * 0.2)], fill=NAVY, width=int(0.016 * S))


def crown(d, cx, cy, w, h, fill):
    pts = [P(cx - w / 2, cy + h / 2), P(cx - w / 2, cy - h * 0.25), P(cx - w * 0.25, cy + h * 0.05),
           P(cx, cy - h / 2), P(cx + w * 0.25, cy + h * 0.05), P(cx + w / 2, cy - h * 0.25),
           P(cx + w / 2, cy + h / 2)]
    d.polygon(pts, fill=fill, outline=NAVY, width=int(0.022 * S))
    for x in (cx - w / 2, cx, cx + w / 2):
        y = cy - h * 0.25 if x != cx else cy - h / 2
        r = 0.035
        d.ellipse([P(x - r, y - r), P(x + r, y + r)], fill=WHITE, outline=NAVY, width=int(0.016 * S))
    d.rectangle([P(cx - w / 2, cy + h * 0.28), P(cx + w / 2, cy + h / 2)], fill=WHITE, outline=NAVY,
                width=int(0.016 * S))


def flame(d, cx, cy, h, outer, inner):
    # a flame with three tongues: points in units of h round (cx, cy), bottom round
    base = [(0.0, 0.5), (-0.3, 0.42), (-0.42, 0.18), (-0.38, -0.08), (-0.26, -0.24), (-0.22, -0.02),
            (-0.12, -0.28), (-0.02, -0.52), (0.08, -0.26), (0.16, -0.36), (0.3, -0.12), (0.4, 0.1),
            (0.36, 0.36), (0.22, 0.47)]
    def shape(scale, dy, fill):
        pts = [P(cx + x * h * 2 * scale, cy + dy + y * h * 2 * scale) for x, y in base]
        d.polygon(pts, fill=fill, outline=NAVY, width=int(0.022 * S))
    shape(1.0, 0, outer)
    shape(0.5, h * 0.42, inner)


def ball(d, cx, cy, r):
    d.ellipse([P(cx - r, cy - r), P(cx + r, cy + r)], fill=WHITE, outline=NAVY, width=int(0.024 * S))
    pent = []
    for i in range(5):
        a = -math.pi / 2 + i * 2 * math.pi / 5
        pent.append(P(cx + r * 0.36 * math.cos(a), cy + r * 0.36 * math.sin(a)))
    d.polygon(pent, fill=NAVY)
    for i in range(5):
        a = -math.pi / 2 + i * 2 * math.pi / 5
        x0, y0 = cx + r * 0.36 * math.cos(a), cy + r * 0.36 * math.sin(a)
        x1, y1 = cx + r * 0.92 * math.cos(a), cy + r * 0.92 * math.sin(a)
        d.line([P(x0, y0), P(x1, y1)], fill=NAVY, width=int(0.018 * S))
        d.ellipse([P(x1 - r * 0.16, y1 - r * 0.16), P(x1 + r * 0.16, y1 + r * 0.16)], fill=NAVY)


def crest(name, body, band, emblem):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon(shield_points(), fill=NAVY)  # the thick dark outline
    d.polygon(shield_points(0.035), fill=body)
    if band:
        # a chevron band across the shield
        inner = Image.new("L", (S, S), 0)
        ImageDraw.Draw(inner).polygon(shield_points(0.035), fill=255)
        stripe = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        sd = ImageDraw.Draw(stripe)
        sd.polygon([P(0, 0.30), P(0.5, 0.58), P(1, 0.30), P(1, 0.44), P(0.5, 0.72), P(0, 0.44)], fill=band)
        img.paste(stripe, (0, 0), Image.composite(stripe, Image.new("RGBA", (S, S)), inner).split()[3])
    # a light shine on the left half
    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shine).polygon(shield_points(0.06)[:21] + [P(0.5, 0.08), P(0.5, 0.90), P(0.18, 0.55)],
                                  fill=(255, 255, 255, 0))
    emblem(d)
    img = img.resize((512, 512), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"))


crest("crest_shield", (205, 210, 225, 255), (60, 120, 230, 255),
      lambda d: star(d, 0.5, 0.40, 0.17, WHITE))
crest("crest_star", (255, 210, 70, 255), None, lambda d: star(d, 0.5, 0.47, 0.26, WHITE))
crest("crest_ball", (60, 120, 230, 255), None, lambda d: ball(d, 0.5, 0.47, 0.22))
crest("crest_ruby", (210, 50, 70, 255), None,
      lambda d: gem(d, 0.5, 0.46, 0.42, 0.34, (240, 90, 110, 255), (255, 170, 180, 255)))
crest("crest_emerald", (40, 160, 95, 255), None,
      lambda d: gem(d, 0.5, 0.46, 0.42, 0.34, (90, 220, 140, 255), (190, 255, 210, 255)))
crest("crest_crown", (150, 90, 220, 255), None, lambda d: crown(d, 0.5, 0.46, 0.46, 0.32, GOLD))
crest("crest_flame", (40, 44, 70, 255), (240, 100, 40, 255),
      lambda d: flame(d, 0.5, 0.42, 0.24, (245, 110, 40, 255), (255, 210, 70, 255)))
print("ok")
