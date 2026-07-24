#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

export PYTHONPATH="$PROJECT_ROOT"

python3 -m compileall -q app wsgi.py

python3 -c \
"from wsgi import application; print('Production WSGI import: OK')"

printf '%s\n' "Production verification completed successfully."
