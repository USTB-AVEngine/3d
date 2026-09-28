#!/usr/bin/env python3
"""Generate one deterministic Human Sound Source candidate with FLUX.2."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import shutil
import tempfile

from PIL import Image


WORKSPACE_ROOT = Path(
    "/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1"
)
MODEL_ROOT = Path("/data/models/hub/models--black-forest-labs--FLUX.2-klein-4B")
MODEL_REVISION = "e7b7dc27f91deacad38e78976d1f2b499d76a294"
ASSET_IDS = (
    "singer_microphone",
    "phone_call",
    "guitar_player",
    "violin_player",
    "pianist",
    "saxophone_player",
    "flute_player",
    "hand_drum_player",
    "megaphone_speaker",
    "clapping_person",
    "coughing_person",
)
PARAMETERS = {
    "width": 1024,
    "height": 1024,
    "num_inference_steps": 28,
    "guidance_scale": 1.0,
    "max_sequence_length": 512,
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_real_directory(path: Path, description: str) -> Path:
    path = path.absolute()
    if path.is_symlink() or not path.is_dir() or path.resolve() != path:
        raise ValueError(f"{description} must be an existing direct directory: {path}")
    return path


def build_plan(args: argparse.Namespace) -> dict:
    if args.gpu < 0 or args.seed < 0:
        raise ValueError("gpu and seed must be non-negative")
    prompt = " ".join(args.prompt.split())
    negative_prompt = " ".join(args.negative_prompt.split())
    if not prompt or not negative_prompt:
        raise ValueError("prompt and negative-prompt must be non-empty")

    workspace = validate_real_directory(WORKSPACE_ROOT, "workspace root")
    generation_root = validate_real_directory(
        workspace / args.asset_id / "generation", "asset generation root"
    )
    output_root = generation_root / f"flux2_seed_{args.seed}_v1"
    if output_root.exists() or output_root.is_symlink():
        raise FileExistsError(f"refusing to replace output: {output_root}")

    snapshot = MODEL_ROOT / "snapshots" / MODEL_REVISION
    if MODEL_ROOT.is_symlink() or snapshot.is_symlink() or not snapshot.is_dir():
        raise ValueError(f"pinned FLUX.2 snapshot is unavailable: {snapshot}")
    if not (snapshot / "model_index.json").is_file():
        raise ValueError(f"model_index.json is missing: {snapshot}")
    incomplete = sorted(MODEL_ROOT.rglob("*.incomplete"))
    if incomplete:
        raise ValueError(f"model cache contains an incomplete file: {incomplete[0]}")

    effective_prompt = f"{prompt} Avoid: {negative_prompt}."
    return {
        "schema": "human_sound_source_flux2_plan_v1",
        "asset_id": args.asset_id,
        "output_root": str(output_root),
        "gpu": args.gpu,
        "seed": args.seed,
        "prompt": prompt,
        "negative_prompt": negative_prompt,
        "effective_prompt": effective_prompt,
        "model": {
            "name": "black-forest-labs/FLUX.2-klein-4B",
            "snapshot": str(snapshot),
            "revision": MODEL_REVISION,
            "local_files_only": True,
        },
        "parameters": PARAMETERS,
        "runner": {
            "path": str(Path(__file__).resolve()),
            "sha256": sha256_file(Path(__file__).resolve()),
        },
        "packages": {
            name: importlib.metadata.version(name)
            for name in ("torch", "diffusers", "Pillow")
        },
    }


def generate(plan: dict) -> Path:
    os.environ.update(
        {
            "CUDA_VISIBLE_DEVICES": str(plan["gpu"]),
            "HF_HUB_CACHE": "/data/models/hub",
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "PYTORCH_CUDA_ALLOC_CONF": "expandable_segments:True",
        }
    )
    import torch
    from diffusers import Flux2KleinPipeline

    output_root = Path(plan["output_root"])
    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{output_root.name}.", suffix=".staging", dir=output_root.parent
        )
    )
    try:
        pipeline = Flux2KleinPipeline.from_pretrained(
            plan["model"]["snapshot"],
            torch_dtype=torch.bfloat16,
            local_files_only=True,
        ).to("cuda")
        generator = torch.Generator("cuda").manual_seed(plan["seed"])
        result = pipeline(
            image=None,
            prompt=plan["effective_prompt"],
            generator=generator,
            **plan["parameters"],
        )
        if not getattr(result, "images", None) or len(result.images) != 1:
            raise RuntimeError("FLUX.2 did not return exactly one image")
        candidate = result.images[0].convert("RGB")
        expected_size = (plan["parameters"]["width"], plan["parameters"]["height"])
        if candidate.size != expected_size:
            raise RuntimeError(f"unexpected candidate size: {candidate.size}")

        candidate_path = staging / "candidate.png"
        candidate.save(candidate_path, format="PNG", optimize=False, compress_level=6)
        with Image.open(candidate_path) as opened:
            opened.verify()
        manifest = {
            **plan,
            "schema": "human_sound_source_flux2_candidate_v1",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "status": "pending_visual_review",
            "output": {
                "path": str(output_root / "candidate.png"),
                "sha256": sha256_file(candidate_path),
                "size_bytes": candidate_path.stat().st_size,
                "mode": "RGB",
                "size": list(expected_size),
            },
        }
        manifest_path = staging / "generation_manifest.json"
        with manifest_path.open("x", encoding="utf-8") as stream:
            json.dump(manifest, stream, ensure_ascii=False, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.rename(staging, output_root)
        return output_root / "generation_manifest.json"
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset-id", choices=ASSET_IDS, required=True)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--negative-prompt", required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--gpu", type=int, required=True)
    parser.add_argument("--preflight-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan = build_plan(args)
    if args.preflight_only:
        print("HUMAN_FLUX2_PREFLIGHT_OK")
        print(json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    manifest = generate(plan)
    print(f"HUMAN_FLUX2_OK manifest={manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
