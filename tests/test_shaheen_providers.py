"""
Tests for the AI Provider Key Manager (app/providers/).

Covers:
- Key discovery from environment variables
- Base key (no suffix) + numbered keys (KEY1, KEY2, …)
- Numeric ordering (not alphabetical)
- Empty key filtering
- Duplicate removal
- Unlimited key count
- Round-robin rotation
- Failover: 401/403 → long cooldown
- Failover: 429 → rate-limit cooldown
- Failover: timeout / connection error → short cooldown
- Failover: 5xx → short cooldown
- All keys on cooldown → NoAvailableKeyError
- Key values never appear in logs
- report_success clears cooldown
- status_snapshot contains no key values
"""

from __future__ import annotations

import logging
import time
from unittest.mock import patch

import pytest

from app.providers.exceptions import InvalidProviderError, NoAvailableKeyError
from app.providers.manager import ProviderKeyManager, _discover_keys
from app.providers.models import ProviderKey


# ---------------------------------------------------------------------------
# _discover_keys unit tests
# ---------------------------------------------------------------------------


class TestDiscoverKeys:
    def test_base_key_only(self):
        env = {"OPENAI_API_KEY": "key-base"}
        with patch.dict("os.environ", env, clear=True):
            keys = _discover_keys("OPENAI_API_KEY")
        assert keys == ["key-base"]

    def test_numbered_keys_only(self):
        env = {"OPENAI_API_KEY1": "key-1", "OPENAI_API_KEY2": "key-2"}
        with patch.dict("os.environ", env, clear=True):
            keys = _discover_keys("OPENAI_API_KEY")
        assert keys == ["key-1", "key-2"]

    def test_base_and_numbered_keys(self):
        env = {
            "OPENAI_API_KEY": "key-base",
            "OPENAI_API_KEY1": "key-1",
            "OPENAI_API_KEY2": "key-2",
        }
        with patch.dict("os.environ", env, clear=True):
            keys = _discover_keys("OPENAI_API_KEY")
        assert keys == ["key-base", "key-1", "key-2"]

    def test_numeric_ordering_not_alphabetical(self):
        # Alphabetically: 1, 10, 2 — but numeric order: 1, 2, 10
        env = {
            "OPENAI_API_KEY1": "key-1",
            "OPENAI_API_KEY10": "key-10",
            "OPENAI_API_KEY2": "key-2",
        }
        with patch.dict("os.environ", env, clear=True):
            keys = _discover_keys("OPENAI_API_KEY")
        assert keys == ["key-1", "key-2", "key-10"]

    def test_empty_values_are_filtered(self):
        env = {
            "OPENAI_API_KEY": "key-base",
            "OPENAI_API_KEY1": "",
            "OPENAI_API_KEY2": "   ",
            "OPENAI_API_KEY3": "key-3",
        }
        with patch.dict("os.environ", env, clear=True):
            keys = _discover_keys("OPENAI_API_KEY")
        assert keys == ["key-base", "key-3"]

    def test_duplicates_are_removed(self):
        env = {
            "OPENAI_API_KEY": "same-key",
            "OPENAI_API_KEY1": "same-key",
            "OPENAI_API_KEY2": "other-key",
        }
        with patch.dict("os.environ", env, clear=True):
            keys = _discover_keys("OPENAI_API_KEY")
        assert keys == ["same-key", "other-key"]

    def test_no_keys_returns_empty_list(self):
        with patch.dict("os.environ", {}, clear=True):
            keys = _discover_keys("OPENAI_API_KEY")
        assert keys == []

    def test_unlimited_key_count(self):
        env = {"OPENAI_API_KEY": "base"} | {
            f"OPENAI_API_KEY{i}": f"key-{i}" for i in range(1, 51)
        }
        with patch.dict("os.environ", env, clear=True):
            keys = _discover_keys("OPENAI_API_KEY")
        assert len(keys) == 51
        assert keys[0] == "base"
        assert keys[50] == "key-50"

    def test_partial_prefix_not_matched(self):
        # OPENAI_API_KEYS should NOT be matched when looking for OPENAI_API_KEY
        env = {"OPENAI_API_KEYS": "wrong"}
        with patch.dict("os.environ", env, clear=True):
            keys = _discover_keys("OPENAI_API_KEY")
        assert keys == []


# ---------------------------------------------------------------------------
# ProviderKeyManager helpers
# ---------------------------------------------------------------------------


def _manager_with_keys(env: dict) -> ProviderKeyManager:
    """Create and load a fresh ProviderKeyManager with the given env."""
    mgr = ProviderKeyManager()
    with patch.dict("os.environ", env, clear=True):
        mgr.load_from_env()
    return mgr


# ---------------------------------------------------------------------------
# Key discovery via manager
# ---------------------------------------------------------------------------


class TestManagerKeyDiscovery:
    def test_detects_base_key(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk-base"})
        assert mgr.has_provider("openai")
        assert mgr.provider_key_count("openai") == 1

    def test_detects_numbered_keys(self):
        mgr = _manager_with_keys(
            {
                "OPENAI_API_KEY": "sk-0",
                "OPENAI_API_KEY1": "sk-1",
                "OPENAI_API_KEY2": "sk-2",
            }
        )
        assert mgr.provider_key_count("openai") == 3

    def test_provider_with_no_keys(self):
        mgr = _manager_with_keys({})
        assert not mgr.has_provider("openai")

    def test_available_providers_sorted(self):
        mgr = _manager_with_keys(
            {"OPENAI_API_KEY": "sk", "ANTHROPIC_API_KEY": "ant"}
        )
        providers = mgr.available_providers()
        assert "openai" in providers
        assert "anthropic" in providers
        assert providers == sorted(providers)

    def test_unknown_provider_raises_invalid(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk"})
        with pytest.raises(InvalidProviderError):
            mgr.get_key("nonexistent_provider_xyz")

    def test_known_provider_no_keys_raises_invalid(self):
        mgr = _manager_with_keys({})
        with pytest.raises(InvalidProviderError):
            mgr.get_key("openai")


# ---------------------------------------------------------------------------
# Round-robin rotation
# ---------------------------------------------------------------------------


class TestRoundRobin:
    def test_single_key_always_returned(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk-only"})
        for _ in range(10):
            key = mgr.get_key("openai")
            assert key.key_value == "sk-only"

    def test_two_keys_alternate(self):
        mgr = _manager_with_keys(
            {"OPENAI_API_KEY": "sk-0", "OPENAI_API_KEY1": "sk-1"}
        )
        first = mgr.get_key("openai").key_value
        second = mgr.get_key("openai").key_value
        third = mgr.get_key("openai").key_value
        assert first != second
        assert third == first

    def test_three_keys_cycle(self):
        mgr = _manager_with_keys(
            {
                "OPENAI_API_KEY": "sk-0",
                "OPENAI_API_KEY1": "sk-1",
                "OPENAI_API_KEY2": "sk-2",
            }
        )
        seen = [mgr.get_key("openai").key_value for _ in range(6)]
        assert seen[0] == seen[3]
        assert seen[1] == seen[4]
        assert seen[2] == seen[5]
        assert len(set(seen)) == 3

    def test_returned_object_is_provider_key(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk-test"})
        key = mgr.get_key("openai")
        assert isinstance(key, ProviderKey)
        assert key.provider == "openai"


# ---------------------------------------------------------------------------
# Failover — 401 / 403 (unauthorized)
# ---------------------------------------------------------------------------


class TestFailoverUnauthorized:
    @pytest.mark.parametrize("status_code", [401, 403])
    def test_unauthorized_key_is_skipped(self, status_code):
        mgr = _manager_with_keys(
            {"OPENAI_API_KEY": "sk-bad", "OPENAI_API_KEY1": "sk-good"}
        )
        bad_key = mgr.get_key("openai").key_value
        mgr.report_error("openai", bad_key, status_code=status_code)
        next_key = mgr.get_key("openai")
        assert next_key.key_value != bad_key

    def test_single_unauthorized_key_raises_no_available(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk-bad"})
        mgr.report_error("openai", "sk-bad", status_code=401)
        with pytest.raises(NoAvailableKeyError):
            mgr.get_key("openai")

    def test_unauthorized_cooldown_is_long(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk-bad"})
        mgr.report_error("openai", "sk-bad", status_code=401)
        # Cooldown should be > 30 minutes for unauthorized keys
        record = mgr._keys["openai"][0]
        remaining = record.cooldown_until - time.monotonic()
        assert remaining > 1800


# ---------------------------------------------------------------------------
# Failover — 429 (rate limited)
# ---------------------------------------------------------------------------


class TestFailoverRateLimited:
    def test_rate_limited_key_is_skipped(self):
        mgr = _manager_with_keys(
            {"OPENAI_API_KEY": "sk-limited", "OPENAI_API_KEY1": "sk-ok"}
        )
        limited_key = mgr.get_key("openai").key_value
        mgr.report_error("openai", limited_key, status_code=429)
        next_key = mgr.get_key("openai")
        assert next_key.key_value != limited_key

    def test_429_cooldown_is_moderate(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk-limited"})
        mgr.report_error("openai", "sk-limited", status_code=429)
        record = mgr._keys["openai"][0]
        remaining = record.cooldown_until - time.monotonic()
        # Should be around 60 seconds, definitely less than 10 minutes
        assert 10 < remaining < 600


# ---------------------------------------------------------------------------
# Failover — timeout / connection error
# ---------------------------------------------------------------------------


class TestFailoverTimeout:
    def test_timeout_key_gets_short_cooldown(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk-slow"})
        mgr.report_error("openai", "sk-slow", error_type="timeout")
        record = mgr._keys["openai"][0]
        remaining = record.cooldown_until - time.monotonic()
        # Short cooldown: > 0 but < 60 seconds
        assert 0 < remaining < 60

    def test_connection_error_gets_short_cooldown(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk-down"})
        mgr.report_error("openai", "sk-down", error_type="connection")
        record = mgr._keys["openai"][0]
        remaining = record.cooldown_until - time.monotonic()
        assert 0 < remaining < 60


# ---------------------------------------------------------------------------
# Failover — 5xx
# ---------------------------------------------------------------------------


class TestFailoverServerError:
    @pytest.mark.parametrize("status_code", [500, 502, 503])
    def test_server_error_gets_cooldown(self, status_code):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk"})
        mgr.report_error("openai", "sk", status_code=status_code)
        record = mgr._keys["openai"][0]
        remaining = record.cooldown_until - time.monotonic()
        assert remaining > 0


# ---------------------------------------------------------------------------
# All keys exhausted
# ---------------------------------------------------------------------------


class TestAllKeysExhausted:
    def test_all_keys_on_cooldown_raises(self):
        mgr = _manager_with_keys(
            {"OPENAI_API_KEY": "sk-0", "OPENAI_API_KEY1": "sk-1"}
        )
        mgr.report_error("openai", "sk-0", status_code=401)
        mgr.report_error("openai", "sk-1", status_code=401)
        with pytest.raises(NoAvailableKeyError):
            mgr.get_key("openai")


# ---------------------------------------------------------------------------
# report_success clears cooldown
# ---------------------------------------------------------------------------


class TestReportSuccess:
    def test_success_clears_cooldown(self):
        mgr = _manager_with_keys({"OPENAI_API_KEY": "sk"})
        mgr.report_error("openai", "sk", status_code=429)
        with pytest.raises(NoAvailableKeyError):
            mgr.get_key("openai")
        mgr.report_success("openai", "sk")
        key = mgr.get_key("openai")
        assert key.key_value == "sk"


# ---------------------------------------------------------------------------
# Key values never appear in logs
# ---------------------------------------------------------------------------


class TestNoKeyLeakInLogs:
    def test_key_value_not_in_warning_log(self, caplog):
        secret = "sk-super-secret-12345"
        mgr = _manager_with_keys({"OPENAI_API_KEY": secret})
        with caplog.at_level(logging.WARNING):
            mgr.report_error("openai", secret, status_code=429)
        for record in caplog.records:
            assert secret not in record.getMessage()

    def test_masked_repr_does_not_expose_full_value(self):
        secret = "sk-super-secret-12345"
        key = ProviderKey(provider="openai", key_value=secret, index=0)
        assert secret not in repr(key)
        assert secret not in str(key)
        assert "***" in key.masked() or "..." in key.masked()


# ---------------------------------------------------------------------------
# status_snapshot — no key values
# ---------------------------------------------------------------------------


class TestStatusSnapshot:
    def test_snapshot_contains_no_key_values(self):
        secret = "sk-super-secret-12345"
        mgr = _manager_with_keys({"OPENAI_API_KEY": secret})
        snapshot = mgr.status_snapshot()
        snapshot_str = str(snapshot)
        assert secret not in snapshot_str

    def test_snapshot_shows_total_and_available(self):
        mgr = _manager_with_keys(
            {"OPENAI_API_KEY": "sk-0", "OPENAI_API_KEY1": "sk-1"}
        )
        snap = mgr.status_snapshot()
        assert snap["openai"]["total_keys"] == 2
        assert snap["openai"]["available_keys"] == 2
        assert snap["openai"]["on_cooldown"] == 0

    def test_snapshot_reflects_cooldown(self):
        mgr = _manager_with_keys(
            {"OPENAI_API_KEY": "sk-0", "OPENAI_API_KEY1": "sk-1"}
        )
        mgr.report_error("openai", "sk-0", status_code=401)
        snap = mgr.status_snapshot()
        assert snap["openai"]["on_cooldown"] == 1
        assert snap["openai"]["available_keys"] == 1


# ---------------------------------------------------------------------------
# Lazy initialisation — regression test for lock deadlock
# ---------------------------------------------------------------------------


class TestLazyInitialisation:
    def test_get_key_without_explicit_load_from_env(self):
        """
        ProviderKeyManager() + immediate get_key() must NOT deadlock.

        Previously, get_key() acquired self._lock and then called
        load_from_env() which tried to acquire the same non-reentrant lock
        a second time, hanging forever.  This test would time out (or block)
        if the bug regresses.
        """
        import threading

        result = {"key": None, "error": None}

        def _call():
            mgr = ProviderKeyManager()
            with patch.dict("os.environ", {"OPENAI_API_KEY": "sk-lazy"}, clear=True):
                # Intentionally do NOT call load_from_env() first
                try:
                    result["key"] = mgr.get_key("openai")
                except Exception as exc:
                    result["error"] = exc

        t = threading.Thread(target=_call, daemon=True)
        t.start()
        t.join(timeout=5)  # 5 seconds is far more than enough; deadlock = hung

        assert not t.is_alive(), "get_key() deadlocked (thread still running)"
        assert result["error"] is None, f"Unexpected error: {result['error']}"
        assert result["key"] is not None
        assert result["key"].key_value == "sk-lazy"

    def test_concurrent_get_key_calls_do_not_deadlock(self):
        """Multiple threads calling get_key() concurrently must all complete."""
        import threading

        errors = []

        def _call():
            mgr = ProviderKeyManager()
            with patch.dict(
                "os.environ",
                {"OPENAI_API_KEY": "sk-a", "OPENAI_API_KEY1": "sk-b"},
                clear=True,
            ):
                try:
                    for _ in range(10):
                        mgr.get_key("openai")
                except Exception as exc:
                    errors.append(exc)

        threads = [threading.Thread(target=_call, daemon=True) for _ in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

        still_alive = [t for t in threads if t.is_alive()]
        assert not still_alive, f"{len(still_alive)} thread(s) deadlocked"
        assert not errors, f"Errors in threads: {errors}"


# ---------------------------------------------------------------------------
# Provider model: ProviderKey
# ---------------------------------------------------------------------------


class TestProviderKeyModel:
    def test_short_key_is_fully_masked(self):
        key = ProviderKey(provider="test", key_value="short", index=0)
        assert key.masked() == "***"

    def test_long_key_shows_prefix_and_suffix(self):
        key = ProviderKey(provider="test", key_value="sk-1234567890abcdef", index=0)
        masked = key.masked()
        assert masked.startswith("sk-1")
        assert masked.endswith("cdef")
        assert "..." in masked
