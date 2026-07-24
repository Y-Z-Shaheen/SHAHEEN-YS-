#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

LOG_PREFIX="[18-production-runtime]"

log() {
    printf '%s %s\n' "$LOG_PREFIX" "$1"
}

fail() {
    printf '%s[ERROR] %s\n' "$LOG_PREFIX" "$1" >&2
    exit 1
}

trap 'fail "فشل التنفيذ عند السطر $LINENO."' ERR

DASHBOARD_APP="app/dashboard/app.py"
REQUIREMENTS_FILE="requirements.txt"
PROCFILE="Procfile"
RAILWAY_CONFIG="railway.toml"
START_SCRIPT="scripts/start-production.sh"

log "بدء إعداد Production Runtime..."

if [[ ! -f "$DASHBOARD_APP" ]]; then
    fail "ملف Dashboard غير موجود: $DASHBOARD_APP"
fi

log "فحص Flask Application..."

python3 -m py_compile "$DASHBOARD_APP"

log "إنشاء Production WSGI Entry Point..."

cat > "wsgi.py" <<'PY'
from __future__ import annotations

from app.dashboard.app import app

application = app

__all__ = [
    "app",
    "application",
]
PY

log "إنشاء Production Startup Script..."

cat > "$START_SCRIPT" <<'BASH'
#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

export PYTHONPATH="${PYTHONPATH:-$PROJECT_ROOT}"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
WORKERS="${WEB_CONCURRENCY:-2}"
TIMEOUT="${GUNICORN_TIMEOUT:-120}"

echo "[SHAHEEN-YS] Starting production server..."
echo "[SHAHEEN-YS] Host: ${HOST}"
echo "[SHAHEEN-YS] Port: ${PORT}"
echo "[SHAHEEN-YS] Workers: ${WORKERS}"

exec gunicorn \
    --bind "${HOST}:${PORT}" \
    --workers "${WORKERS}" \
    --worker-class sync \
    --timeout "${TIMEOUT}" \
    --graceful-timeout 30 \
    --keep-alive 5 \
    --access-logfile - \
    --error-logfile - \
    --capture-output \
    wsgi:application
