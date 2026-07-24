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
        http://127.0.0.1:${PORT:-8080}/health/live/live/live \
        || exit 1

CMD ["sh", "-c", "./scripts/start-production.sh"]
