#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="12-production-bootstrap"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

log() {
    printf '[%s] %s\n' "$SCRIPT_NAME" "$1"
}

error() {
    printf '[%s][ERROR] %s\n' "$SCRIPT_NAME" "$1" >&2
}

fail() {
    error "$1"
    exit 1
}

trap 'error "فشل التنفيذ عند السطر ${LINENO}."' ERR

log "بدء تهيئة بيئة التشغيل الإنتاجية..."

if [[ ! -f "app/dashboard/app.py" ]]; then
    fail "ملف app/dashboard/app.py غير موجود."
fi

if [[ ! -f "app/database.py" ]]; then
    fail "ملف app/database.py غير موجود."
fi

if [[ ! -d "app" ]]; then
    fail "مجلد app غير موجود."
fi

if ! command -v python3 >/dev/null 2>&1; then
    fail "Python 3 غير مثبت."
fi

PYTHON_VERSION="$(
    python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'
)"

log "إصدار Python: ${PYTHON_VERSION}"

export PYTHONPATH="${PROJECT_ROOT}"

export PYTHONUNBUFFERED="1"

export HOST="${HOST:-0.0.0.0}"

export PORT="${PORT:-8080}"

export SHAHEEN_ENV="${SHAHEEN_ENV:-production}"

export DATABASE_URL="${DATABASE_URL:-sqlite:///data/db/shaheen_ys.db}"

log "HOST=${HOST}"
log "PORT=${PORT}"
log "SHAHEEN_ENV=${SHAHEEN_ENV}"

mkdir -p \
    data \
    data/db \
    data/logs \
    data/plugins \
    data/runtime

log "تهيئة قاعدة البيانات..."

python3 - <<'PY'
from app.database import initialize_database

initialize_database()

print("Database initialization completed successfully.")
PY

log "التحقق من Compute API..."

python3 - <<'PY'
from app.compute.api import compute_blueprint

if compute_blueprint is None:
    raise RuntimeError(
        "Compute blueprint was not initialized."
    )

print("Compute API validation passed.")
PY

log "التحقق من Instance API..."

python3 - <<'PY'
from app.compute.instance.api import instance_blueprint

if instance_blueprint is None:
    raise RuntimeError(
        "Instance blueprint was not initialized."
    )

print("Instance API validation passed.")
PY

log "التحقق من Dashboard Factory..."

python3 - <<'PY'
from app.dashboard.app import create_dashboard_app

application = create_dashboard_app()

if application is None:
    raise RuntimeError(
        "Dashboard application was not created."
    )

print("Dashboard factory validation passed.")
PY

log "جميع فحوصات التشغيل نجحت."

log "بدء SHAHEEN-YS على ${HOST}:${PORT}..."

exec python3 - <<'PY'
import os

from app.dashboard.app import create_dashboard_app

application = create_dashboard_app()

host = os.getenv(
    "HOST",
    "0.0.0.0",
)

port = int(
    os.getenv(
        "PORT",
        "8080",
    )
)

application.run(
    host=host,
    port=port,
    debug=False,
    threaded=True,
)
PY
