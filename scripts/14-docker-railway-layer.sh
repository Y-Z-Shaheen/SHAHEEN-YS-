#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="14-docker-railway-layer"
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

log "بدء تهيئة طبقة Docker و Railway..."

if [[ ! -d "app" ]]; then
    fail "مجلد app غير موجود."
fi

if [[ ! -f "app/dashboard/app.py" ]]; then
    fail "ملف app/dashboard/app.py غير موجود."
fi

if [[ ! -f "app/database.py" ]]; then
    fail "ملف app/database.py غير موجود."
fi

if [[ ! -f "requirements.txt" ]]; then
    fail "ملف requirements.txt غير موجود."
fi

log "إنشاء Dockerfile..."

cat > Dockerfile <<'DOCKERFILE'
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN python -m pip install \
    --no-cache-dir \
    --upgrade pip \
    && python -m pip install \
    --no-cache-dir \
    -r requirements.txt

COPY app ./app

COPY config ./config

COPY data ./data

RUN mkdir -p \
    /app/data/db \
    /app/data/logs \
    /app/data/plugins \
    /app/data/runtime

EXPOSE 8080

CMD ["sh", "-c", "python3 -m app.dashboard.app"]
DOCKERFILE

log "تم إنشاء Dockerfile."

log "إنشاء .dockerignore..."

cat > .dockerignore <<'DOCKERIGNORE'
.git
.github
.gitignore
.venv
venv
env
__pycache__
*.pyc
*.pyo
*.pyd
.pytest_cache
.mypy_cache
.ruff_cache
.coverage
htmlcov
dist
build
*.egg-info
tests
docs
changelogs
.env
.env.*
!.env.example
data/logs/*
data/runtime/*
*.log
*.sqlite-shm
*.sqlite-wal
DOCKERIGNORE

log "تم إنشاء .dockerignore."

log "إنشاء railway.toml..."

cat > railway.toml <<'RAILWAY'
[build]
builder = "DOCKERFILE"

[deploy]
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 10
healthcheckPath = "/api/dashboard/status"
healthcheckTimeout = 30
RAILWAY

log "تم إنشاء railway.toml."

log "إنشاء docker-compose.yml..."

cat > docker-compose.yml <<'COMPOSE'
services:
  shaheen-ys:
    build:
      context: .
      dockerfile: Dockerfile

    container_name: shaheen-ys

    restart: unless-stopped

    environment:
      HOST: 0.0.0.0
      PORT: 8080
      SHAHEEN_YS_ENV: production
      DATABASE_URL: sqlite:///data/db/shaheen_ys.db

    ports:
      - "8080:8080"

    volumes:
      - shaheen_ys_data:/app/data

    healthcheck:
      test:
        [
          "CMD",
          "curl",
          "-f",
          "http://127.0.0.1:8080/api/dashboard/status"
        ]

      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

volumes:
  shaheen_ys_data:
COMPOSE

log "تم إنشاء docker-compose.yml."

log "التحقق من Dockerfile..."

if command -v docker >/dev/null 2>&1; then
    dockerfile_size="$(wc -c < Dockerfile)"

    if [[ "$dockerfile_size" -le 0 ]]; then
        fail "Dockerfile فارغ."
    fi

    log "Dockerfile validation passed."
else
    log "Docker غير مثبت محلياً. تم تجاوز اختبار Docker."
fi

log "التحقق من ملفات النشر..."

for required_file in \
    Dockerfile \
    .dockerignore \
    railway.toml \
    docker-compose.yml
do
    if [[ ! -f "$required_file" ]]; then
        fail "الملف غير موجود: $required_file"
    fi
done

log "Deployment configuration validation passed."

log "تم إنشاء طبقة Docker و Railway بنجاح."

log "للتشغيل باستخدام Docker Compose:"
log "docker compose up --build"

log "للنشر على Railway:"
log "اربط مستودع GitHub ثم اختر Dockerfile كطريقة البناء."
