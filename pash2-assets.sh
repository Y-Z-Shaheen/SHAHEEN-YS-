#!/usr/bin/env bash

set -Eeuo pipefail

============================================================

SHAHEEN-YS - PASH2

Branding & WebUI Assets Manager

============================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ASSETS_DIR="${PROJECT_ROOT}/shaheen_ys/webui/static/assets/branding"
STATIC_DIR="${PROJECT_ROOT}/shaheen_ys/webui/static"
TEMP_DIR="${PROJECT_ROOT}/.shaheen-ys-assets-tmp"

LOG_FILE="${PROJECT_ROOT}/pash2-assets.log"

declare -a IMAGE_URLS=(
"https://i.postimg.cc/xjtDL1M6/266cbd15b97755dbe14b638d3de7cf96.jpg"
"https://i.postimg.cc/7Pm8SZ0Q/Picsart-26-07-19-04-17-59-511.png"
"https://i.postimg.cc/9XJ5yQZY/Picsart-26-07-21-04-44-19-389.png"
"https://i.postimg.cc/jqZ0ySP3/Picsart-26-07-22-20-23-50-117.png"
"https://i.postimg.cc/kMf3WgKp/Picsart-26-07-22-20-29-24-877.png"
)

declare -a IMAGE_NAMES=(
"shaheen-ys-logo-1.jpg"
"shaheen-ys-logo-2.png"
"shaheen-ys-logo-3.png"
"shaheen-ys-logo-4.png"
"shaheen-ys-logo-5.png"
)

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

cleanup() {
if [[ -d "${TEMP_DIR}" ]]; then
rm -rf "${TEMP_DIR}"
fi
}

trap cleanup EXIT

require_command() {
local command_name="$1"

if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "الأداة المطلوبة غير مثبتة: ${command_name}"
fi

}

validate_project_root() {
if [[ ! -d "${PROJECT_ROOT}" ]]; then
fail "مجلد المشروع غير موجود: ${PROJECT_ROOT}"
fi

if [[ ! -d "${PROJECT_ROOT}/shaheen_ys" ]]; then
    fail "مجلد shaheen_ys غير موجود. شغّل PASH1 أولاً."
fi

}

prepare_directories() {
log "إنشاء مجلدات أصول الواجهة..."

mkdir -p \
    "${ASSETS_DIR}" \
    "${STATIC_DIR}" \
    "${TEMP_DIR}"

}

download_asset() {
local image_url="$1"
local output_file="$2"

log "جاري تنزيل: ${output_file}"

curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 120 \
    --user-agent "SHAHEEN-YS-Asset-Manager/1.0" \
    "${image_url}" \
    --output "${output_file}"

}

validate_file() {
local file_path="$1"

if [[ ! -f "${file_path}" ]]; then
    fail "لم يتم إنشاء الملف: ${file_path}"
fi

if [[ ! -s "${file_path}" ]]; then
    fail "الملف فارغ: ${file_path}"
fi

}

detect_file_type() {
local file_path="$1"

if command -v file >/dev/null 2>&1; then
    file --brief --mime-type "${file_path}"
else
    printf 'unknown\n'
fi

}

validate_image_type() {
local file_path="$1"
local mime_type

mime_type="$(detect_file_type "${file_path}")"

case "${mime_type}" in
    image/jpeg|image/png|image/webp)
        log "نوع الصورة صحيح: ${mime_type}"
        ;;
    *)
        fail "نوع الملف غير مدعوم أو غير صالح: ${file_path} (${mime_type})"
        ;;
esac

}

download_all_assets() {
local index

for index in "${!IMAGE_URLS[@]}"; do
    local image_url="${IMAGE_URLS[$index]}"
    local image_name="${IMAGE_NAMES[$index]}"
    local output_path="${ASSETS_DIR}/${image_name}"

    download_asset \
        "${image_url}" \
        "${output_path}"

    validate_file "${output_path}"
    validate_image_type "${output_path}"
done

}

create_primary_logo() {
local source_file="${ASSETS_DIR}/shaheen-ys-logo-2.png"
local target_file="${STATIC_DIR}/logo.png"

if [[ ! -f "${source_file}" ]]; then
    log "تحذير: الصورة الأساسية غير موجودة، سيتم استخدام أول صورة متاحة."

    source_file="${ASSETS_DIR}/shaheen-ys-logo-1.jpg"
fi

cp "${source_file}" "${target_file}"

validate_file "${target_file}"

log "تم إنشاء الشعار الأساسي: ${target_file}"

}

create_branding_manifest() {
local manifest_file="${ASSETS_DIR}/manifest.json"

cat > "${manifest_file}" << 'JSON'

{
"project": "SHAHEEN-YS",
"brand": "SHAHEEN-YS",
"language": "ar",
"locale": "ar_JO",
"direction": "rtl",
"primary_logo": "logo.png",
"assets": [
"shaheen-ys-logo-1.jpg",
"shaheen-ys-logo-2.png",
"shaheen-ys-logo-3.png",
"shaheen-ys-logo-4.png",
"shaheen-ys-logo-5.png"
]
}
JSON

log "تم إنشاء manifest.json."

}

create_branding_css() {
local css_file="${STATIC_DIR}/branding.css"

cat > "${css_file}" << 'CSS'

:root {
--shaheen-ys-brand-name: "SHAHEEN-YS";
}

.shaheen-ys-logo {
display: block;
max-width: 220px;
height: auto;
object-fit: contain;
}

.shaheen-ys-brand {
direction: rtl;
text-align: right;
}

.shaheen-ys-brand-title {
font-weight: 700;
letter-spacing: 0.02em;
}
CSS

log "تم إنشاء ملف branding.css."

}

create_favicon_fallback() {
local favicon_path="${STATIC_DIR}/favicon.ico"

if [[ -f "${favicon_path}" ]]; then
    log "favicon.ico موجود مسبقاً، لن يتم استبداله."
    return
fi

if command -v convert >/dev/null 2>&1; then
    convert \
        "${STATIC_DIR}/logo.png" \
        -resize 64x64 \
        "${favicon_path}"

    log "تم إنشاء favicon.ico باستخدام ImageMagick."
    return
fi

log "تحذير: ImageMagick غير مثبت. سيتم الاحتفاظ بالـ logo.png بدون إنشاء favicon.ico."

}

create_assets_readme() {
local readme_file="${ASSETS_DIR}/README.md"

cat > "${readme_file}" << 'MD'

SHAHEEN-YS Branding Assets

هذا المجلد يحتوي على أصول الهوية البصرية المحلية لمشروع SHAHEEN-YS.

الملفات

- "shaheen-ys-logo-1.jpg"
- "shaheen-ys-logo-2.png"
- "shaheen-ys-logo-3.png"
- "shaheen-ys-logo-4.png"
- "shaheen-ys-logo-5.png"
- "manifest.json"

ملاحظات أمنية

لا يعتمد التطبيق أثناء التشغيل على روابط الصور الخارجية.

يتم حفظ الأصول محلياً داخل المشروع لتقليل الاعتماد على خدمات خارجية.

قبل إعادة توزيع الصور تجارياً أو استخدامها في نسخة عامة من المشروع، يجب التأكد من امتلاك حقوق استخدامها.
MD

log "تم إنشاء توثيق أصول الهوية البصرية."

}

show_summary() {
log "=============================================="
log "تم تنفيذ PASH2 بنجاح."
log "=============================================="

printf '\n'
printf '📁 مجلد الأصول:\n%s\n\n' "${ASSETS_DIR}"

printf '🖼️ الملفات المنشأة:\n'

find "${ASSETS_DIR}" \
    -maxdepth 1 \
    -type f \
    -printf ' - %f\n' \
    2>/dev/null || true

printf '\n'
printf '🌐 الشعار الأساسي:\n%s\n' "${STATIC_DIR}/logo.png"

printf '\n'
printf '⚠️ لا تقم برفع ملف .env أو أي مفاتيح سرية إلى GitHub.\n'

}

main() {
log "بدء PASH2: إدارة أصول وهوية SHAHEEN-YS..."

require_command "curl"

validate_project_root
prepare_directories
download_all_assets
create_primary_logo
create_branding_manifest
create_branding_css
create_favicon_fallback
create_assets_readme
show_summary

}

main "$@"
