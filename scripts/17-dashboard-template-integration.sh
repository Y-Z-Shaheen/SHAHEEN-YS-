#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

LOG_PREFIX="[17-dashboard-integration]"

log() {
    printf '%s %s\n' "$LOG_PREFIX" "$1"
}

fail() {
    printf '%s[ERROR] %s\n' "$LOG_PREFIX" "$1" >&2
    exit 1
}

trap 'fail "فشل التنفيذ عند السطر $LINENO."' ERR

DASHBOARD_APP="app/dashboard/app.py"
TEMPLATES_DIR="app/dashboard/templates"
STATIC_DIR="app/dashboard/static"

log "بدء دمج قالب SHAHEEN-YS داخل Dashboard..."

if [[ ! -f "$DASHBOARD_APP" ]]; then
    fail "ملف Dashboard غير موجود: $DASHBOARD_APP"
fi

mkdir -p "$TEMPLATES_DIR"
mkdir -p "$STATIC_DIR/css"
mkdir -p "$STATIC_DIR/js"

log "إنشاء قالب Dashboard الرئيسي..."

cat > "$TEMPLATES_DIR/dashboard.html" <<'HTML'
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">

    <meta
        name="viewport"
        content="width=device-width, initial-scale=1"
    >

    <meta
        name="theme-color"
        content="#070b14"
    >

    <meta
        name="application-name"
        content="SHAHEEN-YS"
    >

    <meta
        name="description"
        content="SHAHEEN-YS Premium Modern AI Platform"
    >

    <title>SHAHEEN-YS Dashboard</title>

    <link
        rel="stylesheet"
        href="{{ url_for(
            'static',
            filename='css/shaheen-ys-dashboard.css'
        ) }}"
    >

    <link
        rel="stylesheet"
        href="{{ url_for(
            'static',
            filename='assets/branding/brand.css'
        ) }}"
    >
</head>

<body>
    <main class="shaheen-dashboard">
        <div class="shaheen-shell">

            <header class="shaheen-topbar shaheen-fade-in">

                <a
                    class="shaheen-brand"
                    href="/"
                    aria-label="SHAHEEN-YS"
                >

                    <img
                        class="shaheen-brand-logo"
                        src="{{ logo_url }}"
                        alt="SHAHEEN-YS"
                        onerror="this.style.display='none';"
                    >

                    <span class="shaheen-brand-content">

                        <strong
                            class="shaheen-brand-name"
                            data-shaheen-brand-name
                        >
                            SHAHEEN-YS
                        </strong>

                        <small class="shaheen-brand-subtitle">
                            Premium Modern AI Platform
                        </small>

                    </span>

                </a>

                <span class="shaheen-status">
                    النظام يعمل
                </span>

            </header>

            <section class="shaheen-grid">

                <article
                    class="shaheen-card shaheen-stat shaheen-fade-in"
                >
                    <p class="shaheen-stat-label">
                        المنصة
                    </p>

                    <h2 class="shaheen-stat-value">
                        SHAHEEN-YS
                    </h2>
                </article>

                <article
                    class="shaheen-card shaheen-stat shaheen-fade-in"
                >
                    <p class="shaheen-stat-label">
                        حالة النظام
                    </p>

                    <h2 class="shaheen-stat-value">
                        {{ dashboard_status }}
                    </h2>
                </article>

                <article
                    class="shaheen-card shaheen-stat shaheen-fade-in"
                >
                    <p class="shaheen-stat-label">
                        قاعدة البيانات
                    </p>

                    <h2 class="shaheen-stat-value">
                        {{ database_status }}
                    </h2>
                </article>

            </section>

            <section
                class="shaheen-card shaheen-fade-in"
                style="margin-top: 24px;"
            >

                <div class="shaheen-card-header">
                    <h2>
                        SHAHEEN-YS Control Center
                    </h2>

                    <span class="shaheen-status">
                        Operational
                    </span>
                </div>

                <div class="shaheen-card-body">

                    <p>
                        منصة SHAHEEN-YS تعمل حالياً بالهوية البصرية
                        الجديدة ونظام Dashboard الموحد.
                    </p>

                    <div
                        class="shaheen-grid"
                        style="margin-top: 18px;"
                    >

                        <div class="shaheen-card shaheen-stat">
                            <p class="shaheen-stat-label">
                                البيئة
                            </p>

                            <h3>
                                {{ environment }}
                            </h3>
                        </div>

                        <div class="shaheen-card shaheen-stat">
                            <p class="shaheen-stat-label">
                                Hostname
                            </p>

                            <h3>
                                {{ hostname }}
                            </h3>
                        </div>

                        <div class="shaheen-card shaheen-stat">
                            <p class="shaheen-stat-label">
                                الإصدار
                            </p>

                            <h3>
                                {{ version }}
                            </h3>
                        </div>

                    </div>

                </div>

            </section>

        </div>
    </main>

    <script
        src="{{ url_for(
            'static',
            filename='js/shaheen-ys-dashboard.js'
        ) }}"
    ></script>
</body>
</html>
HTML

log "تحديد ملف الشعار..."

LOGO_URL="/static/assets/branding/logo.png"

for logo_candidate in \
    "app/dashboard/static/assets/branding/logo.png" \
    "app/dashboard/static/assets/branding/main-logo.png" \
    "app/dashboard/static/assets/branding/primary-logo.png"
do
    if [[ -f "$logo_candidate" ]]; then
        LOGO_URL="/static/assets/branding/$(basename "$logo_candidate")"
        break
    fi
done

log "إضافة دالة Dashboard HTML..."

python3 - "$DASHBOARD_APP" "$LOGO_URL" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

dashboard_path = Path(sys.argv[1])
logo_url = sys.argv[2]

source = dashboard_path.read_text(encoding="utf-8")

if "def dashboard():" not in source:
    raise RuntimeError(
        "لم يتم العثور على دالة dashboard() داخل app/dashboard/app.py"
    )

start_marker = '    @app.get("/")\n    def dashboard():\n'

start_index = source.find(start_marker)

if start_index == -1:
    raise RuntimeError(
        "تعذر تحديد بداية دالة dashboard()"
    )

body_start = start_index + len(start_marker)

next_route_index = source.find(
    "\n    @app.",
    body_start,
)

if next_route_index == -1:
    next_route_index = source.find(
        "\n    return app",
        body_start,
    )

if next_route_index == -1:
    raise RuntimeError(
        "تعذر تحديد نهاية دالة dashboard()"
    )

new_dashboard_function = f'''    @app.get("/")
    def dashboard():
        database_health = check_database_health()

        database_is_healthy = (
            isinstance(database_health, dict)
            and database_health.get("status") == "healthy"
        )

        return render_template(
            "dashboard.html",
            logo_url="{logo_url}",
            dashboard_status=(
                "Operational"
                if database_is_healthy
                else "Degraded"
            ),
            database_status=(
                "Connected"
                if database_is_healthy
                else "Unavailable"
            ),
            environment=os.getenv(
                "SHAHEEN_YS_ENV",
                "development",
            ),
            hostname=socket.gethostname(),
            version=os.getenv(
                "SHAHEEN_YS_VERSION",
                "1.0.0",
            ),
        )

'''

updated_source = (
    source[:start_index]
    + new_dashboard_function
    + source[next_route_index + 1:]
)

dashboard_path.write_text(
    updated_source,
    encoding="utf-8",
)

print(
    "Dashboard route integrated successfully."
)
PY

log "التحقق من Syntax Python..."

python3 -m py_compile "$DASHBOARD_APP"

log "التحقق من القالب..."

if ! grep -q "SHAHEEN-YS Dashboard" \
    "$TEMPLATES_DIR/dashboard.html"
then
    fail "قالب Dashboard لم يتم إنشاؤه بشكل صحيح."
fi

if ! grep -q "render_template" "$DASHBOARD_APP"; then
    fail "لم يتم العثور على render_template داخل Dashboard."
fi

log "التحقق من الهوية البصرية..."

test -f "$STATIC_DIR/css/shaheen-ys-dashboard.css"
test -f "$STATIC_DIR/js/shaheen-ys-dashboard.js"

log "تشغيل اختبار استيراد Dashboard..."

export PYTHONPATH="$PROJECT_ROOT"

python3 - <<'PY'
from app.dashboard.app import app

print("Dashboard import: OK")
print(f"Application name: {app.name}")
PY

log "تم دمج Dashboard مع الهوية البصرية بنجاح."
log "الاسم النهائي: SHAHEEN-YS"
log "الواجهة: Premium Modern Dark-First"
log "الدعم: Termux / Railway / Docker / Linux"
