#!/usr/bin/env bash

set -Eeuo pipefail

============================================================

SHAHEEN-YS - PASH3

Arabic Localization & RTL Foundation

============================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_DIR="${PROJECT_ROOT}/config"
STATIC_DIR="${PROJECT_ROOT}/shaheen_ys/webui/static"
LOCALES_DIR="${PROJECT_ROOT}/shaheen_ys/webui/locales"
REPORT_DIR="${PROJECT_ROOT}/reports"

LOG_FILE="${PROJECT_ROOT}/pash3-arabic.log"
REPORT_FILE="${REPORT_DIR}/chinese-text-report.txt"

log() {
local message="$1"

printf '[%s] %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "${message}" | tee -a "${LOG_FILE}"

}

fail() {
log "ERROR: $1"
exit 1
}

require_command() {
local command_name="$1"

if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "الأداة المطلوبة غير مثبتة: ${command_name}"
fi

}

validate_project() {
if [[ ! -d "${PROJECT_ROOT}" ]]; then
fail "مجلد المشروع غير موجود."
fi

if [[ ! -d "${PROJECT_ROOT}/shaheen_ys" ]]; then
    fail "مجلد shaheen_ys غير موجود. نفذ PASH1 أولاً."
fi

}

prepare_directories() {
mkdir -p 
"${CONFIG_DIR}" 
"${STATIC_DIR}" 
"${LOCALES_DIR}" 
"${REPORT_DIR}"
}

create_arabic_locale() {
local locale_file="${LOCALES_DIR}/ar.json"

cat > "${locale_file}" << 'JSON'

{
"locale": "ar",
"language": "العربية",
"language_native": "العربية",
"direction": "rtl",
"text_direction": "rtl",
"date_format": "YYYY-MM-DD",
"time_format": "HH:mm:ss",
"messages": {
"app_name": "SHAHEEN-YS",
"welcome": "مرحباً بك في SHAHEEN-YS",
"dashboard": "لوحة التحكم",
"settings": "الإعدادات",
"plugins": "الإضافات",
"terminal": "الطرفية",
"github": "GitHub",
"login": "تسجيل الدخول",
"logout": "تسجيل الخروج",
"save": "حفظ",
"cancel": "إلغاء",
"close": "إغلاق",
"loading": "جارٍ التحميل...",
"success": "تمت العملية بنجاح",
"error": "حدث خطأ",
"not_found": "العنصر غير موجود",
"unauthorized": "غير مصرح",
"server_error": "خطأ داخلي في الخادم"
}
}
JSON

log "تم إنشاء ملف الترجمة العربية."

}

create_locale_config() {
local config_file="${CONFIG_DIR}/locale.yml"

cat > "${config_file}" << 'YAML'

default_locale: ar
fallback_locale: ar

supported_locales:

- ar

direction:
ar: rtl

language:
ar:
name: العربية
native_name: العربية
direction: rtl
YAML

log "تم إنشاء إعدادات اللغة العربية."

}

create_rtl_css() {
local rtl_file="${STATIC_DIR}/rtl.css"

cat > "${rtl_file}" << 'CSS'

/*

* SHAHEEN-YS RTL Foundation
  */

html {
direction: rtl;
}

body {
direction: rtl;
text-align: right;
}

input,
textarea,
select,
button {
font-family: inherit;
}

[dir="ltr"] {
direction: ltr;
text-align: left;
}

[dir="rtl"] {
direction: rtl;
text-align: right;
}

.shaheen-ys-layout {
direction: rtl;
}

.shaheen-ys-sidebar {
right: 0;
left: auto;
}

.shaheen-ys-content {
margin-right: 280px;
margin-left: 0;
}

@media (max-width: 768px) {
.shaheen-ys-content {
margin-right: 0;
}
}
CSS

log "تم إنشاء RTL CSS."

}

create_html_metadata() {
local metadata_file="${STATIC_DIR}/arabic-metadata.html"

cat > "${metadata_file}" << 'HTML'

<!-- SHAHEEN-YS Arabic WebUI Metadata --><meta
name="language"
content="ar"

«»

<meta
name="content-language"
content="ar"

«»

<meta
name="direction"
content="rtl"

«»

<meta
name="application-name"
content="SHAHEEN-YS"

«»

HTML

log "تم إنشاء Metadata عربية للواجهة."

}

create_language_settings() {
local settings_file="${CONFIG_DIR}/language-settings.yml"

cat > "${settings_file}" << 'YAML'

application:
name: SHAHEEN-YS
default_language: ar
default_direction: rtl

user_preferences:
allow_language_change: true
default_language: ar

webui:
html_lang: ar
html_dir: rtl

formatting:
decimal_separator: "."
thousands_separator: ","
YAML

log "تم إنشاء إعدادات اللغة الافتراضية."

}

scan_chinese_text() {
log "بدء فحص الملفات بحثاً عن النصوص الصينية..."

: > "${REPORT_FILE}"

if command -v rg >/dev/null 2>&1; then
    rg \
        --line-number \
        --hidden \
        --glob '!*.pyc' \
        --glob '!__pycache__/**' \
        --glob '!.git/**' \
        '[一-龯]|[ぁ-ゟ]|[ァ-ヿ]' \
        "${PROJECT_ROOT}" \
        > "${REPORT_FILE}" \
        || true
else
    grep \
        -RIn \
        --exclude-dir=.git \
        --exclude-dir=__pycache__ \
        --exclude='*.pyc' \
        -E '[一-龯]|[ぁ-ゟ]|[ァ-ヿ]' \
        "${PROJECT_ROOT}" \
        > "${REPORT_FILE}" \
        || true
fi

if [[ -s "${REPORT_FILE}" ]]; then
    log "تم العثور على نصوص آسيوية تحتاج مراجعة."
    log "التقرير: ${REPORT_FILE}"
else
    log "لم يتم العثور على نصوص صينية أو يابانية في الملفات المفحوصة."
fi

}

scan_language_references() {
local language_report="${REPORT_DIR}/language-reference-report.txt"

log "فحص مراجع اللغات القديمة..."

: > "${language_report}"

grep \
    -RIn \
    --exclude-dir=.git \
    --exclude-dir=__pycache__ \
    --exclude='*.pyc' \
    -E \
    'zh-CN|zh_CN|Chinese|中文|简体中文|繁體中文' \
    "${PROJECT_ROOT}" \
    > "${language_report}" \
    || true

if [[ -s "${language_report}" ]]; then
    log "تم العثور على مراجع للغة الصينية."
    log "التقرير: ${language_report}"
else
    log "لم يتم العثور على مراجع لغة صينية واضحة."
fi

}

create_localization_documentation() {
local documentation_file="${LOCALES_DIR}/README.md"

cat > "${documentation_file}" << 'MD'

SHAHEEN-YS Localization

اللغة الافتراضية للمشروع:

العربية

الإعدادات:

Locale: ar
Direction: RTL
HTML lang: ar

قواعد الترجمة

- لا يتم تعديل أسماء المتغيرات البرمجية عشوائياً.
- لا يتم ترجمة أسماء الدوال أو الكلاسات.
- لا يتم تعديل API identifiers.
- لا يتم استبدال النصوص باستخدام Search & Replace عشوائي.
- النصوص المرئية للمستخدم يجب أن تمر عبر نظام الترجمة.

اللغة الافتراضية

ar

MD

log "تم إنشاء توثيق نظام الترجمة."

}

create_language_environment_example() {
local env_file="${PROJECT_ROOT}/.env.example"

if [[ ! -f "${env_file}" ]]; then
    touch "${env_file}"
fi

if ! grep -q '^SHAHEEN_YS_LANGUAGE=' "${env_file}"; then
    printf '\nSHAHEEN_YS_LANGUAGE=ar\n' >> "${env_file}"
fi

if ! grep -q '^SHAHEEN_YS_LOCALE=' "${env_file}"; then
    printf 'SHAHEEN_YS_LOCALE=ar_JO\n' >> "${env_file}"
fi

if ! grep -q '^SHAHEEN_YS_DIRECTION=' "${env_file}"; then
    printf 'SHAHEEN_YS_DIRECTION=rtl\n' >> "${env_file}"
fi

log "تم تحديث .env.example."

}

show_summary() {
printf '\n'
log "=============================================="
log "تم تنفيذ PASH3 بنجاح."
log "=============================================="

printf '\n'
printf '🌐 اللغة الافتراضية: العربية\n'
printf '↔️ اتجاه الواجهة: RTL\n'
printf '📁 ملفات اللغة: %s\n' "${LOCALES_DIR}"
printf '📄 تقرير النصوص الآسيوية: %s\n' "${REPORT_FILE}"
printf '\n'

}

main() {
log "بدء PASH3: تهيئة اللغة العربية و RTL..."

require_command "grep"

validate_project
prepare_directories
create_arabic_locale
create_locale_config
create_rtl_css
create_html_metadata
create_language_settings
scan_chinese_text
scan_language_references
create_localization_documentation
create_language_environment_example
show_summary

}

main "$@"
