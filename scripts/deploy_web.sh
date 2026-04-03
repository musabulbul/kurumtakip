#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v firebase >/dev/null 2>&1; then
  echo "Hata: firebase CLI bulunamadi."
  exit 1
fi

./scripts/build_web.sh

echo ">> Firebase hosting deploy basliyor (admin + booking)..."
firebase deploy --only hosting:admin,hosting:booking

echo ">> Deploy tamamlandi."
