from __future__ import annotations

import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any

from app.database import database_connection
from app.identity.security import (
    generate_api_key,
    generate_session_token,
    hash_secret,
    verify_secret,
)


class IdentityService:
    """
    خدمة الهوية وإدارة API Keys والجلسات.
    """

    def create_api_key(
        self,
        owner_name: str,
    ) -> dict[str, Any]:
        owner_name = owner_name.strip()

        if not owner_name:
            raise ValueError(
                "Owner name cannot be empty."
            )

        if len(owner_name) > 200:
            raise ValueError(
                "Owner name is too long."
            )

        plain_api_key = generate_api_key()
        key_hash = hash_secret(plain_api_key)

        key_prefix = plain_api_key[:20]

        with database_connection() as connection:
            cursor = connection.execute(
                """
                INSERT INTO api_keys (
                    owner_name,
                    key_hash,
                    key_prefix,
                    is_active
                )
                VALUES (?, ?, ?, 1)
                """,
                (
                    owner_name,
                    key_hash,
                    key_prefix,
                ),
            )

            key_id = cursor.lastrowid

            connection.execute(
                """
                INSERT INTO system_events (
                    event_type,
                    service_name,
                    payload
                )
                VALUES (?, ?, ?)
                """,
                (
                    "api_key_created",
                    "identity",
                    f"API key created for owner: {owner_name}",
                ),
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

        with database_connection() as connection:
            row = connection.execute(
                """
                SELECT
                    id,
                    owner_name,
                    key_prefix,
                    is_active,
                    created_at
                FROM api_keys
                WHERE key_hash = ?
                LIMIT 1
                """,
                (key_hash,),
            ).fetchone()

            if row is None:
                return None

            if not bool(row["is_active"]):
                return None

            connection.execute(
                """
                UPDATE api_keys
                SET last_used_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """,
                (row["id"],),
            )

            return dict(row)

    def revoke_api_key(
        self,
        key_id: int,
    ) -> bool:
        if key_id <= 0:
            raise ValueError(
                "Key ID must be greater than zero."
            )

        with database_connection() as connection:
            cursor = connection.execute(
                """
                UPDATE api_keys
                SET is_active = 0
                WHERE id = ?
                AND is_active = 1
                """,
                (key_id,),
            )

            revoked = cursor.rowcount > 0

            if revoked:
                connection.execute(
                    """
                    INSERT INTO system_events (
                        event_type,
                        service_name,
                        payload
                    )
                    VALUES (?, ?, ?)
                    """,
                    (
                        "api_key_revoked",
                        "identity",
                        f"API key ID {key_id} revoked",
                    ),
                )

            return revoked

    def create_session(
        self,
        user_id: int | None = None,
        lifetime_minutes: int = 60,
    ) -> dict[str, Any]:
        if lifetime_minutes <= 0:
            raise ValueError(
                "Session lifetime must be greater than zero."
            )

        session_id = generate_session_token()

        expires_at = (
            datetime.now(timezone.utc)
            + timedelta(minutes=lifetime_minutes)
        ).isoformat()

        with database_connection() as connection:
            connection.execute(
                """
                INSERT INTO sessions (
                    session_id,
                    user_id,
                    expires_at
                )
                VALUES (?, ?, ?)
                """,
                (
                    session_id,
                    user_id,
                    expires_at,
                ),
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

        with database_connection() as connection:
            row = connection.execute(
                """
                SELECT expires_at
                FROM sessions
                WHERE session_id = ?
                LIMIT 1
                """,
                (session_id,),
            ).fetchone()

        if row is None:
            return False

        try:
            expires_at = datetime.fromisoformat(
                row["expires_at"]
            )

            current_time = datetime.now(timezone.utc)

            return current_time < expires_at

        except ValueError:
            return False

    def health_check(self) -> dict[str, Any]:
        try:
            with database_connection() as connection:
                connection.execute(
                    "SELECT 1"
                ).fetchone()

                api_keys_count = connection.execute(
                    """
                    SELECT COUNT(*) AS total
                    FROM api_keys
                    """
                ).fetchone()["total"]

                users_count = connection.execute(
                    """
                    SELECT COUNT(*) AS total
                    FROM users
                    """
                ).fetchone()["total"]

            return {
                "status": "healthy",
                "service": "identity",
                "database": "connected",
                "api_keys": api_keys_count,
                "users": users_count,
            }

        except sqlite3.Error as error:
            return {
                "status": "unhealthy",
                "service": "identity",
                "database": "unavailable",
                "error": str(error),
            }


identity_service = IdentityService()
