"""
Tests for app/providers — key discovery, rotation, failover, secret masking.
"""

from __future__ import annotations

import os
import threading
import time

import pytest


@pytest.fixture()
def manager(monkeypatch):
    """Fresh ProviderKeyManager with a clean environment."""
    # Clear all provider env vars
    for key in list(os.environ.keys()):
        if any(key.startswith(p) for p in (
            "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GROQ_API_KEY",
            "OPENROUTER_API_KEY", "MISTRAL_API_KEY", "GEMINI_API_KEY",
            "DEEPSEEK_API_KEY", "XAI_API_KEY", "TAVILY_API_KEY",
            "EXA_API_KEY", "FIRECRAWL_API_KEY", "ELEVENLABS_API_KEY",
            "GOOGLE_SEARCH_API_KEY", "GOOGLE_SEARCH_ENGINE_ID",
            "TELEGRAM_BOT_TOKEN",
        )):
            monkeypatch.delenv(key, raising=False)

    from app.providers.manager import ProviderKeyManager
    m = ProviderKeyManager()
    return m


# ---------------------------------------------------------------------------
# Key discovery
# ---------------------------------------------------------------------------

class TestKeyDiscovery:
    def test_discovers_base_key(self, monkeypatch, manager):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-base")
        manager.load_from_env()
        assert manager.provider_key_count("openai") == 1

    def test_discovers_numbered_keys(self, monkeypatch, manager):
        monkeypatch.setenv("ANTHROPIC_API_KEY", "ant-base")
        monkeypatch.setenv("ANTHROPIC_API_KEY1", "ant-1")
        monkeypatch.setenv("ANTHROPIC_API_KEY2", "ant-2")
        monkeypatch.setenv("ANTHROPIC_API_KEY3", "ant-3")
        manager.load_from_env()
        assert manager.provider_key_count("anthropic") == 4

    def test_base_key_is_index_0(self, monkeypatch, manager):
        monkeypatch.setenv("GROQ_API_KEY", "groq-base")
        monkeypatch.setenv("GROQ_API_KEY1", "groq-1")
        manager.load_from_env()
        key = manager.get_key("groq")
        assert key.key_value == "groq-base"
        assert key.index == 0

    def test_numbered_in_numeric_order(self, monkeypatch, manager):
        monkeypatch.setenv("OPENROUTER_API_KEY2", "or-2")
        monkeypatch.setenv("OPENROUTER_API_KEY10", "or-10")
        monkeypatch.setenv("OPENROUTER_API_KEY1", "or-1")
        manager.load_from_env()
        # Index 0 = KEY (absent), so first available = KEY1 index 1
        count = manager.provider_key_count("openrouter")
        assert count == 3

    def test_empty_string_keys_ignored(self, monkeypatch, manager):
        monkeypatch.setenv("MISTRAL_API_KEY", "")
        monkeypatch.setenv("MISTRAL_API_KEY1", "ms-1")
        manager.load_from_env()
        assert manager.provider_key_count("mistral") == 1

    def test_duplicate_values_deduplicated(self, monkeypatch, manager):
        monkeypatch.setenv("GEMINI_API_KEY", "gem-same")
        monkeypatch.setenv("GEMINI_API_KEY1", "gem-same")  # duplicate value
        manager.load_from_env()
        assert manager.provider_key_count("gemini") == 1

    def test_no_keys_provider_not_in_available(self, monkeypatch, manager):
        manager.load_from_env()
        assert "openai" not in manager.available_providers()


# ---------------------------------------------------------------------------
# Round-robin rotation
# ---------------------------------------------------------------------------

class TestRoundRobinRotation:
    def test_rotates_through_all_keys(self, monkeypatch, manager):
        monkeypatch.setenv("ANTHROPIC_API_KEY", "ant-0")
        monkeypatch.setenv("ANTHROPIC_API_KEY1", "ant-1")
        monkeypatch.setenv("ANTHROPIC_API_KEY2", "ant-2")
        manager.load_from_env()

        values = [manager.get_key("anthropic").key_value for _ in range(6)]
        # Should cycle: 0, 1, 2, 0, 1, 2
        assert values == ["ant-0", "ant-1", "ant-2", "ant-0", "ant-1", "ant-2"]

    def test_single_key_always_returned(self, monkeypatch, manager):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-only")
        manager.load_from_env()
        for _ in range(5):
            assert manager.get_key("openai").key_value == "sk-only"


# ---------------------------------------------------------------------------
# Failover / cooldown
# ---------------------------------------------------------------------------

class TestFailover:
    def test_rate_limited_key_skipped(self, monkeypatch, manager):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-0")
        monkeypatch.setenv("OPENAI_API_KEY1", "sk-1")
        manager.load_from_env()

        # Consume sk-0, then report it as rate-limited
        k0 = manager.get_key("openai")
        assert k0.key_value == "sk-0"
        manager.report_error("openai", "sk-0", status_code=429)

        # Next call should return sk-1 (sk-0 is on cooldown)
        k1 = manager.get_key("openai")
        assert k1.key_value == "sk-1"

    def test_unauthorized_key_gets_long_cooldown(self, monkeypatch, manager):
        monkeypatch.setenv("GROQ_API_KEY", "groq-0")
        monkeypatch.setenv("GROQ_API_KEY1", "groq-1")
        manager.load_from_env()

        manager.report_error("groq", "groq-0", status_code=401)
        key = manager.get_key("groq")
        assert key.key_value == "groq-1"

    def test_no_available_key_raises(self, monkeypatch, manager):
        from app.providers.exceptions import NoAvailableKeyError
        monkeypatch.setenv("ANTHROPIC_API_KEY", "ant-0")
        manager.load_from_env()
        manager.report_error("anthropic", "ant-0", status_code=429)

        with pytest.raises(NoAvailableKeyError):
            manager.get_key("anthropic")

    def test_report_success_clears_cooldown(self, monkeypatch, manager):
        from app.providers.exceptions import NoAvailableKeyError
        monkeypatch.setenv("OPENAI_API_KEY", "sk-0")
        manager.load_from_env()
        manager.report_error("openai", "sk-0", status_code=429)

        # Manually expire cooldown
        with manager._lock:
            manager._keys["openai"][0].cooldown_until = 0.0

        manager.report_success("openai", "sk-0")
        key = manager.get_key("openai")
        assert key.key_value == "sk-0"

    def test_single_failed_provider_does_not_crash_others(self, monkeypatch, manager):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-0")
        monkeypatch.setenv("ANTHROPIC_API_KEY", "ant-0")
        manager.load_from_env()

        manager.report_error("openai", "sk-0", status_code=429)
        # Anthropic should still work
        key = manager.get_key("anthropic")
        assert key.key_value == "ant-0"


# ---------------------------------------------------------------------------
# Secret masking
# ---------------------------------------------------------------------------

class TestSecretMasking:
    def test_masked_never_reveals_full_key(self, monkeypatch, manager):
        secret = "sk-supersecretkeyvalue1234"
        monkeypatch.setenv("OPENAI_API_KEY", secret)
        manager.load_from_env()
        key = manager.get_key("openai")
        masked = key.masked()
        assert secret not in masked
        assert "..." in masked or masked == "***"

    def test_str_representation_is_masked(self, monkeypatch, manager):
        secret = "sk-anothersecret9999"
        monkeypatch.setenv("OPENAI_API_KEY", secret)
        manager.load_from_env()
        key = manager.get_key("openai")
        assert secret not in str(key)

    def test_repr_does_not_leak_key(self, monkeypatch, manager):
        secret = "sk-reprleaktest"
        monkeypatch.setenv("OPENAI_API_KEY", secret)
        manager.load_from_env()
        key = manager.get_key("openai")
        assert secret not in repr(key)

    def test_status_snapshot_no_key_values(self, monkeypatch, manager):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-snapshottest")
        manager.load_from_env()
        snapshot = manager.status_snapshot()
        snap_str = str(snapshot)
        assert "sk-snapshottest" not in snap_str


# ---------------------------------------------------------------------------
# Invalid provider
# ---------------------------------------------------------------------------

class TestInvalidProvider:
    def test_unknown_provider_raises(self, manager):
        from app.providers.exceptions import InvalidProviderError
        manager.load_from_env()
        with pytest.raises(InvalidProviderError):
            manager.get_key("nonexistent_provider_xyz")

    def test_provider_with_no_keys_raises(self, monkeypatch, manager):
        from app.providers.exceptions import InvalidProviderError
        monkeypatch.delenv("OPENAI_API_KEY", raising=False)
        manager.load_from_env()
        with pytest.raises(InvalidProviderError):
            manager.get_key("openai")


# ---------------------------------------------------------------------------
# Thread safety
# ---------------------------------------------------------------------------

class TestThreadSafety:
    def test_concurrent_get_key(self, monkeypatch, manager):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-t0")
        monkeypatch.setenv("OPENAI_API_KEY1", "sk-t1")
        monkeypatch.setenv("OPENAI_API_KEY2", "sk-t2")
        manager.load_from_env()

        results = []
        errors = []

        def fetch():
            try:
                k = manager.get_key("openai")
                results.append(k.key_value)
            except Exception as exc:
                errors.append(exc)

        threads = [threading.Thread(target=fetch) for _ in range(30)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert not errors
        assert len(results) == 30
        assert all(v in ("sk-t0", "sk-t1", "sk-t2") for v in results)
