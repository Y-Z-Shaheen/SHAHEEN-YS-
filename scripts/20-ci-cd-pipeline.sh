#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

LOG_PREFIX="[20-ci-cd-pipeline]"

log() {
    printf '%s %s\n' "$LOG_PREFIX" "$1"
}

fail() {
    printf '%s[ERROR] %s\n' "$LOG_PREFIX" "$1" >&2
    exit 1
}

trap 'fail "فشل التنفيذ عند السطر $LINENO."' ERR

log "بدء إعداد GitHub Actions CI/CD..."

mkdir -p .github/workflows

log "إنشاء Workflow الخاص بالاختبارات..."

cat > .github/workflows/ci.yml <<'YAML'
name: SHAHEEN-YS CI

on:
  push:
    branches:
      - main
      - develop

  pull_request:
    branches:
      - main
      - develop

permissions:
  contents: read

concurrency:
  group: shaheen-ys-ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  quality:
    name: Code Quality & Tests
    runs-on: ubuntu-latest

    timeout-minutes: 15

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip

      - name: Install Dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt

      - name: Python Syntax Check
        run: |
          python -m compileall -q app
          python -m py_compile wsgi.py

      - name: Initialize Database
        env:
          PYTHONPATH: ${{ github.workspace }}
        run: |
          python -c "
          from app.database import initialize_database
          initialize_database()
          print('Database initialization: OK')
          "

      - name: WSGI Import Test
        env:
          PYTHONPATH: ${{ github.workspace }}
          SHAHEEN_YS_ENV: test
        run: |
          python -c "
          from wsgi import application
          print('WSGI import: OK')
          print(f'Application: {application.name}')
          "

      - name: Database Health Test
        env:
          PYTHONPATH: ${{ github.workspace }}
        run: |
          python -c "
          from app.database import check_database_health

          result = check_database_health()

          print(result)

          if result.get('status') != 'healthy':
              raise SystemExit('Database health check failed')

          print('Database health: OK')
          "

      - name: Run Pytest
        env:
          PYTHONPATH: ${{ github.workspace }}
          SHAHEEN_YS_ENV: test
        run: |
          if find tests -type f -name "test_*.py" -o -name "*_test.py" | grep -q .; then
            pytest -q
          else
            echo "No pytest tests found. Skipping."
          fi

      - name: Validate Visual Identity
        run: |
          test -f app/dashboard/static/branding/brand.css
          test -f app/dashboard/static/branding/brand.js
          test -f app/dashboard/static/branding/manifest.json

          echo "Visual identity assets: OK"

      - name: Check Sensitive Files
        run: |
          if git ls-files | grep -E '(^|/)(\.env|\.env\..*|.*\.pem|.*\.key)$' | grep -vE '(\.example$|\.template$)'; then
            echo "Potential sensitive files detected."
            exit 1
          fi

          echo "Sensitive file check: OK"

  docker:
    name: Docker Build Validation
    runs-on: ubuntu-latest

    timeout-minutes: 20

    needs:
      - quality

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Validate Dockerfile
        run: |
          docker build --check .

      - name: Build Docker Image
        run: |
          docker build \
            --tag shaheen-ys:ci-${{ github.sha }} \
            .

      - name: Inspect Docker Image
        run: |
          docker image inspect shaheen-ys:ci-${{ github.sha }}

      - name: Verify Container User
        run: |
          USER_ID="$(docker run --rm shaheen-ys:ci-${{ github.sha }} id -u)"

          if [ "$USER_ID" = "0" ]; then
            echo "Container is running as root."
            exit 1
          fi

          echo "Container is running as non-root user: $USER_ID"
YAML

log "إنشاء Workflow لفحص الأمان..."

cat > .github/workflows/security.yml <<'YAML'
name: SHAHEEN-YS Security

on:
  push:
    branches:
      - main

  pull_request:
    branches:
      - main

permissions:
  contents: read

jobs:
  secret-scan:
    name: Secret Scan
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Scan Repository For Common Secrets
        run: |
          set -e

          PATTERN='(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})'

          if git grep -n -E "$PATTERN" -- \
              ':!.github/workflows/security.yml' \
              ':!*.md'; then
            echo "Potential secret detected."
            exit 1
          fi

          echo "Secret scan passed."

  python-security:
    name: Python Security Scan
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install Security Tools
        run: |
          python -m pip install --upgrade pip
          pip install bandit

      - name: Run Bandit
        run: |
          bandit \
            -r app \
            -x tests \
            -ll \
            -ii
YAML

log "إنشاء Workflow لفحص الهوية البصرية..."

cat > .github/workflows/branding.yml <<'YAML'
name: SHAHEEN-YS Branding Validation

on:
  push:
    branches:
      - main
      - develop

  pull_request:
    branches:
      - main
      - develop

permissions:
  contents: read

jobs:
  branding:
    name: Validate Visual Identity
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Validate Branding Files
        run: |
          set -e

          REQUIRED_FILES=(
            "app/dashboard/static/branding/brand.css"
            "app/dashboard/static/branding/brand.js"
            "app/dashboard/static/branding/manifest.json"
          )

          for FILE in "${REQUIRED_FILES[@]}"; do
            if [ ! -f "$FILE" ]; then
              echo "Missing branding file: $FILE"
              exit 1
            fi
          done

          echo "All branding files exist."

      - name: Validate Manifest JSON
        run: |
          python -m json.tool \
            app/dashboard/static/branding/manifest.json \
            > /dev/null

          echo "Brand manifest JSON: OK"

      - name: Check SHAHEEN-YS Brand Name
        run: |
          if ! grep -Rni \
              "SHAHEEN-YS" \
              app/dashboard/static/branding; then
            echo "Brand name was not found in branding assets."
            exit 1
          fi

          echo "Brand name validation: OK"
YAML

log "إنشاء Workflow اختياري لنشر Railway..."

cat > .github/workflows/deploy.yml <<'YAML'
name: SHAHEEN-YS Production Deployment

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  deploy:
    name: Deploy To Railway
    runs-on: ubuntu-latest

    environment:
      name: production

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Install Railway CLI
        run: |
          npm install -g @railway/cli

      - name: Deploy To Railway
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
        run: |
          if [ -z "$RAILWAY_TOKEN" ]; then
            echo "RAILWAY_TOKEN secret is not configured."
            exit 1
          fi

          railway up \
            --detach
YAML

log "إنشاء Dependabot Configuration..."

cat > .github/dependabot.yml <<'YAML'
version: 2

updates:
  - package-ecosystem: pip
    directory: "/"
    schedule:
      interval: weekly

    open-pull-requests-limit: 5

  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly

    open-pull-requests-limit: 5
YAML

log "إنشاء Pull Request Template..."

mkdir -p .github/PULL_REQUEST_TEMPLATE

cat > .github/PULL_REQUEST_TEMPLATE/default.md <<'MARKDOWN'
## Description

Describe the changes introduced by this Pull Request.

## Type Of Change

- [ ] Feature
- [ ] Bug Fix
- [ ] Refactoring
- [ ] Documentation
- [ ] Security
- [ ] Infrastructure
- [ ] Visual Identity

## Validation

- [ ] Python Syntax Check
- [ ] Database Initialization
- [ ] WSGI Import
- [ ] Tests
- [ ] Docker Build
- [ ] Security Scan

## Production Impact

Describe any production impact.

## Environment Variables

- [ ] No new environment variables
- [ ] New environment variables documented
- [ ] Secrets are stored only in GitHub Secrets / Railway Variables

## Checklist

- [ ] No secrets committed
- [ ] No `.env` file committed
- [ ] Backward compatibility reviewed
- [ ] Error handling reviewed
- [ ] Documentation updated if necessary
MARKDOWN

log "التحقق من ملفات CI/CD..."

test -f .github/workflows/ci.yml
test -f .github/workflows/security.yml
test -f .github/workflows/branding.yml
test -f .github/workflows/deploy.yml
test -f .github/dependabot.yml

log "التحقق من YAML..."

python3 - <<'PY'
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    print("PyYAML غير مثبت محلياً. سيتم تخطي YAML validation.")
    raise SystemExit(0)

files = [
    Path(".github/workflows/ci.yml"),
    Path(".github/workflows/security.yml"),
    Path(".github/workflows/branding.yml"),
    Path(".github/workflows/deploy.yml"),
    Path(".github/dependabot.yml"),
]

for file_path in files:
    with file_path.open("r", encoding="utf-8") as file:
        yaml.safe_load(file)

    print(f"{file_path}: YAML OK")
PY

log "فحص Git..."

if git diff --check; then
    log "Git whitespace check: OK"
else
    fail "Git whitespace check failed."
fi

log "تم إعداد CI/CD Pipeline بنجاح."
log "CI: Python + Tests + Docker"
log "Security: Secret Scan + Bandit"
log "Branding: Visual Identity Validation"
log "Deployment: Railway Manual Workflow"
log "Dependencies: Dependabot"
