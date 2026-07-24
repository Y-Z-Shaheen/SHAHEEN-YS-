#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${PROJECT_ROOT}/app"
IDENTITY_DIR="${APP_DIR}/identity"

log() {
    printf '[07-identity] %s\n' "$1"
}

error() {
    printf '[07-identity][ERROR] %s\n' "$1" >&2
}

fail() {
    error "$1"
    exit 1
}

command -v python3 >/dev/null 2>&1 || fail "Python 3 غير مثبت."

mkdir -p "${IDENTITY_DIR}"

touch "${APP_DIR}/__init__.py"
touch "${IDENTITY_DIR}/__init__.py"

cat << 'PY_EOF' > "${IDENTITY_DIR}/security.py"
from __future__ import annotations

import hashlib
import hmac
import secrets


API_KEY_PREFIX = "sk_shaheen_"
API_KEY_RANDOM_BYTES = 32


def generate_api_key() -> str:
    """
    توليد API Key باستخدام CSPRNG.
    secrets.token_urlsafe يعتمد على مصدر عشوائي آمن تشفيرياً.
    """

    random_part = secrets.token_urlsafe(API_KEY_RANDOM_BYTES)

    return f"{API_KEY_PREFIX}{random_part}"


def hash_secret(secret: str) -> str:
    """
    تخزين Hash للمفتاح بدلاً من تخزين المفتاح الأصلي.
    """

    if not isinstance(secret, str) or not secret:
        raise ValueError("Secret must be a non-empty string.")

    return hashlib.sha256(
        secret.encode("utf-8")
    ).hexdigest()


def verify_secret(
    plain_secret: str,
    stored_hash: str,
) -> bool:
    """
    مقارنة مقاومة لهجمات Timing Attack.
    """

    if not plain_secret or not stored_hash:
        return False

    calculated_hash = hash_secret(plain_secret)

    return hmac.compare_digest(
        calculated_hash,
        stored_hash,
    )


def generate_session_token() -> str:
    """
    إنشاء Session Token عشوائي آمن.
    """

    return secrets.token_urlsafe(48)


def generate_request_id() -> str:
    """
    معرف آمن لتتبع الطلبات.
    """

    return secrets.token_hex(16)
PY_EOF

cat << 'PY_EOF' > "${IDENTITY_DIR}/service.py"
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
PY_EOF

cat << 'PY_EOF' > "${IDENTITY_DIR}/test_identity.py"
from __future__ import annotations

from app.database import initialize_database
from app.identity.service import IdentityService
from app.identity.security import (
    hash_secret,
    verify_secret,
)


def main() -> int:
    initialize_database()

    service = IdentityService()

    result = service.create_api_key(
        owner_name="SHAHEEN-YS Test Client"
    )

    generated_key = result["api_key"]

    if not generated_key.startswith("sk_shaheen_"):
        print("FAIL: Invalid API key prefix.")
        return 1

    stored_hash = hash_secret(generated_key)

    if not verify_secret(
        generated_key,
        stored_hash,
    ):
        print("FAIL: Secret verification failed.")
        return 1

    if verify_secret(
        "invalid-api-key",
        stored_hash,
    ):
        print("FAIL: Invalid secret was accepted.")
        return 1

    verified = service.verify_api_key(
        generated_key
    )

    if verified is None:
        print("FAIL: API key lookup failed.")
        return 1

    revoked = service.revoke_api_key(
        result["id"]
    )

    if not revoked:
        print("FAIL: API key revocation failed.")
        return 1

    if service.verify_api_key(
        generated_key
    ) is not None:
        print("FAIL: Revoked API key still works.")
        return 1

    session = service.create_session(
        lifetime_minutes=5
    )

    if not service.verify_session(
        session["session_id"]
    ):
        print("FAIL: Session verification failed.")
        return 1

    print("Identity tests passed.")
    print("API key generation: OK")
    print("Hash verification: OK")
    print("Invalid key rejection: OK")
    print("API key revocation: OK")
    print("Session creation: OK")
    print("Session verification: OK")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY_EOF

cat << 'PY_EOF' > "${IDENTITY_DIR}/health.py"
from __future__ import annotations

from app.identity.service import identity_service


def main() -> int:
    result = identity_service.health_check()

    print(result)

    if result.get("status") == "healthy":
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
PY_EOF

python3 -c "from app.database import initialize_database; initialize_database()"

if PYTHONPATH="${PROJECT_ROOT}" python3 "${IDENTITY_DIR}/test_identity.py"; then
    log "تم اجتياز اختبارات Identity بنجاح."
else
    fail "فشلت اختبارات Identity."
fi

python3 "${IDENTITY_DIR}/health.py" || true

log "تم إنشاء طبقة Identity وAuthentication بنجاح."
