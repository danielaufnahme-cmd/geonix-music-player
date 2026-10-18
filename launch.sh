#!/usr/bin/env bash
# Desktop launcher for Music Player. Uses the prebuilt release
# binaries (build them with ./run.sh or see README), its own port and data
# folders, and stops the backend when the window closes.
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")"

export GEONIX_PORT=7802
export GEONIX_DATA_DIR="$HOME/.local/share/geonix-claude"
export GEONIX_MUSIC_DIR="$HOME/Music/Geonix-claude"
API="http://127.0.0.1:${GEONIX_PORT}"
LOG="$GEONIX_DATA_DIR/launch.log"
BACKEND_BIN=backend/target/release/geonix-backend
APP_BIN=app/build/linux/x64/release/bundle/geonix_music_player

mkdir -p "$GEONIX_DATA_DIR" "$GEONIX_MUSIC_DIR"
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') launch"

fail() {
  echo "ERROR: $1"
  notify-send -a "Music Player" -i dialog-error "Music Player failed to start" "$1 — see $LOG"
  exit 1
}

# YouTube changes often and old yt-dlp versions start failing (HTTP 403):
# update it in the background at most once a week. Takes effect next launch.
STAMP="$GEONIX_DATA_DIR/.yt-dlp-updated"
if [ -x worker/.venv/bin/pip ] && [ -z "$(find "$STAMP" -mtime -7 2>/dev/null)" ]; then
  (worker/.venv/bin/pip install -q --upgrade yt-dlp && touch "$STAMP" && echo "yt-dlp updated") &
fi

[ -x "$BACKEND_BIN" ] || fail "Backend not built. Run ./run.sh once."
[ -x "$APP_BIN" ] || fail "App not built. Run ./run.sh once."

BACKEND=""
if ! curl -sf "$API/api/health" >/dev/null; then
  "$BACKEND_BIN" &
  BACKEND=$!
  trap '[ -n "$BACKEND" ] && kill "$BACKEND" 2>/dev/null; wait "$BACKEND" 2>/dev/null' EXIT INT TERM
  for _ in $(seq 1 100); do
    curl -sf "$API/api/health" >/dev/null && break
    kill -0 "$BACKEND" 2>/dev/null || fail "Backend exited during startup."
    sleep 0.1
  done
  curl -sf "$API/api/health" >/dev/null || fail "Backend did not answer on port $GEONIX_PORT."
fi

"$APP_BIN"
echo "=== $(date '+%F %T') app closed"
