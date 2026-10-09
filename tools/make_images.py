"""Generates the channel's bitmap assets (icons, splash, logo, gradients, 9-patches).

Run from the repo root:  python3 tools/make_images.py
Needs Pillow (pip install pillow). Output goes to src/images/.

Palette ("lavender dream"): a deep plum night, lavender for focus, with small
pops of bubblegum pink and butter yellow.
"""

import json
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "images"
FONT_DISPLAY = ROOT / "src" / "fonts" / "Fredoka-SemiBold.ttf"

BG = (21, 16, 40)
LAVENDER = (185, 163, 255)
LAVENDER_LIGHT = (226, 216, 255)
PINK = (255, 158, 207)
BUTTER = (255, 217, 138)
WHITE = (255, 255, 255)

NAME = "ARAN"
PLUS = "+"


def smooth(t):
    return t * t * (3 - 2 * t)


def gradient_fill(size, top, bottom):
    w, h = size
    grad = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    return grad.resize((w, h))


def wordmark_image(text_size, scale=4):
    """'ARAN' in a lavender gradient with a pink '+', on transparent."""
    font = ImageFont.truetype(str(FONT_DISPLAY), text_size * scale)
    plus_font = ImageFont.truetype(str(FONT_DISPLAY), int(text_size * scale * 1.05))
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    tracking = text_size * scale * 0.04
    widths = [probe.textlength(ch, font=font) for ch in NAME]
    name_w = sum(widths) + tracking * (len(NAME) - 1)
    plus_w = probe.textlength(PLUS, font=plus_font)
    gap = text_size * scale * 0.06
    ascent, descent = font.getmetrics()
    w = int(name_w + gap + plus_w + 8 * scale)
    h = int(ascent + descent + 4 * scale)

    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    x = 4 * scale
    for ch, cw in zip(NAME, widths):
        d.text((x, 0), ch, font=font, fill=255)
        x += cw + tracking
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    img.paste(gradient_fill((w, h), LAVENDER_LIGHT, LAVENDER), (0, 0), mask)

    plus_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(plus_layer).text((x + gap - tracking, -text_size * scale * 0.08), PLUS, font=plus_font, fill=PINK + (255,))
    img.alpha_composite(plus_layer)
    return img


def sparkle(draw, cx, cy, r, color):
    """A soft four-point star."""
    pts = []
    for i in range(8):
        angle = math.pi / 4 * i - math.pi / 2
        radius = r if i % 2 == 0 else r * 0.28
        pts.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    draw.polygon(pts, fill=color)


def glow_layer(size, cx, cy, radius, color, strength):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color + (strength,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def brand_card(width, height, text_size):
    """Logo centred on the plum night with lavender and pink glows and a few sparkles."""
    scale = 2
    W, H = width * scale, height * scale
    img = Image.new("RGBA", (W, H), BG + (255,))
    img.alpha_composite(glow_layer((W, H), W * 0.22, H * 0.25, min(W, H) * 0.55, LAVENDER, 110))
    img.alpha_composite(glow_layer((W, H), W * 0.82, H * 0.85, min(W, H) * 0.5, PINK, 80))

    mark = wordmark_image(text_size * scale, scale=2)
    mark = mark.resize((mark.width // 2, mark.height // 2), Image.LANCZOS)
    mx = (W - mark.width) // 2
    my = (H - mark.height) // 2
    img.alpha_composite(mark, (mx, my))

    d = ImageDraw.Draw(img)
    u = text_size * scale
    sparkle(d, mx - u * 0.35, my + u * 0.25, u * 0.22, BUTTER + (255,))
    sparkle(d, mx + mark.width + u * 0.25, my + u * 0.05, u * 0.15, WHITE + (230,))
    sparkle(d, mx + mark.width * 0.72, my + mark.height + u * 0.15, u * 0.12, LAVENDER_LIGHT + (220,))
    return img.convert("RGB").resize((width, height), Image.LANCZOS)


def fade(width, height, direction, max_alpha=255):
    """Background-coloured gradient. direction: 'left' (solid at left), 'bottom', 'top'."""
    img = Image.new("RGBA", (width, height))
    px = img.load()
    for yy in range(height):
        for xx in range(width):
            if direction == "left":
                t = 1 - xx / (width - 1)
            elif direction == "bottom":
                t = yy / (height - 1)
            else:
                t = 1 - yy / (height - 1)
            px[xx, yy] = BG + (int(max_alpha * smooth(t)),)
    return img


def nine_patch(body, radius):
    """Wraps a (2r+2)-square body image as an Android-style 9-patch (Roku reads the same format)."""
    size = body.width
    img = Image.new("RGBA", (size + 2, size + 2), (0, 0, 0, 0))
    img.paste(body, (1, 1))
    px = img.load()
    for i in (1 + radius, 2 + radius):
        px[i, 0] = (0, 0, 0, 255)  # stretchable columns
        px[0, i] = (0, 0, 0, 255)  # stretchable rows
    return img


def rounded(radius, fill=(255, 255, 255, 255), outline_width=0):
    scale = 8
    inner = radius * 2 + 2
    big = Image.new("RGBA", (inner * scale, inner * scale), (0, 0, 0, 0))
    box = (0, 0, inner * scale - 1, inner * scale - 1)
    if outline_width:
        ImageDraw.Draw(big).rounded_rectangle(box, radius=radius * scale, outline=fill, width=outline_width * scale)
    else:
        ImageDraw.Draw(big).rounded_rectangle(box, radius=radius * scale, fill=fill)
    return big.resize((inner, inner), Image.LANCZOS)


def corner_mask(radius):
    """White corners with a clear middle, laid over posters (tinted to the background) to round them."""
    body = rounded(radius)
    mask = Image.new("RGBA", body.size, WHITE + (255,))
    alpha = body.getchannel("A").point(lambda a: 255 - a)
    mask.putalpha(alpha)
    return mask


def glow_png(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            t = min(math.hypot(x - c, y - c) / c, 1)
            px[x, y] = (255, 255, 255, int(255 * (1 - smooth(t)) ** 1.6))
    return img


def player_icons():
    """White glyphs for the player controls, tinted with blendColor on screen."""
    scale = 8
    white = (255, 255, 255, 255)

    def canvas(size):
        return Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))

    def save(img, size, name):
        img.resize((size, size), Image.LANCZOS).save(OUT / name)

    size = 24
    img = canvas(size)
    d = ImageDraw.Draw(img)
    d.polygon([(5 * scale, 2 * scale), (21 * scale, 12 * scale), (5 * scale, 22 * scale)], fill=white)
    save(img, size, "icon_play.png")

    img = canvas(size)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((4 * scale, 3 * scale, 9 * scale, 21 * scale), radius=scale, fill=white)
    d.rounded_rectangle((15 * scale, 3 * scale, 20 * scale, 21 * scale), radius=scale, fill=white)
    save(img, size, "icon_pause.png")

    size = 64
    img = canvas(size)
    ImageDraw.Draw(img).ellipse((0, 0, size * scale - 1, size * scale - 1), fill=white)
    save(img, size, "circle.png")

    img = canvas(size)
    ImageDraw.Draw(img).arc(
        (4 * scale, 4 * scale, 60 * scale, 60 * scale), start=-90, end=180, fill=white, width=6 * scale
    )
    save(img, size, "spinner.png")

    size = 32
    img = canvas(size)
    sparkle(ImageDraw.Draw(img), 16 * scale, 16 * scale, 15 * scale, white)
    save(img, size, "sparkle.png")


# --- Glass ------------------------------------------------------------------------------
#
# Home's tab bar is floating glass, as in the web app (src/styles/shell.css there): a
# translucent plum pill with light along its top and a soft shadow, and a glass lens on
# the tab you're on that springs from tab to tab (components/common/Glass.brs). A Roku
# can't blur what's behind, so the glass is drawn: tint, sheen, rim and shadow.

TAB_W = 112  # one tab's slot
TABS = 5
INSET = 4  # the lens's gap from the bar's edge
BAR_W = TAB_W * TABS + INSET * 2
BAR_H = 48
LENS_W = TAB_W
LENS_H = BAR_H - INSET * 2
SHADOW_PAD = 40


def pill_mask(width, height, scale=8, inset=0.0):
    """A fully rounded pill's coverage, drawn big and shrunk for smooth edges."""
    big = Image.new("L", (width * scale, height * scale), 0)
    i = inset * scale
    r = (height * scale - 2 * i) / 2
    ImageDraw.Draw(big).rounded_rectangle((i, i, width * scale - 1 - i, height * scale - 1 - i), radius=r, fill=255)
    return big.resize((width, height), Image.LANCZOS)


def solid(size, color, mask):
    layer = Image.new("RGBA", size, color[:3] + (0,))
    alpha = mask.point(lambda a: a * color[3] // 255)
    layer.putalpha(alpha)
    return layer


def vertical(size, stops, mask):
    """White with alpha following `stops` [(y fraction, alpha 0-255)...] down the shape."""
    w, h = size
    column = Image.new("L", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        a = stops[-1][1]
        for (t0, a0), (t1, a1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                a = a0 + (a1 - a0) * (t - t0) / max(t1 - t0, 1e-6)
                break
        column.putpixel((0, y), int(a))
    alpha = Image.composite(column.resize(size), Image.new("L", size, 0), mask)
    layer = Image.new("RGBA", size, WHITE + (0,))
    layer.putalpha(alpha)
    return layer


def inner_edge(mask, dx, dy, alpha, blur=0.6):
    """Light caught just inside the edge on one side (CSS's inset box-shadow)."""
    shifted = Image.new("L", mask.size, 0)
    shifted.paste(mask, (dx, dy))
    edge = Image.composite(Image.new("L", mask.size, 0), mask, shifted)
    edge = edge.filter(ImageFilter.GaussianBlur(blur)) if blur else edge
    edge = Image.composite(edge, Image.new("L", mask.size, 0), mask)
    layer = Image.new("RGBA", mask.size, WHITE + (0,))
    layer.putalpha(edge.point(lambda a: a * alpha // 255))
    return layer


def ring(mask, width_px):
    """The band `width_px` wide just inside a shape's edge."""
    inner = mask.filter(ImageFilter.MinFilter(int(width_px * 2) + 1)) if width_px >= 1 else mask
    return Image.composite(Image.new("L", mask.size, 0), mask, inner)


def glass_bar():
    size = (BAR_W, BAR_H)
    mask = pill_mask(*size)
    img = solid(size, (36, 28, 66, 150), mask)
    img.alpha_composite(vertical(size, [(0, 34), (0.42, 8), (0.62, 0), (1, 0)], mask))
    border = ring(mask, 1)
    img.alpha_composite(solid(size, (255, 255, 255, 30), border))
    img.alpha_composite(inner_edge(mask, 0, 1, 64))
    img.alpha_composite(inner_edge(mask, 0, -1, 14))
    return img


def glass_shadow():
    """The bar's shadow on the page: a wide soft one and a closer, darker one."""
    w, h = BAR_W + SHADOW_PAD * 2, BAR_H + SHADOW_PAD * 2

    def offset(dy, blur, alpha):
        mask = Image.new("L", (w, h), 0)
        mask.paste(pill_mask(BAR_W, BAR_H), (SHADOW_PAD, SHADOW_PAD + dy))
        return mask.filter(ImageFilter.GaussianBlur(blur)).point(lambda a: a * alpha // 255)

    img = Image.new("RGBA", (w, h), (8, 5, 20, 0))
    img.putalpha(ImageChops.screen(offset(10, 14, 120), offset(2, 4, 70)))
    return img


def lens_glass():
    """The lens's light: a bright top edge, a fainter bottom one, a lavender glow
    inside and a highlight across its top, as on a curved drop of glass."""
    size = (LENS_W, LENS_H)
    mask = pill_mask(*size)
    img = Image.new("RGBA", size, WHITE + (0,))
    glow = Image.composite(Image.new("L", size, 0), mask, mask.filter(ImageFilter.MinFilter(9))).filter(ImageFilter.GaussianBlur(6))
    glow = Image.composite(glow, Image.new("L", size, 0), mask).point(lambda a: a * 40 // 255)
    lav = Image.new("RGBA", size, (201, 184, 255, 0))
    lav.putalpha(glow)
    img.alpha_composite(lav)
    img.alpha_composite(inner_edge(mask, 1, 2, 150, 0.8))
    img.alpha_composite(inner_edge(mask, -1, -1, 60, 0.8))
    hl_w, hl_h = int(LENS_W * 0.84), int(LENS_H * 0.46)
    hl_mask = pill_mask(hl_w, hl_h)
    highlight = vertical((hl_w, hl_h), [(0, 72), (1, 0)], hl_mask)
    img.alpha_composite(highlight, (int(LENS_W * 0.08), int(LENS_H * 0.04) + 1))
    return img


def lens_rim():
    """The lens's rim catching colour, as glass does: pink, lavender, sky, mint, butter."""
    size = (LENS_W, LENS_H)
    scale = 4
    W, H = LENS_W * scale, LENS_H * scale
    mask = pill_mask(W, H, scale=2)
    band = ring(mask, 1.5 * scale)
    stops = [(255, 158, 207, 204), (185, 163, 255, 204), (140, 220, 255, 191), (170, 255, 200, 166), (255, 217, 138, 191), (255, 158, 207, 204)]
    img = Image.new("RGBA", (W, H))
    px = img.load()
    bp = band.load()
    cx, cy = W / 2, H / 2
    for y in range(H):
        for x in range(W):
            a = bp[x, y]
            if not a:
                continue
            # CSS conic-gradient(from 210deg): angles clockwise from straight up.
            angle = (math.degrees(math.atan2(x - cx, cy - y)) - 210) % 360
            t = angle / 360 * (len(stops) - 1)
            i = min(int(t), len(stops) - 2)
            f = t - i
            c = [stops[i][k] + (stops[i + 1][k] - stops[i][k]) * f for k in range(4)]
            px[x, y] = (int(c[0]), int(c[1]), int(c[2]), int(c[3] * a / 255))
    return img.resize(size, Image.LANCZOS)


def glass_pill(radius=4):
    """A sheen and rim laid over a button's tinted pill (Pills.brs). A 9-patch whose
    stretch row sits below the sheen, so the sheen keeps its height on any button."""
    w, h, stretch_y = radius * 2 + 2, 30, 21
    scale = 8
    big = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), radius=radius * scale, fill=255)
    mask = big.resize((w, h), Image.LANCZOS)
    body = vertical((w, h), [(0, 30), (0.5, 0), (1, 0)], mask)
    body.alpha_composite(solid((w, h), (255, 255, 255, 34), ring(mask, 1)))
    body.alpha_composite(inner_edge(mask, 0, 1, 56, 0))
    img = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    img.paste(body, (1, 1))
    px = img.load()
    for i in (1 + radius, 2 + radius):
        px[i, 0] = (0, 0, 0, 255)
    for i in (stretch_y, stretch_y + 1):
        px[0, i] = (0, 0, 0, 255)
    return img


# --- Intro -------------------------------------------------------------------------------
#
# The intro when ARAN+ opens (components/Intro.brs), after the web app's: ARAN punches
# in out of a glow with light rays bursting behind it, the plus spins and sparks, then it
# flies through the plus into the app. Its pieces, and where they sit (intro.json).

INTRO_SIZE = 124  # the letters' font size on a 1280x720 screen
INTRO_PAD = 32  # room for each piece's glow


def intro_letter(ch, font):
    ascent, descent = font.getmetrics()
    w = int(font.getlength(ch)) + INTRO_PAD * 2
    h = ascent + descent + INTRO_PAD * 2
    scale = 2
    big = Image.new("L", (w * scale, h * scale), 0)
    big_font = ImageFont.truetype(str(FONT_DISPLAY), INTRO_SIZE * scale)
    ImageDraw.Draw(big).text((INTRO_PAD * scale, INTRO_PAD * scale), ch, font=big_font, fill=255)
    mask = big.resize((w, h), Image.LANCZOS)
    glow = mask.filter(ImageFilter.GaussianBlur(12)).point(lambda a: min(255, a * 115 // 255))
    img = Image.new("RGBA", (w, h), (201, 184, 255, 0))
    img.putalpha(glow)
    img.alpha_composite(solid((w, h), (247, 243, 255, 255), mask))
    return img


def intro_plus(size, glow=True, color=PINK):
    """The plus: two rounded bars, 0.18 of its size thick, with a pink glow."""
    pad = INTRO_PAD if glow else 4
    w = size + pad * 2
    scale = 8
    big = Image.new("L", (w * scale, w * scale), 0)
    d = ImageDraw.Draw(big)
    bar = size * 0.3
    r = bar / 2
    o = pad
    d.rounded_rectangle(((o) * scale, (o + size / 2 - r) * scale, (o + size) * scale, (o + size / 2 + r) * scale), radius=r * scale, fill=255)
    d.rounded_rectangle(((o + size / 2 - r) * scale, (o) * scale, (o + size / 2 + r) * scale, (o + size) * scale), radius=r * scale, fill=255)
    mask = big.resize((w, w), Image.LANCZOS)
    img = Image.new("RGBA", (w, w), color + (0,))
    if glow:
        near = mask.filter(ImageFilter.GaussianBlur(size * 0.12)).point(lambda a: a * 230 // 255)
        far = mask.filter(ImageFilter.GaussianBlur(size * 0.34)).point(lambda a: a * 115 // 255)
        img.putalpha(ImageChops.screen(near, far))
    img.alpha_composite(solid((w, w), color + (255,), mask))
    return img


def intro_ray():
    """A thin streak of light, clear at both ends; tinted per ray."""
    w, h = 256, 6
    img = Image.new("RGBA", (w, h), WHITE + (0,))
    px = img.load()
    for x in range(w):
        t = x / (w - 1)
        a = t / 0.3 if t < 0.3 else (1 - t) / 0.7
        for y in range(h):
            edge = 1 - abs(y - (h - 1) / 2) / (h / 2)
            px[x, y] = WHITE + (int(255 * a * min(1, edge * 1.6)),)
    return img


def intro_spark():
    size = 28
    img = Image.new("RGBA", (size, size), PINK + (0,))
    mask = Image.new("L", (size * 8, size * 8), 0)
    c = size * 4
    ImageDraw.Draw(mask).ellipse((c - 20, c - 20, c + 20, c + 20), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    img.putalpha(mask.filter(ImageFilter.GaussianBlur(4)).point(lambda a: min(255, a * 3)))
    img.alpha_composite(solid((size, size), (255, 255, 255, 255), mask))
    return img


def intro_glow():
    """The boom's glow: lavender in the middle, pink further out, gone by half way."""
    size = 256
    img = Image.new("RGBA", (size, size))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            t = math.hypot(x - c, y - c) / c
            if t < 0.44:
                k = t / 0.44
                col = [201 + (255 - 201) * k, 184 + (158 - 184) * k, 255 + (207 - 255) * k]
                a = 0.55 + (0.22 - 0.55) * k
            else:
                k = min((t - 0.44) / 0.52, 1)
                col = [255, 158, 207]
                a = 0.22 * (1 - smooth(k))
            px[x, y] = (int(col[0]), int(col[1]), int(col[2]), int(255 * a))
    return img


def intro_background(width, height):
    """radial-gradient(120% 90% at 50% 45%, #1d1638, #0d0a1a 70%), lightly dithered."""
    img = Image.new("RGB", (width, height))
    px = img.load()
    inner, outer = (29, 22, 56), (13, 10, 26)
    rx, ry = width * 1.2 / 2, height * 0.9 / 2
    rnd = random.Random(3)
    for y in range(height):
        for x in range(width):
            t = min(math.hypot((x - width * 0.5) / rx, (y - height * 0.45) / ry) / 0.7, 1)
            px[x, y] = tuple(max(0, min(255, int(inner[i] + (outer[i] - inner[i]) * t + rnd.random() - 0.5))) for i in range(3))
    return img


def intro_pieces():
    """The intro's images, and intro.json: where each sits in the logo, whose top-left
    is (0, 0). The plus is drawn, not typed, so its middle is its box's middle, which the
    flight through it centres on."""
    font = ImageFont.truetype(str(FONT_DISPLAY), INTRO_SIZE)
    ascent, _ = font.getmetrics()
    layout = {"letters": [], "fontSize": INTRO_SIZE}
    x = 0
    for i, ch in enumerate(NAME):
        img = intro_letter(ch, font)
        name = "intro_" + ch.lower() + ".png"
        img.save(OUT / name)
        advance = font.getlength(ch)
        layout["letters"].append({"uri": "pkg:/images/" + name, "x": round(x) - INTRO_PAD, "y": -INTRO_PAD, "w": img.width, "h": img.height})
        x += advance + 1
    plus = round(INTRO_SIZE * 0.6)
    plus_left = x + INTRO_SIZE * 0.09
    plus_mid_y = ascent - INTRO_SIZE * 0.05 - plus / 2
    plus_img = intro_plus(plus)
    plus_img.save(OUT / "intro_plus.png")
    intro_plus(plus, glow=False, color=WHITE).save(OUT / "intro_plus_flash.png")
    # Without its glow, for the flight through it: a glow made 70 times bigger looks blocky.
    intro_plus(plus, glow=False).save(OUT / "intro_plus_core.png")
    layout["plus"] = {
        "x": round(plus_left) - INTRO_PAD,
        "y": round(plus_mid_y - plus / 2) - INTRO_PAD,
        "w": plus_img.width,
        "h": plus_img.height,
        "size": plus,
        "flashPad": 4,
    }
    layout["width"] = round(plus_left + plus)
    layout["height"] = ascent
    (OUT / "intro.json").write_text(json.dumps(layout, indent=1) + "\n")
    intro_ray().save(OUT / "intro_ray.png")
    intro_spark().save(OUT / "intro_spark.png")
    intro_glow().save(OUT / "intro_glow.png")
    intro_background(320, 180).save(OUT / "intro_bg.png")
    return layout, plus_img


def intro_splash(width, height, layout, plus_img):
    """The splash screen is the intro's first frame: the plus alone, where the logo
    will be, so the intro carries straight on from it."""
    img = intro_background(width // 4, height // 4).resize((width, height), Image.BICUBIC).convert("RGBA")
    scale = width / 1280
    left = (1280 - layout["width"]) / 2
    top = (720 - layout["height"]) / 2
    p = layout["plus"]
    piece = plus_img.resize((round(plus_img.width * scale), round(plus_img.height * scale)), Image.LANCZOS)
    img.alpha_composite(piece, (round((left + p["x"]) * scale), round((top + p["y"]) * scale)))
    return img.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in ("wordmark.png",):
        (OUT / old).unlink(missing_ok=True)
    brand_card(290, 218, 44).save(OUT / "icon_hd.png")
    brand_card(540, 405, 82).save(OUT / "icon_fhd.png")
    layout, plus_img = intro_pieces()
    intro_splash(1280, 720, layout, plus_img).save(OUT / "splash_hd.png")
    intro_splash(1920, 1080, layout, plus_img).save(OUT / "splash_fhd.png")
    mark = wordmark_image(30)
    mark.resize((mark.width // 4, mark.height // 4), Image.LANCZOS).save(OUT / "logo.png")
    fade(440, 540, "left").save(OUT / "fade_left.png")
    fade(960, 260, "bottom").save(OUT / "fade_bottom.png")
    fade(1280, 140, "top", 230).save(OUT / "fade_top.png")
    # Small, sharp corners in the Netflix manner: buttons, cards, poster corners and the
    # focus ring all share a 3-4 px radius.
    nine_patch(rounded(4), 4).save(OUT / "pill.9.png")
    nine_patch(rounded(4), 4).save(OUT / "card.9.png")
    nine_patch(corner_mask(3), 3).save(OUT / "corners.9.png")
    nine_patch(rounded(5, outline_width=3), 5).save(OUT / "ring.9.png")
    glow_png(256).save(OUT / "glow.png")
    glass_bar().save(OUT / "glass_bar.png")
    glass_shadow().save(OUT / "glass_shadow.png")
    lens = Image.new("RGBA", (LENS_W, LENS_H), WHITE + (0,))
    lens.putalpha(pill_mask(LENS_W, LENS_H))
    lens.save(OUT / "lens_fill.png")
    lens_glass().save(OUT / "lens_glass.png")
    lens_rim().save(OUT / "lens_rim.png")
    glass_pill().save(OUT / "glass_pill.9.png")
    player_icons()
    for p in sorted(OUT.iterdir()):
        if p.suffix == ".png":
            print(p.name, Image.open(p).size)


if __name__ == "__main__":
    main()
