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
