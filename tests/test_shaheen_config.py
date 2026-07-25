"""
Tests for SHAHEEN-YS configuration layer (app/config.py).

Covers:
- All environment variable readings and defaults
- Boolean, integer, and enum parsing
- Invalid value handling (warns, uses default)
- Secret fields are not logged
- Production validation errors
"""

from __future__ import annotations

import importlib
import logging
import sys
from unittest.mock import patch

import pytest


def _reload_config(env: dict):
    """Reload app.config with a clean environment."""
    with patch.dict("os.environ", env, clear=True):
        if "app.config" in sys.modules:
            del sys.modules["app.config"]
        import app.config as cfg_module
        return cfg_module.Config


# ---------------------------------------------------------------------------
# Environment / server
# ---------------------------------------------------------------------------


class TestEnvironment:
    def test_default_env_is_development(self):
        cfg = _reload_config({})
        assert cfg.ENV == "development"
        assert cfg.IS_DEVELOPMENT is True
        assert cfg.IS_PRODUCTION is False

    def test_production_env(self):
        cfg = _reload_config({"SHAHEEN_YS_ENV": "production"})
        assert cfg.ENV == "production"
        assert cfg.IS_PRODUCTION is True
        assert cfg.IS_DEVELOPMENT is False

    def test_default_host(self):
        cfg = _reload_config({})
        assert cfg.HOST == "0.0.0.0"

    def test_custom_host(self):
        cfg = _reload_config({"SHAHEEN_YS_HOST": "127.0.0.1"})
        assert cfg.HOST == "127.0.0.1"

    def test_default_port(self):
        cfg = _reload_config({})
        assert cfg.PORT == 8080

    def test_custom_port(self):
        cfg = _reload_config({"PORT": "6185"})
        assert cfg.PORT == 6185

    def test_port_below_minimum_clamped(self, caplog):
        cfg = _reload_config({"PORT": "0"})
        assert cfg.PORT == 1

    def test_port_above_maximum_clamped(self, caplog):
        cfg = _reload_config({"PORT": "99999"})
        assert cfg.PORT == 65535


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------


class TestDatabaseConfig:
    def test_database_url_default_none(self):
        cfg = _reload_config({})
        assert cfg.DATABASE_URL is None

    def test_database_url_set(self):
        url = "postgresql://user:pass@localhost/db"
        cfg = _reload_config({"DATABASE_URL": url})
        assert cfg.DATABASE_URL == url

    def test_database_path_default(self):
        cfg = _reload_config({})
        assert "shaheen_ys.db" in cfg.DATABASE_PATH


# ---------------------------------------------------------------------------
# Localisation
# ---------------------------------------------------------------------------


class TestLocalisation:
    def test_default_language(self):
        cfg = _reload_config({})
        assert cfg.LANGUAGE == "ar"

    def test_default_locale(self):
        cfg = _reload_config({})
        assert cfg.LOCALE == "ar_JO"

    def test_default_timezone(self):
        cfg = _reload_config({})
        assert cfg.TIMEZONE == "Asia/Amman"

    def test_custom_language(self):
        cfg = _reload_config({"SHAHEEN_YS_LANGUAGE": "EN"})
        assert cfg.LANGUAGE == "en"  # lowercased


# ---------------------------------------------------------------------------
# Boolean parsing
# ---------------------------------------------------------------------------


class TestBooleanParsing:
    @pytest.mark.parametrize("val", ["true", "True", "TRUE", "1", "yes", "on"])
    def test_truthy_values(self, val):
        with patch.dict("os.environ", {"SHAHEEN_YS_WEBUI_ENABLED": val}, clear=True):
            if "app.config" in sys.modules:
                del sys.modules["app.config"]
            import app.config as m
            assert m.Config.WEBUI_ENABLED is True
            del sys.modules["app.config"]

    @pytest.mark.parametrize("val", ["false", "False", "FALSE", "0", "no", "off"])
    def test_falsy_values(self, val):
        with patch.dict("os.environ", {"SHAHEEN_YS_WEBUI_ENABLED": val}, clear=True):
            if "app.config" in sys.modules:
                del sys.modules["app.config"]
            import app.config as m
            assert m.Config.WEBUI_ENABLED is False
            del sys.modules["app.config"]

    def test_invalid_bool_warns_and_uses_default(self, caplog):
        with caplog.at_level(logging.WARNING):
            _reload_config({"SHAHEEN_YS_WEBUI_ENABLED": "maybe"})
        assert any("Invalid boolean" in r.message for r in caplog.records)

    def test_terminal_enabled_default(self):
        cfg = _reload_config({})
        assert cfg.TERMINAL_ENABLED is True

    def test_github_enabled_default(self):
        cfg = _reload_config({})
        assert cfg.GITHUB_ENABLED is True


# ---------------------------------------------------------------------------
# Integer parsing
# ---------------------------------------------------------------------------


class TestIntegerParsing:
    def test_max_concurrent_tasks_default(self):
        cfg = _reload_config({})
        assert cfg.MAX_CONCURRENT_TASKS == 10

    def test_max_concurrent_tasks_custom(self):
        cfg = _reload_config({"SHAHEEN_MAX_CONCURRENT_TASKS": "50"})
        assert cfg.MAX_CONCURRENT_TASKS == 50

    def test_invalid_integer_warns_and_uses_default(self, caplog):
        with caplog.at_level(logging.WARNING):
            cfg = _reload_config({"SHAHEEN_MAX_CONCURRENT_TASKS": "banana"})
        assert cfg.MAX_CONCURRENT_TASKS == 10


# ---------------------------------------------------------------------------
# Enum parsing
# ---------------------------------------------------------------------------


class TestEnumParsing:
    @pytest.mark.parametrize("val", ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"])
    def test_valid_log_levels(self, val):
        cfg = _reload_config({"SHAHEEN_LOG_LEVEL": val})
        assert cfg.LOG_LEVEL == val

    def test_invalid_log_level_uses_default(self, caplog):
        with caplog.at_level(logging.WARNING):
            cfg = _reload_config({"SHAHEEN_LOG_LEVEL": "VERBOSE"})
        assert cfg.LOG_LEVEL == "INFO"

    @pytest.mark.parametrize("val", ["light", "dark", "system"])
    def test_valid_themes(self, val):
        cfg = _reload_config({"SHAHEEN_THEME": val})
        assert cfg.THEME == val

    def test_invalid_theme_uses_default(self, caplog):
        with caplog.at_level(logging.WARNING):
            cfg = _reload_config({"SHAHEEN_THEME": "neon"})
        assert cfg.THEME == "system"


# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------


class TestRuntime:
    def test_start_from_latest_default(self):
        cfg = _reload_config({})
        assert cfg.START_FROM_LATEST is True

    def test_node_options_default_empty(self):
        cfg = _reload_config({})
        assert cfg.NODE_OPTIONS == ""

    def test_nitro_preset_default_empty(self):
        cfg = _reload_config({})
        assert cfg.NITRO_PRESET == ""


# ---------------------------------------------------------------------------
# Security — secrets never appear in to_dict output
# ---------------------------------------------------------------------------


class TestSecurityConfig:
    def test_secret_key_default_empty(self):
        cfg = _reload_config({})
        assert cfg.SECRET_KEY == ""

    def test_admin_username_default(self):
        cfg = _reload_config({})
        assert cfg.ADMIN_USERNAME == "admin"

    def test_to_dict_redacts_secret_key(self):
        cfg = _reload_config({"SHAHEEN_YS_SECRET_KEY": "super-secret"})
        d = cfg.to_dict()
        assert d.get("SECRET_KEY") == "[REDACTED]"

    def test_to_dict_redacts_admin_password(self):
        cfg = _reload_config({"SHAHEEN_YS_ADMIN_PASSWORD": "hunter2"})
        d = cfg.to_dict()
        assert d.get("ADMIN_PASSWORD") == "[REDACTED]"

    def test_to_dict_redacts_database_url(self):
        cfg = _reload_config({"DATABASE_URL": "postgresql://u:p@host/db"})
        d = cfg.to_dict()
        assert d.get("DATABASE_URL") == "[REDACTED]"


# ---------------------------------------------------------------------------
# Production validation
# ---------------------------------------------------------------------------


class TestProductionValidation:
    def test_production_with_all_required_vars_is_valid(self):
        cfg = _reload_config(
            {
                "SHAHEEN_YS_ENV": "production",
                "SHAHEEN_YS_SECRET_KEY": "x" * 32,
                "SHAHEEN_YS_ADMIN_PASSWORD": "secure-pw",
                "DATABASE_URL": "postgresql://u:p@host/db",
            }
        )
        errors = cfg.validate()
        assert errors == []

    def test_production_missing_secret_key(self):
        cfg = _reload_config(
            {
                "SHAHEEN_YS_ENV": "production",
                "SHAHEEN_YS_ADMIN_PASSWORD": "pw",
                "DATABASE_URL": "postgresql://u:p@host/db",
            }
        )
        errors = cfg.validate()
        assert any("SECRET_KEY" in e for e in errors)

    def test_production_missing_database_url(self):
        cfg = _reload_config(
            {
                "SHAHEEN_YS_ENV": "production",
                "SHAHEEN_YS_SECRET_KEY": "x" * 32,
                "SHAHEEN_YS_ADMIN_PASSWORD": "pw",
            }
        )
        errors = cfg.validate()
        assert any("DATABASE_URL" in e for e in errors)

    def test_development_has_no_required_vars(self):
        cfg = _reload_config({})
        errors = cfg.validate()
        assert errors == []
