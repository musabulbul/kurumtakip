#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Hata: flutter komutu bulunamadı."
  exit 1
fi

if [[ -z "${NOTIFICATION_URL:-}" ]]; then
  echo "Hata: NOTIFICATION_URL zorunlu."
  echo "Ornek: NOTIFICATION_URL=https://whatsapp-automation-service-cwesfrwhhq-ew.a.run.app ./scripts/build_web.sh"
  exit 1
fi

build_target() {
  local target="$1"
  local output_dir="$2"

  echo ">> Building ${target} -> ${output_dir}"
  flutter build web \
    --release \
    --target="$target" \
    --dart-define=NOTIFICATION_URL="$NOTIFICATION_URL" \
    ${BOOKING_API_BASE_URL:+--dart-define=BOOKING_API_BASE_URL="$BOOKING_API_BASE_URL"}

  rm -rf "$output_dir"
  mkdir -p "$(dirname "$output_dir")"
  cp -R build/web "$output_dir"
}

build_target "lib/main.dart" "build/web_admin"
build_target "lib/main_booking.dart" "build/web_booking"

echo ">> Tamam: build/web_admin ve build/web_booking hazir."
