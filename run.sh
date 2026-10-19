#!/usr/bin/env bash
# Build and start Geonix Music Player: Python worker venv, Rust backend,
# Flutter desktop app (Linux or macOS; Windows: launch.ps1). Closing the
# app stops the backend (and its worker).
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(uname -s)" = "Darwin" ]; then TARGET=macos; else TARGET=linux; fi

PORT="${GEONIX_PORT:-7878}"
API="http://127.0.0.1:${PORT}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing '$1' — run ./setup.sh --check, or see README.md (Getting started)." >&2; exit 1; }; }
for tool in python3 cargo flutter ffmpeg curl; do need "$tool"; done

if curl -sf "${API}/api/health" >/dev/null 2>&1; then
  echo "Something is already answering on port ${PORT}. Stop it or run: GEONIX_PORT=7979 ./run.sh" >&2
  exit 1
fi

echo "==> Python worker"
[ -x worker/.venv/bin/python ] || python3 -m venv worker/.venv
worker/.venv/bin/pip install -q --upgrade -r worker/requirements.txt

echo "==> Rust backend"
(cd backend && cargo build --release)

echo "==> Flutter app"
(cd app && flutter pub get >/dev/null && flutter build "${TARGET}" --release --dart-define=GEONIX_API="${API}")

echo "==> Starting backend on ${API}"
GEONIX_PORT="${PORT}" backend/target/release/geonix-backend &
BACKEND=$!
trap 'kill "${BACKEND}" 2>/dev/null || true' EXIT INT TERM

for _ in $(seq 1 50); do
  curl -sf "${API}/api/health" >/dev/null 2>&1 && break
  kill -0 "${BACKEND}" 2>/dev/null || { echo "Backend failed to start." >&2; exit 1; }
  sleep 0.2
done

echo "==> Opening Geonix"
if [ "${TARGET}" = macos ]; then
  APP_BIN=""
  for exe in app/build/macos/Build/Products/Release/*.app/Contents/MacOS/*; do
    [ -x "$exe" ] && { APP_BIN="$exe"; break; }
  done
  [ -n "${APP_BIN}" ] || { echo "macOS app bundle not found." >&2; exit 1; }
  "${APP_BIN}"
else
  app/build/linux/x64/release/bundle/geonix_music_player
fi
