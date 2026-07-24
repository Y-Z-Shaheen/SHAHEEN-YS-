#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="22-production-readiness"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

log() {
    printf '[%s] %s\n' "$SCRIPT_NAME" "$1"
}

error() {
    printf '[%s][ERROR] %s\n' "$SCRIPT_NAME" "$1" >&2
}

cleanup() {
    local exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        error "فشل التنفيذ عند السطر ${BASH_LINENO[0]}."
    fi

    exit "$exit_code"
}

trap cleanup EXIT

log "بدء تحسين Production Readiness..."

mkdir -p \
    deploy \
    config \
    scripts \
    .github/workflows

log "إنشاء Production Environment Template..."

cat > .env.production.example <<'EOF'
# SHAHEEN-YS Production Environment

SHAHEEN_YS_ENV=production

# Server
SHAHEEN_YS_DASHBOARD_HOST=0.0.0.0
PORT=8080

# Database
SHAHEEN_YS_DATABASE_PATH=data/db/shaheen_ys.db

# Logging
SHAHEEN_YS_LOG_LEVEL=INFO
SHAHEEN_YS_LOG_FORMAT=json

# Security
SHAHEEN_YS_SECRET_KEY=change-this-in-production

# AI Providers
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GOOGLE_API_KEY=

# Optional
SENTRY_DSN=
EOF

log "إنشاء Production WSGI Configuration..."

cat > gunicorn.conf.py <<'PY'
from __future__ import annotations

import multiprocessing
import os


bind = f"0.0.0.0:{os.getenv('PORT', '8080')}"

workers = int(
    os.getenv(
        "WEB_CONCURRENCY",
        str(max(2, multiprocessing.cpu_count() * 2 + 1)),
    )
)

threads = int(
    os.getenv(
        "GUNICORN_THREADS",
        "2",
    )
)

worker_class = "gthread"

timeout = int(
    os.getenv(
        "GUNICORN_TIMEOUT",
        "120",
    )
)

graceful_timeout = int(
    os.getenv(
        "GUNICORN_GRACEFUL_TIMEOUT",
        "30",
    )
)

keepalive = int(
    os.getenv(
        "GUNICORN_KEEPALIVE",
        "5",
    )
)

max_requests = int(
    os.getenv(
        "GUNICORN_MAX_REQUESTS",
        "1000",
    )
)

max_requests_jitter = int(
    os.getenv(
        "GUNICORN_MAX_REQUESTS_JITTER",
        "100",
    )
)

accesslog = "-"

errorlog = "-"

loglevel = os.getenv(
    "SHAHEEN_YS_LOG_LEVEL",
    "info",
)

capture_output = True

preload_app = False

forwarded_allow_ips = "*"

secure_scheme_headers = {
    "X-FORWARDED-PROTO": "https",
}
PY

log "إنشاء Production Start Script..."

cat > scripts/start-production.sh <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

export PYTHONPATH="$PROJECT_ROOT"

exec gunicorn \
    --config gunicorn.conf.py \
    wsgi:application
EOF

chmod +x scripts/start-production.sh

log "إنشاء Railway Configuration..."

cat > railway.toml <<'EOF'
[build]
builder = "DOCKERFILE"

[deploy]
healthcheckPath = "/health/ready"
healthcheckTimeout = 300
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 10
EOF

log "إنشاء Dockerfile Production..."

cat > Dockerfile.production <<'EOF'
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN python -m pip install --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir gunicorn

COPY . .

RUN mkdir -p \
    data/db \
    data/logs \
    data/cache

EXPOSE 8080

HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=30s \
    --retries=5 \
    CMD curl --fail http://127.0.0.1:8080/health/ready || exit 1

CMD ["./scripts/start-production.sh"]
EOF

log "إنشاء Docker Ignore..."

cat > .dockerignore <<'EOF'
.git
.github
.gitignore
.env
.env.*
!.env.production.example
__pycache__
*.pyc
.pytest_cache
.mypy_cache
.ruff_cache
.venv
venv
node_modules
dist
build
coverage
htmlcov
data/logs/*
*.sqlite-shm
*.sqlite-wal
EOF

log "إنشاء Production Security Headers Module..."

mkdir -p app/security

cat > app/security/__init__.py <<'PY'
"""Security utilities for SHAHEEN-YS."""
PY

cat > app/security/headers.py <<'PY'
from __future__ import annotations

from flask import Flask


def register_security_headers(app: Flask) -> None:
    @app.after_request
    def apply_security_headers(response):
        response.headers.setdefault(
            "X-Content-Type-Options",
            "nosniff",
        )

        response.headers.setdefault(
            "X-Frame-Options",
            "SAMEORIGIN",
        )

        response.headers.setdefault(
            "Referrer-Policy",
            "strict-origin-when-cross-origin",
        )

        response.headers.setdefault(
            "Permissions-Policy",
            "camera=(), microphone=(), geolocation=()",
        )

        if not app.debug:
            response.headers.setdefault(
                "Strict-Transport-Security",
                "max-age=31536000; includeSubDomains",
            )

        return response
PY

log "إنشاء Production Verification Script..."

cat > scripts/verify-production.sh <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

export PYTHONPATH="$PROJECT_ROOT"

python3 -m compileall -q app wsgi.py

python3 -c \
"from wsgi import application; print('Production WSGI import: OK')"

printf '%s\n' "Production verification completed successfully."
EOF

chmod +x scripts/verify-production.sh

log "تشغيل فحص Python Syntax..."

python3 -m compileall -q app wsgi.py

log "اختبار Production WSGI..."

if python3 -c \
    "from wsgi import application; print('Production WSGI import: OK')"
then
    log "Production WSGI يعمل بنجاح."
else
    error "فشل استيراد Production WSGI."
    exit 1
fi

log "تم إعداد Production Readiness بنجاح."

printf '\n'
printf '[%s] Railway: جاهز\n' "$SCRIPT_NAME"
printf '[%s] Docker: جاهز\n' "$SCRIPT_NAME"
printf '[%s] Gunicorn: جاهز\n' "$SCRIPT_NAME"
printf '[%s] Health Check: /health/ready\n' "$SCRIPT_NAME"
printf '[%s] Production Start: scripts/start-production.sh\n' "$SCRIPT_NAME"
