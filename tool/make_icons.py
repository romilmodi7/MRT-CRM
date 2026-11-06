"""Builds the MRT CRM launcher icons + splash logo from assets/logo_icon.png (run by the GitHub workflow)."""
from PIL import Image, ImageDraw
import os

SRC = Image.open('assets/logo_icon.png').convert('RGBA')
RES = 'android/app/src/main/res'
WHITE = (255, 255, 255, 255)


def logo(size, fill):
    """Logo scaled to `fill` (0-1) of a square canvas of `size`, transparent background."""
    s = int(size * fill)
    l = SRC.resize((s, s), Image.LANCZOS)
    c = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    c.paste(l, ((size - s) // 2, (size - s) // 2), l)
    return c


def tile(size, shape):
    S = size * 4
    bg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    m = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(m)
    if shape == 'round':
        d.ellipse((0, 0, S - 1, S - 1), fill=255)
    else:
        d.rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.22), fill=255)
    bg.paste(Image.new('RGBA', (S, S), WHITE), (0, 0), m)
    bg.alpha_composite(logo(S, 0.92))
    return bg.resize((size, size), Image.LANCZOS)


legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
for d, s in legacy.items():
    p = f'{RES}/mipmap-{d}'
    os.makedirs(p, exist_ok=True)
    tile(s, 'square').save(f'{p}/ic_launcher.png')
    tile(s, 'round').save(f'{p}/ic_launcher_round.png')
    fg = int(s * 108 / 48)           # adaptive icon foreground: 108dp canvas, logo inside the 66% safe zone
    logo(fg, 0.64).save(f'{p}/ic_launcher_foreground.png')

# splash logo shown by Android while the app starts (white rounded card + logo)
card = tile(360, 'square')
os.makedirs(f'{RES}/drawable-xxhdpi', exist_ok=True)
card.save(f'{RES}/drawable-xxhdpi/splash_logo.png')
print('icons ok')
