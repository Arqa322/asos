#!/usr/bin/env python3
"""Generate the original Huilo wallpapers (procedural, deterministic).

  python3 scripts/make-wallpapers.py [--out DIR] [--size 3840x2160] [--only NAME]

All images are made from scratch here — noise, curves and particles in the
Catppuccin Mocha palette used across Huilo — so they can be shipped freely.
Outputs JPEG wallpapers, 480x270 thumbnails (wallpaper picker) and the
640x480 syslinux boot menu background. Needs numpy and Pillow.
"""
import argparse
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "archiso", "airootfs", "usr", "share", "backgrounds", "huilo")
SPLASH = os.path.join(ROOT, "archiso", "syslinux", "splash.png")
PHOTO = os.path.join(ROOT, "assets", "huilo-photo.jpg")      # the project photo (boot splash, wallpaper #1)
PLYMOUTH = os.path.join(ROOT, "archiso", "airootfs", "usr", "share", "plymouth", "themes", "huilo")

C = {  # Catppuccin Mocha
    "crust": "#11111b", "mantle": "#181825", "base": "#1e1e2e", "surface0": "#313244",
    "surface1": "#45475a", "overlay0": "#6c7086", "lavender": "#b4befe", "blue": "#89b4fa",
    "sapphire": "#74c7ec", "sky": "#89dceb", "teal": "#94e2d5", "green": "#a6e3a1",
    "yellow": "#f9e2af", "peach": "#fab387", "maroon": "#eba0ac", "red": "#f38ba8",
    "mauve": "#cba6f7", "pink": "#f5c2e7", "flamingo": "#f2cdcd", "rosewater": "#f5e0dc",
    "text": "#cdd6f4",
}


def rgb(name):
    h = C.get(name, name).lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def gradient_map(t, stops):
    """t in [0,1] (any shape) -> RGB using [(pos, color), ...]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        m = (t >= p0) & (t <= p1)
        if not m.any():
            continue
        k = ((t[m] - p0) / max(p1 - p0, 1e-6))[..., None]
        out[m] = lerp(rgb(c0), rgb(c1), k)
    return out


# ------------------------------------------------------------------ noise ---
def perlin(shape, res, rng):
    """2D Perlin noise, shape (h, w), res = number of periods (ry, rx)."""
    h, w = shape
    ry, rx = res
    angles = rng.uniform(0, 2 * np.pi, (ry + 1, rx + 1)).astype(np.float32)
    g = np.stack([np.cos(angles), np.sin(angles)], -1)
    ys = np.linspace(0, ry, h, endpoint=False, dtype=np.float32)
    xs = np.linspace(0, rx, w, endpoint=False, dtype=np.float32)
    yi, xi = ys.astype(int), xs.astype(int)
    yf, xf = ys - yi, xs - xi
    Y, X = np.meshgrid(yf, xf, indexing="ij")
    YI, XI = np.meshgrid(yi, xi, indexing="ij")

    def dot(oy, ox):
        gg = g[YI + oy, XI + ox]
        return gg[..., 0] * (X - ox) + gg[..., 1] * (Y - oy)

    fade = lambda t: t * t * t * (t * (t * 6 - 15) + 10)
    u, v = fade(X), fade(Y)
    n0 = lerp(dot(0, 0), dot(0, 1), u)
    n1 = lerp(dot(1, 0), dot(1, 1), u)
    return lerp(n0, n1, v) * 1.41421


def fbm(shape, res, rng, octaves=5, gain=0.5):
    total = np.zeros(shape, np.float32)
    amp, norm = 1.0, 0.0
    ry, rx = res
    for _ in range(octaves):
        total += amp * perlin(shape, (ry, rx), rng)
        norm += amp
        amp *= gain
        ry, rx = ry * 2, rx * 2
    return total / norm


def fbm1d(n, periods, rng, octaves=6, gain=0.5):
    x = np.linspace(0, 1, n, dtype=np.float32)
    out = np.zeros(n, np.float32)
    amp, f = 1.0, periods
    for _ in range(octaves):
        knots = rng.uniform(-1, 1, int(f) + 3).astype(np.float32)
        xp = np.linspace(0, 1, len(knots))
        # smooth (cosine) interpolation between random knots
        pos = x * (len(knots) - 1)
        i = np.minimum(pos.astype(int), len(knots) - 2)
        t = pos - i
        t = (1 - np.cos(t * np.pi)) / 2
        out += amp * lerp(knots[i], knots[i + 1], t)
        amp *= gain
        f *= 2.1
    return out


def stars(img, rng, count, ymax=1.0, big=0.02):
    h, w, _ = img.shape
    layer = np.zeros((h, w), np.float32)
    n = int(count)
    ys = (rng.random(n) ** 1.6 * ymax * h).astype(int)
    xs = rng.integers(0, w, n)
    b = rng.random(n) ** 3
    layer[np.clip(ys, 0, h - 1), xs] = 0.35 + 0.65 * b
    glow = np.asarray(Image.fromarray((layer * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2)), np.float32) / 255
    nb = int(n * big)
    for _ in range(nb):  # a few bright stars with halo
        y, x = rng.integers(0, int(h * ymax)), rng.integers(0, w)
        r = rng.uniform(1.5, 3.2)
        yy, xx = np.ogrid[max(0, y - 40):min(h, y + 40), max(0, x - 40):min(w, x + 40)]
        d = np.sqrt((yy - y) ** 2 + (xx - x) ** 2)
        layer[max(0, y - 40):min(h, y + 40), max(0, x - 40):min(w, x + 40)] += np.exp(-(d / r) ** 2) + 0.15 * np.exp(-d / (r * 6))
    tint = lerp(rgb("lavender"), rgb("rosewater"), 0.5)
    return img + (np.clip(layer, 0, 1.6)[..., None] + glow[..., None] * 1.5) * tint


def finish(img, rng, grain=1.2):
    """dither (avoids banding in gradients) and convert to an image."""
    img = img + rng.normal(0, grain / 255.0, img.shape).astype(np.float32)
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def vgradient(h, w, stops):
    t = np.linspace(0, 1, h, dtype=np.float32)
    col = gradient_map(t, stops)
    return np.repeat(col[:, None, :], w, axis=1)


# ------------------------------------------------------------ wallpapers ---
def peaks(w, h, rng):
    """Night mountains: ridged peaks in layered mist, glowing horizon, moon, stars."""
    img = vgradient(h, w, [(0, "crust"), (0.30, "#141322"), (0.52, "#2a2541"), (0.64, "#5a4566"), (0.70, "#7a5a6e"), (1, "#7a5a6e")])
    img = stars(img, rng, w * h / 2400, ymax=0.55)
    Y, X = np.ogrid[:h, :w]
    mx, my, mr = w * 0.70, h * 0.22, h * 0.042
    d = np.sqrt((X - mx) ** 2 + (Y - my) ** 2)
    img += (np.exp(-(d / (mr * 6)) ** 2) * 0.16 + np.exp(-(d / (mr * 1.8)) ** 2) * 0.10)[..., None] * rgb("lavender")
    craters = fbm((int(mr * 2) + 2, int(mr * 2) + 2), (3, 3), rng, octaves=3)
    disc = (d < mr)
    cy0, cx0 = int(my - mr), int(mx - mr)
    moon = lerp(rgb("rosewater"), rgb("text"), 0.5) * np.ones((h, w, 1), np.float32)
    sub = moon[cy0:cy0 + craters.shape[0], cx0:cx0 + craters.shape[1]]
    sub *= (0.93 + 0.07 * craters[: sub.shape[0], : sub.shape[1]])[..., None]
    edge = smoothstep(mr, mr - 1.5, d)
    img = lerp(img, moon, (edge * disc)[..., None])
    hy = np.arange(h, dtype=np.float32)[:, None]
    img += (np.exp(-((hy - h * 0.62) / (h * 0.09)) ** 2) * 0.20)[..., None] * rgb("peach") * np.ones((1, w, 1))
    layers = [  # base, height, periods, top colour, bottom colour, mist
        (0.50, 0.16, 1.6, "#7d6a93", "#5c4f78", 0.9),
        (0.56, 0.18, 2.2, "#5d5280", "#3d3760", 0.7),
        (0.64, 0.17, 2.8, "#3f3a63", "#28264a", 0.55),
        (0.74, 0.15, 3.4, "#262443", "#17162b", 0.35),
        (0.86, 0.12, 4.2, "#14131f", "#0b0b12", 0.0),
    ]
    for base, amp, periods, ctop, cbot, mist in layers:
        n = fbm1d(w, periods, rng, octaves=7, gain=0.55)
        ridged = 1 - np.abs(n)                      # sharp crests
        ridged = (ridged - ridged.min()) / (np.ptp(ridged) + 1e-6)
        top = (base - amp * ridged ** 2.2) * h
        dist = hy - top[None, :]
        mask = smoothstep(-1.0, 1.0, dist)
        # shading and mist follow a heavily smoothed crest line, so spiky crests
        # do not drag the gradient up and down column by column (vertical stripes)
        k = max(5, w // 12)
        pad = np.pad(top, k, mode="edge")
        smooth_top = np.convolve(pad, np.ones(k) / k, mode="same")[k:-k]
        dist_s = hy - smooth_top[None, :]
        t = smoothstep(-h * 0.05, h * 0.35, dist_s)[..., None]
        body = lerp(rgb(ctop), rgb(cbot), t)
        # moonlight from the upper right: a smooth horizontal ramp, no per-column noise
        ramp = (0.90 + 0.16 * np.linspace(0, 1, w, dtype=np.float32))[None, :, None]
        body = body * ramp
        img = lerp(img, body, mask[..., None])
        img += (np.exp(-(dist / 1.3) ** 2) * 0.07)[..., None] * rgb("lavender")
        if mist:
            fogk = (np.exp(-((dist_s - h * 0.10) / (h * 0.07)) ** 2) * 0.35 * mist)[..., None]
            img = lerp(img, rgb("#4a3f63") * np.ones_like(img), fogk * mask[..., None])
    return img * vignette(h, w, 0.35)[..., None]

def aurora(w, h, rng):
    """Aurora curtains over dark hills and a lake reflection."""
    horizon = int(h * 0.68)
    img = vgradient(h, w, [(0, "crust"), (0.5, "#151525"), (0.68, "#1f2236"), (1, "crust")])
    img = stars(img, rng, w * h / 3200, ymax=0.6)
    sky_h = horizon
    yy = np.arange(sky_h, dtype=np.float32)[:, None]
    acc = np.zeros((sky_h, w, 3), np.float32)
    for k, (cy, spread, c0, c1, strength) in enumerate([
        (0.40, 0.11, "teal", "blue", 1.0),
        (0.30, 0.09, "green", "mauve", 0.65),
        (0.50, 0.06, "sapphire", "pink", 0.4),
    ]):
        line = (cy + 0.13 * fbm1d(w, 1.3, rng, octaves=5)) * h
        rays = fbm((sky_h, w), (2, 60), rng, octaves=3, gain=0.55)  # vertical streaks
        rays = 0.45 + 0.55 * smoothstep(-0.2, 0.7, rays)
        above = line[None, :] - yy                              # >0 above the band edge
        below = np.exp(-np.clip(-above, 0, None) / (h * 0.012))  # sharp lower edge
        up = np.exp(-np.clip(above, 0, None) / (h * spread))     # long fade upwards
        inten = below * up * (0.25 + 0.75 * rays) * strength * (1 - 0.6 * smoothstep(0, h * 0.3, above))
        t = np.clip(above / (h * spread * 1.6), 0, 1)
        col = lerp(rgb(c0), rgb(c1), t[..., None])
        acc += inten[..., None] * col
    acc = np.asarray(Image.fromarray((np.clip(acc, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    img[:sky_h] += acc * 0.95
    # hills
    hy = np.arange(h, dtype=np.float32)[:, None]
    for base, amp, periods, col in [(0.66, 0.07, 2.5, "#1a1b2b"), (0.69, 0.04, 4.0, "#11111b")]:
        ridge = fbm1d(w, periods, rng, octaves=6)
        top = (base - amp * (ridge - ridge.min()) / (np.ptp(ridge) + 1e-6)) * h
        mask = smoothstep(-1.2, 1.2, hy - top[None, :]) * (hy < horizon + 2)
        img = lerp(img, rgb(col) * np.ones_like(img), mask[..., None])
    # lake: reflection of the sky, rippled, darker
    lake_h = h - horizon
    src = img[max(0, horizon - lake_h):horizon][::-1]
    if src.shape[0] < lake_h:
        src = np.concatenate([src, np.repeat(src[-1:], lake_h - src.shape[0], 0)])
    ripple = (np.sin(np.arange(lake_h)[:, None] * 0.9 + fbm((lake_h, w), (6, 3), rng, 3) * 6) * 3).astype(int)
    cols = np.clip(np.arange(w)[None, :] + ripple, 0, w - 1)
    refl = src[np.arange(lake_h)[:, None], cols]
    refl = np.asarray(Image.fromarray((np.clip(refl, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.5)), np.float32) / 255
    fade = (0.75 * (1 - np.linspace(0, 1, lake_h)) ** 1.2)[:, None, None]
    img[horizon:] = lerp(rgb("crust") * np.ones_like(refl), refl, fade)
    return img


def flow(w, h, rng):
    """Silk-like streamlines along a smooth, mostly left-to-right flow field."""
    img = vgradient(h, w, [(0, "crust"), (1, "#16162a")])
    fh, fw = h // 8, w // 8
    field = fbm((fh, fw), (2, 3), rng, octaves=3, gain=0.45)
    ang = field * math.pi * 0.9 + 0.12           # mostly to the right, gently curving
    vx, vy = np.cos(ang), np.sin(ang)
    acc = np.zeros((h, w, 3), np.float32)
    n_particles, steps, step = int(w * h / 700), 900, 1.4
    px = rng.uniform(-w * 0.1, w, n_particles)
    py = rng.uniform(0, h, n_particles)
    hue = np.clip(py / h + rng.normal(0, 0.06, n_particles), 0, 1)
    pal = [(0, "sapphire"), (0.3, "blue"), (0.55, "lavender"), (0.8, "mauve"), (1, "pink")]
    col_all = gradient_map(hue, pal)
    life = rng.uniform(0.35, 1.0, n_particles)
    for i in range(steps):
        ix = np.clip((px / 8).astype(int), 0, fw - 1)
        iy = np.clip((py / 8).astype(int), 0, fh - 1)
        px = px + vx[iy, ix] * step
        py = py + vy[iy, ix] * step
        k = i / steps
        fade = np.clip(np.sin(np.pi * np.clip(k / life, 0, 1)), 0, 1) * (k < life)
        alive = (px >= 0) & (px < w) & (py >= 0) & (py < h) & (fade > 0)
        if not alive.any():
            continue
        np.add.at(acc, (py[alive].astype(int), px[alive].astype(int)), col_all[alive] * (0.05 * fade[alive])[:, None])
    toimg = lambda a, r: np.asarray(Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r)), np.float32) / 255
    fine = toimg(acc, 0.7)
    glow = toimg(acc * 0.6, 12)
    out = img + 1.0 - np.exp(-(fine * 2.6 + glow * 2.2))
    return out * vignette(h, w, 0.5)[..., None]

def vignette(h, w, strength):
    Y, X = np.ogrid[:h, :w]
    d = np.sqrt(((X - w / 2) / (w / 2)) ** 2 + ((Y - h / 2) / (h / 2)) ** 2) / math.sqrt(2)
    return 1 - strength * smoothstep(0.35, 1.05, d)


def waves(w, h, rng):
    """Layered translucent ribbons with bright edges."""
    img = vgradient(h, w, [(0, "crust"), (0.55, "mantle"), (1, "base")])
    img = stars(img, rng, w * h / 9000, ymax=0.45, big=0.0)
    x = np.linspace(0, 1, w, dtype=np.float32)
    hy = np.arange(h, dtype=np.float32)[:, None]
    pal = ["#1e1e2e", "surface0", "blue", "sapphire", "lavender", "mauve", "pink", "peach"]
    n = 9
    for i in range(n):
        t = i / (n - 1)
        base = h * (0.48 + 0.45 * t)
        amp = h * (0.06 + 0.03 * math.sin(i * 1.7))
        ph = rng.uniform(0, 2 * math.pi)
        curve = base + amp * np.sin(2 * math.pi * (x * (0.8 + 0.25 * (i % 2)) + ph)) \
            + h * 0.025 * fbm1d(w, 2.0, rng, octaves=4)
        dist = hy - curve[None, :]
        mask = smoothstep(-1.0, 1.0, dist)
        col = gradient_map(np.full(1, t), [(k / (len(pal) - 1), c) for k, c in enumerate(pal)])[0]
        shade = col * (0.22 + 0.5 * t) * (1 - 0.35 * smoothstep(0, h * 0.35, dist))[..., None]
        img = lerp(img, shade, (mask * (0.55 + 0.35 * t))[..., None])
        edge = np.exp(-(dist / 1.4) ** 2) * (0.35 + 0.4 * t) + np.exp(-(np.abs(dist) / 14)) * 0.06
        img += edge[..., None] * lerp(col, rgb("text"), 0.3)
    return img * vignette(h, w, 0.35)[..., None]


def nebula(w, h, rng):
    """Soft domain-warped nebula with dust lanes, a bright core and stars."""
    hh, ww = h // 2, w // 2
    warp_x = fbm((hh, ww), (2, 3), rng, octaves=4)
    warp_y = fbm((hh, ww), (2, 3), rng, octaves=4)
    base = fbm((hh, ww), (3, 5), rng, octaves=6, gain=0.55)
    yy, xx = np.mgrid[0:hh, 0:ww]
    sx = np.clip((xx + warp_x * ww * 0.18).astype(int), 0, ww - 1)
    sy = np.clip((yy + warp_y * hh * 0.18).astype(int), 0, hh - 1)
    d = base[sy, sx]
    d = (d - d.min()) / (np.ptp(d) + 1e-6)
    hue = fbm((hh, ww), (1, 2), rng, octaves=3)
    hue = (hue - hue.min()) / (np.ptp(hue) + 1e-6)
    # a diagonal band where the nebula is densest
    Y, X = np.mgrid[0:hh, 0:ww].astype(np.float32)
    band = np.exp(-(((Y / hh - 0.5) - 0.35 * (X / ww - 0.5)) / 0.28) ** 2)
    dens = smoothstep(0.25, 0.85, d) * (0.25 + 0.75 * band)
    dust = smoothstep(0.55, 0.8, fbm((hh, ww), (4, 7), rng, octaves=5)) * band
    c1 = gradient_map(hue, [(0, "blue"), (0.5, "mauve"), (1, "pink")])
    col = rgb("crust") + c1 * dens[..., None] ** 1.3 * 0.85
    col += rgb("rosewater") * (smoothstep(0.75, 1.0, d) * band)[..., None] * 0.25
    col *= (1 - 0.65 * dust)[..., None]
    up = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(2))
    img = np.asarray(up, np.float32) / 255
    img = stars(img, rng, w * h / 2000, ymax=1.0, big=0.025)
    return img * vignette(h, w, 0.4)[..., None]

def emblem(layer, cx, cy, s):
    """The Huilo mark: a gradient peak ("A") with an orbit ring passing behind and in front."""
    w, h = layer.size
    ring = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rw, rh, th = s * 1.55, s * 0.32, max(2, int(s * 0.035))
    box = [cx - rw, cy + s * 0.16 - rh, cx + rw, cy + s * 0.16 + rh]
    rd.arc(box, 180, 360, fill=(203, 166, 247, 255), width=th)          # back half
    layer.alpha_composite(ring)
    # peak with a vertical blue -> mauve gradient
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.polygon([(cx, cy - s), (cx + s * 0.86, cy + s * 0.78), (cx - s * 0.86, cy + s * 0.78)], fill=255)
    md.polygon([(cx, cy - s * 0.36), (cx + s * 0.40, cy + s * 0.46), (cx - s * 0.40, cy + s * 0.46)], fill=0)
    t = np.clip((np.arange(h, dtype=np.float32) - (cy - s)) / (s * 1.78), 0, 1)[:, None]
    grad = lerp(rgb("blue"), rgb("mauve"), t)[..., None, :] * np.ones((1, w, 1), np.float32)
    grad = np.concatenate([grad.reshape(h, w, 3), np.asarray(mask, np.float32)[..., None] / 255], -1)
    layer.alpha_composite(Image.fromarray((grad * 255).astype(np.uint8), "RGBA"))
    front = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(front).arc(box, 0, 180, fill=(245, 194, 231, 255), width=th)   # front half
    layer.alpha_composite(front)

def mark(w, h, rng, size=None):
    """Minimal wallpaper: radial glow + the Huilo emblem and wordmark."""
    Y, X = np.ogrid[:h, :w]
    d = np.sqrt(((X - w / 2) / w) ** 2 + ((Y - h * 0.45) / h) ** 2)
    img = gradient_map(np.clip(d * 1.6, 0, 1), [(0, "#2a2a44"), (0.45, "base"), (1, "crust")])
    ss = 2
    layer = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    s = h * 0.16 * ss
    emblem(layer, w * ss / 2, h * 0.43 * ss, s)
    dr = ImageDraw.Draw(layer)
    try:
        font = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-Light.otf", int(h * 0.055 * ss))
        text = "H U I L O"
        tw = dr.textlength(text, font=font)
        dr.text((w * ss / 2 - tw / 2, h * 0.66 * ss), text, font=font, fill=(205, 214, 244, 235))
    except OSError:
        pass
    layer = layer.resize((w, h), Image.LANCZOS)
    a = np.asarray(layer, np.float32) / 255
    glow = np.asarray(layer.filter(ImageFilter.GaussianBlur(h * 0.03)), np.float32) / 255
    img = img + glow[..., :3] * glow[..., 3:] * 0.55
    img = lerp(img, a[..., :3], a[..., 3:])
    return img


def fit_on_blur(src, w, h, blur=40, darken=0.35):
    """Fit src into w x h (whole image visible); the free space is filled with a
    blurred, darkened cover-scaled copy of the same image."""
    sw, sh = src.size
    cover = max(w / sw, h / sh)
    bg = src.resize((max(w, int(sw * cover + 0.5)), max(h, int(sh * cover + 0.5))), Image.LANCZOS)
    bg = bg.crop(((bg.width - w) // 2, (bg.height - h) // 2, (bg.width - w) // 2 + w, (bg.height - h) // 2 + h))
    bg = bg.filter(ImageFilter.GaussianBlur(blur))
    bg = Image.blend(bg, Image.new("RGB", (w, h), (17, 17, 27)), darken)
    fit = min(w / sw, h / sh)
    fg = src.resize((int(sw * fit + 0.5), int(sh * fit + 0.5)), Image.LANCZOS)
    if fit > 1.5:  # upscaled a lot: a light unsharp mask keeps edges crisp
        fg = fg.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    x, y = (w - fg.width) // 2, (h - fg.height) // 2
    shadow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shadow).rectangle([x + 8, y + 12, x + fg.width + 8, y + fg.height + 12], fill=170)
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(6, w // 160)))
    bg.paste(Image.new("RGB", (w, h), (0, 0, 0)), (0, 0), shadow)
    bg.paste(fg, (x, y))
    return bg


def photo(w, h, rng):
    src = Image.open(PHOTO).convert("RGB")
    return np.asarray(fit_on_blur(src, w, h), np.float32) / 255


def photo_assets():
    """syslinux boot menu background and the Plymouth boot splash from the photo."""
    src = Image.open(PHOTO).convert("RGB")
    fit_on_blur(src, 640, 480, blur=18, darken=0.25).save(SPLASH, optimize=True)
    print(f"{SPLASH}  {os.path.getsize(SPLASH) // 1024} KiB")
    os.makedirs(PLYMOUTH, exist_ok=True)
    # the script theme scales splash.png to fit the screen over background.png
    big = src.resize((src.width * 2, src.height * 2), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=2, percent=50, threshold=2))
    big.save(os.path.join(PLYMOUTH, "splash.png"), optimize=True)
    bg = fit_on_blur(src, 1920, 1080, blur=45, darken=0.45)
    bg = bg.filter(ImageFilter.GaussianBlur(30))       # only the colours of the photo
    bg.save(os.path.join(PLYMOUTH, "background.png"), optimize=True)
    print(f"{PLYMOUTH}/splash.png + background.png")


# fixed seeds per wallpaper: adding or reordering entries never changes the others
SEEDS = {"huilo-peaks": 1000, "huilo-aurora": 1001, "huilo-flow": 1002, "huilo-waves": 1003,
         "huilo-nebula": 1004, "huilo-mark": 1005, "huilo-photo": 1006}

WALLPAPERS = [
    ("huilo-photo", "В пизду (фото)", photo),
    ("huilo-peaks", "Горы в сумерках", peaks),
    ("huilo-aurora", "Северное сияние", aurora),
    ("huilo-flow", "Поток", flow),
    ("huilo-waves", "Волны", waves),
    ("huilo-nebula", "Туманность", nebula),
    ("huilo-mark", "Эмблема Huilo", mark),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--size", default="3840x2160")
    ap.add_argument("--only")
    ap.add_argument("--quality", type=int, default=90)
    args = ap.parse_args()
    w, h = map(int, args.size.split("x"))
    os.makedirs(os.path.join(args.out, "thumbs"), exist_ok=True)
    for i, (name, title, fn) in enumerate(WALLPAPERS):
        if args.only and args.only != name:
            continue
        rng = np.random.default_rng(SEEDS.get(name, 999))
        im = finish(fn(w, h, rng), rng)
        path = os.path.join(args.out, name + ".jpg")
        im.save(path, quality=args.quality, subsampling=0, optimize=True, progressive=True)
        im.resize((480, 270), Image.LANCZOS).save(os.path.join(args.out, "thumbs", name + ".jpg"), quality=88)
        print(f"{path}  {os.path.getsize(path) // 1024} KiB  ({title})")
    if not args.only and args.out == OUT:
        photo_assets()
    with open(os.path.join(args.out, "wallpapers.txt"), "w", encoding="utf-8") as f:
        for name, title, _ in WALLPAPERS:
            f.write(f"{name}.jpg\t{title}\n")


if __name__ == "__main__":
    main()
