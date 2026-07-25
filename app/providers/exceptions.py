"""
Exceptions for AI Provider Keys Management.
"""

from __future__ import annotations


class ProviderKeyError(Exception):
    """Base exception for provider key operations."""
    pass


class NoAvailableKeyError(ProviderKeyError):
    """No available keys for the provider."""
    pass


class InvalidProviderError(ProviderKeyError):
    """Invalid provider name."""
    pass


class KeyRotationError(ProviderKeyError):
    """Error during key rotation."""
    pass


class ProviderError(ProviderKeyError):
    """Error from external provider."""
    pass
