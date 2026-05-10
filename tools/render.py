#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = [
#   "moderngl",
#   "numpy",
#   "Pillow",
# ]
# ///
"""Render a Ghostty (Shadertoy-format) GLSL shader to a PNG preview.

Usage:
    uv run tools/render.py shaders/white-bear.glsl previews/white-bear.png
    uv run tools/render.py shaders/foo.glsl previews/foo.png --time 2.5 -w 1600 -H 1000
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import moderngl
import numpy as np
from PIL import Image, ImageDraw, ImageFont


VERTEX_SHADER = """
#version 330
in vec2 in_position;
out vec2 v_uv;
void main() {
    gl_Position = vec4(in_position, 0.0, 1.0);
    v_uv = in_position * 0.5 + 0.5;
}
"""

FRAGMENT_HEADER = """\
#version 330
in vec2 v_uv;
out vec4 out_color;

uniform vec3 iResolution;
uniform float iTime;
uniform sampler2D iChannel0;

"""

FRAGMENT_FOOTER = """
void main() {
    vec2 fragCoord = v_uv * iResolution.xy;
    vec4 fc;
    mainImage(fc, fragCoord);
    out_color = fc;
}
"""


def make_terminal_sample(width: int, height: int) -> np.ndarray:
    """Sample terminal contents for iChannel0 — dark bg with a fake prompt."""
    img = Image.new("RGB", (width, height), (16, 18, 22))
    draw = ImageDraw.Draw(img)

    font = None
    for candidate in (
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/System/Library/Fonts/Monaco.ttf",
    ):
        try:
            font = ImageFont.truetype(candidate, 15)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()

    fg = (180, 195, 210)
    dim = (110, 125, 140)
    prompt_color = (130, 200, 150)

    lines: list[tuple[str, tuple[int, int, int]]] = [
        ("matt@ghostty ~/code/ghostty-shaders $ ls shaders/", prompt_color),
        ("white-bear.glsl", fg),
        ("matt@ghostty ~/code/ghostty-shaders $ cat shaders/white-bear.glsl | head -3", prompt_color),
        ("// White Bear glyph — subtle breathing watermark", dim),
        ("float sdBox(vec2 p, vec2 b) {", fg),
        ("    vec2 d = abs(p) - b;", fg),
        ("matt@ghostty ~/code/ghostty-shaders $ █", prompt_color),
    ]

    y = 28
    for text, color in lines:
        draw.text((28, y), text, font=font, fill=color)
        y += 24

    return np.array(img, dtype=np.uint8)


def render(shader_path: Path, output_path: Path, width: int, height: int, time_value: float) -> None:
    shader_src = shader_path.read_text()
    fragment_shader = FRAGMENT_HEADER + shader_src + FRAGMENT_FOOTER

    ctx = moderngl.create_context(standalone=True, require=330)
    fbo = ctx.simple_framebuffer((width, height))
    fbo.use()

    try:
        prog = ctx.program(vertex_shader=VERTEX_SHADER, fragment_shader=fragment_shader)
    except moderngl.Error as exc:
        print(f"Shader compile error in {shader_path}:\n{exc}", file=sys.stderr)
        sys.exit(1)

    prog["iResolution"].value = (float(width), float(height), 1.0)
    prog["iTime"].value = float(time_value)

    term_data = make_terminal_sample(width, height)
    term_data = np.flipud(term_data)  # PIL is top-down; GL textures are bottom-up
    tex = ctx.texture((width, height), 3, term_data.tobytes())
    tex.use(0)
    prog["iChannel0"].value = 0

    quad = ctx.buffer(np.array([-1, -1, 1, -1, -1, 1, 1, 1], dtype="f4"))
    vao = ctx.simple_vertex_array(prog, quad, "in_position")

    fbo.clear(0.0, 0.0, 0.0, 1.0)
    vao.render(moderngl.TRIANGLE_STRIP)

    img = Image.frombytes("RGB", (width, height), fbo.read(components=3))
    img = img.transpose(Image.FLIP_TOP_BOTTOM)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(output_path)
    print(f"{shader_path.name} → {output_path}  ({width}x{height}, iTime={time_value})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else None)
    parser.add_argument("shader", type=Path, help="Path to .glsl shader")
    parser.add_argument("output", type=Path, help="Path to output PNG")
    parser.add_argument("-w", "--width", type=int, default=1200)
    parser.add_argument("-H", "--height", type=int, default=750)
    parser.add_argument("-t", "--time", type=float, default=0.0, help="iTime value (controls animation phase)")
    args = parser.parse_args()

    render(args.shader, args.output, args.width, args.height, args.time)


if __name__ == "__main__":
    main()
