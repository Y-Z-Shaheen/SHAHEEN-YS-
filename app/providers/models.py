"""
Data models for AI Provider Keys Management.

Defines structures for provider keys, configuration,
and rotation strategy used by ProviderKeyManager.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass, field


class KeyRotationStrategy(enum.Enum):
    """Strategy for selecting the next key."""

    ROUND_ROBIN = "round_robin"
    FAILOVER = "failover"


class KeyStatus(enum.Enum):
    """Runtime status of a provider key."""

    AVAILABLE = "available"
    RATE_LIMITED = "rate_limited"   # HTTP 429
    UNAUTHORIZED = "unauthorized"   # HTTP 401 / 403
    ERROR = "error"                 # 5xx / timeout
    EXHAUSTED = "exhausted"         # All keys unavailable


@dataclass(frozen=True)
class ProviderKey:
    """
    Represents a single API key for a provider.

    The key_value is never logged or serialized to responses.
    """

    provider: str
    key_value: str
    index: int = 0  # 0 = base key (no suffix), 1+ = numbered suffixes

    def masked(self) -> str:
        """Return a safe masked representation for logging."""
        if len(self.key_value) <= 8:
            return "***"
        return f"{self.key_value[:4]}...{self.key_value[-4:]}"

    def __repr__(self) -> str:
        return (
            f"ProviderKey(provider={self.provider!r}, "
            f"key={self.masked()!r}, index={self.index})"
        )

    def __str__(self) -> str:
        return self.masked()


@dataclass
class ProviderConfig:
    """
    Configuration for a single AI provider.

    env_prefix is the base environment variable name, e.g. "OPENAI_API_KEY".
    The manager will also discover OPENAI_API_KEY1, OPENAI_API_KEY2, etc.
    """

    provider: str
    env_prefix: str
    display_name: str = ""

    def __post_init__(self) -> None:
        if not self.display_name:
            self.display_name = self.provider.replace("_", " ").title()


@dataclass
class KeyUsageRecord:
    """Tracks per-key usage and error state for failover."""

    key: ProviderKey
    cooldown_until: float = 0.0       # epoch seconds; 0 = no cooldown
    consecutive_errors: int = 0
    status: KeyStatus = KeyStatus.AVAILABLE

    def is_available(self, now: float) -> bool:
        """True if this key is currently usable."""
        return self.cooldown_until <= now


# ---------------------------------------------------------------------------
# Canonical provider registry
# ---------------------------------------------------------------------------

#: Maps provider name → base environment variable prefix.
#: Each entry discovers BASE, BASE1, BASE2, … automatically.
PROVIDER_REGISTRY: list[ProviderConfig] = [
    ProviderConfig("openrouter",          "OPENROUTER_API_KEY",      "OpenRouter"),
    ProviderConfig("telegram",            "TELEGRAM_BOT_TOKEN",      "Telegram"),
    ProviderConfig("tavily",              "TAVILY_API_KEY",           "Tavily"),
    ProviderConfig("xai",                 "XAI_API_KEY",              "xAI"),
    ProviderConfig("openai",              "OPENAI_API_KEY",           "OpenAI"),
    ProviderConfig("mistral",             "MISTRAL_API_KEY",          "Mistral"),
    ProviderConfig("groq",                "GROQ_API_KEY",             "Groq"),
    ProviderConfig("gemini",              "GEMINI_API_KEY",           "Gemini"),
    ProviderConfig("exa",                 "EXA_API_KEY",              "Exa"),
    ProviderConfig("firecrawl",           "FIRECRAWL_API_KEY",        "Firecrawl"),
    ProviderConfig("elevenlabs",          "ELEVENLABS_API_KEY",       "ElevenLabs"),
    ProviderConfig("anthropic",           "ANTHROPIC_API_KEY",        "Anthropic"),
    ProviderConfig("deepseek",            "DEEPSEEK_API_KEY",         "DeepSeek"),
    ProviderConfig("google_search",       "GOOGLE_SEARCH_API_KEY",    "Google Search"),
    ProviderConfig("google_search_engine","GOOGLE_SEARCH_ENGINE_ID",  "Google Search Engine"),
]

#: Lookup by provider name (lower-case).
PROVIDER_BY_NAME: dict[str, ProviderConfig] = {
    cfg.provider: cfg for cfg in PROVIDER_REGISTRY
}
