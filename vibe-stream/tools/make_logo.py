"""Generates the Vibe Stream brand images (own artwork, replaces the IPVIO logo files)."""
import sys, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

RES = sys.argv[1]            # .../app/src/main/res
FONT = RES + "/font/outfit_bold.ttf"
BG = (14, 11, 31)            # deep indigo
C1 = (124, 77, 255)          # violet
C2 = (255, 64, 129)          # pink
C3 = (255, 171, 64)          # amber

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
def grad_color(t):
    return lerp(C1, C2, t * 2) if t < 0.5 else lerp(C2, C3, (t - 0.5) * 2)

def gradient(size):
    w, h = size
    g = Image.new("RGB", (w, h))
    px = g.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = grad_color(min(1.0, max(0.0, (x / w * 0.65 + y / h * 0.35))))
    return g

def mark(size):
    """Rounded play triangle with three 'vibe' bars cut out on the left; RGBA, transparent background."""
    S = 4
    n = size * S
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    r = n * 0.085
    # triangle (rounded by drawing a thick outline with round joins)
    a = (n * 0.30, n * 0.16); b = (n * 0.30, n * 0.84); c = (n * 0.86, n * 0.50)
    d.polygon([a, b, c], fill=255)
    d.line([a, b, c, a], fill=255, width=int(r * 2), joint="curve")
    for p in (a, b, c): d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)
    # three bars left of the triangle
    bw = n * 0.055
    for i, hgt in enumerate((0.30, 0.50, 0.38)):
        x = n * (0.055 + i * 0.0) + i * bw * 0.0
    xs = [n * 0.045, n * 0.125]
    hs = [0.26, 0.44]
    for x, hgt in zip(xs, hs):
        y0 = n * (0.5 - hgt / 2); y1 = n * (0.5 + hgt / 2)
        d.rounded_rectangle([x, y0, x + bw, y1], radius=bw / 2, fill=255)
    g = gradient((n, n)).convert("RGBA")
    g.putalpha(m)
    return g.resize((size, size), Image.LANCZOS)

def on_bg(size, scale, radius=0.0, circle=False):
    """Mark centered on the background colour; optional rounded square or circle shape (RGBA)."""
    S = 4
    n = size * S
    base = Image.new("RGBA", (n, n), BG + (255,))
    mk = mark(int(n * scale))
    base.alpha_composite(mk, ((n - mk.width) // 2 + int(n * 0.015), (n - mk.height) // 2))
    mask = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask)
    if circle: d.ellipse([0, 0, n - 1, n - 1], fill=255)
    elif radius > 0: d.rounded_rectangle([0, 0, n - 1, n - 1], radius=n * radius, fill=255)
    else: d.rectangle([0, 0, n, n], fill=255)
    base.putalpha(mask)
    return base.resize((size, size), Image.LANCZOS)

# In-app mark
mark(256).save(RES + "/drawable/ic_brand_mark.png")
# Adaptive icon foreground: 108dp canvas, mark inside the 66dp safe zone, transparent around it
fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
mk = mark(210)
fg.alpha_composite(mk, ((432 - 210) // 2 + 6, (432 - 210) // 2))
fg.save(RES + "/drawable/ic_logo_fg.png")
# Legacy launcher icons
for dens, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
    on_bg(px, 0.62, radius=0.22).save(f"{RES}/mipmap-{dens}/ic_launcher.webp", lossless=True)
    on_bg(px, 0.58, circle=True).save(f"{RES}/mipmap-{dens}/ic_launcher_round.webp", lossless=True)
# TV banner 640x360: mark + name
W, H = 640, 360
ban = Image.new("RGBA", (W, H), BG + (255,))
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([-120, -160, 260, 160], fill=C1 + (70,))
gd.ellipse([420, 220, 760, 520], fill=C2 + (60,))
ban.alpha_composite(glow.filter(ImageFilter.GaussianBlur(70)))
mk = mark(150)
ban.alpha_composite(mk, (70, (H - 150) // 2))
d = ImageDraw.Draw(ban)
f1 = ImageFont.truetype(FONT, 92)
f2 = ImageFont.truetype(FONT, 40)
d.text((250, 108), "VIBE", font=f1, fill=(255, 255, 255))
d.text((254, 208), "STREAM", font=f2, fill=(196, 188, 230))
ban.convert("RGB").save(RES + "/drawable/banner.png")
print("ok")
