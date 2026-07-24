#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

echo "[08-api-gateway] بدء تهيئة API Gateway..."

export PYTHONPATH="$PROJECT_ROOT${PYTHONPATH:+:$PYTHONPATH}"

if [[ ! -f "$PROJECT_ROOT/app/__init__.py" ]]; then
    echo "[08-api-gateway][ERROR] الملف app/__init__.py غير موجود."
    exit 1
fi

if [[ ! -f "$PROJECT_ROOT/app/database.py" ]]; then
    echo "[08-api-gateway][ERROR] الملف app/database.py غير موجود."
    exit 1
fi

if [[ ! -f "$PROJECT_ROOT/app/gateway/__init__.py" ]]; then
    echo "[08-api-gateway] إنشاء app/gateway/__init__.py..."
    touch "$PROJECT_ROOT/app/gateway/__init__.py"
fi

if [[ ! -f "$PROJECT_ROOT/app/gateway/test_gateway.py" ]]; then
    echo "[08-api-gateway][ERROR] ملف اختبار API Gateway غير موجود."
    exit 1
fi

echo "[08-api-gateway] تهيئة قاعدة البيانات..."

python3 -c "
from app.database import initialize_database
initialize_database()
"

echo "[08-api-gateway] تشغيل اختبارات API Gateway..."

python3 -m app.gateway.test_gateway

echo "[08-api-gateway] تم تشغيل API Gateway بنجاح."
