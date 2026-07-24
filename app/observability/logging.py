from __future__ import annotations

import json
import logging
import os
import sys
import traceback
from datetime import datetime, timezone
from typing import Any


SENSITIVE_KEYS = {
    "password",
    "secret",
    "token",
    "api_key",
    "authorization",
    "cookie",
    "access_token",
    "refresh_token",
}


class JsonFormatter(logging.Formatter):
    """إخراج سجلات منظمة بصيغة JSON مناسبة لـ Railway وProduction."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(
                timezone.utc
            ).isoformat(),

            "level": record.levelname,

            "logger": record.name,

            "message": record.getMessage(),

            "service": os.getenv(
                "SHAHEEN_YS_SERVICE",
                "shaheen-ys",
            ),

            "environment": os.getenv(
                "SHAHEEN_YS_ENV",
                "development",
            ),
        }

        request_id = getattr(
            record,
            "request_id",
            None,
        )

        if request_id:
            payload["request_id"] = request_id

        extra_data = getattr(
            record,
            "extra_data",
            None,
        )

        if isinstance(extra_data, dict):
            payload["data"] = sanitize_data(
                extra_data
            )

        if record.exc_info:
            payload["exception"] = {
                "type": record.exc_info[0].__name__
                if record.exc_info[0]
                else "Exception",

                "message": str(
                    record.exc_info[1]
                )
                if record.exc_info[1]
                else "",

                "traceback": traceback.format_exception(
                    *record.exc_info
                ),
            }

        return json.dumps(
            payload,
            ensure_ascii=False,
            default=str,
        )


def sanitize_data(
    data: dict[str, Any],
) -> dict[str, Any]:
    """منع تسريب الأسرار داخل Logs."""

    sanitized: dict[str, Any] = {}

    for key, value in data.items():
        normalized_key = key.lower().replace(
            "-",
            "_",
        )

        if (
            normalized_key in SENSITIVE_KEYS
            or any(
                sensitive_key in normalized_key
                for sensitive_key in SENSITIVE_KEYS
            )
        ):
            sanitized[key] = "[REDACTED]"
        else:
            sanitized[key] = value

    return sanitized


def configure_logging() -> None:
    """تهيئة Logging مركزي للتطبيق."""

    root_logger = logging.getLogger()

    root_logger.setLevel(
        os.getenv(
            "LOG_LEVEL",
            "INFO",
        ).upper()
    )

    handler = logging.StreamHandler(
        sys.stdout
    )

    handler.setFormatter(
        JsonFormatter()
    )

    root_logger.handlers.clear()

    root_logger.addHandler(handler)


def get_logger(
    name: str,
) -> logging.Logger:
    return logging.getLogger(name)
