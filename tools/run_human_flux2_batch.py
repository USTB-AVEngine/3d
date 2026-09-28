#!/usr/bin/env python3
"""Generate a resumable batch of Human Sound Source candidates with FLUX.2."""

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
from typing import Any

from PIL import Image


WORKSPACE_ROOT = Path(
    "/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1"
)
MODEL_ROOT = Path("/data/models/hub/models--black-forest-labs--FLUX.2-klein-4B")
MODEL_REVISION = "e7b7dc27f91deacad38e78976d1f2b499d76a294"
ASSET_IDS = {
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
}
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


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def require_real_file(path: Path, description: str) -> Path:
    path = path.absolute()
    if path.is_symlink() or not path.is_file() or path.resolve() != path:
        raise ValueError(f"{description} must be a direct file: {path}")
    return path


def require_real_directory(path: Path, description: str) -> Path:
    path = path.absolute()
    if path.is_symlink() or not path.is_dir() or path.resolve() != path:
        raise ValueError(f"{description} must be a direct directory: {path}")
    return path


def load_jobs(path: Path) -> list[dict[str, Any]]:
    path = require_real_file(path, "jobs JSON")
    payload = load_json(path)
    if not isinstance(payload, dict) or payload.get("schema") != "human_sound_source_flux2_jobs_v1":
        raise ValueError("invalid Human Flux2 jobs schema")
    jobs = payload.get("jobs")
    if not isinstance(jobs, list) or not jobs:
        raise ValueError("jobs must be a non-empty list")
    seen_assets: set[str] = set()
    seen_seeds: set[int] = set()
    normalized: list[dict[str, Any]] = []
    for job in jobs:
        if not isinstance(job, dict) or set(job) != {
            "asset_id", "seed", "prompt", "negative_prompt"
        }:
            raise ValueError("each job must have exact asset/prompt/seed fields")
        asset_id = job["asset_id"]
        seed = job["seed"]
        prompt = " ".join(str(job["prompt"]).split())
        negative_prompt = " ".join(str(job["negative_prompt"]).split())
        if asset_id not in ASSET_IDS or asset_id in seen_assets:
            raise ValueError(f"invalid or duplicate asset_id: {asset_id!r}")
        if not isinstance(seed, int) or seed < 0 or seed in seen_seeds:
            raise ValueError(f"invalid or duplicate seed: {seed!r}")
        if not prompt or not negative_prompt:
            raise ValueError(f"empty prompt for {asset_id}")
        seen_assets.add(asset_id)
        seen_seeds.add(seed)
        normalized.append({
            "asset_id": asset_id,
            "seed": seed,
            "prompt": prompt,
            "negative_prompt": negative_prompt,
            "effective_prompt": f"{prompt} Avoid: {negative_prompt}.",
        })
    return normalized


def snapshot_path() -> Path:
    snapshot = MODEL_ROOT / "snapshots" / MODEL_REVISION
    if MODEL_ROOT.is_symlink() or snapshot.is_symlink() or not snapshot.is_dir():
        raise ValueError(f"pinned FLUX.2 snapshot is unavailable: {snapshot}")
    if not (snapshot / "model_index.json").is_file():
        raise ValueError(f"model_index.json is missing: {snapshot}")
    incomplete = sorted(MODEL_ROOT.rglob("*.incomplete"))
    if incomplete:
        raise ValueError(f"model cache contains an incomplete file: {incomplete[0]}")
    return snapshot


def expected_output(job: dict[str, Any]) -> Path:
    workspace = require_real_directory(WORKSPACE_ROOT, "workspace root")
    generation = require_real_directory(
        workspace / job["asset_id"] / "generation", "generation root"
    )
    return generation / f"flux2_seed_{job['seed']}_v1"


def validate_existing(job: dict[str, Any], output_root: Path) -> bool:
    candidate = output_root / "candidate.png"
    manifest_path = output_root / "generation_manifest.json"
    if not output_root.exists():
        return False
    if output_root.is_symlink() or not output_root.is_dir():
        raise ValueError(f"invalid existing output root: {output_root}")
    manifest = load_json(require_real_file(manifest_path, "existing manifest"))
    if (
        manifest.get("schema") != "human_sound_source_flux2_candidate_v1"
        or manifest.get("asset_id") != job["asset_id"]
        or manifest.get("seed") != job["seed"]
        or manifest.get("prompt") != job["prompt"]
        or manifest.get("negative_prompt") != job["negative_prompt"]
        or manifest.get("model", {}).get("revision") != MODEL_REVISION
        or manifest.get("parameters") != PARAMETERS
        or manifest.get("output", {}).get("sha256")
        != sha256_file(require_real_file(candidate, "existing candidate"))
    ):
        raise ValueError(f"existing output does not match requested job: {output_root}")
    return True


def generate_one(job: dict[str, Any], pipeline: Any, torch: Any) -> Path:
    output_root = expected_output(job)
    if validate_existing(job, output_root):
        print(f"HUMAN_FLUX2_BATCH_SKIP asset={job['asset_id']} output={output_root}", flush=True)
        return output_root / "generation_manifest.json"
    staging = Path(tempfile.mkdtemp(
        prefix=f".{output_root.name}.", suffix=".staging", dir=output_root.parent
    ))
    try:
        generator = torch.Generator("cuda").manual_seed(job["seed"])
        result = pipeline(
            image=None,
            prompt=job["effective_prompt"],
            generator=generator,
            **PARAMETERS,
        )
        if not getattr(result, "images", None) or len(result.images) != 1:
            raise RuntimeError("FLUX.2 did not return exactly one image")
        candidate_image = result.images[0].convert("RGB")
        if candidate_image.size != (PARAMETERS["width"], PARAMETERS["height"]):
            raise RuntimeError(f"unexpected candidate size: {candidate_image.size}")
        candidate = staging / "candidate.png"
        candidate_image.save(candidate, format="PNG", optimize=False, compress_level=6)
        with Image.open(candidate) as opened:
            opened.verify()
        manifest = {
            "schema": "human_sound_source_flux2_candidate_v1",
            "status": "pending_visual_review",
            "created_at": datetime.now(timezone.utc).isoformat(),
            **job,
            "output_root": str(output_root),
            "model": {
                "name": "black-forest-labs/FLUX.2-klein-4B",
                "snapshot": str(snapshot_path()),
                "revision": MODEL_REVISION,
                "local_files_only": True,
            },
            "parameters": PARAMETERS,
            "runner": {
                "path": str(Path(__file__).resolve()),
                "sha256": sha256_file(Path(__file__).resolve()),
            },
            "output": {
                "path": str(output_root / "candidate.png"),
                "sha256": sha256_file(candidate),
                "size_bytes": candidate.stat().st_size,
                "mode": "RGB",
                "size": [PARAMETERS["width"], PARAMETERS["height"]],
            },
        }
        manifest_path = staging / "generation_manifest.json"
        with manifest_path.open("x", encoding="utf-8") as stream:
            json.dump(manifest, stream, ensure_ascii=False, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.rename(staging, output_root)
        print(f"HUMAN_FLUX2_BATCH_GENERATED asset={job['asset_id']} output={output_root}", flush=True)
        return output_root / "generation_manifest.json"
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs-json", type=Path, required=True)
    parser.add_argument(
        "--asset-id",
        choices=sorted(ASSET_IDS),
        help="Run or preflight only this asset from the jobs file.",
    )
    parser.add_argument("--gpu", type=int, required=True)
    parser.add_argument("--preflight-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.gpu < 0:
        raise ValueError("gpu must be non-negative")
    jobs = load_jobs(args.jobs_json)
    if args.asset_id:
        jobs = [job for job in jobs if job["asset_id"] == args.asset_id]
        if not jobs:
            raise ValueError(f"asset_id is not present in jobs JSON: {args.asset_id}")
    snapshot = snapshot_path()
    plan = {
        "schema": "human_sound_source_flux2_batch_plan_v1",
        "gpu": args.gpu,
        "jobs": [
            {**job, "output_root": str(expected_output(job))} for job in jobs
        ],
        "model_revision": MODEL_REVISION,
        "model_snapshot": str(snapshot),
        "parameters": PARAMETERS,
        "packages": {
            name: importlib.metadata.version(name)
            for name in ("torch", "diffusers", "Pillow")
        },
    }
    if args.preflight_only:
        print("HUMAN_FLUX2_BATCH_PREFLIGHT_OK")
        print(json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True))
        return 0

    os.environ.update({
        "CUDA_VISIBLE_DEVICES": str(args.gpu),
        "HF_HUB_CACHE": "/data/models/hub",
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "PYTORCH_CUDA_ALLOC_CONF": "expandable_segments:True",
    })
    import torch
    from diffusers import Flux2KleinPipeline

    pending = [job for job in jobs if not validate_existing(job, expected_output(job))]
    if pending:
        pipeline = Flux2KleinPipeline.from_pretrained(
            str(snapshot), torch_dtype=torch.bfloat16, local_files_only=True
        ).to("cuda")
        for job in jobs:
            generate_one(job, pipeline, torch)
    else:
        for job in jobs:
            generate_one(job, None, None)
    print(f"HUMAN_FLUX2_BATCH_OK jobs={len(jobs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
