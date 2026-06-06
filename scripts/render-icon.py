#!/usr/bin/env python3
"""
Render the Loomings icon using Pillow.
Nautical abstract: fog layers + emerging whale silhouette on deep navy.
Generates all macOS-required PNG sizes.
"""

from PIL import Image, ImageDraw
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "icons" / "rendered"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── Pequod palette ─────────────────────────────────────────────────────
NAVY       = (13, 47, 66)     # #0D2F42
NAVY_DEEP  = (2, 16, 27)      # #02101B
NAVY_DARK  = (6, 24, 38)      # #061826
NAVY_ABYSS = (1, 10, 18)      # #010A12
CREAM      = (247, 243, 238)  # #F7F3EE
BEIGE      = (234, 225, 215)  # #EAE1D7
BEIGE_DIM  = (219, 201, 182)  # #DBC9B6
AMBER      = (189, 140, 104)  # #BD8C68
AMBER_LT   = (212, 168, 130)  # #D4A882
TEAL       = (22, 63, 84)     # #163F54


def lerp(a, b, t):
    """Linear interpolation between two colors."""
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def lerp_alpha(a, b, t):
    """Linear interpolation including alpha."""
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


def squircle_mask(size, radius_pct=0.22):
    """Create a mask image with macOS-style rounded rectangle."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    r = int(size * radius_pct)
    # Use a smoother approach: multiple overlaid rounded rects with antialiasing
    draw.rounded_rectangle([(0, 0), (size - 1, size - 1)], radius=r, fill=255)
    return mask


def gradient_bg(size):
    """Deep navy gradient, lighter at top."""
    img = Image.new("RGBA", (size, size))
    for y in range(size):
        t = y / size
        color = lerp(NAVY, NAVY_DEEP, t * 1.3)  # faster descent into deep
        if t > 0.7:
            color = lerp(NAVY_DEEP, NAVY_ABYSS, (t - 0.7) / 0.3)
        for x in range(size):
            img.putpixel((x, y), (*color, 255))
    return img


def fog_band(size, y_start, height, fog_index):
    """A horizontal fog band that fades in from left to right."""
    band = Image.new("RGBA", (size, height))
    fog_colors = [
        (*CREAM, 0),
        (*BEIGE, 0),
        (*BEIGE_DIM, 0),
    ]
    # Different fog layers have different opacity profiles
    opacity_profiles = [
        # (start_x_pct, peak_x_pct, end_x_pct, peak_alpha)
        [(0.30, 0.55, 0.75, 0.15)],
        [(0.35, 0.60, 0.80, 0.12)],
        [(0.40, 0.65, 0.85, 0.08)],
    ]
    profile = opacity_profiles[fog_index % 3]
    base_color = [CREAM, BEIGE, BEIGE_DIM][fog_index % 3]

    for x in range(size):
        x_pct = x / size
        alpha = 0
        for seg in profile:
            if x_pct >= seg[0] and x_pct <= seg[2]:
                if x_pct <= seg[1]:
                    alpha = seg[3] * (x_pct - seg[0]) / (seg[1] - seg[0])
                else:
                    alpha = seg[3] * (1 - (x_pct - seg[1]) / (seg[2] - seg[1]))
        alpha = max(0, min(255, int(alpha * 255)))
        for y in range(height):
            band.putpixel((x, y), (*base_color, alpha))
    return band


def whale_silhouette(size):
    """Abstract sperm whale silhouette emerging from the left, sharpening rightward."""
    shape = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shape)

    # Control points for the whale back curve (normalized to 0-1)
    # Starts flat on left, rises into a hump, tapers to tail on right
    points = []
    baseline_y = 0.62  # where the bottom of the shape sits
    for i in range(size + 1):
        x_pct = i / size
        # Whale back profile: flat start, rising hump, descending tail
        if x_pct < 0.08:
            y = baseline_y  # flat, submerged
        elif x_pct < 0.35:
            t = (x_pct - 0.08) / 0.27
            y = baseline_y - 0.02 * t  # slight rise
        elif x_pct < 0.55:
            t = (x_pct - 0.35) / 0.20
            # Smooth hump using sine-like curve
            y = baseline_y - 0.02 - 0.15 * math.sin(t * math.pi)
        elif x_pct < 0.75:
            t = (x_pct - 0.55) / 0.20
            y = baseline_y - 0.02 - 0.15 * (1 - t)  # descend
        elif x_pct < 0.90:
            t = (x_pct - 0.75) / 0.15
            y = baseline_y - 0.02 + 0.04 * t  # slight rise for tail
        else:
            t = (x_pct - 0.90) / 0.10
            y = baseline_y - 0.02 + 0.04 - 0.08 * t  # tail taper

        y = max(0.1, min(0.95, y))
        points.append((i, int(y * size)))

    # Fill from curve down to bottom
    for x in range(size):
        _, curve_y = points[x]
        # Right side: fully opaque dark silhouette
        # Left side: fading into fog
        x_pct = x / size
        if x_pct < 0.20:
            alpha_pct = 0
        elif x_pct < 0.45:
            alpha_pct = (x_pct - 0.20) / 0.25 * 0.5
        elif x_pct < 0.65:
            alpha_pct = 0.5 + (x_pct - 0.45) / 0.20 * 0.4
        else:
            alpha_pct = 0.9 + (x_pct - 0.65) / 0.35 * 0.1

        alpha = int(alpha_pct * 255)
        for y in range(curve_y, size):
            existing = shape.getpixel((x, y))
            # Blend: darker silhouette toward right, fading toward left
            color = lerp(NAVY_DEEP, NAVY_ABYSS, alpha_pct)
            shape.putpixel((x, y), (*color, alpha))

    # Highlight edge along the top of the silhouette
    for x in range(int(size * 0.35), int(size * 0.85)):
        _, curve_y = points[x]
        for dy in range(-3, 1):
            y = curve_y + dy
            if 0 <= y < size:
                existing = shape.getpixel((x, y))
                if existing[3] > 0:
                    shape.putpixel((x, y), (*TEAL, min(existing[3] + 40, 255)))

    return shape


def amber_glow(size):
    """Soft amber radial glow at upper right."""
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx, cy = int(size * 0.85), int(size * 0.22)
    max_r = int(size * 0.30)

    for x in range(size):
        for y in range(size):
            dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            if dist < max_r:
                t = dist / max_r
                alpha = int((1 - t) * (1 - t) * 0.38 * 255)
                glow.putpixel((x, y), (*AMBER, alpha))

    # Small bright dot: lantern
    for dx in range(-4, 5):
        for dy in range(-4, 5):
            dist = math.sqrt(dx * dx + dy * dy)
            if dist <= 4:
                x, y = cx + dx, cy + dy
                if 0 <= x < size and 0 <= y < size:
                    alpha = int(0.7 * 255) if dist <= 2 else int((1 - dist / 4) * 0.3 * 255)
                    glow.putpixel((x, y), (*AMBER_LT, alpha))

    return glow


def render_icon(size):
    """Compose the full icon at the given size."""
    img = gradient_bg(size)

    # Amber glow (behind fog)
    glow = amber_glow(size)
    img = Image.alpha_composite(img, glow)

    # Horizon lines
    draw = ImageDraw.Draw(img)
    horizon1 = int(size * 0.56)
    horizon2 = int(size * 0.59)
    for x in range(size):
        # Thin amber horizon
        img.putpixel((x, horizon1), (*AMBER, 30))
        img.putpixel((x, horizon2), (*BEIGE_DIM, 20))

    # Fog layers
    fog_positions = [
        (int(size * 0.50), int(size * 0.18)),
        (int(size * 0.38), int(size * 0.14)),
        (int(size * 0.28), int(size * 0.10)),
    ]
    for i, (y_pos, h) in enumerate(fog_positions):
        fog_band_img = fog_band(size, y_pos, h, i)
        # Paste fog band onto full-size transparent canvas
        fog_full = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        fog_full.paste(fog_band_img, (0, y_pos))
        img = Image.alpha_composite(img, fog_full)

    # Whale silhouette
    whale = whale_silhouette(size)
    img = Image.alpha_composite(img, whale)

    # Foreground fog overlay (softens left edge of silhouette)
    fg_fog = Image.new("RGBA", (size, int(size * 0.40)))
    for x in range(size):
        x_pct = x / size
        if x_pct < 0.45:
            alpha = int((0.45 - x_pct) / 0.45 * 0.20 * 255)
        else:
            alpha = 0
        for y in range(fg_fog.height):
            fg_fog.putpixel((x, y), (*CREAM, alpha))
    img.paste(fg_fog, (0, int(size * 0.30)), fg_fog)

    # Bottom darkening
    for y in range(int(size * 0.80), size):
        t = (y - size * 0.80) / (size * 0.20)
        alpha = int(t * 0.3 * 255)
        for x in range(size):
            existing = img.getpixel((x, y))
            img.putpixel((x, y), (
                max(0, existing[0] - alpha // 3),
                max(0, existing[1] - alpha // 3),
                max(0, existing[2] - alpha // 3),
                existing[3],
            ))

    # Apply squircle mask
    mask = squircle_mask(size)
    img.putalpha(mask)

    return img


# ── Render all sizes ───────────────────────────────────────────────────

SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_64x64.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
    "icon_256.png": 256,
    "icon_1024.png": 1024,
}

for name, size in SIZES.items():
    out_path = OUT_DIR / name
    img = render_icon(size)
    img.save(out_path, "PNG")
    print(f"  {name} ({size}×{size})")

print(f"\nDone. {len(SIZES)} sizes rendered to {OUT_DIR}/")
print(f"Next: copy icon_1024.png → src-tauri/icons/icon.png")
print(f"      copy icon_256.png → src/icon.png")
print(f"      regenerate ICNS with scripts/build-icon.sh")
