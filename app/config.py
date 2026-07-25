"""
Configuration management for SHAHEEN-YS.

متغيرات البيئة المدعومة:
- SHAHEEN_YS_ENV: production, development
- SHAHEEN_YS_HOST: Server host (default: 0.0.0.0)
- PORT: Server port from Railway (will read from os.environ)
- DATABASE_URL: PostgreSQL connection URL for Production
- SHAHEEN_YS_DATABASE_PATH: SQLite path for Development fallback
- SHAHEEN_YS_LANGUAGE: Language code (default: ar)
- SHAHEEN_YS_LOCALE: Locale code (default: ar_JO)
- SHAHEEN_YS_TIMEZONE: Timezone (default: Asia/Amman)
- SHAHEEN_YS_DATA_DIR: Data directory path
- SHAHEEN_YS_PLUGIN_DIR: Plugin directory path
- SHAHEEN_YS_WEBUI_ENABLED: Enable WebUI (default: true)
- SHAHEEN_YS_TERMINAL_ENABLED: Enable Terminal (default: true)
- SHAHEEN_YS_GITHUB_ENABLED: Enable GitHub integration (default: true)
- SHAHEEN_YS_GITHUB_REPOSITORY: GitHub repository
- SHAHEEN_MAX_CONCURRENT_TASKS: Max concurrent tasks (default: 10)
- SHAHEEN_LOG_LEVEL: Logging level (default: INFO)
- SHAHEEN_START_FROM_LATEST: Start from latest (default: true)
- SHAHEEN_THEME: UI theme (default: system)
- NODE_OPTIONS: Node.js options
- NITRO_PRESET: Nitro preset
- SHAHEEN_YS_SECRET_KEY: Secret key for encryption
- SHAHEEN_YS_ADMIN_USERNAME: Admin username
- SHAHEEN_YS_ADMIN_PASSWORD: Admin password
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Optional


logger = logging.getLogger(__name__)


# ============================================================================
# Helper Functions
# ============================================================================


def get_bool_env(
    name: str,
    default: bool = False,
) -> bool:
    """
    Parse boolean environment variable.
    
    Accepts: true, false, 1, 0, yes, no, on, off (case-insensitive)
    """
    value = os.getenv(name, "").lower().strip()
    
    if not value:
        return default
    
    if value in ("true", "1", "yes", "on"):
        return True
    elif value in ("false", "0", "no", "off"):
        return False
    else:
        logger.warning(
            f"Invalid boolean value for {name}: {value!r}, using default: {default}"
        )
        return default


def get_int_env(
    name: str,
    default: int,
    minimum: Optional[int] = None,
    maximum: Optional[int] = None,
) -> int:
    """
    Parse integer environment variable with optional bounds.
    """
    value = os.getenv(name)
    
    if value is None:
        return default
    
    try:
        parsed = int(value.strip())
    except ValueError:
        logger.warning(
            f"Invalid integer value for {name}: {value!r}, using default: {default}"
        )
        return default
    
    if minimum is not None and parsed < minimum:
        logger.warning(
            f"{name} value {parsed} is below minimum {minimum}, using minimum"
        )
        return minimum
    
    if maximum is not None and parsed > maximum:
        logger.warning(
            f"{name} value {parsed} is above maximum {maximum}, using maximum"
        )
        return maximum
    
    return parsed


def get_enum_env(
    name: str,
    default: str,
    allowed_values: set[str],
) -> str:
    """
    Parse enum environment variable.
    """
    value = os.getenv(name, default).lower().strip()
    
    if value not in allowed_values:
        logger.warning(
            f"Invalid value for {name}: {value!r}, using default: {default}"
        )
        return default
    
    return value


# ============================================================================
# Core Configuration
# ============================================================================


class Config:
    """
    Centralized configuration for SHAHEEN-YS.
    """
    
    # ========== Environment ==========
    ENV = os.getenv("SHAHEEN_YS_ENV", "development").lower()
    IS_PRODUCTION = ENV == "production"
    IS_DEVELOPMENT = ENV == "development"
    
    # ========== Server ==========
    HOST = os.getenv("SHAHEEN_YS_HOST", "0.0.0.0")
    
    # Railway provides PORT dynamically, fallback to 8080
    PORT = get_int_env("PORT", 8080, minimum=1, maximum=65535)
    
    # ========== Database ==========
    # Production: uses DATABASE_URL (PostgreSQL)
    # Development: uses SHAHEEN_YS_DATABASE_PATH (SQLite) as fallback
    DATABASE_URL = os.getenv("DATABASE_URL")
    DATABASE_PATH = os.getenv(
        "SHAHEEN_YS_DATABASE_PATH",
        "./data/db/shaheen_ys.db",
    )
    
    # Ensure parent directory exists
    _db_path = Path(DATABASE_PATH).resolve()
    _db_path.parent.mkdir(parents=True, exist_ok=True)
    
    # ========== Localization ==========
    LANGUAGE = os.getenv("SHAHEEN_YS_LANGUAGE", "ar").lower()
    LOCALE = os.getenv("SHAHEEN_YS_LOCALE", "ar_JO")
    TIMEZONE = os.getenv("SHAHEEN_YS_TIMEZONE", "Asia/Amman")
    
    # ========== Paths ==========
    DATA_DIR = Path(
        os.getenv("SHAHEEN_YS_DATA_DIR", "./data")
    ).resolve()
    
    PLUGIN_DIR = Path(
        os.getenv("SHAHEEN_YS_PLUGIN_DIR", "./data/plugins")
    ).resolve()
    
    # Ensure directories exist
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    PLUGIN_DIR.mkdir(parents=True, exist_ok=True)
    
    # ========== Features ==========
    WEBUI_ENABLED = get_bool_env("SHAHEEN_YS_WEBUI_ENABLED", True)
    TERMINAL_ENABLED = get_bool_env("SHAHEEN_YS_TERMINAL_ENABLED", True)
    GITHUB_ENABLED = get_bool_env("SHAHEEN_YS_GITHUB_ENABLED", True)
    GITHUB_REPOSITORY = os.getenv("SHAHEEN_YS_GITHUB_REPOSITORY", "")
    
    # ========== Runtime ==========
    MAX_CONCURRENT_TASKS = get_int_env(
        "SHAHEEN_MAX_CONCURRENT_TASKS",
        default=10,
        minimum=1,
        maximum=1000,
    )
    
    LOG_LEVEL = get_enum_env(
        "SHAHEEN_LOG_LEVEL",
        default="INFO",
        allowed_values={"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"},
    )
    
    START_FROM_LATEST = get_bool_env("SHAHEEN_START_FROM_LATEST", True)
    THEME = get_enum_env(
        "SHAHEEN_THEME",
        default="system",
        allowed_values={"light", "dark", "system"},
    )
    
    # ========== Node/Nitro ==========
    NODE_OPTIONS = os.getenv("NODE_OPTIONS", "")
    NITRO_PRESET = os.getenv("NITRO_PRESET", "")
    
    # ========== Security ==========
    SECRET_KEY = os.getenv("SHAHEEN_YS_SECRET_KEY", "")
    ADMIN_USERNAME = os.getenv("SHAHEEN_YS_ADMIN_USERNAME", "admin")
    ADMIN_PASSWORD = os.getenv("SHAHEEN_YS_ADMIN_PASSWORD", "")
    
    # ========== Logging ==========
    LOG_FORMAT = "json"  # JSON format for Production
    
    @classmethod
    def to_dict(cls) -> dict[str, any]:
        """
        Convert config to dictionary (with sensitive values redacted).
        Useful for debugging and monitoring.
        """
        sensitive_keys = {
            "SECRET_KEY",
            "ADMIN_PASSWORD",
            "DATABASE_URL",
        }
        
        return {
            key: (
                "[REDACTED]"
                if key in sensitive_keys
                else getattr(cls, key)
            )
            for key in dir(cls)
            if (
                not key.startswith("_")
                and key.isupper()
                and not callable(getattr(cls, key))
            )
        }
    
    @classmethod
    def validate(cls) -> list[str]:
        """
        Validate critical configuration.
        
        Returns list of validation errors (empty if valid).
        """
        errors = []
        
        # Production validations
        if cls.IS_PRODUCTION:
            if not cls.SECRET_KEY:
                errors.append("SHAHEEN_YS_SECRET_KEY is required in production")
            
            if not cls.ADMIN_PASSWORD:
                errors.append("SHAHEEN_YS_ADMIN_PASSWORD is required in production")
            
            if not cls.DATABASE_URL:
                errors.append(
                    "DATABASE_URL is required in production (for PostgreSQL)"
                )
        
        return errors


# ============================================================================
# Log Configuration
# ============================================================================


def configure_logging() -> None:
    """
    Configure logging for SHAHEEN-YS.
    """
    import sys
    from app.observability.logging import JsonFormatter
    
    # Get root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(Config.LOG_LEVEL)
    
    # Remove existing handlers
    root_logger.handlers.clear()
    
    # Create console handler with JSON formatter
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    
    root_logger.addHandler(handler)
    
    # Log configuration on startup (only in development)
    if Config.IS_DEVELOPMENT:
        logger.info(
            "SHAHEEN-YS Configuration loaded",
            extra={"extra_data": {"env": Config.ENV, "port": Config.PORT}},
        )


# ============================================================================
# Initialization
# ============================================================================


def initialize_config() -> None:
    """
    Initialize configuration on application startup.
    """
    configure_logging()
    
    # Validate configuration
    errors = Config.validate()
    if errors:
        for error in errors:
            logger.error(error)
        
        if Config.IS_PRODUCTION:
            raise RuntimeError(
                f"Configuration validation failed with {len(errors)} error(s)"
            )
