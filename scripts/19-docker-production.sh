#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

LOG_PREFIX="[19-docker-production]"

log() {
    printf '%s %s\n' "$LOG_PREFIX" "$1"
}

fail() {
    printf '%s[ERROR] %s\n' "$LOG_PREFIX" "$1" >&2
    exit 1
}

trap 'fail "فشل التنفيذ عند السطر $LINENO."' ERR

log "بدء إعداد Docker Production لـ SHAHEEN-YS..."

if [[ ! -f "wsgi.py" ]]; then
    fail "ملف wsgi.py غير موجود. شغّل السكريبت 18 أولاً."
fi

if [[ ! -f "scripts/start-production.sh" ]]; then
    fail "ملف start-production.sh غير موجود. شغّل السكريبت 18 أولاً."
fi

log "إنشاء Dockerfile Production..."

cat > Dockerfile <<'DOCKERFILE'
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=utf-8 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    SHAHEEN_YS_ENV=production \
    HOST=0.0.0.0

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system shaheen \
    && useradd \
        --system \
        --gid shaheen \
        --create-home \
        --home-dir /home/shaheen \
        shaheen

COPY requirements.txt .

RUN python -m pip install --upgrade pip \
    && python -m pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p \
        /app/data/db \
        /app/data/plugins \
        /app/data/dist \
        /app/logs \
    && chown -R shaheen:shaheen /app

USER shaheen

EXPOSE 8080

HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=30s \
    --retries=5 \
    CMD curl \
        --fail \
        --silent \
        http://127.0.0.1:${PORT:-8080}/health \
        || exit 1

CMD ["sh", "-c", "./scripts/start-production.sh"]
DOCKERFILE

log "إنشاء Docker Ignore..."

cat > .dockerignore <<'EOF'
.git
.gitignore
.github
.idea
.vscode

__pycache__
*.py[cod]
*.pyo

.pytest_cache
.mypy_cache
.ruff_cache
.coverage
htmlcov

.venv
venv
env
ENV

node_modules
.npm
.yarn

*.log
logs/*.log

.env
.env.*
!.env.example
!.env.production.example

data/db/*.db
data/db/*.db-*
data/cache
data/tmp

dist
build
*.egg-info

tests
docs/_build

.DS_Store
Thumbs.db
EOF

log "إنشاء Docker Compose Production..."

cat > docker-compose.yml <<'YAML'
services:
  shaheen-ys:
    build:
      context: .
      dockerfile: Dockerfile

    container_name: shaheen-ys

    restart: unless-stopped

    ports:
      - "${PORT:-8080}:${PORT:-8080}"

    environment:
      SHAHEEN_YS_ENV: ${SHAHEEN_YS_ENV:-production}
      SHAHEEN_YS_VERSION: ${SHAHEEN_YS_VERSION:-1.0.0}

      HOST: 0.0.0.0
      PORT: ${PORT:-8080}

      WEB_CONCURRENCY: ${WEB_CONCURRENCY:-2}
      GUNICORN_TIMEOUT: ${GUNICORN_TIMEOUT:-120}

      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
      GOOGLE_API_KEY: ${GOOGLE_API_KEY:-}

      SHAHEEN_YS_ADMIN_USERNAME: ${SHAHEEN_YS_ADMIN_USERNAME:-}
      SHAHEEN_YS_ADMIN_PASSWORD: ${SHAHEEN_YS_ADMIN_PASSWORD:-}

    volumes:
      - shaheen_ys_data:/app/data
      - shaheen_ys_logs:/app/logs

    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl --fail --silent http://127.0.0.1:$${PORT:-8080}/health || exit 1"
        ]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

    stop_grace_period: 30s

volumes:
  shaheen_ys_data:
    name: shaheen_ys_data

  shaheen_ys_logs:
    name: shaheen_ys_logs
YAML

log "إنشاء Docker Environment Example..."

cat > .env.docker.example <<'ENV'
SHAHEEN_YS_ENV=production
SHAHEEN_YS_VERSION=1.0.0

HOST=0.0.0.0
PORT=8080

WEB_CONCURRENCY=2
GUNICORN_TIMEOUT=120

OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GOOGLE_API_KEY=

SHAHEEN_YS_ADMIN_USERNAME=
SHAHEEN_YS_ADMIN_PASSWORD=
ENV

log "إنشاء سكريبت تشغيل Docker..."

cat > scripts/docker-production.sh <<'BASH'
#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

COMMAND="${1:-up}"

case "$COMMAND" in
    build)
        docker compose build --no-cache
        ;;

    up)
        docker compose up -d --build
        ;;

    down)
        docker compose down
        ;;

    restart)
        docker compose down
        docker compose up -d --build
        ;;

    logs)
        docker compose logs -f --tail=200
        ;;

    status)
        docker compose ps
        ;;

    health)
        PORT="${PORT:-8080}"

        curl \
            --fail \
            --silent \
            "http://127.0.0.1:${PORT}/health"

        printf '\n'
        ;;

    shell)
        docker compose exec shaheen-ys /bin/sh
        ;;

    *)
        echo "Usage:"
        echo "  $0 build"
        echo "  $0 up"
        echo "  $0 down"
        echo "  $0 restart"
        echo "  $0 logs"
        echo "  $0 status"
        echo "  $0 health"
        echo "  $0 shell"
        exit 1
        ;;
esac
