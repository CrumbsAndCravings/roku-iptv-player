"""Generates the channel's bitmap assets (icons, splash, gradients, 9-patches).

Run from the repo root:  python3 tools/make_images.py
Needs Pillow (pip install pillow). Output goes to src/images/.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "images"
FONT_BOLD = ROOT / "src" / "fonts" / "Outfit-Bold.ttf"

BG = (11, 11, 15)
AMBER = (245, 184, 61)
WHITE = (245, 245, 247)
NAME = "MARQUEE"


def smooth(t):
    return t * t * (3 - 2 * t)


def tracked_text(draw, xy, text, font, fill, tracking):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + tracking


def tracked_width(draw, text, font, tracking):
    return sum(draw.textlength(ch, font=font) for ch in text) + tracking * (len(text) - 1)


def bulbs(draw, x0, x1, y, radius, gap, color):
    """A row of marquee light bulbs between x0 and x1."""
    count = int((x1 - x0) // gap) + 1
    span = (count - 1) * gap
    start = x0 + ((x1 - x0) - span) / 2
    for i in range(count):
        cx = start + i * gap
        draw.ellipse((cx - radius, y - radius, cx + radius, y + radius), fill=color)


def brand_card(width, height, text_size):
    """Wordmark centred on the background, with a row of bulbs above and below."""
    scale = 4
    img = Image.new("RGB", (width * scale, height * scale), BG)
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(str(FONT_BOLD), text_size * scale)
    tracking = text_size * scale * 0.14
    tw = tracked_width(draw, NAME, font, tracking)
    ascent, descent = font.getmetrics()
    cap = ascent * 0.72
    x = (width * scale - tw) / 2
    y = (height * scale - cap) / 2 - (ascent - cap)
    tracked_text(draw, (x, y), NAME, font, WHITE, tracking)
    r = text_size * scale * 0.06
    gap = text_size * scale * 0.34
    pad = text_size * scale * 0.55
    top = (height * scale - cap) / 2 - pad
    bottom = (height * scale + cap) / 2 + pad
    bulbs(draw, x, x + tw, top, r, gap, AMBER)
    bulbs(draw, x, x + tw, bottom, r, gap, AMBER)
    return img.resize((width, height), Image.LANCZOS)


def wordmark(text_size):
    """Transparent wordmark used in the top nav."""
    scale = 4
    font = ImageFont.truetype(str(FONT_BOLD), text_size * scale)
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    tracking = text_size * scale * 0.14
    tw = tracked_width(probe, NAME, font, tracking)
    ascent, descent = font.getmetrics()
    w, h = int(tw + 8 * scale), int((ascent + descent) + 4 * scale)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    tracked_text(ImageDraw.Draw(img), (4 * scale, 0), NAME, font, AMBER + (255,), tracking)
    return img.resize((w // scale, h // scale), Image.LANCZOS)


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


def nine_patch(radius):
    """White rounded rectangle as an Android-style 9-patch (Roku reads the same format)."""
    scale = 8
    inner = radius * 2 + 2
    big = Image.new("RGBA", (inner * scale, inner * scale), (0, 0, 0, 0))
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, inner * scale - 1, inner * scale - 1), radius=radius * scale, fill=(255, 255, 255, 255)
    )
    body = big.resize((inner, inner), Image.LANCZOS)
    img = Image.new("RGBA", (inner + 2, inner + 2), (0, 0, 0, 0))
    img.paste(body, (1, 1))
    px = img.load()
    for i in (1 + radius, 2 + radius):
        px[i, 0] = (0, 0, 0, 255)  # stretchable columns
        px[0, i] = (0, 0, 0, 255)  # stretchable rows
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


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    brand_card(290, 218, 34).save(OUT / "icon_hd.png")
    brand_card(540, 405, 62).save(OUT / "icon_fhd.png")
    brand_card(1280, 720, 72).save(OUT / "splash_hd.png")
    brand_card(1920, 1080, 108).save(OUT / "splash_fhd.png")
    wordmark(24).save(OUT / "wordmark.png")
    fade(440, 540, "left").save(OUT / "fade_left.png")
    fade(960, 260, "bottom").save(OUT / "fade_bottom.png")
    fade(1280, 140, "top", 230).save(OUT / "fade_top.png")
    nine_patch(8).save(OUT / "pill.9.png")
    player_icons()
    for p in sorted(OUT.iterdir()):
        print(p.name, Image.open(p).size)


if __name__ == "__main__":
    main()
