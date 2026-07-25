"""
Identity service for SHAHEEN-YS.

Manages API keys and sessions using the unified database layer
(supports both PostgreSQL and SQLite via SQLAlchemy).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.database import check_database_health, database_connection, insert_and_get_id
from app.identity.security import (
    generate_api_key,
    generate_session_token,
    hash_secret,
    verify_secret,
)


class IdentityService:
    """
    خدمة الهوية وإدارة API Keys والجلسات.

    All SQL uses SQLAlchemy text() with named parameters (:name style)
    for compatibility with both SQLite and PostgreSQL.
    """

    def create_api_key(
        self,
        owner_name: str,
    ) -> dict[str, Any]:
        owner_name = owner_name.strip()

        if not owner_name:
            raise ValueError("Owner name cannot be empty.")

        if len(owner_name) > 200:
            raise ValueError("Owner name is too long.")

        plain_api_key = generate_api_key()
        key_hash = hash_secret(plain_api_key)
        key_prefix = plain_api_key[:20]

        with database_connection() as conn:
            key_id = insert_and_get_id(
                conn,
                "INSERT INTO api_keys (owner_name, key_hash, key_prefix, is_active)"
                " VALUES (:owner_name, :key_hash, :key_prefix, 1)",
                {
                    "owner_name": owner_name,
                    "key_hash": key_hash,
                    "key_prefix": key_prefix,
                },
            )

            conn.execute(
                text(
                    "INSERT INTO system_events (event_type, service_name, payload)"
                    " VALUES (:event_type, :service_name, :payload)"
                ),
                {
                    "event_type": "api_key_created",
                    "service_name": "identity",
                    "payload": f"API key created for owner: {owner_name}",
                },
            )

        return {
            "id": key_id,
            "owner_name": owner_name,
            "api_key": plain_api_key,
            "key_prefix": key_prefix,
            "is_active": True,
        }

    def verify_api_key(
        self,
        api_key: str,
    ) -> dict[str, Any] | None:
        if not api_key:
            return None

        key_hash = hash_secret(api_key)

        with database_connection() as conn:
            row = conn.execute(
                text(
                    "SELECT id, owner_name, key_prefix, is_active, created_at"
                    " FROM api_keys WHERE key_hash = :key_hash LIMIT 1"
                ),
                {"key_hash": key_hash},
            ).mappings().fetchone()

            if row is None:
                return None

            if not bool(row["is_active"]):
                return None

            conn.execute(
                text(
                    "UPDATE api_keys SET last_used_at = CURRENT_TIMESTAMP"
                    " WHERE id = :id"
                ),
                {"id": row["id"]},
            )

            return dict(row)

    def revoke_api_key(
        self,
        key_id: int,
    ) -> bool:
        if key_id <= 0:
            raise ValueError("Key ID must be greater than zero.")

        with database_connection() as conn:
            result = conn.execute(
                text(
                    "UPDATE api_keys SET is_active = 0"
                    " WHERE id = :id AND is_active = 1"
                ),
                {"id": key_id},
            )

            revoked = result.rowcount > 0

            if revoked:
                conn.execute(
                    text(
                        "INSERT INTO system_events"
                        " (event_type, service_name, payload)"
                        " VALUES (:event_type, :service_name, :payload)"
                    ),
                    {
                        "event_type": "api_key_revoked",
                        "service_name": "identity",
                        "payload": f"API key ID {key_id} revoked",
                    },
                )

            return revoked

    def create_session(
        self,
        user_id: int | None = None,
        lifetime_minutes: int = 60,
    ) -> dict[str, Any]:
        if lifetime_minutes <= 0:
            raise ValueError("Session lifetime must be greater than zero.")

        session_id = generate_session_token()
        expires_at = (
            datetime.now(timezone.utc) + timedelta(minutes=lifetime_minutes)
        ).isoformat()

        with database_connection() as conn:
            conn.execute(
                text(
                    "INSERT INTO sessions (session_id, user_id, expires_at)"
                    " VALUES (:session_id, :user_id, :expires_at)"
                ),
                {
                    "session_id": session_id,
                    "user_id": user_id,
                    "expires_at": expires_at,
                },
            )

        return {
            "session_id": session_id,
            "expires_at": expires_at,
        }

    def verify_session(
        self,
        session_id: str,
    ) -> bool:
        if not session_id:
            return False

        with database_connection() as conn:
            row = conn.execute(
                text(
                    "SELECT expires_at FROM sessions"
                    " WHERE session_id = :session_id LIMIT 1"
                ),
                {"session_id": session_id},
            ).mappings().fetchone()

        if row is None:
            return False

        try:
            expires_at = datetime.fromisoformat(row["expires_at"])
            return datetime.now(timezone.utc) < expires_at
        except ValueError:
            return False

    def health_check(self) -> dict[str, Any]:
        try:
            with database_connection() as conn:
                conn.execute(text("SELECT 1")).fetchone()

                api_keys_count = conn.execute(
                    text("SELECT COUNT(*) AS total FROM api_keys")
                ).fetchone()[0]

                users_count = conn.execute(
                    text("SELECT COUNT(*) AS total FROM users")
                ).fetchone()[0]

            return {
                "status": "healthy",
                "service": "identity",
                "database": "connected",
                "api_keys": api_keys_count,
                "users": users_count,
            }
        except SQLAlchemyError as exc:
            return {
                "status": "unhealthy",
                "service": "identity",
                "database": "unavailable",
                "error": str(exc),
            }


identity_service = IdentityService()
