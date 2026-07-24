#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

LOG_PREFIX="[21-observability]"

log() {
    printf '%s %s\n' "$LOG_PREFIX" "$1"
}

fail() {
    printf '%s[ERROR] %s\n' "$LOG_PREFIX" "$1" >&2
    exit 1
}

trap 'fail "فشل التنفيذ عند السطر $LINENO."' ERR

log "بدء إعداد Observability & Monitoring..."

mkdir -p app/observability

touch app/observability/__init__.py

log "إنشاء Structured Logging Module..."

cat > app/observability/logging.py <<'PY'
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
PY

log "إنشاء Request ID Middleware..."

cat > app/observability/request_context.py <<'PY'
from __future__ import annotations

import uuid
from contextvars import ContextVar


_request_id: ContextVar[str | None] = ContextVar(
    "shaheen_ys_request_id",
    default=None,
)


def generate_request_id() -> str:
    return uuid.uuid4().hex


def set_request_id(
    request_id: str,
) -> None:
    _request_id.set(request_id)


def get_request_id() -> str | None:
    return _request_id.get()


def clear_request_id() -> None:
    _request_id.set(None)
PY

log "إنشاء Metrics Module..."

cat > app/observability/metrics.py <<'PY'
from __future__ import annotations

from collections import Counter
from threading import Lock
from time import monotonic


class ApplicationMetrics:
    """Metrics بسيطة وخفيفة بدون الاعتماد على خدمة خارجية."""

    def __init__(self) -> None:
        self._lock = Lock()

        self._started_at = monotonic()

        self._total_requests = 0

        self._total_errors = 0

        self._status_codes: Counter[int] = Counter()

    def record_request(
        self,
        status_code: int,
    ) -> None:
        with self._lock:
            self._total_requests += 1

            self._status_codes[
                status_code
            ] += 1

            if status_code >= 500:
                self._total_errors += 1

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            return {
                "total_requests": self._total_requests,

                "total_errors": self._total_errors,

                "status_codes": dict(
                    self._status_codes
                ),

                "uptime_seconds": round(
                    monotonic()
                    - self._started_at,
                    2,
                ),
            }


metrics = ApplicationMetrics()
PY

log "إضافة Observability إلى Flask Dashboard..."

python3 - <<'PY'
from pathlib import Path

path = Path("app/dashboard/app.py")

source = path.read_text(
    encoding="utf-8"
)

imports = '''from app.observability.logging import (
    configure_logging,
    get_logger,
)

from app.observability.metrics import metrics

from app.observability.request_context import (
    clear_request_id,
    generate_request_id,
    get_request_id,
    set_request_id,
)

'''

if "from app.observability.logging import" not in source:
    marker = "from flask import Flask, jsonify, render_template\n"

    if marker not in source:
        raise RuntimeError(
            "تعذر العثور على Flask imports."
        )

    source = source.replace(
        marker,
        marker + imports,
        1,
    )

logger_init = '''
configure_logging()

logger = get_logger(
    "shaheen_ys.dashboard"
)

'''

if 'logger = get_logger(' not in source:
    marker = "from app.observability.request_context import (\n"

    marker_end = source.find(
        ")\n",
        source.find(marker),
    )

    if marker_end == -1:
        raise RuntimeError(
            "تعذر تحديد نهاية Observability imports."
        )

    insert_at = marker_end + 2

    source = (
        source[:insert_at]
        + logger_init
        + source[insert_at:]
    )

middleware = '''
    @app.before_request
    def before_request_observability():
        import time

        from flask import request

        incoming_request_id = request.headers.get(
            "X-Request-ID"
        )

        request_id = (
            incoming_request_id
            if incoming_request_id
            and len(incoming_request_id) <= 128
            else generate_request_id()
        )

        set_request_id(request_id)

        request.environ[
            "shaheen_ys_started_at"
        ] = time.monotonic()

    @app.after_request
    def after_request_observability(response):
        import time

        from flask import request

        started_at = request.environ.get(
            "shaheen_ys_started_at"
        )

        duration_ms = None

        if isinstance(
            started_at,
            float,
        ):
            duration_ms = round(
                (
                    time.monotonic()
                    - started_at
                )
                * 1000,
                2,
            )

        request_id = get_request_id()

        if request_id:
            response.headers[
                "X-Request-ID"
            ] = request_id

        metrics.record_request(
            response.status_code
        )

        logger.info(
            "HTTP request completed",
            extra={
                "request_id": request_id,
                "extra_data": {
                    "method": request.method,
                    "path": request.path,
                    "status_code": response.status_code,
                    "duration_ms": duration_ms,
                },
            },
        )

        clear_request_id()

        return response

    @app.teardown_request
    def teardown_request_observability(
        exception
    ):
        if exception is not None:
            logger.exception(
                "Unhandled request exception",
                exc_info=(
                    type(exception),
                    exception,
                    exception.__traceback__,
                ),
            )

        clear_request_id()

'''

if "def before_request_observability" not in source:
    marker = "    @app.get(\"/\")"

    if marker not in source:
        raise RuntimeError(
            "تعذر العثور على Dashboard route."
        )

    source = source.replace(
        marker,
        middleware + marker,
        1,
    )

routes = '''
    @app.get("/health")
    def health():
        database_health = check_database_health()

        database_is_healthy = (
            isinstance(
                database_health,
                dict,
            )
            and database_health.get(
                "status"
            )
            == "healthy"
        )

        return jsonify(
            {
                "status": (
                    "healthy"
                    if database_is_healthy
                    else "unhealthy"
                ),

                "service": "SHAHEEN-YS",

                "database": database_health,

                "request_id": get_request_id(),
            }
        ), (
            200
            if database_is_healthy
            else 503
        )

    @app.get("/health/live")
    def liveness():
        return jsonify(
            {
                "status": "alive",
                "service": "SHAHEEN-YS",
                "request_id": get_request_id(),
            }
        ), 200

    @app.get("/health/ready")
    def readiness():
        database_health = check_database_health()

        database_is_ready = (
            isinstance(
                database_health,
                dict,
            )
            and database_health.get(
                "status"
            )
            == "healthy"
        )

        return jsonify(
            {
                "status": (
                    "ready"
                    if database_is_ready
                    else "not_ready"
                ),

                "service": "SHAHEEN-YS",

                "database": database_health,

                "request_id": get_request_id(),
            }
        ), (
            200
            if database_is_ready
            else 503
        )

    @app.get("/metrics")
    def application_metrics():
        return jsonify(
            {
                "service": "SHAHEEN-YS",
                "metrics": metrics.snapshot(),
                "request_id": get_request_id(),
            }
        ), 200

'''

if "def liveness():" not in source:
    marker = '    @app.get("/")'

    if marker not in source:
        raise RuntimeError(
            "تعذر العثور على route الرئيسية."
        )

    source = source.replace(
        marker,
        routes + marker,
        1,
    )

path.write_text(
    source,
    encoding="utf-8",
)

print(
    "Observability integration completed."
)
PY

log "إضافة متغيرات Logging إلى ملف Production Environment..."

cat >> .env.production.example <<'ENV'

# Observability
LOG_LEVEL=INFO
SHAHEEN_YS_SERVICE=shaheen-ys
ENV

log "تحديث Docker Health Check..."

python3 - <<'PY'
from pathlib import Path

path = Path("Dockerfile")

source = path.read_text(
    encoding="utf-8"
)

source = source.replace(
    "http://127.0.0.1:${PORT:-8080}/health",
    "http://127.0.0.1:${PORT:-8080}/health/live",
)

path.write_text(
    source,
    encoding="utf-8",
)

print(
    "Docker health check updated."
)
PY

log "تحديث Railway Health Check..."

python3 - <<'PY'
from pathlib import Path

for filename in (
    "railway.toml",
):

    path = Path(filename)

    if not path.exists():
        continue

    source = path.read_text(
        encoding="utf-8"
    )

    source = source.replace(
        'healthcheckPath = "/health"',
        'healthcheckPath = "/health/ready"',
    )

    path.write_text(
        source,
        encoding="utf-8",
    )

print(
    "Railway health check updated."
)
PY

log "التحقق من Python Syntax..."

python3 -m compileall -q app
python3 -m py_compile wsgi.py

log "اختبار استيراد Observability..."

export PYTHONPATH="$PROJECT_ROOT"

python3 - <<'PY'
from app.observability.logging import (
    configure_logging,
)

from app.observability.metrics import (
    metrics,
)

from app.observability.request_context import (
    generate_request_id,
)

configure_logging()

request_id = generate_request_id()

metrics.record_request(200)

print(
    "Observability import: OK"
)

print(
    f"Request ID: {request_id}"
)

print(
    metrics.snapshot()
)
PY

log "اختبار Flask Application..."

python3 - <<'PY'
from wsgi import application

client = application.test_client()

response = client.get(
    "/health/live"
)

if response.status_code != 200:
    raise SystemExit(
        f"Liveness check failed: {response.status_code}"
    )

response = client.get(
    "/health/ready"
)

if response.status_code not in (
    200,
    503,
):
    raise SystemExit(
        f"Readiness check failed: {response.status_code}"
    )

request_id = response.headers.get(
    "X-Request-ID"
)

if not request_id:
    raise SystemExit(
        "X-Request-ID header is missing."
    )

print(
    "Flask observability tests: OK"
)

print(
    f"Request ID: {request_id}"
)
PY

log "تم إعداد Observability & Monitoring بنجاح."
log "Logging: Structured JSON"
log "Request ID: Enabled"
log "Liveness: /health/live"
log "Readiness: /health/ready"
log "Health: /health"
log "Metrics: /metrics"
log "Platform: Railway / Docker / Linux"
