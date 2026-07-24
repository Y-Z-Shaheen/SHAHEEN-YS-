#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="24-production-readiness"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${PROJECT_ROOT}/data/reports"
REPORT_FILE="${REPORT_DIR}/production-readiness-report.json"
RELEASE_MANIFEST="${PROJECT_ROOT}/release-manifest.json"

log() {
    printf '[%s] %s\n' "${SCRIPT_NAME}" "$1"
}

error() {
    printf '[%s][ERROR] %s\n' "${SCRIPT_NAME}" "$1" >&2
}

cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        error "فشل تنفيذ السكريبت عند السطر ${BASH_LINENO[0]:-unknown}."
    fi
}

trap cleanup EXIT

cd "${PROJECT_ROOT}"

log "بدء فحص Production Readiness لـ SHAHEEN-YS..."

mkdir -p "${REPORT_DIR}"

required_files=(
    "wsgi.py"
    "requirements.txt"
    "app/__init__.py"
    "app/database.py"
    "app/dashboard/app.py"
    "app/observability"
)

missing_files=()

for required_file in "${required_files[@]}"; do
    if [[ ! -e "${required_file}" ]]; then
        missing_files+=("${required_file}")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    error "الملفات أو المجلدات التالية مفقودة:"
    printf ' - %s\n' "${missing_files[@]}"
    exit 1
fi

log "تم التحقق من الملفات الأساسية."

log "فحص Python Syntax..."

python_files=()

while IFS= read -r -d '' file; do
    python_files+=("${file}")
done < <(
    find app scripts -type f -name '*.py' -print0 2>/dev/null || true
)

if [[ -f "wsgi.py" ]]; then
    python_files+=("wsgi.py")
fi

if [[ ${#python_files[@]} -gt 0 ]]; then
    python3 -m py_compile "${python_files[@]}"
fi

log "Python Syntax: OK"

log "اختبار استيراد WSGI..."

python3 - <<'PY'
from wsgi import application

if application is None:
    raise RuntimeError("WSGI application is None.")

print("WSGI import: OK")
PY

log "WSGI Import: OK"

log "فحص Flask Routes..."

python3 - <<'PY'
from wsgi import application

required_routes = {
    "/health",
    "/health/live",
    "/health/ready",
    "/metrics",
}

available_routes = {
    rule.rule
    for rule in application.url_map.iter_rules()
}

missing_routes = required_routes - available_routes

if missing_routes:
    raise RuntimeError(
        f"Missing production routes: {sorted(missing_routes)}"
    )

print("Required production routes: OK")
PY

log "Production Health Routes: OK"

log "فحص متطلبات Python..."

if [[ ! -s "requirements.txt" ]]; then
    error "requirements.txt فارغ أو غير موجود."
    exit 1
fi

if grep -nE '(^|[[:space:]])(password|secret|token|api[_-]?key)[[:space:]]*=' \
    requirements.txt \
    2>/dev/null; then
    error "تم العثور على احتمال وجود بيانات حساسة داخل requirements.txt."
    exit 1
fi

log "requirements.txt: OK"

log "فحص الأسرار الحساسة داخل ملفات Git..."

sensitive_patterns=(
    'OPENAI_API_KEY=sk-'
    'ANTHROPIC_API_KEY=sk-ant-'
    'GOOGLE_API_KEY=AIza'
    'RAILWAY_TOKEN='
    'AWS_SECRET_ACCESS_KEY='
    'PRIVATE_KEY='
)

secret_found=0

for pattern in "${sensitive_patterns[@]}"; do
    if git grep -nE "${pattern}" -- \
        ':!*.example' \
        ':!*.sample' \
        ':!README.md' \
        2>/dev/null; then

        secret_found=1
    fi
done

if [[ ${secret_found} -eq 1 ]]; then
    error "تحذير أمني: تم العثور على بيانات قد تكون أسراراً داخل Git."
    error "قم بإزالتها فوراً وتدوير المفاتيح المتأثرة."
    exit 1
fi

log "Git Secret Scan: OK"

log "فحص ملفات البيئة..."

if [[ -f ".env.example" ]]; then
    if grep -nE '^[A-Z0-9_]+=$' ".env.example" >/dev/null 2>&1; then
        log ".env.example يحتوي على متغيرات بيئية فارغة جاهزة للتهيئة."
    fi
else
    error "ملف .env.example غير موجود."
    exit 1
fi

if [[ -f ".env" ]]; then
    log "تم العثور على .env المحلي — لن يتم تضمينه في Release Manifest."
fi

log "Environment Configuration: OK"

log "فحص ملفات Deployment..."

deployment_files=()

for deployment_file in \
    "Dockerfile" \
    "docker-compose.yml" \
    "docker-compose.yaml" \
    "railway.json" \
    "railway.toml" \
    "Procfile"; do

    if [[ -f "${deployment_file}" ]]; then
        deployment_files+=("${deployment_file}")
    fi
done

if [[ ${#deployment_files[@]} -eq 0 ]]; then
    error "لم يتم العثور على أي ملف Deployment."
    exit 1
fi

log "Deployment Files: ${deployment_files[*]}"

log "فحص Dockerfile..."

if [[ -f "Dockerfile" ]]; then
    if ! grep -qE '(^|[[:space:]])(CMD|ENTRYPOINT)[[:space:]]' Dockerfile; then
        error "Dockerfile لا يحتوي على CMD أو ENTRYPOINT."
        exit 1
    fi

    log "Dockerfile: OK"
fi

log "فحص Railway Configuration..."

if [[ -f "railway.json" ]]; then
    python3 -m json.tool railway.json >/dev/null
    log "railway.json: Valid JSON"
fi

if [[ -f "railway.toml" ]]; then
    log "railway.toml: موجود."
fi

log "فحص Git Status..."

git_status="$(git status --short 2>/dev/null || true)"

if [[ -n "${git_status}" ]]; then
    log "يوجد تغييرات محلية غير مرفوعة — وهذا طبيعي قبل Release."
else
    log "Git Working Tree: Clean"
fi

log "إنشاء Production Readiness Report..."

python3 - <<'PY'
import json
import os
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path

project_root = Path.cwd()
report_dir = project_root / "data" / "reports"
report_dir.mkdir(parents=True, exist_ok=True)

def get_git_value(command):
    try:
        result = subprocess.run(
            command,
            cwd=project_root,
            capture_output=True,
            text=True,
            check=False,
        )

        value = result.stdout.strip()

        return value or None

    except Exception:
        return None

deployment_files = []

for file_name in [
    "Dockerfile",
    "docker-compose.yml",
    "docker-compose.yaml",
    "railway.json",
    "railway.toml",
    "Procfile",
]:
    if (project_root / file_name).exists():
        deployment_files.append(file_name)

report = {
    "project": "SHAHEEN-YS",
    "status": "production-ready",
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "python_version": platform.python_version(),
    "platform": platform.platform(),
    "git_branch": get_git_value(["git", "branch", "--show-current"]),
    "git_commit": get_git_value(["git", "rev-parse", "HEAD"]),
    "checks": {
        "python_syntax": "passed",
        "wsgi_import": "passed",
        "health_routes": "passed",
        "requirements": "passed",
        "secret_scan": "passed",
        "environment_configuration": "passed",
        "deployment_configuration": "passed",
    },
    "health_endpoints": [
        "/health",
        "/health/live",
        "/health/ready",
        "/metrics",
    ],
    "deployment_files": deployment_files,
}

report_file = report_dir / "production-readiness-report.json"

report_file.write_text(
    json.dumps(report, indent=2, ensure_ascii=False),
    encoding="utf-8",
)

print(f"Production readiness report created: {report_file}")
PY

log "إنشاء Release Manifest..."

python3 - <<'PY'
import hashlib
import json
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path

project_root = Path.cwd()

def git_value(command):
    try:
        result = subprocess.run(
            command,
            cwd=project_root,
            capture_output=True,
            text=True,
            check=False,
        )

        value = result.stdout.strip()

        return value or None

    except Exception:
        return None

def file_sha256(path):
    digest = hashlib.sha256()

    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)

    return digest.hexdigest()

tracked_files = []

for file_name in [
    "wsgi.py",
    "requirements.txt",
    "Dockerfile",
    "railway.json",
    "railway.toml",
    "Procfile",
    "app/dashboard/app.py",
    "app/database.py",
]:
    path = project_root / file_name

    if path.is_file():
        tracked_files.append(
            {
                "path": file_name,
                "sha256": file_sha256(path),
            }
        )

manifest = {
    "product": "SHAHEEN-YS",
    "release_type": "production",
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "python_version": platform.python_version(),
    "git": {
        "branch": git_value(["git", "branch", "--show-current"]),
        "commit": git_value(["git", "rev-parse", "HEAD"]),
    },
    "deployment_targets": [
        "Railway",
        "Docker",
        "Linux",
        "Self-Hosted",
    ],
    "health_checks": [
        "/health",
        "/health/live",
        "/health/ready",
        "/metrics",
    ],
    "files": tracked_files,
}

Path("release-manifest.json").write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False),
    encoding="utf-8",
)

print("Release manifest created successfully.")
PY

log "فحص نهائي..."

test -f "${REPORT_FILE}"
test -f "${RELEASE_MANIFEST}"

log "تم تنفيذ Production Readiness بنجاح."
log "Project: SHAHEEN-YS"
log "Status: PRODUCTION READY"
log "Report: ${REPORT_FILE}"
log "Manifest: ${RELEASE_MANIFEST}"
log "Deployment Targets: Railway / Docker / Linux / Self-Hosted"
