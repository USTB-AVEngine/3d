#!/usr/bin/env python3
"""Inspect GLB structure without modifying the asset or requiring 3D packages."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
from typing import Any


GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
TRIANGLES_MODE = 4


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_glb_document(path: Path) -> tuple[dict[str, Any], int, int]:
    with path.open("rb") as stream:
        header = stream.read(12)
        if len(header) != 12:
            raise ValueError("truncated GLB header")
        magic, version, declared_length = struct.unpack("<III", header)
        if magic != GLB_MAGIC:
            raise ValueError("not a GLB file")
        if version != 2:
            raise ValueError(f"unsupported GLB version: {version}")
        if declared_length != path.stat().st_size:
            raise ValueError(
                f"declared length {declared_length} differs from file size {path.stat().st_size}"
            )
        chunk_header = stream.read(8)
        if len(chunk_header) != 8:
            raise ValueError("missing GLB JSON chunk")
        chunk_length, chunk_type = struct.unpack("<II", chunk_header)
        if chunk_type != JSON_CHUNK:
            raise ValueError("first GLB chunk is not JSON")
        payload = stream.read(chunk_length)
        if len(payload) != chunk_length:
            raise ValueError("truncated GLB JSON chunk")
    document = json.loads(payload.rstrip(b" \t\r\n\x00").decode("utf-8"))
    return document, version, declared_length


def accessor(document: dict[str, Any], index: int) -> dict[str, Any]:
    accessors = document.get("accessors", [])
    if not isinstance(index, int) or index < 0 or index >= len(accessors):
        raise ValueError(f"invalid accessor index: {index}")
    return accessors[index]


def primitive_counts(
    document: dict[str, Any], primitive: dict[str, Any]
) -> tuple[int, int | None]:
    attributes = primitive.get("attributes", {})
    position_index = attributes.get("POSITION")
    if position_index is None:
        raise ValueError("mesh primitive has no POSITION accessor")
    vertex_count = int(accessor(document, position_index)["count"])
    mode = int(primitive.get("mode", TRIANGLES_MODE))
    if mode != TRIANGLES_MODE:
        return vertex_count, None
    if "indices" in primitive:
        index_count = int(accessor(document, primitive["indices"])["count"])
        if index_count % 3:
            raise ValueError("triangle index count is not divisible by three")
        return vertex_count, index_count // 3
    if vertex_count % 3:
        raise ValueError("non-indexed triangle vertex count is not divisible by three")
    return vertex_count, vertex_count // 3


def local_position_bounds(document: dict[str, Any]) -> dict[str, Any]:
    minima: list[list[float]] = []
    maxima: list[list[float]] = []
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            position_index = primitive.get("attributes", {}).get("POSITION")
            if position_index is None:
                continue
            position = accessor(document, position_index)
            if "min" in position and "max" in position:
                minima.append([float(value) for value in position["min"]])
                maxima.append([float(value) for value in position["max"]])
    if not minima:
        return {"available": False}
    minimum = [min(values) for values in zip(*minima)]
    maximum = [max(values) for values in zip(*maxima)]
    extent = [high - low for low, high in zip(minimum, maximum)]
    return {
        "available": True,
        "minimum": minimum,
        "maximum": maximum,
        "extent": extent,
        "note": "Accessor-local bounds; node transforms are reported separately.",
    }


def inspect(path: Path) -> dict[str, Any]:
    path = path.resolve()
    document, version, declared_length = load_glb_document(path)
    primitive_records: list[dict[str, Any]] = []
    total_vertices = 0
    total_triangles = 0
    all_triangles = True
    for mesh_index, mesh in enumerate(document.get("meshes", [])):
        for primitive_index, primitive in enumerate(mesh.get("primitives", [])):
            vertices, triangles = primitive_counts(document, primitive)
            total_vertices += vertices
            if triangles is None:
                all_triangles = False
            else:
                total_triangles += triangles
            primitive_records.append({
                "mesh_index": mesh_index,
                "primitive_index": primitive_index,
                "mode": int(primitive.get("mode", TRIANGLES_MODE)),
                "vertex_count": vertices,
                "triangle_count": triangles,
                "material_index": primitive.get("material"),
                "attributes": sorted(primitive.get("attributes", {})),
                "extensions": sorted(primitive.get("extensions", {})),
            })
    nodes = document.get("nodes", [])
    transformed_nodes = sum(
        1
        for node in nodes
        if any(field in node for field in ("matrix", "translation", "rotation", "scale"))
    )
    return {
        "schema": "avengine_glb_structure_inspection_v1",
        "status": "passed",
        "path": str(path),
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
        "glb_version": version,
        "declared_length": declared_length,
        "asset_generator": document.get("asset", {}).get("generator"),
        "scene_count": len(document.get("scenes", [])),
        "default_scene": document.get("scene"),
        "node_count": len(nodes),
        "transformed_node_count": transformed_nodes,
        "mesh_count": len(document.get("meshes", [])),
        "primitive_count": len(primitive_records),
        "vertex_count_sum": total_vertices,
        "triangle_count_sum": total_triangles if all_triangles else None,
        "material_count": len(document.get("materials", [])),
        "texture_count": len(document.get("textures", [])),
        "image_count": len(document.get("images", [])),
        "skin_count": len(document.get("skins", [])),
        "animation_count": len(document.get("animations", [])),
        "camera_count": len(document.get("cameras", [])),
        "extensions_used": document.get("extensionsUsed", []),
        "extensions_required": document.get("extensionsRequired", []),
        "local_position_bounds": local_position_bounds(document),
        "primitives": primitive_records,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("glb", type=Path, nargs="+")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    reports = []
    for glb in args.glb:
        report = inspect(glb)
        reports.append(report)
        if args.output_dir:
            args.output_dir.mkdir(parents=True, exist_ok=True)
            output = args.output_dir / f"{glb.stem}.structure.json"
            with output.open("w", encoding="utf-8", newline="\n") as stream:
                json.dump(report, stream, ensure_ascii=False, indent=2, sort_keys=True)
                stream.write("\n")
    print(json.dumps(reports, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
