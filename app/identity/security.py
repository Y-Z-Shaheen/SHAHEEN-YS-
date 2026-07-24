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
