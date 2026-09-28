#!/usr/bin/env python3
"""Create a non-destructive, meter-scaled runtime GLB from a raw Pixal3D GLB."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
from typing import Any


GLB_MAGIC = 0x46546C67
GLB_VERSION = 2
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_glb(path: Path) -> tuple[dict[str, Any], list[tuple[int, bytes]]]:
    payload = path.read_bytes()
    if len(payload) < 20:
        raise ValueError("truncated GLB")
    magic, version, declared_length = struct.unpack_from("<III", payload, 0)
    if magic != GLB_MAGIC or version != GLB_VERSION:
        raise ValueError("input is not a GLB 2.0 file")
    if declared_length != len(payload):
        raise ValueError("GLB declared length does not match file size")

    chunks: list[tuple[int, bytes]] = []
    offset = 12
    while offset < len(payload):
        if offset + 8 > len(payload):
            raise ValueError("truncated GLB chunk header")
        length, chunk_type = struct.unpack_from("<II", payload, offset)
        offset += 8
        end = offset + length
        if end > len(payload):
            raise ValueError("truncated GLB chunk")
        chunks.append((chunk_type, payload[offset:end]))
        offset = end
    if not chunks or chunks[0][0] != JSON_CHUNK:
        raise ValueError("first GLB chunk is not JSON")
    document = json.loads(chunks[0][1].rstrip(b" \t\r\n\x00").decode("utf-8"))
    return document, chunks[1:]


def encode_glb(document: dict[str, Any], trailing_chunks: list[tuple[int, bytes]]) -> bytes:
    json_payload = json.dumps(
        document, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    json_payload += b" " * ((-len(json_payload)) % 4)
    encoded_chunks = [struct.pack("<II", len(json_payload), JSON_CHUNK) + json_payload]
    for chunk_type, chunk_payload in trailing_chunks:
        if len(chunk_payload) % 4:
            raise ValueError("source GLB contains an unaligned trailing chunk")
        encoded_chunks.append(
            struct.pack("<II", len(chunk_payload), chunk_type) + chunk_payload
        )
    body = b"".join(encoded_chunks)
    return struct.pack("<III", GLB_MAGIC, GLB_VERSION, 12 + len(body)) + body


def accessor_bounds(document: dict[str, Any]) -> tuple[list[float], list[float]]:
    minima: list[list[float]] = []
    maxima: list[list[float]] = []
    accessors = document.get("accessors", [])
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            position_index = primitive.get("attributes", {}).get("POSITION")
            if not isinstance(position_index, int) or position_index >= len(accessors):
                raise ValueError("mesh has an invalid POSITION accessor")
            position = accessors[position_index]
            if "min" not in position or "max" not in position:
                raise ValueError("POSITION accessor has no min/max bounds")
            minima.append([float(value) for value in position["min"]])
            maxima.append([float(value) for value in position["max"]])
    if not minima:
        raise ValueError("GLB contains no bounded mesh primitives")
    return (
        [min(values) for values in zip(*minima)],
        [max(values) for values in zip(*maxima)],
    )


def ensure_simple_pixal_scene(document: dict[str, Any]) -> tuple[int, list[int]]:
    scenes = document.get("scenes", [])
    scene_index = int(document.get("scene", 0))
    if scene_index < 0 or scene_index >= len(scenes):
        raise ValueError("GLB has no valid default scene")
    roots = scenes[scene_index].get("nodes", [])
    if not roots:
        raise ValueError("default scene has no root nodes")
    nodes = document.get("nodes", [])
    for index in roots:
        node = nodes[index]
        if any(field in node for field in ("matrix", "translation", "rotation", "scale")):
            raise ValueError("source scene already has a transformed root node")
    return scene_index, list(roots)


def standardize_document(
    document: dict[str, Any], *, asset_id: str, target_height_m: float, source_sha256: str
) -> dict[str, Any]:
    minimum, maximum = accessor_bounds(document)
    source_height = maximum[1] - minimum[1]
    if source_height <= 0.0:
        raise ValueError("mesh height must be positive")
    scale = target_height_m / source_height
    center_x = (minimum[0] + maximum[0]) / 2.0
    center_z = (minimum[2] + maximum[2]) / 2.0
    translation = [-scale * center_x, -scale * minimum[1], -scale * center_z]

    scene_index, roots = ensure_simple_pixal_scene(document)
    nodes = document.setdefault("nodes", [])
    root_index = len(nodes)
    nodes.append({
        "name": "AVEngineStandardizationRoot",
        "children": roots,
        "matrix": [
            scale, 0.0, 0.0, 0.0,
            0.0, scale, 0.0, 0.0,
            0.0, 0.0, scale, 0.0,
            translation[0], translation[1], translation[2], 1.0,
        ],
        "extras": {
            "asset_id": asset_id,
            "source_sha256": source_sha256,
            "standardization": "center_xz_ground_y_target_height_v1",
            "target_height_m": target_height_m,
        },
    })
    document["scenes"][scene_index]["nodes"] = [root_index]

    material_changes = []
    for index, material in enumerate(document.get("materials", [])):
        pbr = material.setdefault("pbrMetallicRoughness", {})
        before = {
            "metallicFactor": pbr.get("metallicFactor", 1.0),
            "roughnessFactor": pbr.get("roughnessFactor", 1.0),
        }
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 0.8
        material_changes.append({
            "material_index": index,
            "before": before,
            "after": {"metallicFactor": 0.0, "roughnessFactor": 0.8},
        })

    normalized_min = [
        scale * minimum[0] + translation[0],
        scale * minimum[1] + translation[1],
        scale * minimum[2] + translation[2],
    ]
    normalized_max = [
        scale * maximum[0] + translation[0],
        scale * maximum[1] + translation[1],
        scale * maximum[2] + translation[2],
    ]
    return {
        "source_bounds": {"min": minimum, "max": maximum},
        "normalized_bounds_m": {"min": normalized_min, "max": normalized_max},
        "scale": scale,
        "translation": translation,
        "material_changes": material_changes,
        "root_node_index": root_index,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--asset-id", required=True)
    parser.add_argument("--target-height-m", type=float, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--preflight-only", action="store_true")
    args = parser.parse_args()

    source = args.input.resolve()
    output = args.output.resolve()
    if source == output:
        raise ValueError("output must not overwrite the raw input GLB")
    if args.target_height_m <= 0.0 or args.target_height_m > 3.0:
        raise ValueError("target height must be greater than 0 and at most 3 meters")
    if not source.is_file():
        raise FileNotFoundError(source)
    if output.exists() and not args.preflight_only:
        raise FileExistsError(f"refusing to overwrite existing output: {output}")

    source_sha256 = sha256_file(source)
    document, trailing_chunks = read_glb(source)
    source_chunk_hashes = [sha256_bytes(payload) for _, payload in trailing_chunks]
    standardization = standardize_document(
        document,
        asset_id=args.asset_id,
        target_height_m=args.target_height_m,
        source_sha256=source_sha256,
    )
    report: dict[str, Any] = {
        "schema": "human_sound_source_glb_standardization_v1",
        "status": "preflight_passed" if args.preflight_only else "passed",
        "asset_id": args.asset_id,
        "source": {"path": str(source), "sha256": source_sha256},
        "output": {"path": str(output)},
        "target_height_m": args.target_height_m,
        "up_axis": "+Y",
        "forward_axis": "-Z",
        "geometry_preserved": True,
        "texture_payloads_preserved": True,
        "trailing_chunk_sha256": source_chunk_hashes,
        "standardization": standardization,
    }

    if not args.preflight_only:
        encoded = encode_glb(document, trailing_chunks)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(encoded)
        check_document, check_chunks = read_glb(output)
        check_chunk_hashes = [sha256_bytes(payload) for _, payload in check_chunks]
        if check_chunk_hashes != source_chunk_hashes:
            output.unlink(missing_ok=True)
            raise RuntimeError("output changed a non-JSON GLB chunk")
        if len(check_document.get("nodes", [])) != len(document.get("nodes", [])):
            output.unlink(missing_ok=True)
            raise RuntimeError("output GLB JSON validation failed")
        report["output"].update({
            "sha256": sha256_file(output),
            "size_bytes": output.stat().st_size,
        })
        manifest = (args.manifest or output.with_suffix(".manifest.json")).resolve()
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(
            json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        report["manifest"] = str(manifest)

    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
