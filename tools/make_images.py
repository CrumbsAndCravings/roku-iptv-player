"""Generates the channel's bitmap assets (icons, splash, logo, gradients, 9-patches).

Run from the repo root:  python3 tools/make_images.py
Needs Pillow (pip install pillow). Output goes to src/images/.

Palette ("lavender dream"): a deep plum night, lavender for focus, with small
pops of bubblegum pink and butter yellow.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

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


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in ("wordmark.png",):
        (OUT / old).unlink(missing_ok=True)
    brand_card(290, 218, 44).save(OUT / "icon_hd.png")
    brand_card(540, 405, 82).save(OUT / "icon_fhd.png")
    brand_card(1280, 720, 92).save(OUT / "splash_hd.png")
    brand_card(1920, 1080, 138).save(OUT / "splash_fhd.png")
    mark = wordmark_image(30)
    mark.resize((mark.width // 4, mark.height // 4), Image.LANCZOS).save(OUT / "logo.png")
    fade(440, 540, "left").save(OUT / "fade_left.png")
    fade(960, 260, "bottom").save(OUT / "fade_bottom.png")
    fade(1280, 140, "top", 230).save(OUT / "fade_top.png")
    nine_patch(rounded(14), 14).save(OUT / "pill.9.png")
    nine_patch(rounded(10), 10).save(OUT / "card.9.png")
    nine_patch(corner_mask(10), 10).save(OUT / "corners.9.png")
    nine_patch(rounded(15, outline_width=3), 15).save(OUT / "ring.9.png")
    glow_png(256).save(OUT / "glow.png")
    player_icons()
    for p in sorted(OUT.iterdir()):
        print(p.name, Image.open(p).size)


if __name__ == "__main__":
    main()
