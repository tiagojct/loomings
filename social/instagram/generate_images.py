#!/usr/bin/env python3
"""Generate all Loomings Instagram post images with Pillow.

Usage:
    pip install pillow
    python3 social/instagram/generate_images.py

The output PNGs (~7 MB total) live in social/instagram/images/ which is
gitignored — only this script is versioned. Re-run when the icon,
screenshot, or palette changes.
"""

import os, sys, textwrap
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# ── Paths ──────────────────────────────────────────────────────────────
LOOMINGS    = os.path.expanduser("~/github/loomings")
OUT_DIR     = os.path.join(LOOMINGS, "social/instagram/images")
ICON_PATH   = os.path.join(LOOMINGS, "icons/rendered/icon_1024.png")
SCREENSHOT  = os.path.join(LOOMINGS, "docs/assets/screenshot.png")
OG_CARD     = os.path.join(LOOMINGS, "docs/assets/og.png")

# ── Dimensions ─────────────────────────────────────────────────────────
W, H = 1080, 1350  # 4:5 Instagram portrait
MARGIN = 86  # ~8% safe margin

# ── Colours ────────────────────────────────────────────────────────────
BELOW_DECK  = (11, 31, 45)      # #0B1F2D
NAVY        = (13, 47, 66)      # #0D2F42
PARCHMENT   = (241, 231, 210)   # #F1E7D2
AMBER       = (189, 140, 104)   # #BD8C68
AMBER_DIM   = (139, 99, 72)     # #8B6348
AMBER_LIGHT = (212, 168, 130)   # #D4A882
CREAM       = (247, 243, 238)   # #F7F3EE
CREAM_WARM  = (237, 227, 204)   # #EDE3CC
INK          = (26, 45, 60)      # #1A2D3C
SOFT_INK    = (60, 80, 95)
MUTED       = (126, 118, 96)    # #7E7660

# ── Fonts ──────────────────────────────────────────────────────────────
def load_font(size, style="regular"):
    """Load Georgia (Source Serif fallback), JetBrains Mono, or Didot."""
    base = "/System/Library/Fonts/Supplemental"
    jb   = os.path.expanduser("~/Library/Fonts")
    if style == "mono":
        path = os.path.join(jb, "JetBrainsMono-Regular.ttf")
    elif style == "mono_bold":
        path = os.path.join(jb, "JetBrainsMono-Bold.ttf")
    elif style == "didot":
        path = os.path.join(base, "Didot.ttc")
    elif style == "georgia_bold":
        path = os.path.join(base, "Georgia Bold.ttf")
    elif style == "georgia_italic":
        path = os.path.join(base, "Georgia Italic.ttf")
    else:
        path = os.path.join(base, "Georgia.ttf")
    return ImageFont.truetype(path, size)

# ── Helpers ────────────────────────────────────────────────────────────
def draw_centered_text(draw, text, y, font, fill, max_w=None):
    """Center text horizontally, return bottom y."""
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    if max_w and tw > max_w:
        # Simple wrap: scale down
        scale = max_w / tw
        font = load_font(int(font.size * scale), _style_of(font))
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
    x = (W - tw) // 2
    draw.text((x, y), text, font=font, fill=fill)
    return y + (bbox[3] - bbox[1])

def _style_of(font):
    path = font.path.lower() if hasattr(font, 'path') else ''
    if 'jetbrains' in path: return 'mono_bold' if 'bold' in path else 'mono'
    if 'didot' in path: return 'didot'
    if 'bold' in path and 'italic' in path: return 'georgia_bold'
    if 'italic' in path: return 'georgia_italic'
    if 'bold' in path: return 'georgia_bold'
    return 'regular'

def draw_rule(draw, y, color, width=60, thickness=2):
    """Centered horizontal rule."""
    x0 = (W - width) // 2
    draw.rectangle([x0, y, x0 + width, y + thickness], fill=color)
    return y + thickness + 12

def new_image(bg_color):
    """Create a new 1080x1350 image."""
    return Image.new("RGB", (W, H), bg_color)

def draw_mark(draw, text="tiagojct.eu/loomings", y=None, color=MUTED, size=18):
    """Bottom-right URL mark."""
    if y is None:
        y = H - 60
    font = load_font(size, "mono")
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text((W - tw - MARGIN, y), text, font=font, fill=color)

def draw_amber_pill(draw, text, cx, cy, font_size=32):
    """Draw an amber-outline pill with cream mono text."""
    font = load_font(font_size, "mono_bold")
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    padding_x, padding_y = 24, 16
    x0, y0 = cx - tw//2 - padding_x, cy - th//2 - padding_y
    x1, y1 = cx + tw//2 + padding_x, cy + th//2 + padding_y
    draw.rounded_rectangle([x0, y0, x1, y1], radius=16, outline=AMBER, width=2)
    draw.text((cx - tw//2, cy - th//2), text, font=font, fill=CREAM)
    return y1 + 20

def draw_key_pill(draw, key, x, y, size=28):
    """Single keyboard key pill — amber outline, cream mono."""
    font = load_font(size, "mono")
    bbox = draw.textbbox((0, 0), key, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    px, py = 14, 10
    draw.rounded_rectangle(
        [x, y, x + tw + px*2, y + th + py*2],
        radius=10, outline=AMBER, width=2
    )
    draw.text((x + px, y + py), key, font=font, fill=CREAM)
    return x + tw + px*2, y + th//2


# ══════════════════════════════════════════════════════════════════════════
# POST GENERATORS
# ══════════════════════════════════════════════════════════════════════════

def post_01():
    """Launch — icon + title on atmospheric bg."""
    try:
        bg = Image.open(os.path.join(OUT_DIR, "01_bg.png")).convert("RGB").resize((W, H))
    except:
        bg = new_image(BELOW_DECK)
        # Fallback: simple radial gradient
        draw = ImageDraw.Draw(bg)
        for y in range(H):
            for x in range(W):
                dx, dy = x - W//2, y - H//3
                dist = (dx*dx + dy*dy) ** 0.5
                r = max(H//2, H)
                t = min(1.0, dist / r)
                fade = 0.15 * (1 - t)
                r = int(BELOW_DECK[0] + fade * 30)
                g = int(BELOW_DECK[1] + fade * 30)
                b = int(BELOW_DECK[2] + fade * 20)
                draw.point((x, y), fill=(r, g, b))
    draw = ImageDraw.Draw(bg)

    # Icon at ~320x320, centered, 30% from top
    icon = Image.open(ICON_PATH).convert("RGBA")
    icon_size = 320
    icon = icon.resize((icon_size, icon_size), Image.LANCZOS)
    icon_x = (W - icon_size) // 2
    icon_y = int(H * 0.28)
    bg.paste(icon, (icon_x, icon_y), icon)

    # Title
    y = icon_y + icon_size + 36
    title_font = load_font(140, "didot")
    y = draw_centered_text(draw, "Loomings", y, title_font, CREAM_WARM)
    y += 8

    # Amber rule
    y = draw_rule(draw, y, AMBER_LIGHT, 60) + 4

    # Version
    v_font = load_font(28, "mono")
    draw_centered_text(draw, "v1.0.0", y, v_font, AMBER_LIGHT)

    # URL
    draw_mark(draw, size=18)

    bg.save(os.path.join(OUT_DIR, "01_launch.png"), optimize=True)
    print("  ✓ 01_launch.png")


def post_02():
    """Call me Ishmael — 5-slide carousel."""
    # Slide 1 – Pull quote
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    y = H // 2 - 120
    q_font = load_font(110, "didot")
    y = draw_centered_text(draw, "Call me Ishmael.", y, q_font, INK)
    y += 16
    attr_font = load_font(28)
    draw_centered_text(draw, "— Herman Melville, 1851", y, attr_font, SOFT_INK)
    draw_mark(draw, "loomings.app", size=16)
    img.save(os.path.join(OUT_DIR, "02_slide1.png"), optimize=True)

    # Slide 2 – Longer quote
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    quote = ("Some years ago — never mind how long precisely — having little "
             "or no money in my purse, and nothing particular to interest me "
             "on shore, I thought I would sail about a little and see the "
             "watery part of the world.")
    q_font2 = load_font(36, "georgia_italic")
    lines = textwrap.wrap(quote, width=45)
    total_h = len(lines) * 50
    y = (H - total_h) // 2
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=q_font2)
        tw = bbox[2] - bbox[0]
        draw.text((MARGIN, y), line, font=q_font2, fill=INK)
        y += 50
    img.save(os.path.join(OUT_DIR, "02_slide2.png"), optimize=True)

    # Slide 3 – Chapter is the namesake
    img = new_image(BELOW_DECK)
    draw = ImageDraw.Draw(img)
    y = H // 3 + 20
    chap_font = load_font(24, "mono")
    draw_centered_text(draw, "Chapter 1", y, chap_font, AMBER)
    y += 60
    name_font = load_font(200, "didot")
    y = draw_centered_text(draw, "Loomings", y, name_font, CREAM)
    y += 30
    sub_font = load_font(26)
    draw_centered_text(draw, "the app is named after the chapter.", y, sub_font, MUTED)
    img.save(os.path.join(OUT_DIR, "02_slide3.png"), optimize=True)

    # Slide 4 – Screenshot
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    cap_font = load_font(26, "georgia_italic")
    draw_centered_text(draw, "the bundled example file.", H // 8, cap_font, INK)
    try:
        ss = Image.open(SCREENSHOT).convert("RGB")
        ss_w, ss_h = 900, int(900 * ss.height / ss.width)
        ss = ss.resize((ss_w, ss_h), Image.LANCZOS)
        # Frame + shadow
        frame = Image.new("RGB", (ss_w + 48, ss_h + 48), NAVY)
        shadow = Image.new("RGBA", (ss_w + 60, ss_h + 60), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        sd.rectangle([10, 10, ss_w + 50, ss_h + 50], fill=(0, 0, 0, 48))
        shadow = shadow.filter(ImageFilter.GaussianBlur(8))
        # Paste onto parchment
        sx = (W - ss_w - 48) // 2
        sy = H // 2 - (ss_h + 48) // 2 + 20
        img.paste(shadow, (sx - 6, sy - 6), shadow)
        frame.paste(ss, (24, 24))
        img.paste(frame, (sx, sy))
    except Exception as e:
        print(f"    [warn] screenshot paste failed: {e}")
    img.save(os.path.join(OUT_DIR, "02_slide4.png"), optimize=True)

    # Slide 5 – CTA
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    cta_font = load_font(44, "didot")
    y = draw_centered_text(draw, "Open it the moment", H // 3, cta_font, INK)
    draw_centered_text(draw, "you install.", y + 8, cta_font, INK)
    y += 40
    y = draw_amber_pill(draw, "Help → Open Example", W // 2, y, 28)
    draw_centered_text(draw, "tiagojct.eu/loomings", y + 20, load_font(20, "mono"), MUTED)
    img.save(os.path.join(OUT_DIR, "02_slide5.png"), optimize=True)

    print("  ✓ 02_slide1-5.png")


def post_03():
    """What it is not — 9-slide carousel."""
    nots = [
        "No cloud sync.",
        "No account.",
        "No tracking.",
        "No newsletter.",
        "No themes marketplace.",
        "No AI assistant in the margin.",
        "No mobile companion.",
    ]

    # Slide 1 – Cover
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    title_font = load_font(110, "didot")
    y = draw_centered_text(draw, "What it is not.", H // 2 - 60, title_font, INK)
    y += 16
    y = draw_rule(draw, y, AMBER)
    draw_centered_text(draw, "swipe →", y + 20, load_font(22), MUTED)
    img.save(os.path.join(OUT_DIR, "03_slide1.png"), optimize=True)

    # Slides 2-8
    n_font = load_font(96, "didot")
    for i, text in enumerate(nots):
        img = new_image(PARCHMENT)
        draw = ImageDraw.Draw(img)
        draw_centered_text(draw, f"— {text}", H // 2 - 30, n_font, INK)
        draw_mark(draw, "loomings.app", size=16)
        img.save(os.path.join(OUT_DIR, f"03_slide{i+2}.png"), optimize=True)

    # Slide 9 – Coda
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    coda_font = load_font(60, "didot")
    y = draw_centered_text(draw, "The files are your files.", H // 2 - 60, coda_font, INK)
    draw_centered_text(draw, "They live wherever you put them.", y + 16, coda_font, INK)
    y += 50
    draw_centered_text(draw, "tiagojct.eu/loomings", y, load_font(22, "mono"), MUTED)
    img.save(os.path.join(OUT_DIR, "03_slide9.png"), optimize=True)

    print("  ✓ 03_slide1-9.png")


def post_04():
    """Pequod palette — 5 colour bands."""
    bands = [
        ("parchment",    "#F1E7D2", PARCHMENT, INK),
        ("amber light",  "#D4A882", AMBER_LIGHT, INK),
        ("amber",        "#BD8C68", AMBER, INK),
        ("navy",         "#0D2F42", NAVY, CREAM),
        ("below deck",   "#0B1F2D", BELOW_DECK, CREAM),
    ]
    BAND_H = H // len(bands)
    img = new_image((0, 0, 0))
    draw = ImageDraw.Draw(img)

    for i, (name, hex_str, color, label_color) in enumerate(bands):
        y0 = i * BAND_H
        # Band
        draw.rectangle([0, y0, W, y0 + BAND_H], fill=color)
        # Name (left side)
        name_font = load_font(48, "didot")
        draw.text((MARGIN, y0 + BAND_H // 2 - 30), name, font=name_font, fill=label_color)
        # Hex (right side)
        hex_font = load_font(28, "mono")
        hex_text = f"· {hex_str}"
        bbox = draw.textbbox((0, 0), hex_text, font=hex_font)
        tw = bbox[2] - bbox[0]
        draw.text((W - tw - MARGIN, y0 + BAND_H // 2 - 14), hex_text, font=hex_font, fill=label_color)

    # Wordmark top-left
    word_font = load_font(36, "didot")
    draw.text((MARGIN, 30), "Loomings", font=word_font, fill=AMBER_LIGHT if bands[0][2] == PARCHMENT else INK)
    sub_font = load_font(22)
    draw.text((MARGIN, 72), "the pequod palette", font=sub_font, fill=MUTED)

    img.save(os.path.join(OUT_DIR, "04_palette.png"), optimize=True)
    print("  ✓ 04_palette.png")


def post_06():
    """Keyboard shortcuts — 8-slide carousel."""
    shortcuts = [
        ("⌘", "P", "Outline", "Fuzzy-jump to any heading."),
        ("⌘", "F", "Find", "Search the document, with regex if you want."),
        ("⌘", "⇧", "D", "Focus", "Dim everything outside the current sentence."),
        ("⌘", "⇧", "P", "Preview", "Toggle the rendered markdown."),
        ("⌘", "⇧", "W", "Width", "Cycle the column width."),
        ("⌘", "⇧", "T", "Theme", "Cycle the theme — system, light, dark."),
        ("⌘", "⇧", "G", "Goal", "Cycle a word goal."),
    ]

    for idx, keys in enumerate(shortcuts):
        img = new_image(BELOW_DECK)
        draw = ImageDraw.Draw(img)

        # Draw key pills centered
        key_items = [k for k in keys[:-2] if isinstance(k, str)]  # all but action + desc
        pill_h = 60
        plus_w = 30
        total_w = len(key_items) * 90 + (len(key_items) - 1) * plus_w  # rough
        x = W // 2 - total_w // 2
        y = H // 2 - 160

        for j, key in enumerate(key_items):
            pill_font = load_font(32, "mono")
            bbox = draw.textbbox((0, 0), key, font=pill_font)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            px, py = 16, 12
            draw.rounded_rectangle(
                [x, y, x + tw + px*2, y + th + py*2],
                radius=8, outline=AMBER, width=2
            )
            draw.text((x + px, y + py), key, font=pill_font, fill=CREAM)
            x += tw + px*2
            if j < len(key_items) - 1:
                plus = load_font(24)
                draw.text((x + 4, y + py + 2), "+", font=plus, fill=MUTED)
                x += plus_w

        y += pill_h + 36
        # Amber rule
        y = draw_rule(draw, y, AMBER, 80) + 4
        # Action name
        action_font = load_font(76, "didot")
        y = draw_centered_text(draw, keys[-2], y, action_font, CREAM)
        y += 12
        # Explanation
        exp_font = load_font(26)
        draw_centered_text(draw, keys[-1], y, exp_font, MUTED)

        draw_mark(draw, "loomings.app", size=16)
        img.save(os.path.join(OUT_DIR, f"06_slide{idx+1}.png"), optimize=True)

    # Slide 8 – CTA
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    cta_font = load_font(58, "didot")
    y = draw_centered_text(draw, "Seven shortcuts.", H // 2 - 40, cta_font, INK)
    draw_centered_text(draw, "The rest stays out of the way.", y + 12, cta_font, INK)
    y += 50
    draw_centered_text(draw, "tiagojct.eu/loomings", y, load_font(22, "mono"), MUTED)
    img.save(os.path.join(OUT_DIR, "06_slide8.png"), optimize=True)

    print("  ✓ 06_slide1-8.png")


def post_07():
    """Icon evolution — 4-slide carousel."""
    # Slide 1 – Cover
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    title_font = load_font(76, "didot")
    y = draw_centered_text(draw, "the icon,", H // 2 - 50, title_font, INK)
    draw_centered_text(draw, "before it was the icon.", y + 10, title_font, INK)
    y += 20
    draw_rule(draw, y, AMBER)
    draw_mark(draw, "loomings.app", size=16)
    img.save(os.path.join(OUT_DIR, "07_slide1.png"), optimize=True)

    # Slide 2 – Drafts (symbolic — we don't have actual early drafts, so abstract representation)
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    # Draw 3 abstract icon placeholders
    for i, label in enumerate(["(starburst)", "(flat L)", "(whale-tail)"]):
        bx = W // 2 - 350 + i * 240
        by = H // 2 - 120
        draw.rounded_rectangle([bx, by, bx + 200, by + 200], radius=36,
                               outline=AMBER_DIM, fill=BELOW_DECK, width=2)
        l_font = load_font(14, "mono")
        bbox = draw.textbbox((0, 0), label, font=l_font)
        tw = bbox[2] - bbox[0]
        draw.text((bx + 100 - tw//2, by + 210), label, font=l_font, fill=MUTED)
    draw_centered_text(draw, "drafts.", H - 120, load_font(22, "georgia_italic"), MUTED)
    img.save(os.path.join(OUT_DIR, "07_slide2.png"), optimize=True)

    # Slide 3 – Final icon
    img = new_image(BELOW_DECK)
    draw = ImageDraw.Draw(img)
    top_font = load_font(56, "didot")
    draw_centered_text(draw, "italic didot, amber, navy.", H // 5, top_font, CREAM)
    try:
        icon = Image.open(ICON_PATH).convert("RGBA")
        icon_size = 400
        icon = icon.resize((icon_size, icon_size), Image.LANCZOS)
        ix = (W - icon_size) // 2
        iy = H // 2 - icon_size // 2 - 20
        img.paste(icon, (ix, iy), icon)
    except:
        pass
    sub_font = load_font(26)
    draw_centered_text(draw, "Apple's Icon Composer applies the glass;", H - 180, sub_font, MUTED)
    draw_centered_text(draw, "the squircle is its own shape.", H - 145, sub_font, MUTED)
    img.save(os.path.join(OUT_DIR, "07_slide3.png"), optimize=True)

    # Slide 4 – CTA
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    cta_font = load_font(60, "didot")
    y = draw_centered_text(draw, "Most icons take three drafts.", H // 2 - 30, cta_font, INK)
    y += 20
    draw_centered_text(draw, "this one took about thirty.", y, load_font(28), MUTED)
    y += 40
    draw_centered_text(draw, "tiagojct.eu/loomings", y, load_font(22, "mono"), MUTED)
    img.save(os.path.join(OUT_DIR, "07_slide4.png"), optimize=True)

    print("  ✓ 07_slide1-4.png")


def post_08():
    """There is magic in it — quote on atmospheric bg."""
    try:
        img = Image.open(os.path.join(OUT_DIR, "08_bg.png")).convert("RGB").resize((W, H))
    except:
        img = new_image(BELOW_DECK)
    draw = ImageDraw.Draw(img)

    # Quote centered upper third
    q_font = load_font(130, "didot")
    y = draw_centered_text(draw, "There is magic in it.", H // 3 - 20, q_font, CREAM)
    y += 16
    y = draw_rule(draw, y, AMBER, 80)
    attr_font = load_font(28)
    draw_centered_text(draw, "— Herman Melville, Loomings, 1851", y + 4, attr_font, MUTED)

    # Horizon line in lower area
    hy = H - 280
    draw.line([(W * 0.2, hy), (W * 0.8, hy)], fill=AMBER, width=1)
    # Two amber dots flanking
    for dx in [-4, 4]:
        draw.ellipse([(W // 2 + dx - 3, hy - 3), (W // 2 + dx + 3, hy + 3)], fill=AMBER)

    img.save(os.path.join(OUT_DIR, "08_magic.png"), optimize=True)
    print("  ✓ 08_magic.png")


def post_09():
    """Electron → Tauri — 4-slide carousel."""
    # Slide 1 – Hook
    img = new_image(BELOW_DECK)
    draw = ImageDraw.Draw(img)
    big_font = load_font(220, "didot")
    # 180 MB struck through
    tw_180 = draw.textbbox((0, 0), "180 MB", font=big_font)[2]
    x_180 = (W - tw_180) // 2
    y_180 = H // 2 - 130
    draw.text((x_180, y_180), "180 MB", font=big_font, fill=CREAM)
    # Strike-through
    strike_y = y_180 + 110
    draw.line([(x_180 - 10, strike_y), (x_180 + tw_180 + 10, strike_y)], fill=AMBER, width=4)
    # 12 MB
    draw_centered_text(draw, "12 MB", y_180 + 140, big_font, AMBER_LIGHT)
    sub_font = load_font(32)
    draw_centered_text(draw, "the same writing app.", H - 200, sub_font, MUTED)
    img.save(os.path.join(OUT_DIR, "09_slide1.png"), optimize=True)

    # Slide 2 – Why
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    why_font = load_font(40, "didot")
    lines = [
        "Electron bundles a full Chromium.",
        "Tauri uses the OS web view.",
        "Loomings has no reason to ship a browser.",
    ]
    y = H // 2 - 80
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=why_font)
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) // 2, y), line, font=why_font, fill=INK)
        y += 55
    draw_mark(draw)
    img.save(os.path.join(OUT_DIR, "09_slide2.png"), optimize=True)

    # Slide 3 – Numbers table
    img = new_image(BELOW_DECK)
    draw = ImageDraw.Draw(img)
    mono_font = load_font(32, "mono")
    table_data = [
        ("metric",      "electron", "tauri"),
        ("binary",      "180 MB",   "12 MB"),
        ("idle RAM",    "150 MB",   "30 MB"),
        ("cold start",  "1.8 s",    "0.4 s"),
        ("rust backend","no",       "yes"),
    ]
    col_w = [220, 150, 120]
    start_y = H // 2 - 120
    for row_i, row in enumerate(table_data):
        x = 180
        for col_i, cell in enumerate(row):
            if row_i == 0:
                draw.text((x, start_y + row_i * 50), cell, font=load_font(24, "mono_bold"), fill=AMBER)
            else:
                draw.text((x, start_y + row_i * 50), cell, font=mono_font, fill=CREAM)
            x += col_w[col_i]
    draw_rule(draw, start_y + len(table_data) * 50 + 10, AMBER)
    draw_centered_text(draw, "loomings v1.0.0", start_y + len(table_data) * 50 + 30,
                       load_font(26, "didot"), MUTED)
    img.save(os.path.join(OUT_DIR, "09_slide3.png"), optimize=True)

    # Slide 4 – CTA
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)
    cta_font = load_font(56, "didot")
    y = draw_centered_text(draw, "Tauri 2. CodeMirror 6.", H // 2 - 40, cta_font, INK)
    draw_centered_text(draw, "About twelve megabytes.", y + 10, cta_font, INK)
    y += 50
    draw_centered_text(draw, "open source · MIT · tiagojct.eu/loomings", y, load_font(22, "mono"), MUTED)
    img.save(os.path.join(OUT_DIR, "09_slide4.png"), optimize=True)

    print("  ✓ 09_slide1-4.png")


def post_11():
    """Built by one — single image."""
    img = new_image(PARCHMENT)
    draw = ImageDraw.Draw(img)

    y = H // 2 - 140
    y = draw_rule(draw, y, AMBER, 60) + 8
    title_font = load_font(110, "didot")
    y = draw_centered_text(draw, "Made by one.", y, title_font, INK)
    y += 12
    y = draw_rule(draw, y, AMBER, 60) + 16

    stats_font = load_font(28, "didot")
    stats = [
        "about 2,180 lines of code.",
        "one person.",
        "spare evenings.",
        "MIT licensed.",
        "on github.",
    ]
    for line in stats:
        y = draw_centered_text(draw, line, y, stats_font, SOFT_INK)
        y += 6
    y += 10
    y = draw_rule(draw, y, AMBER, 60) + 10
    draw_centered_text(draw, "tiagojct.eu/loomings", y, load_font(20, "mono"), MUTED)

    img.save(os.path.join(OUT_DIR, "11_built_by_one.png"), optimize=True)
    print("  ✓ 11_built_by_one.png")


def post_12():
    """Call for feedback — single image."""
    img = new_image(BELOW_DECK)
    draw = ImageDraw.Draw(img)

    # Big amber question mark
    q_font = load_font(280, "didot")
    draw_centered_text(draw, "?", H // 4 - 20, q_font, AMBER_LIGHT)

    # Title
    title_font = load_font(70, "didot")
    y = draw_centered_text(draw, "What is the editor", H // 2 - 20, title_font, CREAM)
    draw_centered_text(draw, "doing wrong?", y + 6, title_font, CREAM)
    y += 30
    y = draw_rule(draw, y, AMBER) + 8

    sub_font = load_font(26)
    lines = ["GitHub issues open.", "DMs open.", "email is on the website."]
    for line in lines:
        y = draw_centered_text(draw, line, y, sub_font, MUTED)
        y += 4

    draw_mark(draw)
    img.save(os.path.join(OUT_DIR, "12_feedback.png"), optimize=True)
    print("  ✓ 12_feedback.png")


# ══════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Generating Loomings Instagram images...\n")

    post_01()
    post_02()
    post_03()
    post_04()
    post_06()
    post_07()
    post_08()
    post_09()
    post_11()
    post_12()

    print(f"\nDone. Images in {OUT_DIR}/")
