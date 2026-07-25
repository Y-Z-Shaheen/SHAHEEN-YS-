"""
AI Provider Keys Management System.

Supports multiple providers with unlimited keys per provider.
Implements round-robin rotation, failover, and error handling.
"""

from __future__ import annotations

from .manager import ProviderKeyManager, get_provider_manager
from .models import ProviderKey, ProviderConfig, KeyRotationStrategy
from .exceptions import (
    ProviderKeyError,
    NoAvailableKeyError,
    InvalidProviderError,
)

__all__ = [
    "ProviderKeyManager",
    "get_provider_manager",
    "ProviderKey",
    "ProviderConfig",
    "KeyRotationStrategy",
    "ProviderKeyError",
    "NoAvailableKeyError",
    "InvalidProviderError",
]
