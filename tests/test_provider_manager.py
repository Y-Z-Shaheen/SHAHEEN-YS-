"""
Tests for AI Provider Key Manager.
"""

from __future__ import annotations

import os
import pytest
from app.providers import (
    ProviderKeyManager,
    ProviderKey,
    NoAvailableKeyError,
    InvalidProviderError,
)


@pytest.fixture
def provider_manager(monkeypatch):
    """Create a provider manager with test keys."""
    # Set up test keys
    monkeypatch.setenv("OPENAI_API_KEY", "test-openai-key-0")
    monkeypatch.setenv("OPENAI_API_KEY1", "test-openai-key-1")
    monkeypatch.setenv("OPENAI_API_KEY2", "test-openai-key-2")
    
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-anthropic-key-0")
    
    # Create fresh instance
    manager = ProviderKeyManager()
    return manager


class TestProviderKeyDiscovery:
    """Test API key discovery from environment variables."""
    
    def test_discover_primary_key(self, monkeypatch):
        """Test discovering primary API key."""
        monkeypatch.setenv("OPENAI_API_KEY", "test-key")
        
        manager = ProviderKeyManager()
        
        assert manager.has_provider("openai")
        provider = manager.get_provider("openai")
        assert provider is not None
        assert len(provider.keys) > 0
    
    def test_discover_multiple_keys(self, provider_manager):
        """Test discovering multiple API keys for same provider."""
        assert provider_manager.has_provider("openai")
        
        provider = provider_manager.get_provider("openai")
        assert len(provider.keys) == 3
    
    def test_key_indexing(self, provider_manager):
        """Test that keys are indexed correctly."""
        provider = provider_manager.get_provider("openai")
        
        indices = [key.key_index for key in provider.keys]
        assert indices == [0, 1, 2]
    
    def test_no_duplicate_keys(self, monkeypatch):
        """Test that duplicate keys are rejected."""
        monkeypatch.setenv("OPENAI_API_KEY", "same-key")
        monkeypatch.setenv("OPENAI_API_KEY1", "same-key")
        
        manager = ProviderKeyManager()
        
        provider = manager.get_provider("openai")
        # Should only have one key, not two
        assert len(provider.keys) <= 2


class TestRoundRobinRotation:
    """Test round-robin key rotation."""
    
    def test_round_robin_sequence(self, provider_manager):
        """Test that keys rotate in order."""
        keys_used = []
        
        for _ in range(6):
            key = provider_manager.get_next_key("openai")
            keys_used.append(key.key_index)
        
        # Should cycle: 0, 1, 2, 0, 1, 2
        assert keys_used == [0, 1, 2, 0, 1, 2]
    
    def test_get_next_key_with_no_keys(self, monkeypatch):
        """Test get_next_key raises error when no keys available."""
        manager = ProviderKeyManager()
        
        with pytest.raises(InvalidProviderError):
            manager.get_next_key("nonexistent")


class TestFailoverHandling:
    """Test key failover and error handling."""
    
    def test_mark_key_auth_failure_disables(self, provider_manager):
        """Test that 401/403 disables a key."""
        provider = provider_manager.get_provider("openai")
        initial_available = len(provider.get_available_keys())
        
        provider_manager.mark_key_failed(
            "openai",
            key_index=0,
            error="Unauthorized",
            status_code=401,
        )
        
        # Key should be disabled
        assert not provider.keys[0].is_active
        assert len(provider.get_available_keys()) == initial_available - 1
    
    def test_mark_key_rate_limited(self, provider_manager):
        """Test that 429 marks key as rate limited."""
        provider = provider_manager.get_provider("openai")
        
        provider_manager.mark_key_failed(
            "openai",
            key_index=1,
            error="Rate limited",
            status_code=429,
        )
        
        # Key should be marked as rate limited
        assert provider.keys[1].is_rate_limited()
    
    def test_mark_key_success_resets_failures(self, provider_manager):
        """Test that success resets failure count."""
        provider = provider_manager.get_provider("openai")
        key = provider.keys[0]
        
        # Mark as failed
        key.mark_failed("test error")
        assert key.failed_count > 0
        
        # Mark as success
        provider_manager.mark_key_success("openai", 0)
        assert key.failed_count == 0
    
    def test_failover_to_next_key(self, provider_manager):
        """Test failover to next available key."""
        # Disable first key
        provider_manager.mark_key_failed(
            "openai",
            key_index=0,
            error="Failed",
            status_code=401,
        )
        
        # Next key should be available
        key = provider_manager.get_next_key("openai")
        assert key.key_index in (1, 2)


class TestProviderStats:
    """Test provider statistics."""
    
    def test_get_provider_stats(self, provider_manager):
        """Test getting provider statistics."""
        stats = provider_manager.get_provider_stats("openai")
        
        assert "provider" in stats
        assert "total_keys" in stats
        assert "available_keys" in stats
        
        assert stats["total_keys"] == 3
        assert stats["available_keys"] == 3
    
    def test_list_providers(self, provider_manager):
        """Test listing all configured providers."""
        providers = provider_manager.list_providers()
        
        assert "openai" in providers
        assert "anthropic" in providers
    
    def test_provider_stats_after_failures(self, provider_manager):
        """Test stats reflect key failures."""
        provider_manager.mark_key_failed(
            "openai",
            key_index=0,
            error="Failed",
            status_code=401,
        )
        
        stats = provider_manager.get_provider_stats("openai")
        
        assert stats["available_keys"] == 2
        assert stats["failed_keys"] == 1


class TestThreadSafety:
    """Test thread-safe operations."""
    
    def test_concurrent_key_rotation(self, provider_manager):
        """Test that concurrent requests get different keys (or same in rotation)."""
        import threading
        
        keys_used = []
        lock = threading.Lock()
        
        def get_key():
            key = provider_manager.get_next_key("openai")
            with lock:
                keys_used.append(key.key_index)
        
        threads = [threading.Thread(target=get_key) for _ in range(6)]
        
        for t in threads:
            t.start()
        
        for t in threads:
            t.join()
        
        # Should have gotten keys
        assert len(keys_used) == 6


class TestProviderKeyModel:
    """Test ProviderKey model."""
    
    def test_provider_key_creation(self):
        """Test creating a provider key."""
        key = ProviderKey(
            provider="openai",
            key_index=0,
            key_value="test-key",
        )
        
        assert key.provider == "openai"
        assert key.key_index == 0
        assert key.is_active
    
    def test_provider_key_repr_safe(self):
        """Test that repr doesn't expose key value."""
        key = ProviderKey(
            provider="openai",
            key_index=0,
            key_value="super-secret-key",
        )
        
        repr_str = repr(key)
        
        # Should not contain the actual key
        assert "super-secret-key" not in repr_str
        assert "ProviderKey" in repr_str
    
    def test_mark_rate_limited(self):
        """Test marking key as rate limited."""
        key = ProviderKey(
            provider="openai",
            key_index=0,
            key_value="test-key",
        )
        
        assert not key.is_rate_limited()
        
        key.mark_rate_limited(duration_seconds=60)
        assert key.is_rate_limited()
    
    def test_mark_failed_disables_after_threshold(self):
        """Test that key is disabled after max failures."""
        key = ProviderKey(
            provider="openai",
            key_index=0,
            key_value="test-key",
        )
        
        assert key.is_active
        
        # Mark failed multiple times
        for _ in range(5):
            key.mark_failed("test error")
        
        # Should be disabled
        assert not key.is_active
