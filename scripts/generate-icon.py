#!/usr/bin/env python3
"""Generate Cocxy Terminal app icon - clean, minimalist, powerful.

Design: Dark rounded square with terminal prompt ">", cursor block,
and three connected neural dots representing AI agent awareness.
No text label — the Dock shows the app name.
"""

from PIL import Image, ImageDraw, ImageFont
import os
import json


# Catppuccin Mocha colors
CRUST = (17, 17, 27)
BASE = (30, 30, 46)
SURFACE1 = (69, 71, 90)
BLUE = (137, 180, 250)
LAVENDER = (180, 190, 254)
GREEN = (166, 227, 161)


def create_icon(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    s = size
    padding = int(s * 0.04)
    icon_size = s - padding * 2
    corner = int(icon_size * 0.22)

    # Outer rounded rect (Crust)
    draw.rounded_rectangle(
        [padding, padding, s - padding, s - padding],
        radius=corner, fill=CRUST
    )

    # Inner rounded rect (Base)
    inner = int(s * 0.08)
    draw.rounded_rectangle(
        [inner, inner, s - inner, s - inner],
        radius=int(corner * 0.85), fill=BASE
    )

    # Terminal prompt ">"
    prompt_size = int(s * 0.38)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFMono-Bold.otf", prompt_size)
    except (IOError, OSError):
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", prompt_size)
        except (IOError, OSError):
            font = ImageFont.load_default()

    prompt_x = int(s * 0.14)
    prompt_y = int(s * 0.24)
    draw.text((prompt_x, prompt_y), ">", fill=BLUE, font=font)

    # Cursor block (lavender)
    cx = int(s * 0.50)
    cy = int(s * 0.30)
    cw = int(s * 0.055)
    ch = int(s * 0.28)
    draw.rounded_rectangle(
        [cx, cy, cx + cw, cy + ch],
        radius=int(cw * 0.3), fill=LAVENDER
    )

    # AI neural dots — larger for visibility at small sizes
    dot_r = int(s * 0.045)
    dots = [
        (int(s * 0.60), int(s * 0.72), BLUE),    # bottom-left
        (int(s * 0.76), int(s * 0.72), BLUE),    # bottom-right
        (int(s * 0.68), int(s * 0.58), GREEN),   # top (active agent)
    ]

    # Connecting lines
    line_color = (*SURFACE1, 150)
    line_w = max(2, int(s * 0.007))
    for i in range(len(dots)):
        for j in range(i + 1, len(dots)):
            draw.line(
                [(dots[i][0], dots[i][1]), (dots[j][0], dots[j][1])],
                fill=line_color, width=line_w
            )

    # Draw dots with glow
    for (cx, cy, color) in dots:
        glow_r = int(dot_r * 1.6)
        glow_color = (*color, 50)
        draw.ellipse(
            [cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r],
            fill=glow_color
        )
        draw.ellipse(
            [cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r],
            fill=color
        )

    return img


def main():
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assets_dir = os.path.join(
        project_root, "Sources", "App", "Assets.xcassets", "AppIcon.appiconset"
    )
    os.makedirs(assets_dir, exist_ok=True)

    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    master = create_icon(1024)
    for filename, size in sizes.items():
        filepath = os.path.join(assets_dir, filename)
        if size == 1024:
            master.save(filepath, "PNG")
        else:
            resized = master.resize((size, size), Image.LANCZOS)
            resized.save(filepath, "PNG")
        print(f"  {filename} ({size}x{size})")

    contents = {
        "images": [
            {"filename": f"icon_{s}x{s}{'@2x' if sc == '2x' else ''}.png",
             "idiom": "mac", "scale": sc, "size": f"{s}x{s}"}
            for s, sc in [(16, "1x"), (16, "2x"), (32, "1x"), (32, "2x"),
                          (128, "1x"), (128, "2x"), (256, "1x"), (256, "2x"),
                          (512, "1x"), (512, "2x")]
        ],
        "info": {"author": "xcode", "version": 1}
    }
    with open(os.path.join(assets_dir, "Contents.json"), 'w') as f:
        json.dump(contents, f, indent=2)

    print(f"\nIcon at: {assets_dir}")


if __name__ == "__main__":
    main()
