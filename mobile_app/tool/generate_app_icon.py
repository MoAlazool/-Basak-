"""Generates the Basak Android launcher icons from the master artwork.

Usage (from mobile_app/):
    python tool/generate_app_icon.py assets/branding/basak_icon_master.webp

Outputs
  * Adaptive icon (Android 8+): mipmap-*/ic_launcher_foreground.png +
    mipmap-*/ic_launcher_background.png, wired by mipmap-anydpi-v26/*.xml.
    Layers are 108dp; the pin + bus sit inside the 72dp safe zone so every
    launcher mask (circle, squircle, teardrop) shows the whole mark.
  * Legacy icons (Android 7 and below): circular mipmap-*/ic_launcher.png and
    ic_launcher_round.png.
  * In-app logo: assets/images/basak_icon.png (circular, transparent corners).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SRC = sys.argv[1]
RES = os.path.join('android', 'app', 'src', 'main', 'res')
CANVAS = 1440            # 108dp layer at 13.33 px/dp
VISIBLE_R = 480          # 72dp safe zone radius on that canvas
ART_CENTER = (640, 635)  # centre of the pin + bus in the master artwork
ART_R = 480              # radius of the artwork disc taken from the master
FEATHER = 44             # soft edge so parallax never shows a seam

DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

art = Image.open(SRC).convert('RGB')


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


# Background gradient sampled from the artwork's own backdrop (left edge of the
# disc, away from the pin) so the foreground disc blends in seamlessly.
top_y, bottom_y = ART_CENTER[1] - ART_R + 60, ART_CENTER[1] + ART_R - 40
sample_x = ART_CENTER[0] - ART_R + 70
top = art.getpixel((sample_x, top_y))
bottom = art.getpixel((sample_x, bottom_y))

background = Image.new('RGB', (CANVAS, CANVAS))
draw = ImageDraw.Draw(background)
offset = CANVAS // 2 - ART_CENTER[1]
for y in range(CANVAS):
    t = min(1.0, max(0.0, ((y - offset) - top_y) / (bottom_y - top_y)))
    draw.line([(0, y), (CANVAS, y)], fill=lerp(top, bottom, t))

# Foreground: the artwork disc with a feathered edge on a transparent layer.
foreground = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
crop = art.crop((ART_CENTER[0] - ART_R, ART_CENTER[1] - ART_R,
                 ART_CENTER[0] + ART_R, ART_CENTER[1] + ART_R))
mask = Image.new('L', crop.size, 0)
ImageDraw.Draw(mask).ellipse((FEATHER // 2, FEATHER // 2,
                              crop.size[0] - FEATHER // 2, crop.size[1] - FEATHER // 2), fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(FEATHER / 3))
crop_rgba = crop.convert('RGBA')
crop_rgba.putalpha(mask)
pos = (CANVAS // 2 - ART_R, CANVAS // 2 - ART_R)
foreground.alpha_composite(crop_rgba, pos)

# Flattened circular icon (legacy launchers + in-app logo).
flat = background.convert('RGBA')
flat.alpha_composite(foreground)
disc = flat.crop((CANVAS // 2 - VISIBLE_R, CANVAS // 2 - VISIBLE_R,
                  CANVAS // 2 + VISIBLE_R, CANVAS // 2 + VISIBLE_R))
SS = 4  # supersampled anti-aliased circle
circle = Image.new('L', (disc.size[0] * SS, disc.size[1] * SS), 0)
ImageDraw.Draw(circle).ellipse((0, 0, circle.size[0] - 1, circle.size[1] - 1), fill=255)
circle = circle.resize(disc.size, Image.LANCZOS)
round_icon = disc.copy()
round_icon.putalpha(circle)

for name, scale in DENSITIES.items():
    folder = os.path.join(RES, f'mipmap-{name}')
    os.makedirs(folder, exist_ok=True)
    layer = round(108 * scale)
    foreground.resize((layer, layer), Image.LANCZOS).save(os.path.join(folder, 'ic_launcher_foreground.png'))
    background.resize((layer, layer), Image.LANCZOS).save(os.path.join(folder, 'ic_launcher_background.png'))
    legacy = round(48 * scale)
    small = round_icon.resize((legacy, legacy), Image.LANCZOS)
    small.save(os.path.join(folder, 'ic_launcher.png'))
    small.save(os.path.join(folder, 'ic_launcher_round.png'))

anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
os.makedirs(anydpi, exist_ok=True)
xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
       '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
       '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
       '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
       '</adaptive-icon>\n')
for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
    with open(os.path.join(anydpi, name), 'w', encoding='utf-8') as fh:
        fh.write(xml)

os.makedirs(os.path.join('assets', 'images'), exist_ok=True)
round_icon.resize((512, 512), Image.LANCZOS).save(os.path.join('assets', 'images', 'basak_icon.png'))
print('icons written; backdrop', top, '->', bottom)
