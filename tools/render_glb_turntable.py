#!/usr/bin/env python3
"""Render textured GLB turntable views with trimesh and ModernGL."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageOps


VERTEX_SHADER = """
#version 330
uniform mat4 mvp;
uniform mat4 model;
in vec3 in_position;
in vec3 in_normal;
in vec2 in_uv;
out vec3 world_normal;
out vec2 uv;
void main() {
    gl_Position = mvp * vec4(in_position, 1.0);
    world_normal = mat3(model) * in_normal;
    uv = in_uv;
}
"""


FRAGMENT_SHADER = """
#version 330
uniform sampler2D base_color;
uniform vec3 light_direction;
in vec3 world_normal;
in vec2 uv;
out vec4 fragment_color;
void main() {
    vec3 normal = normalize(world_normal);
    float diffuse = abs(dot(normal, normalize(light_direction)));
    float illumination = 0.82 + 0.18 * diffuse;
    vec4 albedo = texture(base_color, uv);
    fragment_color = vec4(albedo.rgb * illumination, albedo.a);
}
"""


VIEW_NAMES = ("front", "right", "back", "left")
VIEW_AZIMUTHS = (0.0, 90.0, 180.0, 270.0)


def normalize(vector: np.ndarray) -> np.ndarray:
    length = float(np.linalg.norm(vector))
    if length == 0.0:
        raise ValueError("cannot normalize a zero vector")
    return vector / length


def look_at(eye: np.ndarray, target: np.ndarray, up: np.ndarray) -> np.ndarray:
    forward = normalize(target - eye)
    side = normalize(np.cross(forward, up))
    camera_up = np.cross(side, forward)
    matrix = np.eye(4, dtype=np.float32)
    matrix[0, :3] = side
    matrix[1, :3] = camera_up
    matrix[2, :3] = -forward
    matrix[0, 3] = -np.dot(side, eye)
    matrix[1, 3] = -np.dot(camera_up, eye)
    matrix[2, 3] = np.dot(forward, eye)
    return matrix


def perspective(vertical_fov_degrees: float, aspect: float, near: float, far: float) -> np.ndarray:
    scale = 1.0 / math.tan(math.radians(vertical_fov_degrees) / 2.0)
    matrix = np.zeros((4, 4), dtype=np.float32)
    matrix[0, 0] = scale / aspect
    matrix[1, 1] = scale
    matrix[2, 2] = (far + near) / (near - far)
    matrix[2, 3] = (2.0 * far * near) / (near - far)
    matrix[3, 2] = -1.0
    return matrix


def material_image(mesh: Any) -> Image.Image:
    material = getattr(mesh.visual, "material", None)
    candidates = (
        getattr(material, "baseColorTexture", None),
        getattr(material, "image", None),
    )
    for candidate in candidates:
        if candidate is None:
            continue
        if isinstance(candidate, Image.Image):
            return candidate.convert("RGBA")
        try:
            return Image.fromarray(np.asarray(candidate)).convert("RGBA")
        except Exception:
            continue
    return Image.new("RGBA", (1, 1), (190, 190, 190, 255))


def load_single_mesh(path: Path) -> Any:
    import trimesh

    loaded = trimesh.load(path, force="scene", process=False)
    geometries = list(loaded.geometry.values())
    if len(geometries) != 1:
        raise ValueError(f"expected one geometry, found {len(geometries)}")
    mesh = geometries[0]
    if not hasattr(mesh, "vertices") or not hasattr(mesh, "faces"):
        raise ValueError("GLB geometry is not a triangle mesh")
    return mesh


def make_interleaved(mesh: Any) -> tuple[np.ndarray, np.ndarray]:
    positions = np.asarray(mesh.vertices, dtype=np.float32)
    normals = np.asarray(mesh.vertex_normals, dtype=np.float32)
    uv = getattr(mesh.visual, "uv", None)
    if uv is None:
        uv_array = np.zeros((len(positions), 2), dtype=np.float32)
    else:
        uv_array = np.asarray(uv, dtype=np.float32)
    if positions.shape != normals.shape or uv_array.shape != (len(positions), 2):
        raise ValueError("unexpected position, normal or UV shape")
    interleaved = np.concatenate((positions, normals, uv_array), axis=1).astype(np.float32)
    indices = np.asarray(mesh.faces, dtype=np.uint32).reshape(-1)
    return interleaved, indices


def create_context() -> tuple[Any, str]:
    import moderngl

    errors = []
    for backend in ("egl", None):
        try:
            if backend is None:
                return moderngl.create_standalone_context(require=330), "default"
            return moderngl.create_standalone_context(require=330, backend=backend), backend
        except Exception as error:
            errors.append(f"{backend or 'default'}: {error}")
    raise RuntimeError("failed to create ModernGL context: " + "; ".join(errors))


def render_asset(
    path: Path,
    output_dir: Path,
    size: int,
    *,
    flip_texture_v: bool,
    texture_filter: str,
    brightness: float,
) -> dict[str, Any]:
    import moderngl

    mesh = load_single_mesh(path)
    interleaved, indices = make_interleaved(mesh)
    texture_image = material_image(mesh)
    if flip_texture_v:
        texture_image = ImageOps.flip(texture_image)
    if brightness != 1.0:
        texture_image = ImageEnhance.Brightness(texture_image).enhance(brightness)
    context, backend = create_context()
    program = context.program(vertex_shader=VERTEX_SHADER, fragment_shader=FRAGMENT_SHADER)
    vertex_buffer = context.buffer(interleaved.tobytes())
    index_buffer = context.buffer(indices.tobytes())
    vertex_array = context.vertex_array(
        program,
        [(vertex_buffer, "3f 3f 2f", "in_position", "in_normal", "in_uv")],
        index_buffer=index_buffer,
        index_element_size=4,
    )
    texture = context.texture(texture_image.size, 4, texture_image.tobytes())
    if texture_filter == "mipmap":
        texture.build_mipmaps()
        texture.filter = (moderngl.LINEAR_MIPMAP_LINEAR, moderngl.LINEAR)
    elif texture_filter == "nearest":
        texture.filter = (moderngl.NEAREST, moderngl.NEAREST)
    else:
        # Pixal3D emits a dense atlas with many tiny UV islands and almost no
        # padding. Generated mip levels bleed dark neighboring texels into
        # those islands, so plain linear sampling is the safer review default.
        texture.filter = (moderngl.LINEAR, moderngl.LINEAR)
    texture.repeat_x = True
    texture.repeat_y = True
    texture.use(location=0)
    program["base_color"].value = 0

    color = context.texture((size, size), 4)
    depth = context.depth_renderbuffer((size, size))
    framebuffer = context.framebuffer(color_attachments=[color], depth_attachment=depth)
    context.enable(moderngl.DEPTH_TEST)
    context.disable(moderngl.CULL_FACE)

    bounds = np.asarray(mesh.bounds, dtype=np.float32)
    center = bounds.mean(axis=0)
    extent = bounds[1] - bounds[0]
    radius = float(np.linalg.norm(extent) / 2.0)
    if radius <= 0.0:
        raise ValueError("mesh has empty bounds")
    distance = radius / math.tan(math.radians(34.0) / 2.0) * 1.18
    projection = perspective(34.0, 1.0, max(radius * 0.01, 0.001), distance + radius * 4.0)
    model = np.eye(4, dtype=np.float32)
    program["model"].write(model.T.tobytes())
    program["light_direction"].value = (0.35, 0.75, 0.55)

    output_dir.mkdir(parents=True, exist_ok=True)
    rendered: list[Path] = []
    for name, azimuth_degrees in zip(VIEW_NAMES, VIEW_AZIMUTHS):
        angle = math.radians(azimuth_degrees)
        eye = center + np.array(
            [math.sin(angle) * distance, extent[1] * 0.04, math.cos(angle) * distance],
            dtype=np.float32,
        )
        view = look_at(eye, center, np.array([0.0, 1.0, 0.0], dtype=np.float32))
        mvp = projection @ view @ model
        program["mvp"].write(mvp.T.astype(np.float32).tobytes())
        framebuffer.use()
        framebuffer.clear(0.92, 0.93, 0.94, 1.0, depth=1.0)
        vertex_array.render(mode=moderngl.TRIANGLES)
        pixels = framebuffer.read(components=4, alignment=1)
        image = Image.frombytes("RGBA", (size, size), pixels).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        output = output_dir / f"{name}.png"
        image.convert("RGB").save(output, quality=95)
        rendered.append(output)

    sheet = Image.new("RGB", (size * 2, size * 2), (235, 237, 240))
    draw = ImageDraw.Draw(sheet)
    for index, (name, output) in enumerate(zip(VIEW_NAMES, rendered)):
        tile = Image.open(output).convert("RGB")
        x = (index % 2) * size
        y = (index // 2) * size
        sheet.paste(tile, (x, y))
        draw.rectangle((x + 10, y + 10, x + 112, y + 42), fill=(25, 28, 32))
        draw.text((x + 20, y + 18), name, fill=(255, 255, 255))
    sheet_path = output_dir / "turntable_sheet.png"
    sheet.save(sheet_path, quality=95)

    return {
        "schema": "avengine_glb_turntable_render_v1",
        "status": "passed",
        "glb": str(path.resolve()),
        "backend": backend,
        "size": size,
        "vertex_count": int(len(mesh.vertices)),
        "triangle_count": int(len(mesh.faces)),
        "bounds": bounds.tolist(),
        "texture_size": list(texture_image.size),
        "texture_sampling": {
            "filter": texture_filter,
            "flip_v": flip_texture_v,
            "brightness": brightness,
        },
        "views": [str(path.resolve()) for path in rendered],
        "sheet": str(sheet_path.resolve()),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--size", type=int, default=512)
    texture_orientation = parser.add_mutually_exclusive_group()
    texture_orientation.add_argument(
        "--flip-texture-v",
        dest="flip_texture_v",
        action="store_true",
        help="Use the glTF-correct vertical texture orientation (default).",
    )
    texture_orientation.add_argument(
        "--no-flip-texture-v",
        dest="flip_texture_v",
        action="store_false",
        help="Disable the glTF texture-orientation correction for diagnostics.",
    )
    parser.set_defaults(flip_texture_v=True)
    parser.add_argument(
        "--texture-filter",
        choices=("linear", "nearest", "mipmap"),
        default="linear",
        help="Texture minification mode. Linear avoids Pixal3D UV-atlas mip bleeding.",
    )
    parser.add_argument(
        "--brightness",
        type=float,
        default=1.0,
        help="Preview-only base-color multiplier applied before upload.",
    )
    args = parser.parse_args()
    if args.size < 128 or args.size > 2048:
        raise ValueError("size must be between 128 and 2048")
    if args.brightness <= 0.0 or args.brightness > 4.0:
        raise ValueError("brightness must be greater than 0 and at most 4")
    report = render_asset(
        args.glb,
        args.output_dir,
        args.size,
        flip_texture_v=args.flip_texture_v,
        texture_filter=args.texture_filter,
        brightness=args.brightness,
    )
    report_path = args.output_dir / "render_manifest.json"
    with report_path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
