"""
Compute instance service for SHAHEEN-YS.

Uses the shared SQLAlchemy database layer (database_connection) so that
both SQLite (development) and PostgreSQL (production) are supported
without any raw sqlite3 calls.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import text

from app.database import database_connection


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def get_compute_health() -> dict[str, Any]:
    """Return health status for the compute service."""
    try:
        with database_connection() as conn:
            conn.execute(
                text(
                    "SELECT 1 FROM compute_instances LIMIT 1"
                )
            )
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
    """Return all compute instances ordered by creation time."""
    with database_connection() as conn:
        rows = conn.execute(
            text(
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
            )
        ).mappings().fetchall()

    return [dict(row) for row in rows]


def get_instance(instance_id: str) -> dict[str, Any] | None:
    """Return a single compute instance by ID, or None if not found."""
    with database_connection() as conn:
        row = conn.execute(
            text(
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
                WHERE id = :id
                """
            ),
            {"id": instance_id},
        ).mappings().fetchone()

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
    """
    Create a new compute instance record.

    Raises ValueError if an instance with the same name already exists.
    """
    del metadata  # reserved for future use

    instance_id = f"shaheen-{uuid.uuid4().hex}"
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
        with database_connection() as conn:
            conn.execute(
                text(
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
                    VALUES (
                        :id,
                        :name,
                        :image,
                        :cpu,
                        :memory_mb,
                        :status,
                        :created_at,
                        :updated_at
                    )
                    """
                ),
                instance,
            )
    except Exception as exc:
        # Catch unique-constraint violations from both SQLite and PostgreSQL
        msg = str(exc).lower()
        if "unique" in msg or "duplicate" in msg:
            raise ValueError(
                "An instance with this name already exists."
            ) from exc
        raise

    return instance
