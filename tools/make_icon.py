#!/usr/bin/env python3
"""Generate the EnTimeCode app icon: a video camera whose lens is a clock face."""
import math
from PIL import Image, ImageDraw

S = 1024
SS = 4                      # supersample factor
W = S * SS
img = Image.new("RGB", (W, W), (0, 0, 0))
d = ImageDraw.Draw(img)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


# --- Background: vertical gradient filling the whole square ---
# App Store icons must be opaque with no alpha and no transparent corners;
# iOS applies the rounded-rectangle mask itself.
top = (37, 99, 235)        # blue
bot = (14, 165, 165)       # teal
for y in range(W):
    t = y / W
    d.line([(0, y), (W, y)], fill=lerp(top, bot, t))

# Foreground drawn on a transparent overlay so soft shadows/edges blend correctly,
# then composited onto the opaque background and flattened to RGB at the end.
overlay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(overlay)


def px(v):
    return int(v * SS)


# --- Camera body ---
body_l, body_t, body_r, body_b = px(150), px(330), px(720), px(710)
body_color = (245, 247, 250, 255)
shadow = (0, 0, 0, 60)
d.rounded_rectangle([body_l + px(10), body_t + px(16), body_r + px(10), body_b + px(16)],
                    radius=px(70), fill=shadow)              # soft drop shadow
d.rounded_rectangle([body_l, body_t, body_r, body_b], radius=px(70), fill=body_color)

# --- Viewfinder bump on top of the body ---
vf_l, vf_t, vf_r, vf_b = px(250), px(250), px(470), px(345)
d.rounded_rectangle([vf_l, vf_t, vf_r, vf_b], radius=px(34), fill=body_color)

# --- Lens / record snout on the right (a tapered nozzle) ---
lens_cx, lens_cy = px(560), px(520)
snout = [(px(690), px(440)), (px(880), px(385)),
         (px(880), px(655)), (px(690), px(600))]
d.polygon(snout, fill=body_color)
d.ellipse([px(840), px(385), px(920), px(655)], fill=(210, 220, 232, 255))

# --- Clock face (the main lens) ---
face_r = px(155)
ring_outer = (90, 110, 140, 255)
face_bg = (250, 252, 255, 255)
d.ellipse([lens_cx - face_r - px(20), lens_cy - face_r - px(20),
           lens_cx + face_r + px(20), lens_cy + face_r + px(20)], fill=ring_outer)
d.ellipse([lens_cx - face_r, lens_cy - face_r,
           lens_cx + face_r, lens_cy + face_r], fill=face_bg)

# Hour ticks.
tick_col = (45, 60, 90, 255)
for i in range(12):
    ang = math.radians(i * 30 - 90)
    r1 = face_r - px(26)
    r2 = face_r - (px(50) if i % 3 == 0 else px(40))
    wdt = px(12) if i % 3 == 0 else px(7)
    x1 = lens_cx + r1 * math.cos(ang)
    y1 = lens_cy + r1 * math.sin(ang)
    x2 = lens_cx + r2 * math.cos(ang)
    y2 = lens_cy + r2 * math.sin(ang)
    d.line([(x1, y1), (x2, y2)], fill=tick_col, width=wdt)

# Clock hands (pointing to ~10:08, a classic pleasant pose).
hand_col = (37, 99, 235, 255)


def hand(angle_deg, length, width, color):
    ang = math.radians(angle_deg - 90)
    x = lens_cx + length * math.cos(ang)
    y = lens_cy + length * math.sin(ang)
    d.line([(lens_cx, lens_cy), (x, y)], fill=color, width=width)


hand(300, face_r - px(70), px(20), hand_col)     # hour hand (~10)
hand(48, face_r - px(40), px(14), hand_col)      # minute hand (~:08)
d.ellipse([lens_cx - px(18), lens_cy - px(18),
           lens_cx + px(18), lens_cy + px(18)], fill=hand_col)

# --- Record dot on the viewfinder bump ---
rec_c = (px(300), px(297))
d.ellipse([rec_c[0] - px(22), rec_c[1] - px(22),
           rec_c[0] + px(22), rec_c[1] + px(22)], fill=(235, 72, 72, 255))

# --- Composite overlay onto opaque background, then downsample and flatten to RGB ---
composed = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
out = composed.resize((S, S), Image.LANCZOS)
out.save("EnTimeCode/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
print("wrote icon-1024.png (opaque RGB, no alpha)")
