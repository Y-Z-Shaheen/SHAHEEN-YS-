from __future__ import annotations

import os


def get_int_env(
    name: str,
    default: int,
    minimum: int,
    maximum: int,
) -> int:
    value = os.getenv(name)

    if value is None:
        return default

    try:
        parsed_value = int(value)
    except ValueError:
        return default

    return max(
        minimum,
        min(parsed_value, maximum),
    )


HOST = os.getenv(
    "SHAHEEN_API_HOST",
    "127.0.0.1",
)

PORT = get_int_env(
    "SHAHEEN_API_PORT",
    8080,
    1,
    65535,
)

RATE_LIMIT_REQUESTS = get_int_env(
    "SHAHEEN_RATE_LIMIT_REQUESTS",
    60,
    1,
    10000,
)

RATE_LIMIT_WINDOW_SECONDS = get_int_env(
    "SHAHEEN_RATE_LIMIT_WINDOW_SECONDS",
    60,
    1,
    3600,
)

MAX_BODY_SIZE_BYTES = get_int_env(
    "SHAHEEN_MAX_BODY_SIZE",
    5 * 1024 * 1024,
    1024,
    100 * 1024 * 1024,
)

ALLOWED_ORIGINS = os.getenv(
    "SHAHEEN_ALLOWED_ORIGINS",
    "http://127.0.0.1:8080",
).split(",")

ENVIRONMENT = os.getenv(
    "SHAHEEN_ENVIRONMENT",
    "development",
)
