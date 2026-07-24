#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

export PYTHONPATH="$PROJECT_ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "[11-instance] بدء تهيئة Instance Management Layer..."

mkdir -p \
    "$PROJECT_ROOT/app/compute/instance"

touch "$PROJECT_ROOT/app/compute/instance/__init__.py"

if [[ ! -f "$PROJECT_ROOT/app/compute/service.py" ]]; then
    echo "[11-instance][ERROR] ملف Compute Service غير موجود."
    echo "[11-instance][ERROR] شغّل السكريبت 10 أولاً."
    exit 1
fi

cat > "$PROJECT_ROOT/app/compute/instance/manager.py" << 'PYTHON_EOF'
from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from app.compute.service import (
    create_instance,
    get_compute_health,
    get_instance,
    start_instance,
    stop_instance,
    terminate_instance,
)


class InstanceStatus(StrEnum):
    CREATED = "created"
    PROVISIONING = "provisioning"
    RUNNING = "running"
    STOPPED = "stopped"
    TERMINATED = "terminated"


@dataclass(frozen=True)
class InstanceTransition:
    source: str
    target: str


ALLOWED_TRANSITIONS: set[InstanceTransition] = {
    InstanceTransition(
        InstanceStatus.CREATED,
        InstanceStatus.PROVISIONING,
    ),
    InstanceTransition(
        InstanceStatus.PROVISIONING,
        InstanceStatus.RUNNING,
    ),
    InstanceTransition(
        InstanceStatus.RUNNING,
        InstanceStatus.STOPPED,
    ),
    InstanceTransition(
        InstanceStatus.STOPPED,
        InstanceStatus.RUNNING,
    ),
    InstanceTransition(
        InstanceStatus.CREATED,
        InstanceStatus.TERMINATED,
    ),
    InstanceTransition(
        InstanceStatus.PROVISIONING,
        InstanceStatus.TERMINATED,
    ),
    InstanceTransition(
        InstanceStatus.RUNNING,
        InstanceStatus.TERMINATED,
    ),
    InstanceTransition(
        InstanceStatus.STOPPED,
        InstanceStatus.TERMINATED,
    ),
}


class InstanceManager:
    """
    مدير دورة حياة Instances.

    المسؤولية:
    - التحقق من الحالة الحالية.
    - منع الانتقالات غير الصحيحة.
    - استدعاء Compute Service.
    """

    def __init__(self) -> None:
        self.service_name = "instance-management"

    def _get_required_instance(
        self,
        instance_id: str,
    ) -> dict[str, Any]:
        instance = get_instance(instance_id)

        if instance is None:
            raise ValueError(
                f"Instance not found: {instance_id}"
            )

        return instance

    def _validate_transition(
        self,
        current_status: str,
        target_status: str,
    ) -> None:
        transition = InstanceTransition(
            current_status,
            target_status,
        )

        if transition not in ALLOWED_TRANSITIONS:
            raise ValueError(
                "Invalid instance state transition: "
                f"{current_status} -> {target_status}"
            )

    def create(
        self,
        name: str,
        image: str = "shaheen-ys/compute:local",
        cpu: int = 1,
        memory_mb: int = 512,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        return create_instance(
            name=name,
            image=image,
            cpu=cpu,
            memory_mb=memory_mb,
            metadata=metadata,
        )

    def provision(
        self,
        instance_id: str,
    ) -> dict[str, Any]:
        instance = self._get_required_instance(
            instance_id
        )

        self._validate_transition(
            instance["status"],
            InstanceStatus.PROVISIONING,
        )

        from app.compute.service import (
            update_instance_status,
        )

        return update_instance_status(
            instance_id,
            InstanceStatus.PROVISIONING,
        )

    def start(
        self,
        instance_id: str,
    ) -> dict[str, Any]:
        instance = self._get_required_instance(
            instance_id
        )

        current_status = instance["status"]

        if current_status == InstanceStatus.CREATED:
            self.provision(instance_id)

        elif current_status == InstanceStatus.PROVISIONING:
            pass

        elif current_status == InstanceStatus.STOPPED:
            pass

        elif current_status == InstanceStatus.RUNNING:
            return instance

        else:
            raise ValueError(
                "Cannot start instance from status: "
                f"{current_status}"
            )

        return start_instance(instance_id)

    def stop(
        self,
        instance_id: str,
    ) -> dict[str, Any]:
        instance = self._get_required_instance(
            instance_id
        )

        self._validate_transition(
            instance["status"],
            InstanceStatus.STOPPED,
        )

        return stop_instance(instance_id)

    def terminate(
        self,
        instance_id: str,
    ) -> dict[str, Any]:
        instance = self._get_required_instance(
            instance_id
        )

        if instance["status"] == InstanceStatus.TERMINATED:
            return instance

        self._validate_transition(
            instance["status"],
            InstanceStatus.TERMINATED,
        )

        return terminate_instance(instance_id)

    def health(self) -> dict[str, Any]:
        compute_health = get_compute_health()

        return {
            "status": (
                "healthy"
                if compute_health.get("status")
                == "healthy"
                else "unhealthy"
            ),
            "service": self.service_name,
            "compute": compute_health,
        }
PYTHON_EOF

cat > "$PROJECT_ROOT/app/compute/instance/api.py" << 'PYTHON_EOF'
from __future__ import annotations

from flask import Blueprint, jsonify

from app.compute.instance.manager import (
    InstanceManager,
)


instance_manager = InstanceManager()

instance_blueprint = Blueprint(
    "instance_management",
    __name__,
    url_prefix="/api/instances",
)


@instance_blueprint.get("/health")
def instance_health():
    health = instance_manager.health()

    status_code = (
        200
        if health["status"] == "healthy"
        else 503
    )

    return jsonify(health), status_code


@instance_blueprint.post("/<instance_id>/provision")
def provision_instance(instance_id: str):
    try:
        instance = instance_manager.provision(
            instance_id
        )

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


@instance_blueprint.post("/<instance_id>/start")
def start_managed_instance(instance_id: str):
    try:
        instance = instance_manager.start(
            instance_id
        )

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


@instance_blueprint.post("/<instance_id>/stop")
def stop_managed_instance(instance_id: str):
    try:
        instance = instance_manager.stop(
            instance_id
        )

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


@instance_blueprint.post(
    "/<instance_id>/terminate"
)
def terminate_managed_instance(instance_id: str):
    try:
        instance = instance_manager.terminate(
            instance_id
        )

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

cat > "$PROJECT_ROOT/app/compute/instance/test_manager.py" << 'PYTHON_EOF'
from __future__ import annotations

import tempfile
from pathlib import Path

from app.compute import service
from app.compute.instance.manager import (
    InstanceManager,
)


def main() -> None:
    original_database_path = service.DATABASE_PATH

    with tempfile.TemporaryDirectory() as temporary_directory:
        service.DATABASE_PATH = (
            Path(temporary_directory)
            / "instance_management_test.db"
        )

        service.ensure_compute_schema()

        manager = InstanceManager()

        instance = manager.create(
            name="managed-instance",
            image="shaheen-ys/test:local",
            cpu=1,
            memory_mb=256,
        )

        assert instance["status"] == "created"

        provisioned = manager.provision(
            instance["id"]
        )

        assert (
            provisioned["status"]
            == "provisioning"
        )

        running = manager.start(
            instance["id"]
        )

        assert running["status"] == "running"

        stopped = manager.stop(
            instance["id"]
        )

        assert stopped["status"] == "stopped"

        restarted = manager.start(
            instance["id"]
        )

        assert restarted["status"] == "running"

        terminated = manager.terminate(
            instance["id"]
        )

        assert (
            terminated["status"]
            == "terminated"
        )

        health = manager.health()

        assert health["status"] == "healthy"

        service.DATABASE_PATH = (
            original_database_path
        )

    print(
        "[11-instance] Instance Management tests "
        "passed successfully."
    )


if __name__ == "__main__":
    main()
PYTHON_EOF

echo "[11-instance] تشغيل اختبارات Instance Management..."

python3 -m app.compute.instance.test_manager

echo "[11-instance] تم إنشاء Instance Management Layer بنجاح."
