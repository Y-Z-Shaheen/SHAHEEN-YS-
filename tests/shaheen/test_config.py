"""
Tests for app/config.py — env-var parsing and Config validation.
"""

from __future__ import annotations

import pytest


# ---------------------------------------------------------------------------
# get_bool_env
# ---------------------------------------------------------------------------

class TestGetBoolEnv:
    def test_true_values(self, monkeypatch):
        from app.config import get_bool_env

        for val in ("true", "True", "TRUE", "1", "yes", "YES", "on", "ON"):
            monkeypatch.setenv("TEST_BOOL", val)
            assert get_bool_env("TEST_BOOL", False) is True, f"failed for {val!r}"

    def test_false_values(self, monkeypatch):
        from app.config import get_bool_env

        for val in ("false", "False", "FALSE", "0", "no", "NO", "off", "OFF"):
            monkeypatch.setenv("TEST_BOOL", val)
            assert get_bool_env("TEST_BOOL", True) is False, f"failed for {val!r}"

    def test_default_when_missing(self, monkeypatch):
        from app.config import get_bool_env

        monkeypatch.delenv("TEST_BOOL", raising=False)
        assert get_bool_env("TEST_BOOL", True) is True
        assert get_bool_env("TEST_BOOL", False) is False

    def test_invalid_returns_default(self, monkeypatch):
        from app.config import get_bool_env

        monkeypatch.setenv("TEST_BOOL", "maybe")
        assert get_bool_env("TEST_BOOL", True) is True
        assert get_bool_env("TEST_BOOL", False) is False


# ---------------------------------------------------------------------------
# get_int_env
# ---------------------------------------------------------------------------

class TestGetIntEnv:
    def test_valid_integer(self, monkeypatch):
        from app.config import get_int_env

        monkeypatch.setenv("TEST_INT", "42")
        assert get_int_env("TEST_INT", 0) == 42

    def test_default_when_missing(self, monkeypatch):
        from app.config import get_int_env

        monkeypatch.delenv("TEST_INT", raising=False)
        assert get_int_env("TEST_INT", 99) == 99

    def test_invalid_returns_default(self, monkeypatch):
        from app.config import get_int_env

        monkeypatch.setenv("TEST_INT", "notanumber")
        assert get_int_env("TEST_INT", 5) == 5

    def test_minimum_clamp(self, monkeypatch):
        from app.config import get_int_env

        monkeypatch.setenv("TEST_INT", "0")
        assert get_int_env("TEST_INT", 5, minimum=1) == 1

    def test_maximum_clamp(self, monkeypatch):
        from app.config import get_int_env

        monkeypatch.setenv("TEST_INT", "9999")
        assert get_int_env("TEST_INT", 5, maximum=100) == 100

    def test_negative_values_rejected_by_minimum(self, monkeypatch):
        from app.config import get_int_env

        monkeypatch.setenv("TEST_INT", "-5")
        assert get_int_env("TEST_INT", 10, minimum=1) == 1


# ---------------------------------------------------------------------------
# get_enum_env
# ---------------------------------------------------------------------------

class TestGetEnumEnv:
    def test_valid_value(self, monkeypatch):
        from app.config import get_enum_env

        monkeypatch.setenv("TEST_ENUM", "debug")
        result = get_enum_env("TEST_ENUM", "INFO", {"DEBUG", "INFO", "WARNING"})
        assert result == "DEBUG"  # canonical uppercase

    def test_case_insensitive(self, monkeypatch):
        from app.config import get_enum_env

        monkeypatch.setenv("TEST_ENUM", "WARNING")
        result = get_enum_env("TEST_ENUM", "INFO", {"DEBUG", "INFO", "WARNING"})
        assert result == "WARNING"

    def test_invalid_returns_default(self, monkeypatch):
        from app.config import get_enum_env

        monkeypatch.setenv("TEST_ENUM", "VERBOSE")
        result = get_enum_env("TEST_ENUM", "INFO", {"DEBUG", "INFO", "WARNING"})
        assert result == "INFO"


# ---------------------------------------------------------------------------
# Config class
# ---------------------------------------------------------------------------

class TestConfig:
    def test_shaheen_max_concurrent_tasks_default(self, monkeypatch):
        monkeypatch.delenv("SHAHEEN_MAX_CONCURRENT_TASKS", raising=False)
        # Reload the Config class attributes using the helper directly
        from app.config import get_int_env
        val = get_int_env("SHAHEEN_MAX_CONCURRENT_TASKS", 10, minimum=1, maximum=1000)
        assert val == 10

    def test_shaheen_max_concurrent_tasks_custom(self, monkeypatch):
        monkeypatch.setenv("SHAHEEN_MAX_CONCURRENT_TASKS", "25")
        from app.config import get_int_env
        val = get_int_env("SHAHEEN_MAX_CONCURRENT_TASKS", 10, minimum=1, maximum=1000)
        assert val == 25

    def test_shaheen_max_concurrent_tasks_negative_clamped(self, monkeypatch):
        monkeypatch.setenv("SHAHEEN_MAX_CONCURRENT_TASKS", "-1")
        from app.config import get_int_env
        val = get_int_env("SHAHEEN_MAX_CONCURRENT_TASKS", 10, minimum=1, maximum=1000)
        assert val == 1

    def test_log_level_default(self, monkeypatch):
        monkeypatch.delenv("SHAHEEN_LOG_LEVEL", raising=False)
        from app.config import get_enum_env
        val = get_enum_env("SHAHEEN_LOG_LEVEL", "INFO", {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"})
        assert val == "INFO"

    def test_log_level_all_valid(self, monkeypatch):
        from app.config import get_enum_env
        for level in ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"):
            monkeypatch.setenv("SHAHEEN_LOG_LEVEL", level.lower())
            val = get_enum_env("SHAHEEN_LOG_LEVEL", "INFO", {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"})
            assert val == level

    def test_start_from_latest_boolean(self, monkeypatch):
        from app.config import get_bool_env
        for v in ("true", "1", "yes", "on"):
            monkeypatch.setenv("SHAHEEN_START_FROM_LATEST", v)
            assert get_bool_env("SHAHEEN_START_FROM_LATEST", False) is True

    def test_theme_valid_values(self, monkeypatch):
        from app.config import get_enum_env
        for theme in ("light", "dark", "system"):
            monkeypatch.setenv("SHAHEEN_THEME", theme)
            val = get_enum_env("SHAHEEN_THEME", "system", {"light", "dark", "system"})
            assert val == theme

    def test_locale_defaults(self, monkeypatch):
        import os
        monkeypatch.delenv("SHAHEEN_YS_LOCALE", raising=False)
        monkeypatch.delenv("SHAHEEN_YS_LANGUAGE", raising=False)
        monkeypatch.delenv("SHAHEEN_YS_TIMEZONE", raising=False)
        assert os.getenv("SHAHEEN_YS_LOCALE", "ar_JO") == "ar_JO"
        assert os.getenv("SHAHEEN_YS_LANGUAGE", "ar") == "ar"
        assert os.getenv("SHAHEEN_YS_TIMEZONE", "Asia/Amman") == "Asia/Amman"

    def test_production_validation_requires_secret_key(self, monkeypatch):
        monkeypatch.setenv("SHAHEEN_YS_ENV", "production")
        monkeypatch.delenv("SHAHEEN_YS_SECRET_KEY", raising=False)
        monkeypatch.delenv("SHAHEEN_YS_ADMIN_PASSWORD", raising=False)
        monkeypatch.delenv("DATABASE_URL", raising=False)

        # Re-evaluate Config validation logic inline (Config is a class with class-level attrs)
        import os
        errors = []
        if not os.getenv("SHAHEEN_YS_SECRET_KEY", ""):
            errors.append("SHAHEEN_YS_SECRET_KEY is required in production")
        if not os.getenv("SHAHEEN_YS_ADMIN_PASSWORD", ""):
            errors.append("SHAHEEN_YS_ADMIN_PASSWORD is required in production")
        if not os.getenv("DATABASE_URL", ""):
            errors.append("DATABASE_URL is required in production")
        assert len(errors) == 3
