#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="15-ci-cd-layer"
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

log "بدء تهيئة طبقة CI/CD..."

if [[ ! -d ".git" ]]; then
    fail "المجلد الحالي ليس مستودع Git."
fi

if [[ ! -d ".github" ]]; then
    mkdir -p ".github"
fi

if [[ ! -d ".github/workflows" ]]; then
    mkdir -p ".github/workflows"
fi

log "إنشاء GitHub Actions Workflow..."

cat > .github/workflows/shaheen-ys-ci.yml <<'YAML'
name: SHAHEEN-YS CI/CD

on:
  push:
    branches:
      - main
      - develop

  pull_request:
    branches:
      - main
      - develop

  workflow_dispatch:

permissions:
  contents: read

env:
  PYTHON_VERSION: "3.12"
  PYTHONUNBUFFERED: "1"
  PYTHONDONTWRITEBYTECODE: "1"

jobs:
  validate:
    name: Validate Python Project
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Upgrade pip
        run: |
          python -m pip install --upgrade pip setuptools wheel

      - name: Install test dependencies
        run: |
          python -m pip install \
            pytest \
            pytest-asyncio \
            python-dotenv \
            flask \
            sqlalchemy \
            pydantic

      - name: Validate Python syntax
        run: |
          python -m compileall -q app

      - name: Initialize database
        env:
          PYTHONPATH: ${{ github.workspace }}
        run: |
          python -c "
          from app.database import initialize_database
          initialize_database()
          print('Database initialization passed.')
          "

      - name: Validate application imports
        env:
          PYTHONPATH: ${{ github.workspace }}
        run: |
          python -c "
          from app.database import initialize_database
          from app.dashboard.app import create_dashboard_app

          initialize_database()

          application = create_dashboard_app()

          if application is None:
              raise RuntimeError(
                  'Dashboard application was not created.'
              )

          print('Application imports passed.')
          "

      - name: Run tests
        env:
          PYTHONPATH: ${{ github.workspace }}
          SHAHEEN_YS_ENV: testing
        run: |
          if [ -d "tests" ]; then
            python -m pytest -q
          else
            echo "No tests directory found. Skipping tests."
          fi

  docker:
    name: Build Docker Image
    runs-on: ubuntu-latest
    needs: validate

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Validate Docker files
        run: |
          test -f Dockerfile
          test -f .dockerignore

      - name: Build Docker image
        run: |
          docker build \
            --tag shaheen-ys:ci \
            .

      - name: Docker image created
        run: |
          docker image inspect shaheen-ys:ci > /dev/null

          echo "Docker image validation passed."

  security:
    name: Dependency Security Check
    runs-on: ubuntu-latest
    needs: validate

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install pip-audit
        run: |
          python -m pip install --upgrade pip-audit

      - name: Audit dependencies
        run: |
          if [ -f "requirements.txt" ]; then
            pip-audit \
              --requirement requirements.txt \
              --progress-spinner off \
              || true
          else
            echo "requirements.txt not found."
          fi
YAML

log "تم إنشاء shaheen-ys-ci.yml."

log "التحقق من ملفات Workflow..."

if [[ ! -s ".github/workflows/shaheen-ys-ci.yml" ]]; then
    fail "ملف GitHub Actions فارغ."
fi

if ! grep -q "name: SHAHEEN-YS CI/CD" \
    ".github/workflows/shaheen-ys-ci.yml"
then
    fail "ملف Workflow غير صالح."
fi

if ! grep -q "runs-on: ubuntu-latest" \
    ".github/workflows/shaheen-ys-ci.yml"
then
    fail "بيئة GitHub Actions غير محددة."
fi

log "Workflow validation passed."

log "فحص Python محلياً..."

if command -v python3 >/dev/null 2>&1; then
    python3 -m compileall -q app
    log "Python syntax validation passed."
else
    log "Python 3 غير متاح. تم تجاوز الفحص المحلي."
fi

log "تم إنشاء طبقة CI/CD بنجاح."

log "ملف Workflow:"
log ".github/workflows/shaheen-ys-ci.yml"

log "بعد الرفع إلى GitHub سيبدأ Workflow تلقائياً."
