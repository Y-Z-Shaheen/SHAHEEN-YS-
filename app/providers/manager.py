"""
AI Provider Key Manager for SHAHEEN-YS.

Features:
- Automatic key discovery from environment variables (BASE, BASE1, BASE2, …, BASEn)
- Thread-safe round-robin rotation (per Gunicorn worker — see note below)
- Failover on 401/403 (long cooldown), 429 (rate-limit backoff), timeout/5xx (short backoff)
- No plaintext key values in logs or API responses

Note on multi-worker deployments
---------------------------------
Rotation state is maintained per-process. In a Gunicorn multi-worker setup, each
worker tracks its own counter independently. This means the round-robin is not
globally synchronized across workers, but is fully correct and safe within a single
worker. Workload is naturally distributed by the OS scheduler across workers.
If you require global rotation state, add a shared counter in PostgreSQL or Redis.
"""

from __future__ import annotations

import logging
import os
import re
import threading
import time
from typing import Iterator

from .exceptions import (
    InvalidProviderError,
    NoAvailableKeyError,
)
from .models import (
    PROVIDER_BY_NAME,
    PROVIDER_REGISTRY,
    KeyRotationStrategy,
    KeyStatus,
    KeyUsageRecord,
    ProviderConfig,
    ProviderKey,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Cooldown durations (seconds)
# ---------------------------------------------------------------------------

_COOLDOWN_UNAUTHORIZED = 3600.0   # 401 / 403  → 1 hour
_COOLDOWN_RATE_LIMITED = 60.0     # 429         → 60 seconds
_COOLDOWN_SERVER_ERROR = 30.0     # 5xx         → 30 seconds
_COOLDOWN_TIMEOUT = 15.0          # timeout     → 15 seconds
_COOLDOWN_UNKNOWN = 10.0          # other error → 10 seconds


def _discover_keys(prefix: str) -> list[str]:
    """
    Discover all environment variable values for a given prefix.

    Order:
      1. BASE (no number suffix)  → index 0
      2. BASE1, BASE2, …, BASEn  → sorted numerically

    Empty strings and duplicates are removed.

    Example:
        prefix = "OPENAI_API_KEY"
        Discovers: OPENAI_API_KEY, OPENAI_API_KEY1, OPENAI_API_KEY2, …
    """
    discovered: list[str] = []

    # Base key (no numeric suffix)
    base_val = os.environ.get(prefix, "").strip()
    if base_val:
        discovered.append(base_val)

    # Numbered keys: PREFIX1, PREFIX2, …
    # Use a regex anchored to the exact prefix + digits only
    pattern = re.compile(rf"^{re.escape(prefix)}(\d+)$")
    numbered: dict[int, str] = {}
    for env_key, env_val in os.environ.items():
        m = pattern.match(env_key)
        if m:
            val = env_val.strip()
            if val:
                numbered[int(m.group(1))] = val

    # Add in strict numeric order (not alphabetical)
    for n in sorted(numbered.keys()):
        val = numbered[n]
        if val not in discovered:          # remove duplicates
            discovered.append(val)

    return discovered


class ProviderKeyManager:
    """
    Thread-safe AI provider key manager with round-robin and failover.

    Lifecycle
    ---------
    Instantiate once per process. Call load_from_env() on startup.
    Use get_key(provider) to obtain the next key.
    Call report_error(provider, key_value, …) after a failed request
    so the manager can apply the appropriate cooldown.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        # provider → ordered list of KeyUsageRecord
        self._keys: dict[str, list[KeyUsageRecord]] = {}
        # provider → current round-robin counter (wraps around)
        self._counters: dict[str, int] = {}
        self._loaded = False

    # ------------------------------------------------------------------
    # Setup
    # ------------------------------------------------------------------

    def load_from_env(self) -> None:
        """
        Discover all provider keys from environment variables.
        Safe to call multiple times — subsequent calls reload all keys.
        """
        with self._lock:
            self._load_unlocked()

    def _load_unlocked(self) -> None:
        """
        Internal key-discovery logic — MUST be called while already holding
        ``self._lock``. Extracted so that ``get_key()`` can trigger lazy
        loading without trying to re-acquire the non-reentrant lock.
        """
        self._keys.clear()
        self._counters.clear()

        for cfg in PROVIDER_REGISTRY:
            raw_keys = _discover_keys(cfg.env_prefix)
            records = [
                KeyUsageRecord(
                    key=ProviderKey(
                        provider=cfg.provider,
                        key_value=kv,
                        index=idx,
                    )
                )
                for idx, kv in enumerate(raw_keys)
            ]
            if records:
                self._keys[cfg.provider] = records
                self._counters[cfg.provider] = 0
                logger.debug(
                    "Loaded %d key(s) for provider '%s'",
                    len(records),
                    cfg.provider,
                )

        self._loaded = True

        total = sum(len(v) for v in self._keys.values())
        logger.info(
            "ProviderKeyManager loaded %d key(s) across %d provider(s)",
            total,
            len(self._keys),
        )

    # ------------------------------------------------------------------
    # Key retrieval
    # ------------------------------------------------------------------

    def get_key(self, provider: str) -> ProviderKey:
        """
        Return the next available key for the given provider.

        Uses round-robin rotation, skipping any keys that are on cooldown.

        Raises:
            InvalidProviderError: if the provider is not in the registry
                                  or no keys are configured.
            NoAvailableKeyError:  if all keys for the provider are
                                  currently on cooldown.
        """
        provider = provider.lower()

        if provider not in PROVIDER_BY_NAME:
            raise InvalidProviderError(
                f"Unknown provider: {provider!r}. "
                f"Supported: {sorted(PROVIDER_BY_NAME)}"
            )

        with self._lock:
            if not self._loaded:
                # Call the internal helper — we already hold the lock.
                # Never call load_from_env() here; that would deadlock on
                # the non-reentrant threading.Lock.
                self._load_unlocked()

            records = self._keys.get(provider)
            if not records:
                raise InvalidProviderError(
                    f"No keys configured for provider '{provider}'. "
                    f"Set {PROVIDER_BY_NAME[provider].env_prefix} in environment."
                )

            now = time.monotonic()
            n = len(records)

            # Scan up to n slots starting from current counter
            start = self._counters[provider]
            for offset in range(n):
                idx = (start + offset) % n
                record = records[idx]
                if record.is_available(now):
                    # Advance counter past this slot for next call
                    self._counters[provider] = (idx + 1) % n
                    return record.key

            raise NoAvailableKeyError(
                f"All {n} key(s) for provider '{provider}' are on cooldown. "
                "Try again later."
            )

    def has_provider(self, provider: str) -> bool:
        """Return True if at least one key is configured for this provider."""
        provider = provider.lower()
        with self._lock:
            return bool(self._keys.get(provider))

    def provider_key_count(self, provider: str) -> int:
        """Return the number of keys configured for this provider."""
        provider = provider.lower()
        with self._lock:
            return len(self._keys.get(provider, []))

    def available_providers(self) -> list[str]:
        """Return list of providers that have at least one key configured."""
        with self._lock:
            return sorted(self._keys.keys())

    # ------------------------------------------------------------------
    # Error reporting / failover
    # ------------------------------------------------------------------

    def report_error(
        self,
        provider: str,
        key_value: str,
        *,
        status_code: int | None = None,
        error_type: str = "unknown",
    ) -> None:
        """
        Report a failed request so the manager can apply a cooldown.

        Arguments:
            provider:    Provider name (e.g. "openai").
            key_value:   The exact key value that failed (not logged).
            status_code: HTTP status code if available.
            error_type:  One of "timeout", "connection", or any string.

        Cooldown rules:
            401 / 403 → key marked unauthorized for 1 hour
            429       → key rate-limited for 60 seconds
            5xx       → short error cooldown of 30 seconds
            timeout   → short cooldown of 15 seconds
            other     → 10-second cooldown
        """
        provider = provider.lower()
        cooldown = self._cooldown_for(status_code, error_type)
        new_status = self._status_for(status_code, error_type)

        with self._lock:
            records = self._keys.get(provider, [])
            for record in records:
                if record.key.key_value == key_value:
                    record.cooldown_until = time.monotonic() + cooldown
                    record.consecutive_errors += 1
                    record.status = new_status
                    logger.warning(
                        "Provider '%s' key %s reported error "
                        "(status=%s, type=%s, cooldown=%.0fs)",
                        provider,
                        record.key.masked(),
                        status_code,
                        error_type,
                        cooldown,
                    )
                    break

    def report_success(self, provider: str, key_value: str) -> None:
        """Reset error state for a key after a successful request."""
        provider = provider.lower()
        with self._lock:
            records = self._keys.get(provider, [])
            for record in records:
                if record.key.key_value == key_value:
                    record.cooldown_until = 0.0
                    record.consecutive_errors = 0
                    record.status = KeyStatus.AVAILABLE
                    break

    # ------------------------------------------------------------------
    # Status / introspection (safe for API responses — no key values)
    # ------------------------------------------------------------------

    def status_snapshot(self) -> dict:
        """
        Return a safe status snapshot for monitoring endpoints.
        Never includes key values.
        """
        now = time.monotonic()
        with self._lock:
            snapshot: dict = {}
            for provider, records in self._keys.items():
                available = sum(1 for r in records if r.is_available(now))
                snapshot[provider] = {
                    "total_keys": len(records),
                    "available_keys": available,
                    "on_cooldown": len(records) - available,
                }
            return snapshot

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _cooldown_for(status_code: int | None, error_type: str) -> float:
        if status_code in (401, 403):
            return _COOLDOWN_UNAUTHORIZED
        if status_code == 429:
            return _COOLDOWN_RATE_LIMITED
        if status_code is not None and 500 <= status_code < 600:
            return _COOLDOWN_SERVER_ERROR
        if error_type in ("timeout", "connection"):
            return _COOLDOWN_TIMEOUT
        return _COOLDOWN_UNKNOWN

    @staticmethod
    def _status_for(status_code: int | None, error_type: str) -> KeyStatus:
        if status_code in (401, 403):
            return KeyStatus.UNAUTHORIZED
        if status_code == 429:
            return KeyStatus.RATE_LIMITED
        return KeyStatus.ERROR


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------

_manager_lock = threading.Lock()
_manager: ProviderKeyManager | None = None


def get_provider_manager() -> ProviderKeyManager:
    """
    Return the process-level ProviderKeyManager singleton.

    Keys are loaded from environment variables on first access.
    """
    global _manager
    if _manager is None:
        with _manager_lock:
            if _manager is None:
                _manager = ProviderKeyManager()
                _manager.load_from_env()
    return _manager
