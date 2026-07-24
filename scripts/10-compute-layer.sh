#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

export PYTHONPATH="$PROJECT_ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "[10-compute] بدء تهيئة Compute Layer..."

mkdir -p \
    "$PROJECT_ROOT/app/compute" \
    "$PROJECT_ROOT/app/compute/instance"

touch "$PROJECT_ROOT/app/compute/__init__.py"
touch "$PROJECT_ROOT/app/compute/instance/__init__.py"

if [[ ! -f "$PROJECT_ROOT/app/database.py" ]]; then
    echo "[10-compute][ERROR] الملف app/database.py غير موجود."
    exit 1
fi

cat > "$PROJECT_ROOT/app/compute/service.py" << 'PYTHON_EOF'
from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[2]

DATABASE_PATH = Path(
    os.getenv(
        "SHAHEEN_YS_DATABASE_PATH",
        str(PROJECT_ROOT / "data" / "db" / "shaheen_ys.db"),
    )
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_compute_schema() -> None:
    DATABASE_PATH.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with sqlite3.connect(DATABASE_PATH) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS compute_instances (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                image TEXT NOT NULL,
                status TEXT NOT NULL,
                runtime TEXT NOT NULL,
                cpu INTEGER NOT NULL,
                memory_mb INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}'
            )
            """
        )

        connection.commit()


def detect_container_runtime() -> str:
    configured_runtime = os.getenv(
        "SHAHEEN_YS_CONTAINER_RUNTIME",
        "auto",
    ).lower()

    if configured_runtime in {"docker", "podman", "mock"}:
        if configured_runtime == "mock":
            return "mock"

        runtime_path = subprocess.run(
            ["sh", "-c", f"command -v {configured_runtime}"],
            capture_output=True,
            text=True,
            check=False,
        )

        if runtime_path.returncode == 0:
            return configured_runtime

        return "mock"

    for runtime in ("docker", "podman"):
        runtime_path = subprocess.run(
            ["sh", "-c", f"command -v {runtime}"],
            capture_output=True,
            text=True,
            check=False,
        )

        if runtime_path.returncode == 0:
            return runtime

    return "mock"


def create_instance(
    name: str,
    image: str = "shaheen-ys/compute:local",
    cpu: int = 1,
    memory_mb: int = 512,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    ensure_compute_schema()

    normalized_name = name.strip()

    if not normalized_name:
        raise ValueError("Instance name cannot be empty.")

    if len(normalized_name) > 128:
        raise ValueError(
            "Instance name cannot exceed 128 characters."
        )

    if cpu < 1:
        raise ValueError("CPU count must be at least 1.")

    if memory_mb < 128:
        raise ValueError(
            "Memory must be at least 128 MB."
        )

    instance_id = str(uuid.uuid4())

    now = utc_now()

    runtime = detect_container_runtime()

    instance = {
        "id": instance_id,
        "name": normalized_name,
        "image": image,
        "status": "created",
        "runtime": runtime,
        "cpu": cpu,
        "memory_mb": memory_mb,
        "created_at": now,
        "updated_at": now,
        "metadata": metadata or {},
    }

    try:
        with sqlite3.connect(DATABASE_PATH) as connection:
            connection.execute(
                """
                INSERT INTO compute_instances (
                    id,
                    name,
                    image,
                    status,
                    runtime,
                    cpu,
                    memory_mb,
                    created_at,
                    updated_at,
                    metadata
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    instance["id"],
                    instance["name"],
                    instance["image"],
                    instance["status"],
                    instance["runtime"],
                    instance["cpu"],
                    instance["memory_mb"],
                    instance["created_at"],
                    instance["updated_at"],
                    json.dumps(
                        instance["metadata"],
                        ensure_ascii=False,
                    ),
                ),
            )

            connection.commit()

    except sqlite3.IntegrityError as error:
        raise ValueError(
            f"Instance name already exists: {normalized_name}"
        ) from error

    return instance


def get_instance(instance_id: str) -> dict[str, Any] | None:
    ensure_compute_schema()

    with sqlite3.connect(DATABASE_PATH) as connection:
        connection.row_factory = sqlite3.Row

        row = connection.execute(
            """
            SELECT
                id,
                name,
                image,
                status,
                runtime,
                cpu,
                memory_mb,
                created_at,
                updated_at,
                metadata
            FROM compute_instances
            WHERE id = ?
            """,
            (instance_id,),
        ).fetchone()

    if row is None:
        return None

    instance = dict(row)

    try:
        instance["metadata"] = json.loads(
            instance["metadata"]
        )
    except json.JSONDecodeError:
        instance["metadata"] = {}

    return instance


def list_instances() -> list[dict[str, Any]]:
    ensure_compute_schema()

    with sqlite3.connect(DATABASE_PATH) as connection:
        connection.row_factory = sqlite3.Row

        rows = connection.execute(
            """
            SELECT
                id,
                name,
                image,
                status,
                runtime,
                cpu,
                memory_mb,
                created_at,
                updated_at,
                metadata
            FROM compute_instances
            ORDER BY created_at DESC
            """
        ).fetchall()

    instances = []

    for row in rows:
        instance = dict(row)

        try:
            instance["metadata"] = json.loads(
                instance["metadata"]
            )
        except json.JSONDecodeError:
            instance["metadata"] = {}

        instances.append(instance)

    return instances


def update_instance_status(
    instance_id: str,
    status: str,
) -> dict[str, Any]:
    allowed_statuses = {
        "created",
        "running",
        "stopped",
        "terminated",
    }

    if status not in allowed_statuses:
        raise ValueError(
            f"Invalid instance status: {status}"
        )

    ensure_compute_schema()

    now = utc_now()

    with sqlite3.connect(DATABASE_PATH) as connection:
        cursor = connection.execute(
            """
            UPDATE compute_instances
            SET
                status = ?,
                updated_at = ?
            WHERE id = ?
            """,
            (
                status,
                now,
                instance_id,
            ),
        )

        connection.commit()

        if cursor.rowcount == 0:
            raise ValueError(
                f"Instance not found: {instance_id}"
            )

    instance = get_instance(instance_id)

    if instance is None:
        raise RuntimeError(
            "Instance disappeared after status update."
        )

    return instance


def start_instance(instance_id: str) -> dict[str, Any]:
    instance = get_instance(instance_id)

    if instance is None:
        raise ValueError(
            f"Instance not found: {instance_id}"
        )

    if instance["status"] == "terminated":
        raise ValueError(
            "Terminated instances cannot be started."
        )

    return update_instance_status(
        instance_id,
        "running",
    )


def stop_instance(instance_id: str) -> dict[str, Any]:
    instance = get_instance(instance_id)

    if instance is None:
        raise ValueError(
            f"Instance not found: {instance_id}"
        )

    if instance["status"] == "terminated":
        raise ValueError(
            "Terminated instances cannot be stopped."
        )

    return update_instance_status(
        instance_id,
        "stopped",
    )


def terminate_instance(instance_id: str) -> dict[str, Any]:
    instance = get_instance(instance_id)

    if instance is None:
        raise ValueError(
            f"Instance not found: {instance_id}"
        )

    return update_instance_status(
        instance_id,
        "terminated",
    )


def get_compute_health() -> dict[str, Any]:
    try:
        ensure_compute_schema()

        instances = list_instances()

        runtime = detect_container_runtime()

        return {
            "status": "healthy",
            "service": "compute",
            "runtime": runtime,
            "instances": len(instances),
            "database": str(DATABASE_PATH),
        }

    except Exception as error:
        return {
            "status": "unhealthy",
            "service": "compute",
            "error": str(error),
        }
PYTHON_EOF

cat > "$PROJECT_ROOT/app/compute/api.py" << 'PYTHON_EOF'
from __future__ import annotations

from flask import Blueprint, jsonify, request

from app.compute.service import (
    create_instance,
    get_compute_health,
    get_instance,
    list_instances,
    start_instance,
    stop_instance,
    terminate_instance,
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
def get_single_instance(instance_id: str):
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
    payload = request.get_json(silent=True) or {}

    try:
        instance = create_instance(
            name=str(payload.get("name", "")),
            image=str(
                payload.get(
                    "image",
                    "shaheen-ys/compute:local",
                )
            ),
            cpu=int(payload.get("cpu", 1)),
            memory_mb=int(
                payload.get(
                    "memory_mb",
                    512,
                )
            ),
            metadata=payload.get(
                "metadata",
                {},
            ),
        )

        return jsonify(
            {
                "status": "success",
                "instance": instance,
            }
        ), 201

    except (ValueError, TypeError) as error:
        return jsonify(
            {
                "status": "error",
                "message": str(error),
            }
        ), 400


@compute_blueprint.post(
    "/instances/<instance_id>/start"
)
def start_existing_instance(instance_id: str):
    try:
        instance = start_instance(instance_id)

        return jsonify(
            {
                "status": "success",
                "instance": instance,
            }
        )

    except ValueError as error:
        return jsonify(
            {
                "status": "error",
                "message": str(error),
            }
        ), 400


@compute_blueprint.post(
    "/instances/<instance_id>/stop"
)
def stop_existing_instance(instance_id: str):
    try:
        instance = stop_instance(instance_id)

        return jsonify(
            {
                "status": "success",
                "instance": instance,
            }
        )

    except ValueError as error:
        return jsonify(
            {
                "status": "error",
                "message": str(error),
            }
        ), 400


@compute_blueprint.delete(
    "/instances/<instance_id>"
)
def terminate_existing_instance(instance_id: str):
    try:
        instance = terminate_instance(instance_id)

        return jsonify(
            {
                "status": "success",
                "instance": instance,
            }
        )

    except ValueError as error:
        return jsonify(
            {
                "status": "error",
                "message": str(error),
            }
        ), 400
PYTHON_EOF

cat > "$PROJECT_ROOT/app/compute/test_compute.py" << 'PYTHON_EOF'
from __future__ import annotations

import tempfile
from pathlib import Path

from app.compute import service


def main() -> None:
    original_database_path = service.DATABASE_PATH

    with tempfile.TemporaryDirectory() as temporary_directory:
        service.DATABASE_PATH = (
            Path(temporary_directory)
            / "compute_test.db"
        )

        service.ensure_compute_schema()

        instance = service.create_instance(
            name="test-instance",
            image="shaheen-ys/test:local",
            cpu=1,
            memory_mb=256,
        )

        assert instance["status"] == "created"

        running_instance = service.start_instance(
            instance["id"]
        )

        assert running_instance["status"] == "running"

        stopped_instance = service.stop_instance(
            instance["id"]
        )

        assert stopped_instance["status"] == "stopped"

        terminated_instance = (
            service.terminate_instance(
                instance["id"]
            )
        )

        assert (
            terminated_instance["status"]
            == "terminated"
        )

        instances = service.list_instances()

        assert len(instances) == 1

        health = service.get_compute_health()

        assert health["status"] == "healthy"

        service.DATABASE_PATH = original_database_path

    print(
        "[10-compute] Compute tests passed successfully."
    )


if __name__ == "__main__":
    main()
PYTHON_EOF

echo "[10-compute] تهيئة قاعدة بيانات Compute..."

python3 -c "
from app.compute.service import ensure_compute_schema
ensure_compute_schema()
"

echo "[10-compute] تشغيل اختبارات Compute..."

python3 -m app.compute.test_compute

echo "[10-compute] فحص Container Runtime..."

python3 -c "
from app.compute.service import detect_container_runtime
runtime = detect_container_runtime()
print(f'[10-compute] Runtime: {runtime}')
"

echo "[10-compute] تم إنشاء Compute Layer بنجاح."
