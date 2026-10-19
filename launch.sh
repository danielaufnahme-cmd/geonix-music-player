#!/usr/bin/env bash
# Desktop launcher for Music Player (Linux and macOS). Uses the prebuilt
# release binaries (build them once with ./setup.sh), its own port and data
# folders, and stops the backend when the window closes.
# Settings: environment variables, else ~/.config/geonix/geonix.env (see
# README, Configuration), else the defaults below. Windows: launch.ps1.
set -uo pipefail

# Follow symlinks to find the repo (no `readlink -f`: macOS doesn't have it).
SELF="$0"
while [ -L "$SELF" ]; do
  LINK="$(readlink "$SELF")"
  case "$LINK" in
    /*) SELF="$LINK" ;;
    *) SELF="$(dirname "$SELF")/$LINK" ;;
  esac
done
cd "$(dirname "$SELF")" || exit 1
# shellcheck source=tools/geonix_env.sh
. tools/geonix_env.sh
geonix_load_config

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  DEFAULT_DATA="$HOME/Library/Application Support/Geonix"
  DEFAULT_MUSIC="$HOME/Music/Geonix"
else
  DEFAULT_DATA="$HOME/.local/share/geonix"
  DEFAULT_MUSIC="$HOME/Music/Geonix"
fi
export GEONIX_PORT="${GEONIX_PORT:-7802}"
export GEONIX_DATA_DIR="${GEONIX_DATA_DIR:-$DEFAULT_DATA}"
export GEONIX_MUSIC_DIR="${GEONIX_MUSIC_DIR:-$DEFAULT_MUSIC}"
API="http://127.0.0.1:${GEONIX_PORT}"
LOG="$GEONIX_DATA_DIR/launch.log"
BACKEND_BIN=backend/target/release/geonix-backend

if [ "$OS" = "Darwin" ]; then
  APP_BIN=""
  for bundle in app/build/macos/Build/Products/Release/*.app; do
    for exe in "$bundle"/Contents/MacOS/*; do
      [ -x "$exe" ] && { APP_BIN="$exe"; break 2; }
    done
  done
else
  APP_BIN=app/build/linux/x64/release/bundle/geonix_music_player
fi

# GEONIX_LAUNCH_DRY_RUN=1: only print what would be started (for testing);
# creates no folders and writes no log.
if [ -n "${GEONIX_LAUNCH_DRY_RUN:-}" ]; then
  echo "dry run: backend=$BACKEND_BIN app=$APP_BIN api=$API data=$GEONIX_DATA_DIR music=$GEONIX_MUSIC_DIR after_downloads=${GEONIX_AFTER_DOWNLOADS:-}"
  exit 0
fi

mkdir -p "$GEONIX_DATA_DIR" "$GEONIX_MUSIC_DIR"
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') launch"

notify_error() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Music Player" -i dialog-error "Music Player failed to start" "$1" || true
  elif [ "$OS" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
    osascript -e 'on run argv' \
      -e 'display notification (item 1 of argv) with title "Music Player failed to start"' \
      -e 'end run' "$1" || true
  fi
}

fail() {
  echo "ERROR: $1"
  notify_error "$1 — see $LOG"
  exit 1
}

# YouTube changes often and old yt-dlp versions start failing (HTTP 403):
# update it in the background at most once a week. Takes effect next launch.
STAMP="$GEONIX_DATA_DIR/.yt-dlp-updated"
if [ -x worker/.venv/bin/pip ] && [ -z "$(find "$STAMP" -mtime -7 2>/dev/null)" ]; then
  (worker/.venv/bin/pip install -q --upgrade yt-dlp && touch "$STAMP" && echo "yt-dlp updated") &
fi

[ -x "$BACKEND_BIN" ] || fail "Backend not built. Run ./setup.sh once."
[ -n "$APP_BIN" ] && [ -x "$APP_BIN" ] || fail "App not built. Run ./setup.sh once."

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
