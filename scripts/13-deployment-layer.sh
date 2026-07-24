#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="13-deployment-layer"
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

log "بدء تهيئة طبقة النشر..."

if [[ ! -d "app" ]]; then
    fail "مجلد app غير موجود."
fi

if [[ ! -f "app/dashboard/app.py" ]]; then
    fail "ملف app/dashboard/app.py غير موجود."
fi

if [[ ! -f "app/database.py" ]]; then
    fail "ملف app/database.py غير موجود."
fi

if ! command -v python3 >/dev/null 2>&1; then
    fail "Python 3 غير مثبت."
fi

export PYTHONPATH="$PROJECT_ROOT"

log "التحقق من ملفات Python..."

python3 -m py_compile \
    app/database.py \
    app/dashboard/app.py \
    app/compute/service.py \
    app/compute/api.py \
    app/compute/instance/api.py

log "فحص Python syntax نجح."

log "اختبار استيراد المكونات..."

python3 - <<'PY'
from app.database import initialize_database
from app.compute.api import compute_blueprint
from app.compute.instance.api import instance_blueprint
from app.dashboard.app import create_dashboard_app

initialize_database()

if compute_blueprint is None:
    raise RuntimeError(
        "Compute blueprint غير متاح."
    )

if instance_blueprint is None:
    raise RuntimeError(
        "Instance blueprint غير متاح."
    )

application = create_dashboard_app()

if application is None:
    raise RuntimeError(
        "Dashboard application لم يتم إنشاؤه."
    )

print(
    "Deployment imports validation passed."
)
PY

log "تم اجتياز فحص مكونات التطبيق."

log "التحقق من متغيرات التشغيل..."

export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-8080}"
export SHAHEEN_YS_ENV="${SHAHEEN_YS_ENV:-production}"

log "HOST=${HOST}"
log "PORT=${PORT}"
log "SHAHEEN_YS_ENV=${SHAHEEN_YS_ENV}"

log "إنشاء مجلدات التشغيل..."

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

print(
    "Production database initialization passed."
)
PY

log "التحقق من صحة تطبيق Flask..."

python3 - <<'PY'
from app.dashboard.app import create_dashboard_app

application = create_dashboard_app()

with application.test_client() as client:
    response = client.get(
        "/api/dashboard/status"
    )

    if response.status_code not in {
        200,
        503,
    }:
        raise RuntimeError(
            f"Unexpected dashboard status: "
            f"{response.status_code}"
        )

print(
    "Dashboard HTTP validation passed."
)
PY

log "تم اجتياز جميع اختبارات طبقة النشر."

log "Deployment layer initialized successfully."

log "لتشغيل التطبيق محلياً أو على VPS:"
log "HOST=0.0.0.0 PORT=8080 python3 -m app.dashboard.app"

log "على Railway:"
log "يتم استخدام PORT الذي توفره المنصة تلقائياً."

