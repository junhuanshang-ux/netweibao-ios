#!/usr/bin/env python3
"""Generate the 1024x1024 App Store icon for 网维宝."""

from pathlib import Path
import math

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "NetWeiBao" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"

S = 2048


def lerp_color(start, end, t):
    return tuple(int(start[i] + (end[i] - start[i]) * t) for i in range(3))


def main():
    # Deep ocean gradient.
    img = Image.new("RGB", (S, S), (5, 8, 15))
    draw = ImageDraw.Draw(img)
    top = (4, 12, 20)
    bottom = (5, 30, 31)
    for y in range(S):
        draw.line([(0, y), (S, y)], fill=lerp_color(top, bottom, y / (S - 1)))

    # Teal glow behind the network.
    glow = Image.new("L", (S, S), 0)
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((S * 0.12, S * 0.00, S * 0.95, S * 0.84), fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.11))
    teal = Image.new("RGB", (S, S), (20, 210, 165))
    img = Image.composite(teal, img, glow.point(lambda p: int(p * 0.34)))

    # Blue glow at the bottom.
    blue_glow = Image.new("L", (S, S), 0)
    blue_draw = ImageDraw.Draw(blue_glow)
    blue_draw.ellipse((S * 0.45, S * 0.58, S * 1.10, S * 1.08), fill=130)
    blue_glow = blue_glow.filter(ImageFilter.GaussianBlur(S * 0.10))
    blue = Image.new("RGB", (S, S), (40, 100, 220))
    img = Image.composite(blue, img, blue_glow.point(lambda p: int(p * 0.28)))

    # Blueprint grid.
    grid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    step = S // 14
    for index in range(1, 14):
        position = index * step
        grid_draw.line([(position, 0), (position, S)], fill=(120, 220, 210, 14), width=2)
        grid_draw.line([(0, position), (S, position)], fill=(120, 220, 210, 14), width=2)
    img = Image.alpha_composite(img.convert("RGBA"), grid)

    nodes = [
        (0.50, 0.27),
        (0.29, 0.50),
        (0.72, 0.50),
        (0.38, 0.74),
        (0.64, 0.74),
        (0.50, 0.52),
    ]
    edges = [
        (0, 1),
        (0, 2),
        (1, 3),
        (2, 4),
        (3, 4),
        (0, 5),
        (1, 5),
        (2, 5),
        (3, 5),
        (4, 5),
    ]

    lines = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    line_draw = ImageDraw.Draw(lines)
    for start, end in edges:
        line_draw.line(
            [
                (int(nodes[start][0] * S), int(nodes[start][1] * S)),
                (int(nodes[end][0] * S), int(nodes[end][1] * S)),
            ],
            fill=(75, 235, 195, 215),
            width=8,
        )

    img = Image.alpha_composite(img, lines.filter(ImageFilter.GaussianBlur(24)))
    img = Image.alpha_composite(img, lines)

    # Halo around every outer node.
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    halo_draw = ImageDraw.Draw(halo)
    for index, (x, y) in enumerate(nodes[:5]):
        radius = S * (0.074 if index == 0 else 0.052)
        halo_draw.ellipse(
            (x * S - radius, y * S - radius, x * S + radius, y * S + radius),
            fill=(65, 235, 190, 170),
        )
    img = Image.alpha_composite(img, halo.filter(ImageFilter.GaussianBlur(30)))

    # Solid nodes.
    node_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    node_draw = ImageDraw.Draw(node_layer)
    for index, (x, y) in enumerate(nodes[:5]):
        radius = S * (0.043 if index == 0 else 0.031)
        node_draw.ellipse(
            (x * S - radius, y * S - radius, x * S + radius, y * S + radius),
            fill=(5, 20, 23, 255),
            outline=(135, 255, 225, 255),
            width=9,
        )
        dot = S * 0.0095
        node_draw.ellipse(
            (x * S - dot, y * S - dot, x * S + dot, y * S + dot),
            fill=(150, 255, 228, 255),
        )

    # A faint inner ring at the hub.
    cx, cy = nodes[5]
    ring = S * 0.105
    node_draw.arc(
        (cx * S - ring, cy * S - ring, cx * S + ring, cy * S + ring),
        start=200,
        end=520,
        fill=(95, 160, 255, 190),
        width=6,
    )
    img = Image.alpha_composite(img, node_layer)

    # Signal trace across the bottom.
    trace = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    trace_draw = ImageDraw.Draw(trace)
    points = []
    for index in range(161):
        t = index / 160
        x = S * (0.13 + 0.74 * t)
        envelope = math.exp(-((t - 0.5) ** 2) * 5.0)
        y = S * (0.875 + 0.05 * math.sin(t * math.pi * 6) * envelope)
        points.append((x, y))
    trace_draw.line(points, fill=(100, 165, 255, 225), width=7)
    img = Image.alpha_composite(img, trace.filter(ImageFilter.GaussianBlur(12)))
    img = Image.alpha_composite(img, trace)

    # Quiet top highlight.
    highlight = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.ellipse((S * 0.08, -S * 0.25, S * 0.92, S * 0.22), fill=(255, 255, 255, 10))
    img = Image.alpha_composite(img, highlight.filter(ImageFilter.GaussianBlur(80)))

    final = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    final.save(OUTPUT, "PNG", optimize=True)
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
