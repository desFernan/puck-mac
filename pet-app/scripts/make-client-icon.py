"""Turn the full-bleed 1024 iOS export into a macOS app icon set.

macOS does not round app icons for you the way iOS does -- whatever is in the
asset is exactly what the Dock draws. A square iOS export therefore shows up
as a white tile next to every other app's squircle. Big Sur's icon grid puts
the rounded content in the middle 824/1024 of the canvas with a ~185px corner
radius, leaving the rest transparent for the shadow to breathe into.
"""
from PIL import Image, ImageDraw, ImageFilter
import pathlib

REPO = pathlib.Path(__file__).resolve().parent.parent
SRC = REPO / "design" / "client-icon-source-1024.png"
OUT = REPO / "Puck/Resources/Assets.xcassets/AppIconClient.appiconset"

CANVAS = 1024
CONTENT = 824           # Big Sur content square
RADIUS = 185            # its corner radius
SS = 4                  # supersample factor for a clean edge

art = Image.open(SRC).convert("RGBA").resize((CONTENT, CONTENT), Image.LANCZOS)

# Rounded mask, drawn big and downsampled so the curve isn't stair-stepped.
mask = Image.new("L", (CONTENT * SS, CONTENT * SS), 0)
ImageDraw.Draw(mask).rounded_rectangle(
    [0, 0, CONTENT * SS - 1, CONTENT * SS - 1], radius=RADIUS * SS, fill=255
)
mask = mask.resize((CONTENT, CONTENT), Image.LANCZOS)
art.putalpha(mask)

canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
offset = (CANVAS - CONTENT) // 2

# The drop shadow every macOS icon sits on: without it a pale icon looks
# pasted onto the Dock rather than resting on it.
shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 90), (offset, offset + 10), mask)
canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(12)))
canvas.paste(art, (offset, offset), art)

# The ten entries Contents.json already declares.
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = size * scale
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        canvas.resize((px, px), Image.LANCZOS).save(OUT / name)
        print(f"{name}: {px}x{px}")
