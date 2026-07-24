#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

LOG_PREFIX="[16-dashboard-branding]"

log() {
    printf '%s %s\n' "$LOG_PREFIX" "$1"
}

error() {
    printf '%s[ERROR] %s\n' "$LOG_PREFIX" "$1" >&2
    exit 1
}

trap 'error "فشل التنفيذ عند السطر $LINENO."' ERR

log "بدء دمج الهوية البصرية داخل Dashboard..."

if [[ ! -d "app/dashboard" ]]; then
    error "مجلد app/dashboard غير موجود."
fi

BRANDING_DIR="app/dashboard/static/assets/branding"
STATIC_DIR="app/dashboard/static"
TEMPLATES_DIR="app/dashboard/templates"
DASHBOARD_APP="app/dashboard/app.py"

mkdir -p "$BRANDING_DIR"
mkdir -p "$STATIC_DIR/css"
mkdir -p "$STATIC_DIR/js"
mkdir -p "$TEMPLATES_DIR"

log "فحص أصول الهوية البصرية..."

if [[ ! -f "$BRANDING_DIR/brand.css" ]]; then
    log "brand.css غير موجود، سيتم إنشاؤه."
fi

if [[ ! -f "$BRANDING_DIR/brand.js" ]]; then
    log "brand.js غير موجود، سيتم إنشاؤه."
fi

log "إنشاء طبقة CSS العامة..."

cat > "$STATIC_DIR/css/shaheen-ys-dashboard.css" <<'CSS'
:root {
    --shaheen-bg-primary: #070b14;
    --shaheen-bg-secondary: #0d1320;
    --shaheen-bg-tertiary: #121a2a;

    --shaheen-surface: rgba(18, 26, 42, 0.78);
    --shaheen-surface-solid: #111827;

    --shaheen-text-primary: #f8fafc;
    --shaheen-text-secondary: #aab4c5;
    --shaheen-text-muted: #6f7c91;

    --shaheen-border: rgba(255, 255, 255, 0.10);
    --shaheen-border-strong: rgba(255, 255, 255, 0.18);

    --shaheen-primary: #d6b36a;
    --shaheen-primary-hover: #edcf8a;
    --shaheen-secondary: #8b5cf6;
    --shaheen-accent: #22d3ee;

    --shaheen-success: #22c55e;
    --shaheen-warning: #f59e0b;
    --shaheen-danger: #ef4444;

    --shaheen-radius-sm: 10px;
    --shaheen-radius-md: 16px;
    --shaheen-radius-lg: 24px;

    --shaheen-shadow-sm: 0 8px 24px rgba(0, 0, 0, 0.20);
    --shaheen-shadow-lg: 0 24px 80px rgba(0, 0, 0, 0.40);

    --shaheen-transition-fast: 160ms ease;
    --shaheen-transition-normal: 280ms ease;
}

* {
    box-sizing: border-box;
}

html {
    min-height: 100%;
    background: var(--shaheen-bg-primary);
}

body {
    min-height: 100vh;
    margin: 0;
    color: var(--shaheen-text-primary);
    background:
        radial-gradient(
            circle at 10% 10%,
            rgba(139, 92, 246, 0.12),
            transparent 32%
        ),
        radial-gradient(
            circle at 90% 20%,
            rgba(34, 211, 238, 0.08),
            transparent 28%
        ),
        linear-gradient(
            135deg,
            var(--shaheen-bg-primary),
            var(--shaheen-bg-secondary)
        );
    font-family:
        Inter,
        ui-sans-serif,
        system-ui,
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        sans-serif;
    overflow-x: hidden;
}

body::before {
    position: fixed;
    inset: 0;
    z-index: -1;
    pointer-events: none;
    content: "";
    opacity: 0.20;
    background-image:
        linear-gradient(
            rgba(255, 255, 255, 0.025) 1px,
            transparent 1px
        ),
        linear-gradient(
            90deg,
            rgba(255, 255, 255, 0.025) 1px,
            transparent 1px
        );
    background-size: 40px 40px;
}

a {
    color: inherit;
    text-decoration: none;
}

button,
input,
select,
textarea {
    font: inherit;
}

.shaheen-dashboard {
    min-height: 100vh;
    padding: 24px;
}

.shaheen-shell {
    width: min(1440px, 100%);
    margin: 0 auto;
}

.shaheen-topbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20px;
    padding: 18px 22px;
    margin-bottom: 24px;
    border: 1px solid var(--shaheen-border);
    border-radius: var(--shaheen-radius-lg);
    background: rgba(13, 19, 32, 0.72);
    box-shadow: var(--shaheen-shadow-sm);
    backdrop-filter: blur(24px);
}

.shaheen-brand {
    display: inline-flex;
    align-items: center;
    gap: 14px;
    min-width: 0;
}

.shaheen-brand-logo {
    display: block;
    width: 48px;
    height: 48px;
    object-fit: cover;
    border-radius: 14px;
    box-shadow:
        0 0 0 1px rgba(214, 179, 106, 0.28),
        0 12px 30px rgba(0, 0, 0, 0.28);
}

.shaheen-brand-content {
    display: flex;
    flex-direction: column;
    gap: 3px;
}

.shaheen-brand-name {
    margin: 0;
    font-size: 1.05rem;
    font-weight: 800;
    letter-spacing: 0.08em;
}

.shaheen-brand-subtitle {
    margin: 0;
    color: var(--shaheen-text-secondary);
    font-size: 0.78rem;
}

.shaheen-card {
    border: 1px solid var(--shaheen-border);
    border-radius: var(--shaheen-radius-lg);
    background: var(--shaheen-surface);
    box-shadow: var(--shaheen-shadow-sm);
    backdrop-filter: blur(22px);
    transition:
        transform var(--shaheen-transition-normal),
        border-color var(--shaheen-transition-normal),
        box-shadow var(--shaheen-transition-normal);
}

.shaheen-card:hover {
    border-color: var(--shaheen-border-strong);
    box-shadow: var(--shaheen-shadow-lg);
    transform: translateY(-3px);
}

.shaheen-card-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 22px 24px 0;
}

.shaheen-card-body {
    padding: 24px;
}

.shaheen-grid {
    display: grid;
    grid-template-columns: repeat(
        auto-fit,
        minmax(240px, 1fr)
    );
    gap: 18px;
}

.shaheen-stat {
    padding: 22px;
}

.shaheen-stat-label {
    margin: 0 0 8px;
    color: var(--shaheen-text-secondary);
    font-size: 0.85rem;
}

.shaheen-stat-value {
    margin: 0;
    font-size: clamp(1.6rem, 4vw, 2.5rem);
    font-weight: 800;
}

.shaheen-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-height: 42px;
    padding: 0 18px;
    color: #0b0f18;
    border: 0;
    border-radius: 12px;
    background: linear-gradient(
        135deg,
        var(--shaheen-primary),
        var(--shaheen-primary-hover)
    );
    cursor: pointer;
    font-weight: 800;
    transition:
        transform var(--shaheen-transition-fast),
        filter var(--shaheen-transition-fast);
}

.shaheen-button:hover {
    filter: brightness(1.08);
    transform: translateY(-2px);
}

.shaheen-button:active {
    transform: translateY(0);
}

.shaheen-status {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    color: var(--shaheen-success);
    font-size: 0.88rem;
    font-weight: 700;
}

.shaheen-status::before {
    width: 8px;
    height: 8px;
    content: "";
    border-radius: 50%;
    background: currentColor;
    box-shadow: 0 0 14px currentColor;
}

.shaheen-fade-in {
    animation: shaheenFadeIn 520ms ease both;
}

@keyframes shaheenFadeIn {
    from {
        opacity: 0;
        transform: translateY(12px);
    }

    to {
        opacity: 1;
        transform: translateY(0);
    }
}

@media (max-width: 720px) {
    .shaheen-dashboard {
        padding: 12px;
    }

    .shaheen-topbar {
        align-items: flex-start;
        flex-direction: column;
        padding: 16px;
    }

    .shaheen-card-header,
    .shaheen-card-body {
        padding-left: 18px;
        padding-right: 18px;
    }
}

@media (prefers-reduced-motion: reduce) {
    *,
    *::before,
    *::after {
        scroll-behavior: auto !important;
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
    }
}
CSS

log "إنشاء JavaScript الخاص بالواجهة..."

cat > "$STATIC_DIR/js/shaheen-ys-dashboard.js" <<'JS'
(() => {
    "use strict";

    const SHAHEEN = {
        name: "SHAHEEN-YS",
        version: "1.0.0",
    };

    function applyBranding() {
        document.documentElement.dataset.brand = SHAHEEN.name;

        const brandedElements = document.querySelectorAll(
            "[data-shaheen-brand-name]"
        );

        brandedElements.forEach((element) => {
            element.textContent = SHAHEEN.name;
        });

        const title = document.querySelector("title");

        if (title && !title.textContent.includes(SHAHEEN.name)) {
            title.textContent = `${SHAHEEN.name} Dashboard`;
        }
    }

    function initializeAnimations() {
        const elements = document.querySelectorAll(
            ".shaheen-fade-in"
        );

        elements.forEach((element, index) => {
            element.style.animationDelay = `${index * 45}ms`;
        });
    }

    function initialize() {
        applyBranding();
        initializeAnimations();
    }

    if (document.readyState === "loading") {
        document.addEventListener(
            "DOMContentLoaded",
            initialize,
            { once: true }
        );
    } else {
        initialize();
    }
})();
JS

log "تحديد ملف الشعار الرئيسي..."

LOGO_PATH=""

for candidate in \
    "$BRANDING_DIR/logo.png" \
    "$BRANDING_DIR/main-logo.png" \
    "$BRANDING_DIR/primary-logo.png" \
    "$BRANDING_DIR/logo.jpg" \
    "$BRANDING_DIR/main-logo.jpg"
do
    if [[ -f "$candidate" ]]; then
        LOGO_PATH="$candidate"
        break
    fi
done

if [[ -z "$LOGO_PATH" ]]; then
    log "لم يتم العثور على ملف شعار محلي معروف."
    log "سيتم استخدام مسار branding مرن داخل القالب."
    LOGO_URL="/static/assets/branding/logo.png"
else
    LOGO_URL="/static/assets/branding/$(basename "$LOGO_PATH")"
fi

log "إنشاء قالب Dashboard موحد..."

cat > "$TEMPLATES_DIR/shaheen_base.html" <<'HTML'
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
                        onerror="
                            this.style.display='none';
                        "
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

            {% block content %}{% endblock %}
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

log "إنشاء صفحة Dashboard الأساسية..."

cat > "$TEMPLATES_DIR/dashboard.html" <<'HTML'
{% extends "shaheen_base.html" %}

{% block content %}
<section class="shaheen-grid">
    <article class="shaheen-card shaheen-stat shaheen-fade-in">
        <p class="shaheen-stat-label">
            المنصة
        </p>

        <h2 class="shaheen-stat-value">
            SHAHEEN-YS
        </h2>
    </article>

    <article class="shaheen-card shaheen-stat shaheen-fade-in">
        <p class="shaheen-stat-label">
            حالة النظام
        </p>

        <h2 class="shaheen-stat-value">
            Operational
        </h2>
    </article>

    <article class="shaheen-card shaheen-stat shaheen-fade-in">
        <p class="shaheen-stat-label">
            قاعدة البيانات
        </p>

        <h2 class="shaheen-stat-value">
            Connected
        </h2>
    </article>
</section>
{% endblock %}
HTML

log "التحقق من وجود create_dashboard_app..."

if ! grep -q "def create_dashboard_app" "$DASHBOARD_APP"; then
    error "لم يتم العثور على create_dashboard_app داخل $DASHBOARD_APP"
fi

log "التحقق من صحة Python..."

python3 -m py_compile "$DASHBOARD_APP"

log "التحقق من ملفات الهوية..."

test -f "$STATIC_DIR/css/shaheen-ys-dashboard.css"
test -f "$STATIC_DIR/js/shaheen-ys-dashboard.js"
test -f "$TEMPLATES_DIR/shaheen_base.html"
test -f "$TEMPLATES_DIR/dashboard.html"

log "تم دمج الهوية البصرية داخل Dashboard بنجاح."
log "اسم المنتج: SHAHEEN-YS"
log "النمط: Premium Modern Dark-First"
log "الدعم: Termux / Railway / Docker / Linux"
log "الخطوة التالية: اختبار Dashboard بعد الدمج."
