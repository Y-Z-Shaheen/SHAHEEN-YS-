#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${PROJECT_ROOT}/data/cache"
CACHE_CONFIG_DIR="${PROJECT_ROOT}/config"

log() {
    printf '[06-cache] %s\n' "$1"
}

error() {
    printf '[06-cache][ERROR] %s\n' "$1" >&2
}

mkdir -p "${CACHE_DIR}"
mkdir -p "${CACHE_CONFIG_DIR}"

cat << 'PY_EOF' > "${PROJECT_ROOT}/app/cache.py"
from __future__ import annotations

import json
import os
import threading
import time
from dataclasses import dataclass
from typing import Any


try:
    import redis
except ImportError:
    redis = None


@dataclass
class CacheEntry:
    value: Any
    expires_at: float | None


class MemoryCache:
    """
    ذاكرة Cache داخلية تستخدم كـ fallback عندما لا يتوفر Redis.
    """

    def __init__(self) -> None:
        self._storage: dict[str, CacheEntry] = {}
        self._lock = threading.RLock()

    def set(
        self,
        key: str,
        value: Any,
        ttl: int | None = None,
    ) -> bool:
        expires_at = None

        if ttl is not None:
            if ttl <= 0:
                raise ValueError("TTL must be greater than zero.")

            expires_at = time.time() + ttl

        with self._lock:
            self._storage[key] = CacheEntry(
                value=value,
                expires_at=expires_at,
            )

        return True

    def get(self, key: str) -> Any | None:
        with self._lock:
            entry = self._storage.get(key)

            if entry is None:
                return None

            if (
                entry.expires_at is not None
                and time.time() >= entry.expires_at
            ):
                del self._storage[key]
                return None

            return entry.value

    def delete(self, key: str) -> bool:
        with self._lock:
            return self._storage.pop(key, None) is not None

    def exists(self, key: str) -> bool:
        return self.get(key) is not None

    def clear(self) -> None:
        with self._lock:
            self._storage.clear()

    def health_check(self) -> dict[str, Any]:
        return {
            "status": "healthy",
            "backend": "memory",
            "entries": len(self._storage),
        }


class RedisCache:
    """
    Redis backend اختياري.
    """

    def __init__(self, url: str) -> None:
        if redis is None:
            raise RuntimeError(
                "redis Python package is not installed."
            )

        self.client = redis.Redis.from_url(
            url,
            decode_responses=True,
            socket_connect_timeout=3,
            socket_timeout=3,
            health_check_interval=30,
        )

    def set(
        self,
        key: str,
        value: Any,
        ttl: int | None = None,
    ) -> bool:
        serialized_value = json.dumps(
            value,
            ensure_ascii=False,
        )

        return bool(
            self.client.set(
                name=key,
                value=serialized_value,
                ex=ttl,
            )
        )

    def get(self, key: str) -> Any | None:
        value = self.client.get(key)

        if value is None:
            return None

        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return value

    def delete(self, key: str) -> bool:
        return bool(self.client.delete(key))

    def exists(self, key: str) -> bool:
        return bool(self.client.exists(key))

    def health_check(self) -> dict[str, Any]:
        try:
            latency_start = time.perf_counter()
            self.client.ping()
            latency_ms = round(
                (time.perf_counter() - latency_start) * 1000,
                2,
            )

            return {
                "status": "healthy",
                "backend": "redis",
                "latency_ms": latency_ms,
            }

        except Exception as error:
            return {
                "status": "unhealthy",
                "backend": "redis",
                "error": str(error),
            }


def create_cache() -> MemoryCache | RedisCache:
    """
    اختيار Redis عند توفره، وإلا استخدام Memory Cache.
    """

    cache_backend = os.getenv(
        "SHAHEEN_CACHE_BACKEND",
        "auto",
    ).lower()

    redis_url = os.getenv(
        "REDIS_URL",
        "redis://127.0.0.1:6379/0",
    )

    if cache_backend == "memory":
        return MemoryCache()

    if cache_backend == "redis":
        if redis is None:
            raise RuntimeError(
                "Redis backend requested but redis package is not installed."
            )

        return RedisCache(redis_url)

    if cache_backend == "auto" and redis is not None:
        try:
            redis_cache = RedisCache(redis_url)

            if redis_cache.health_check()["status"] == "healthy":
                return redis_cache

        except Exception:
            pass

    return MemoryCache()


cache = create_cache()


def cache_health_check() -> dict[str, Any]:
    return cache.health_check()
PY_EOF

cat << 'PY_EOF' > "${PROJECT_ROOT}/app/cache_health.py"
from __future__ import annotations

from app.cache import cache_health_check


def main() -> int:
    result = cache_health_check()

    print(result)

    return 0 if result.get("status") == "healthy" else 1


if __name__ == "__main__":
    raise SystemExit(main())
PY_EOF

cat << 'ENV_EOF' > "${CACHE_CONFIG_DIR}/cache.env.example"
# auto = Redis إذا كان متاحاً، وإلا Memory Cache
SHAHEEN_CACHE_BACKEND=auto

# Redis URL المحلي
REDIS_URL=redis://127.0.0.1:6379/0
ENV_EOF

cat << 'PY_EOF' > "${PROJECT_ROOT}/app/cache_test.py"
from __future__ import annotations

from app.cache import cache


def main() -> int:
    test_key = "shaheen:test:key"
    test_value = {
        "project": "SHAHEEN-YS",
        "status": "working",
    }

    cache.set(
        key=test_key,
        value=test_value,
        ttl=60,
    )

    result = cache.get(test_key)

    if result != test_value:
        print("Cache test failed.")
        return 1

    print("Cache test passed.")
    print(f"Backend: {type(cache).__name__}")
    print(f"Value: {result}")

    cache.delete(test_key)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY_EOF

chmod 600 "${CACHE_CONFIG_DIR}/cache.env.example"

log "تم إنشاء طبقة Cache بنجاح."
log "Redis اختياري، وMemory Cache يعمل كـ fallback."

if python3 -c "import app.cache" 2>/dev/null; then
    log "تم تحميل طبقة Cache بنجاح."
else
    error "فشل تحميل طبقة Cache."
    exit 1
fi

if python3 "${PROJECT_ROOT}/app/cache_test.py"; then
    log "تم اجتياز اختبار Cache بنجاح."
else
    error "فشل اختبار Cache."
    exit 1
fi

python3 "${PROJECT_ROOT}/app/cache_health.py" || true

log "اكتمل السكريبت السادس بنجاح."
