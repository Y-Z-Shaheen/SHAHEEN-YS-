from __future__ import annotations

import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.database import DATABASE_PATH


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _ensure_instances_table() -> None:
    database_path = Path(DATABASE_PATH)

    database_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with sqlite3.connect(database_path) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS compute_instances (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                image TEXT NOT NULL,
                cpu INTEGER NOT NULL,
                memory_mb INTEGER NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )

        connection.commit()


def get_compute_health() -> dict[str, Any]:
    try:
        _ensure_instances_table()

        with sqlite3.connect(DATABASE_PATH) as connection:
            connection.execute(
                "SELECT 1"
            ).fetchone()

        return {
            "status": "healthy",
            "service": "compute",
            "database": "connected",
        }

    except Exception as error:
        return {
            "status": "unhealthy",
            "service": "compute",
            "database": "disconnected",
            "error": str(error),
        }


def list_instances() -> list[dict[str, Any]]:
    _ensure_instances_table()

    with sqlite3.connect(DATABASE_PATH) as connection:
        connection.row_factory = sqlite3.Row

        rows = connection.execute(
            """
            SELECT
                id,
                name,
                image,
                cpu,
                memory_mb,
                status,
                created_at,
                updated_at
            FROM compute_instances
            ORDER BY created_at DESC
            """
        ).fetchall()

    return [
        dict(row)
        for row in rows
    ]


def get_instance(
    instance_id: str,
) -> dict[str, Any] | None:
    _ensure_instances_table()

    with sqlite3.connect(DATABASE_PATH) as connection:
        connection.row_factory = sqlite3.Row

        row = connection.execute(
            """
            SELECT
                id,
                name,
                image,
                cpu,
                memory_mb,
                status,
                created_at,
                updated_at
            FROM compute_instances
            WHERE id = ?
            """,
            (instance_id,),
        ).fetchone()

    if row is None:
        return None

    return dict(row)


def create_instance(
    name: str,
    image: str,
    cpu: int,
    memory_mb: int,
    metadata: Any = None,
) -> dict[str, Any]:
    del metadata

    _ensure_instances_table()

    instance_id = (
        f"shaheen-{uuid.uuid4().hex}"
    )

    timestamp = _utc_now()

    instance = {
        "id": instance_id,
        "name": name,
        "image": image,
        "cpu": cpu,
        "memory_mb": memory_mb,
        "status": "created",
        "created_at": timestamp,
        "updated_at": timestamp,
    }

    try:
        with sqlite3.connect(DATABASE_PATH) as connection:
            connection.execute(
                """
                INSERT INTO compute_instances (
                    id,
                    name,
                    image,
                    cpu,
                    memory_mb,
                    status,
                    created_at,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    instance["id"],
                    instance["name"],
                    instance["image"],
                    instance["cpu"],
                    instance["memory_mb"],
                    instance["status"],
                    instance["created_at"],
                    instance["updated_at"],
                ),
            )

            connection.commit()

    except sqlite3.IntegrityError as error:
        raise ValueError(
            "An instance with this name already exists."
        ) from error

    return instance
