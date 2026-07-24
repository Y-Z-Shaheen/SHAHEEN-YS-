#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

export PYTHONPATH="$PROJECT_ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "[09-dashboard] بدء تهيئة طبقة Dashboard..."

mkdir -p \
    "$PROJECT_ROOT/app/dashboard/templates" \
    "$PROJECT_ROOT/app/dashboard/static"

touch "$PROJECT_ROOT/app/dashboard/__init__.py"

if [[ ! -f "$PROJECT_ROOT/app/database.py" ]]; then
    echo "[09-dashboard][ERROR] الملف app/database.py غير موجود."
    exit 1
fi

if ! python3 -c "import flask" 2>/dev/null; then
    echo "[09-dashboard][ERROR] Flask غير مثبت."
    echo "[09-dashboard] قم بتثبيته باستخدام:"
    echo "pip install flask"
    exit 1
fi

cat > "$PROJECT_ROOT/app/dashboard/app.py" << 'PYTHON_EOF'
from __future__ import annotations

import os
import socket
from datetime import datetime, timezone

from flask import Flask, jsonify, render_template

from app.database import check_database_health, initialize_database


def create_dashboard_app() -> Flask:
    app = Flask(
        __name__,
        template_folder="templates",
        static_folder="static",
    )

    app.config["JSON_SORT_KEYS"] = False

    @app.get("/")
    def dashboard():
        database_health = check_database_health()

        return render_template(
            "dashboard.html",
            database=database_health,
            hostname=socket.gethostname(),
            timestamp=datetime.now(timezone.utc).isoformat(),
        )

    @app.get("/health")
    def health():
        database_health = check_database_health()

        database_is_healthy = (
            isinstance(database_health, dict)
            and database_health.get("status") == "healthy"
        )

        response = {
            "service": "SHAHEEN-YS Dashboard",
            "status": "healthy" if database_is_healthy else "degraded",
            "database": database_health,
            "hostname": socket.gethostname(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        return jsonify(response), 200 if database_is_healthy else 503

    @app.get("/api/dashboard/status")
    def dashboard_status():
        database_health = check_database_health()

        return jsonify(
            {
                "service": "dashboard",
                "platform": "SHAHEEN-YS",
                "status": "operational",
                "database": database_health,
                "environment": os.getenv(
                    "SHAHEEN_YS_ENV",
                    "development",
                ),
            }
        )

    return app


app = create_dashboard_app()


if __name__ == "__main__":
    initialize_database()

    host = os.getenv("SHAHEEN_YS_DASHBOARD_HOST", "127.0.0.1")
    port = int(os.getenv("SHAHEEN_YS_DASHBOARD_PORT", "8080"))

    app.run(
        host=host,
        port=port,
        debug=False,
    )
PYTHON_EOF

cat > "$PROJECT_ROOT/app/dashboard/templates/dashboard.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>SHAHEEN-YS Dashboard</title>

    <style>
        :root {
            color-scheme: dark;
        }

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            min-height: 100vh;
            font-family:
                system-ui,
                -apple-system,
                BlinkMacSystemFont,
                "Segoe UI",
                sans-serif;
            background:
                radial-gradient(
                    circle at top,
                    #1f2937 0%,
                    #111827 45%,
                    #030712 100%
                );
            color: #f9fafb;
        }

        .container {
            width: min(1100px, calc(100% - 32px));
            margin: 40px auto;
        }

        .header {
            padding: 28px;
            border: 1px solid #374151;
            border-radius: 18px;
            background: rgba(17, 24, 39, 0.88);
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.35);
        }

        h1 {
            margin: 0 0 10px;
            font-size: clamp(2rem, 5vw, 3.5rem);
        }

        .subtitle {
            margin: 0;
            color: #9ca3af;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(
                auto-fit,
                minmax(220px, 1fr)
            );
            gap: 18px;
            margin-top: 22px;
        }

        .card {
            padding: 22px;
            border: 1px solid #374151;
            border-radius: 16px;
            background: rgba(31, 41, 55, 0.82);
        }

        .card h2 {
            margin-top: 0;
            font-size: 1.15rem;
        }

        .status {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 8px 12px;
            border-radius: 999px;
            background: #064e3b;
            color: #a7f3d0;
            font-weight: 700;
        }

        .status::before {
            content: "";
            width: 9px;
            height: 9px;
            border-radius: 50%;
            background: currentColor;
        }

        code {
            display: block;
            overflow-x: auto;
            margin-top: 12px;
            padding: 12px;
            border-radius: 10px;
            background: #030712;
            color: #d1d5db;
        }
    </style>
</head>

<body>
    <main class="container">
        <section class="header">
            <h1>🦅 SHAHEEN-YS</h1>

            <p class="subtitle">
                Microservices-based Cloud Platform
            </p>

            <p>
                <span class="status">
                    النظام يعمل
                </span>
            </p>
        </section>

        <section class="grid">
            <article class="card">
                <h2>🗄️ قاعدة البيانات</h2>

                <p>
                    الحالة:
                    <strong>
                        {{ database.get("status", "unknown") }}
                    </strong>
                </p>
            </article>

            <article class="card">
                <h2>🖥️ الخادم</h2>

                <p>
                    {{ hostname }}
                </p>
            </article>

            <article class="card">
                <h2>🌐 API Health</h2>

                <p>
                    <a href="/health">
                        /health
                    </a>
                </p>
            </article>

            <article class="card">
                <h2>📊 Dashboard API</h2>

                <p>
                    <a href="/api/dashboard/status">
                        /api/dashboard/status
                    </a>
                </p>
            </article>
        </section>

        <section class="card" style="margin-top: 22px;">
            <h2>⏱️ آخر تحديث</h2>

            <code>
                {{ timestamp }}
            </code>
        </section>
    </main>
</body>
</html>
HTML_EOF

cat > "$PROJECT_ROOT/app/dashboard/test_dashboard.py" << 'PYTHON_EOF'
from __future__ import annotations

from app.dashboard.app import create_dashboard_app


def main() -> None:
    application = create_dashboard_app()

    application.testing = True

    client = application.test_client()

    dashboard_response = client.get("/")

    if dashboard_response.status_code != 200:
        raise RuntimeError(
            f"Dashboard returned HTTP {dashboard_response.status_code}"
        )

    health_response = client.get("/health")

    if health_response.status_code not in (200, 503):
        raise RuntimeError(
            f"Health endpoint returned HTTP {health_response.status_code}"
        )

    status_response = client.get("/api/dashboard/status")

    if status_response.status_code != 200:
        raise RuntimeError(
            "Dashboard status endpoint is not responding correctly"
        )

    print("[09-dashboard] Dashboard tests passed successfully.")


if __name__ == "__main__":
    main()
PYTHON_EOF

echo "[09-dashboard] تهيئة قاعدة البيانات..."

python3 -c "
from app.database import initialize_database
initialize_database()
"

echo "[09-dashboard] تشغيل اختبارات Dashboard..."

python3 -m app.dashboard.test_dashboard

echo "[09-dashboard] تم إنشاء Dashboard بنجاح."
echo
echo "[09-dashboard] لتشغيل لوحة التحكم:"
echo "python3 -m app.dashboard.app"
echo
echo "[09-dashboard] رابط لوحة التحكم:"
echo "http://127.0.0.1:8080"
