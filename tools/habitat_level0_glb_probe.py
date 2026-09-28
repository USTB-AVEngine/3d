#!/usr/bin/env python3
"""Probe static GLB loading through Habitat-Sim without changing AVEngine state."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import time
import traceback
from typing import Any


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def make_simulator(habitat_sim: Any, gpu: int) -> Any:
    simulator_config = habitat_sim.SimulatorConfiguration()
    simulator_config.scene_id = "NONE"
    simulator_config.enable_physics = True
    if hasattr(simulator_config, "gpu_device_id"):
        simulator_config.gpu_device_id = gpu
    agent_config = habitat_sim.agent.AgentConfiguration()
    return habitat_sim.Simulator(
        habitat_sim.Configuration(simulator_config, [agent_config])
    )


def make_object_attributes(habitat_sim: Any, manager: Any, handle: str) -> Any:
    attributes_module = getattr(habitat_sim, "attributes", None)
    attributes_class = getattr(attributes_module, "ObjectAttributes", None)
    if attributes_class is not None:
        return attributes_class()
    create = getattr(manager, "create_new_template", None)
    if create is None:
        raise RuntimeError("Habitat object-template API is unavailable")
    try:
        return create(handle, False)
    except TypeError:
        return create(handle)


def register_template(manager: Any, attributes: Any, handle: str) -> Any:
    try:
        return manager.register_template(attributes, handle)
    except TypeError:
        return manager.register_template(attributes)


def add_object(object_manager: Any, registration: Any, handle: str) -> Any:
    add_by_handle = getattr(object_manager, "add_object_by_template_handle", None)
    if add_by_handle is not None:
        return add_by_handle(handle)
    add_by_id = getattr(object_manager, "add_object_by_template_id", None)
    if add_by_id is None:
        raise RuntimeError("Habitat rigid-object creation API is unavailable")
    return add_by_id(registration)


def probe_asset(habitat_sim: Any, simulator: Any, path: Path, index: int) -> dict[str, Any]:
    started = time.perf_counter()
    record: dict[str, Any] = {
        "path": str(path),
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
        "status": "failed",
    }
    template_handle = f"avengine_level0::{index}::{path.stem}"
    try:
        template_manager = simulator.get_object_template_manager()
        attributes = make_object_attributes(habitat_sim, template_manager, template_handle)
        attributes.render_asset_handle = str(path)
        attributes.collision_asset_handle = str(path)
        if hasattr(attributes, "use_mesh_collision"):
            attributes.use_mesh_collision = True
        if hasattr(attributes, "is_collidable"):
            attributes.is_collidable = True
        registration = register_template(template_manager, attributes, template_handle)
        if isinstance(registration, int) and registration < 0:
            raise RuntimeError(f"template registration failed with id {registration}")

        object_manager = simulator.get_rigid_object_manager()
        rigid_object = add_object(object_manager, registration, template_handle)
        if rigid_object is None:
            raise RuntimeError("Habitat returned no rigid object")
        if hasattr(habitat_sim, "physics") and hasattr(habitat_sim.physics, "MotionType"):
            rigid_object.motion_type = habitat_sim.physics.MotionType.STATIC

        record.update({
            "status": "passed",
            "template_handle": template_handle,
            "template_registration": registration,
            "object_id": getattr(rigid_object, "object_id", None),
            "visual_node_count": len(getattr(rigid_object, "visual_scene_nodes", []) or []),
        })
        object_id = getattr(rigid_object, "object_id", None)
        if object_id is not None and hasattr(object_manager, "remove_object_by_id"):
            object_manager.remove_object_by_id(object_id)
    except Exception as error:
        record["error_type"] = type(error).__name__
        record["error"] = str(error)
        record["traceback"] = traceback.format_exc()
    record["wall_seconds"] = time.perf_counter() - started
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--gpu", type=int, default=0)
    args = parser.parse_args()

    assets = [path.resolve() for path in args.asset]
    missing = [str(path) for path in assets if not path.is_file()]
    if missing:
        raise FileNotFoundError("missing assets: " + ", ".join(missing))

    os.environ.setdefault("MAGNUM_LOG", "quiet")
    os.environ.setdefault("HABITAT_SIM_LOG", "quiet")
    started = time.perf_counter()
    report: dict[str, Any] = {
        "schema": "human_sound_source_habitat_level0_probe_v1",
        "status": "failed",
        "gpu": args.gpu,
        "assets": [],
    }
    simulator = None
    try:
        import habitat_sim

        report["habitat_sim_module"] = str(Path(habitat_sim.__file__).resolve())
        simulator = make_simulator(habitat_sim, args.gpu)
        report["assets"] = [
            probe_asset(habitat_sim, simulator, path, index)
            for index, path in enumerate(assets)
        ]
        passed = sum(item["status"] == "passed" for item in report["assets"])
        report["passed_count"] = passed
        report["failed_count"] = len(report["assets"]) - passed
        report["status"] = "passed" if passed == len(report["assets"]) else "failed"
    except Exception as error:
        report["setup_error_type"] = type(error).__name__
        report["setup_error"] = str(error)
        report["setup_traceback"] = traceback.format_exc()
    finally:
        if simulator is not None:
            simulator.close()

    report["wall_seconds"] = time.perf_counter() - started
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
