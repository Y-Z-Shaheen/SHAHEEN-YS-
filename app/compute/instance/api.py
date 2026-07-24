from __future__ import annotations

from typing import Any

from flask import Blueprint, jsonify, request

from app.compute.service import (
    create_instance,
    get_instance,
    list_instances,
)


instance_blueprint = Blueprint(
    "instances",
    __name__,
    url_prefix="/api/instances",
)


@instance_blueprint.get("/health")
def instances_health():
    return jsonify(
        {
            "status": "healthy",
            "service": "instance-management",
        }
    )


@instance_blueprint.get("")
@instance_blueprint.get("/")
def get_all_instances():
    try:
        instances = list_instances()

        return jsonify(
            {
                "status": "success",
                "instances": instances,
                "count": len(instances),
            }
        )

    except Exception:
        return jsonify(
            {
                "status": "error",
                "message": "Failed to retrieve instances.",
            }
        ), 500


@instance_blueprint.get("/<instance_id>")
def get_instance_by_id(
    instance_id: str,
):
    try:
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

    except Exception:
        return jsonify(
            {
                "status": "error",
                "message": "Failed to retrieve instance.",
            }
        ), 500


@instance_blueprint.post("")
@instance_blueprint.post("/")
def create_new_instance():
    payload: dict[str, Any] = (
        request.get_json(
            silent=True
        )
        or {}
    )

    name = payload.get("name")

    if not isinstance(name, str):
        return jsonify(
            {
                "status": "error",
                "message": "The 'name' field is required.",
            }
        ), 400

    name = name.strip()

    if not name:
        return jsonify(
            {
                "status": "error",
                "message": "The 'name' field cannot be empty.",
            }
        ), 400

    image = payload.get(
        "image",
        "shaheen-ys/compute:local",
    )

    cpu = payload.get(
        "cpu",
        1,
    )

    memory_mb = payload.get(
        "memory_mb",
        512,
    )

    if (
        not isinstance(cpu, int)
        or isinstance(cpu, bool)
        or cpu < 1
    ):
        return jsonify(
            {
                "status": "error",
                "message": "CPU must be a positive integer.",
            }
        ), 400

    if (
        not isinstance(memory_mb, int)
        or isinstance(memory_mb, bool)
        or memory_mb < 128
    ):
        return jsonify(
            {
                "status": "error",
                "message": (
                    "memory_mb must be an integer "
                    "greater than or equal to 128."
                ),
            }
        ), 400

    try:
        instance = create_instance(
            name=name,
            image=str(image),
            cpu=cpu,
            memory_mb=memory_mb,
            metadata=payload.get(
                "metadata"
            ),
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
        ), 409

    except Exception:
        return jsonify(
            {
                "status": "error",
                "message": "Failed to create instance.",
            }
        ), 500
