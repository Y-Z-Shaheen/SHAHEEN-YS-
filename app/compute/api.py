from __future__ import annotations

from typing import Any

from flask import Blueprint, jsonify, request

from app.compute.service import (
    create_instance,
    get_compute_health,
    get_instance,
    list_instances,
)


compute_blueprint = Blueprint(
    "compute",
    __name__,
    url_prefix="/api/compute",
)


@compute_blueprint.get("/health")
def compute_health():
    health = get_compute_health()

    status_code = (
        200
        if health.get("status") == "healthy"
        else 503
    )

    return jsonify(health), status_code


@compute_blueprint.get("/instances")
def get_instances():
    return jsonify(
        {
            "status": "success",
            "instances": list_instances(),
        }
    )


@compute_blueprint.get("/instances/<instance_id>")
def get_single_instance(
    instance_id: str,
):
    instance = get_instance(instance_id)

    if instance is None:
        return jsonify(
            {
                "status": "error",
                "message": "Instance not found.",
            }
        ), 404

    return jsonify(
        {
            "status": "success",
            "instance": instance,
        }
    )


@compute_blueprint.post("/instances")
def create_new_instance():
    payload: dict[str, Any] = (
        request.get_json(
            silent=True
        )
        or {}
    )

    name = payload.get("name")

    if not isinstance(name, str) or not name.strip():
        return jsonify(
            {
                "status": "error",
                "message": (
                    "The 'name' field is required."
                ),
            }
        ), 400

    image = payload.get(
        "image",
        "shaheen-ys/compute:local",
    )

    cpu = payload.get("cpu", 1)

    memory_mb = payload.get(
        "memory_mb",
        512,
    )

    if not isinstance(cpu, int) or cpu < 1:
        return jsonify(
            {
                "status": "error",
                "message": (
                    "'cpu' must be a positive integer."
                ),
            }
        ), 400

    if (
        not isinstance(memory_mb, int)
        or memory_mb < 128
    ):
        return jsonify(
            {
                "status": "error",
                "message": (
                    "'memory_mb' must be "
                    "at least 128."
                ),
            }
        ), 400

    try:
        instance = create_instance(
            name=name.strip(),
            image=str(image),
            cpu=cpu,
            memory_mb=memory_mb,
            metadata=payload.get("metadata"),
        )

        return jsonify(
            {
                "status": "success",
                "instance": instance,
            }
        ), 201

    except ValueError as error:
        return jsonify(
            {
                "status": "error",
                "message": str(error),
            }
        ), 400

    except Exception:
        return jsonify(
            {
                "status": "error",
                "message": (
                    "Failed to create instance."
                ),
            }
        ), 500
