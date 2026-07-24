#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="15-visual-identity"
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

log "بدء تطبيق الهوية البصرية لـ SHAHEEN-YS..."

mkdir -p \
    app/dashboard/static/assets/branding \
    app/dashboard/static/assets/icons \
    app/dashboard/static/assets/images \
    app/dashboard/static/css \
    app/dashboard/static/js \
    app/dashboard/templates

BRANDING_DIR="app/dashboard/static/assets/branding"
IMAGES_DIR="app/dashboard/static/assets/images"

MAIN_LOGO_URL="https://i.postimg.cc/9XJ5yQZY/Picsart-26-07-21-04-44-19-389.png"

IMAGE_1_URL="https://i.postimg.cc/LsjpbFgS/Picsart-26-07-23-03-11-34-365.png"

IMAGE_2_URL="https://i.postimg.cc/W40vHcqT/Picsart-26-07-23-03-11-56-173.png"

IMAGE_3_URL="https://i.postimg.cc/Dz1TM34F/Picsart-26-07-23-03-12-22-367.png"

IMAGE_4_URL="https://i.postimg.cc/1zDQj1Vh/Picsart-26-07-23-03-20-52-434.png"

download_asset() {
    local url="$1"
    local destination="$2"

    if command -v curl >/dev/null 2>&1; then
        curl \
            --fail \
            --location \
            --silent \
            --show-error \
            --retry 3 \
            --connect-timeout 20 \
            "$url" \
            --output "$destination"
        return
    fi

    if command -v wget >/dev/null 2>&1; then
        wget \
            --quiet \
            --tries=3 \
            --timeout=20 \
            --output-document="$destination" \
            "$url"
        return
    fi

    fail "curl أو wget غير مثبت."
}

log "تنزيل الشعار الرئيسي..."

download_asset \
    "$MAIN_LOGO_URL" \
    "$BRANDING_DIR/logo.png"

log "تنزيل الأصول البصرية..."

download_asset \
    "$IMAGE_1_URL" \
    "$IMAGES_DIR/shaheen-ys-01.png"

download_asset \
    "$IMAGE_2_URL" \
    "$IMAGES_DIR/shaheen-ys-02.png"

download_asset \
    "$IMAGE_3_URL" \
    "$IMAGES_DIR/shaheen-ys-03.png"

download_asset \
    "$IMAGE_4_URL" \
    "$IMAGES_DIR/shaheen-ys-04.png"

log "إنشاء ملف الهوية البصرية..."

cat > "$BRANDING_DIR/brand.json" <<'JSON'
{
  "name": "SHAHEEN-YS",
  "display_name": "SHAHEEN-YS",
  "short_name": "SHAHEEN-YS",
  "description": "SHAHEEN-YS AI Platform",
  "theme": {
    "mode": "dark-first",
    "supports_light_mode": true,
    "primary": "#D4AF37",
    "secondary": "#8B5CF6",
    "accent": "#00D4FF",
    "background": "#070B14",
    "surface": "#111827",
    "surface_elevated": "#1F2937",
    "text": "#F8FAFC",
    "text_muted": "#94A3B8",
    "success": "#22C55E",
    "warning": "#F59E0B",
    "danger": "#EF4444"
  },
  "typography": {
    "font_family": "Inter",
    "heading_weight": 800,
    "body_weight": 400
  },
  "design": {
    "style": "premium-modern",
    "glassmorphism": true,
    "gradients": true,
    "animations": true,
    "rounded_cards": true,
    "dark_mode": true,
    "light_mode": true
  }
}
JSON

log "إنشاء نظام CSS المركزي..."

cat > app/dashboard/static/css/shaheen-ys-brand.css <<'CSS'
:root {
    --shaheen-primary: #D4AF37;
    --shaheen-secondary: #8B5CF6;
    --shaheen-accent: #00D4FF;

    --shaheen-background: #070B14;
    --shaheen-surface: #111827;
    --shaheen-surface-elevated: #1F2937;

    --shaheen-text: #F8FAFC;
    --shaheen-text-muted: #94A3B8;

    --shaheen-success: #22C55E;
    --shaheen-warning: #F59E0B;
    --shaheen-danger: #EF4444;

    --shaheen-radius-sm: 8px;
    --shaheen-radius-md: 14px;
    --shaheen-radius-lg: 22px;

    --shaheen-shadow:
        0 20px 60px rgba(0, 0, 0, 0.35);

    --shaheen-glass:
        rgba(17, 24, 39, 0.72);

    --shaheen-gradient:
        linear-gradient(
            135deg,
            #D4AF37 0%,
            #8B5CF6 50%,
            #00D4FF 100%
        );
}

* {
    box-sizing: border-box;
}

html {
    scroll-behavior: smooth;
}

body {
    margin: 0;
    min-height: 100vh;

    color: var(--shaheen-text);

    background:
        radial-gradient(
            circle at 10% 10%,
            rgba(139, 92, 246, 0.18),
            transparent 35%
        ),
        radial-gradient(
            circle at 90% 10%,
            rgba(0, 212, 255, 0.12),
            transparent 35%
        ),
        var(--shaheen-background);

    font-family:
        Inter,
        system-ui,
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        sans-serif;
}

.shaheen-card {
    background:
        linear-gradient(
            135deg,
            rgba(255, 255, 255, 0.08),
            rgba(255, 255, 255, 0.02)
        ),
        var(--shaheen-glass);

    border: 1px solid rgba(255, 255, 255, 0.1);

    border-radius: var(--shaheen-radius-lg);

    box-shadow: var(--shaheen-shadow);

    backdrop-filter: blur(18px);

    transition:
        transform 250ms ease,
        border-color 250ms ease,
        box-shadow 250ms ease;
}

.shaheen-card:hover {
    transform: translateY(-4px);

    border-color:
        rgba(212, 175, 55, 0.45);

    box-shadow:
        0 24px 80px rgba(0, 0, 0, 0.45),
        0 0 40px rgba(212, 175, 55, 0.08);
}

.shaheen-button {
    display: inline-flex;

    align-items: center;
    justify-content: center;

    min-height: 44px;

    padding:
        0.75rem
        1.25rem;

    border: 0;

    border-radius:
        var(--shaheen-radius-md);

    color: #ffffff;

    background:
        var(--shaheen-gradient);

    font-weight: 700;

    cursor: pointer;

    transition:
        transform 180ms ease,
        box-shadow 180ms ease,
        filter 180ms ease;
}

.shaheen-button:hover {
    transform: translateY(-2px);

    filter: brightness(1.08);

    box-shadow:
        0 12px 32px rgba(139, 92, 246, 0.28);
}

.shaheen-button:active {
    transform: translateY(0);
}

.shaheen-brand-gradient {
    background:
        var(--shaheen-gradient);

    -webkit-background-clip: text;
    background-clip: text;

    color: transparent;
}

.shaheen-glow {
    box-shadow:
        0 0 30px rgba(212, 175, 55, 0.18),
        0 0 80px rgba(139, 92, 246, 0.12);
}

.shaheen-logo {
    display: block;

    width: 56px;
    height: 56px;

    object-fit: contain;

    border-radius: 16px;

    box-shadow:
        0 0 30px rgba(212, 175, 55, 0.25);
}

.shaheen-animated-entry {
    animation:
        shaheen-entry 500ms ease both;
}

@keyframes shaheen-entry {
    from {
        opacity: 0;
        transform: translateY(12px);
    }

    to {
        opacity: 1;
        transform: translateY(0);
    }
}

@media (prefers-reduced-motion: reduce) {
    *,
    *::before,
    *::after {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
        scroll-behavior: auto !important;
    }
}
CSS

log "إنشاء manifest.json..."

cat > app/dashboard/static/manifest.json <<'JSON'
{
  "name": "SHAHEEN-YS",
  "short_name": "SHAHEEN-YS",
  "description": "SHAHEEN-YS AI Platform",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#070B14",
  "theme_color": "#D4AF37",
  "icons": [
    {
      "src": "/static/assets/branding/logo.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
JSON

log "إنشاء ملف الهوية البصرية JavaScript..."

cat > app/dashboard/static/js/shaheen-ys-brand.js <<'JS'
(function () {
    "use strict";

    const BRAND_NAME = "SHAHEEN-YS";

    document.title = BRAND_NAME;

    document.documentElement
        .setAttribute(
            "data-brand",
            "shaheen-ys"
        );

    window.SHAHEEN_YS_BRAND = Object.freeze({
        name: BRAND_NAME,
        theme: "premium-modern",
        defaultMode: "dark"
    });
})();
JS

log "إنشاء ملف CSS للهوية البصرية..."

cat > app/dashboard/static/assets/branding/brand.css <<'CSS'
@import url(
    "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap"
);

@import url(
    "../css/shaheen-ys-brand.css"
);
CSS

log "إنشاء ملف favicon..."

if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
from pathlib import Path
import shutil

source = Path(
    "app/dashboard/static/assets/branding/logo.png"
)

destination = Path(
    "app/dashboard/static/favicon.png"
)

if source.exists():
    shutil.copyfile(
        source,
        destination
    )

print(
    "Favicon source created successfully."
)
PY
else
    log "Python غير متاح. تم تجاوز إنشاء favicon."
fi

log "إنشاء ملف تعريف الهوية..."

cat > BRANDING.md <<'MD'
# SHAHEEN-YS Brand Identity

## Product Name

SHAHEEN-YS

## Visual Direction

Premium modern technology platform.

The visual language combines:

- Authority
- Luxury
- Modern technology
- Glassmorphism
- Motion
- Dark-first interfaces
- Gold accents
- Royal purple
- Electric cyan

## Primary Color

#D4AF37

## Secondary Color

#8B5CF6

## Accent Color

#00D4FF

## Background

#070B14

## Surface

#111827

## Text

#F8FAFC

## Muted Text

#94A3B8

## Typography

Inter.

## Interface

Dark mode is the primary experience.

Light mode remains supported.

## Product Name

SHAHEEN-YS
MD

log "فحص الأصول البصرية..."

for required_asset in \
    "$BRANDING_DIR/logo.png" \
    "$IMAGES_DIR/shaheen-ys-01.png" \
    "$IMAGES_DIR/shaheen-ys-02.png" \
    "$IMAGES_DIR/shaheen-ys-03.png" \
    "$IMAGES_DIR/shaheen-ys-04.png"
do
    if [[ ! -s "$required_asset" ]]; then
        fail "الأصل البصري غير موجود أو فارغ: $required_asset"
    fi
done

log "تم التحقق من جميع الصور."

log "البحث عن مراجع AstrBot المرئية..."

if command -v grep >/dev/null 2>&1; then
    grep -RIl \
        --exclude-dir=.git \
        --exclude-dir=__pycache__ \
        "AstrBot" \
        app \
        config \
        README.md \
        2>/dev/null \
        | while IFS= read -r file; do
            log "مراجعة: $file"
        done || true
fi

log "تم تطبيق الهوية البصرية لـ SHAHEEN-YS بنجاح."

log "الاسم النهائي: SHAHEEN-YS"

log "النمط: Premium Modern Dark-First"

log "الخطوة التالية: دمج ملفات CSS وBrand Assets داخل صفحات Dashboard."
