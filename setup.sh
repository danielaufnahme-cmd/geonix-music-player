#!/usr/bin/env bash
# One-command setup / update for Linux and macOS (Windows: setup.ps1).
# 1. checks the prerequisites and prints the install command for your system,
# 2. creates the Python worker venv, builds the release backend and the
#    release app (wired to the launcher's port),
# 3. on Linux optionally adds a menu entry that runs ./launch.sh.
#
# Usage: ./setup.sh [--desktop-entry | --no-desktop-entry] [--check]
#   --desktop-entry     add the menu entry without asking
#   --no-desktop-entry  don't add it and don't ask
#   --check             only check the prerequisites, build nothing
# Without a flag it asks (y/N) when run in a terminal and skips otherwise.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(pwd -P)"

DESKTOP=ask
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --desktop-entry) DESKTOP=yes ;;
    --no-desktop-entry) DESKTOP=no ;;
    --check) CHECK_ONLY=1 ;;
    -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see ./setup.sh --help)" >&2; exit 2 ;;
  esac
done

# shellcheck source=tools/geonix_env.sh
. tools/geonix_env.sh
geonix_load_config
PORT="${GEONIX_PORT:-7802}"

# --- Which system is this? -------------------------------------------------
OS="$(uname -s)"
DISTRO=other
if [ "$OS" = "Darwin" ]; then
  DISTRO=macos
elif [ -r /etc/os-release ]; then
  IDS="$(. /etc/os-release; echo "${ID:-} ${ID_LIKE:-}")"
  case " $IDS " in
    *" arch "* | *" cachyos "* | *" manjaro "* | *" endeavouros "*) DISTRO=arch ;;
    *" fedora "*) DISTRO=fedora ;;
    *" debian "* | *" ubuntu "*) DISTRO=debian ;;
  esac
fi

# --- Prerequisites -----------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

PYTHON=""
for candidate in python3 python3.14 python3.13 python3.12 python3.11; do
  if have "$candidate" && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    PYTHON="$(command -v "$candidate")"
    break
  fi
done

MISSING=()
have cargo || MISSING+=(rust)
have flutter || MISSING+=(flutter)
if [ -z "$PYTHON" ]; then
  MISSING+=(python)
elif ! [ -x worker/.venv/bin/python ] && ! "$PYTHON" -c 'import venv, ensurepip' 2>/dev/null; then
  MISSING+=(python-venv)
fi
have ffmpeg || MISSING+=(ffmpeg)
have curl || MISSING+=(curl)
if [ "$OS" = "Darwin" ]; then
  xcodebuild -version >/dev/null 2>&1 || MISSING+=(xcode)
  have pod || MISSING+=(cocoapods)
else
  have clang++ || MISSING+=(clang)
  have cmake || MISSING+=(cmake)
  have ninja || MISSING+=(ninja)
  if have pkg-config; then
    pkg-config --exists gtk+-3.0 || MISSING+=(gtk3)
    pkg-config --exists mpv || MISSING+=(libmpv)
  else
    MISSING+=(pkg-config gtk3 libmpv)
  fi
fi

# Package names per item and system ("" = not installed with the package manager).
package_for() {
  case "$DISTRO:$1" in
    arch:rust) echo rustup ;;
    arch:python | arch:python-venv) echo python ;;
    arch:clang) echo "clang base-devel" ;;
    arch:pkg-config) echo pkgconf ;;
    arch:libmpv) echo mpv ;;
    arch:ffmpeg | arch:curl | arch:cmake | arch:ninja | arch:gtk3) echo "$1" ;;
    debian:python) echo "python3 python3-venv" ;;
    debian:python-venv) echo python3-venv ;;
    debian:clang) echo "clang build-essential" ;;
    debian:ninja) echo ninja-build ;;
    debian:gtk3) echo libgtk-3-dev ;;
    debian:libmpv) echo "libmpv-dev mpv" ;;
    debian:ffmpeg | debian:curl | debian:cmake | debian:pkg-config) echo "$1" ;;
    fedora:python | fedora:python-venv) echo python3 ;;
    fedora:clang) echo "clang gcc-c++" ;;
    fedora:ninja) echo ninja-build ;;
    fedora:pkg-config) echo pkgconf-pkg-config ;;
    fedora:gtk3) echo gtk3-devel ;;
    fedora:libmpv) echo "mpv mpv-devel" ;;
    fedora:ffmpeg) echo ffmpeg-free ;;
    fedora:curl | fedora:cmake) echo "$1" ;;
    macos:python | macos:python-venv) echo python@3.12 ;;
    macos:ffmpeg | macos:cocoapods | macos:curl) echo "$1" ;;
  esac
}

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "Missing: ${MISSING[*]}" >&2
  echo >&2
  PKGS=""
  for item in "${MISSING[@]}"; do
    p="$(package_for "$item")"
    [ -n "$p" ] && PKGS="$PKGS $p"
  done
  PKGS="${PKGS# }"
  if [ -n "$PKGS" ]; then
    echo "Install with:" >&2
    case "$DISTRO" in
      arch) echo "  sudo pacman -S --needed $PKGS" >&2 ;;
      debian) echo "  sudo apt update && sudo apt install $PKGS" >&2 ;;
      fedora) echo "  sudo dnf install $PKGS" >&2 ;;
      macos) echo "  brew install $PKGS" >&2 ;;
    esac
  fi
  for item in "${MISSING[@]}"; do
    case "$DISTRO:$item" in
      arch:rust) echo "  rustup default stable" >&2 ;;
      *:rust) echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh   # Rust (rustup), then open a new terminal" >&2 ;;
      arch:flutter) echo "  yay -S flutter-bin   # AUR (any helper), or see https://docs.flutter.dev/get-started/install/linux/desktop" >&2 ;;
      debian:flutter) echo "  sudo snap install flutter --classic   # or see https://docs.flutter.dev/get-started/install/linux/desktop" >&2 ;;
      macos:flutter) echo "  brew install --cask flutter" >&2 ;;
      *:flutter) echo "  Flutter: https://docs.flutter.dev/get-started/install/linux/desktop" >&2 ;;
      macos:xcode) echo "  Xcode: install it from the App Store, then: sudo xcodebuild -runFirstLaunch && sudo xcodebuild -license accept" >&2 ;;
    esac
  done
  if [ "$DISTRO" = other ]; then
    echo "Install these with your package manager (development packages for gtk3 and libmpv)." >&2
  fi
  echo >&2
  echo "Then run ./setup.sh again. Details: README.md, \"Getting started\"." >&2
  exit 1
fi
echo "==> Prerequisites OK (python: $PYTHON)"
[ "$CHECK_ONLY" = 1 ] && exit 0

# --- Build -------------------------------------------------------------------
echo "==> Python worker (worker/.venv)"
[ -x worker/.venv/bin/python ] || "$PYTHON" -m venv worker/.venv
worker/.venv/bin/python -m pip install -q --upgrade pip
worker/.venv/bin/python -m pip install -q --upgrade -r worker/requirements.txt

echo "==> Rust backend (cargo build --release)"
(cd backend && cargo build --release)

echo "==> Flutter app (port $PORT)"
if [ "$OS" = "Darwin" ]; then TARGET=macos; else TARGET=linux; fi
(cd app && flutter pub get && flutter build "$TARGET" --release --dart-define=GEONIX_API="http://127.0.0.1:${PORT}")

# --- Menu entry (Linux) ------------------------------------------------------
if [ "$OS" = "Linux" ]; then
  if [ "$DESKTOP" = ask ]; then
    DESKTOP=no
    if [ -t 0 ] && [ -t 1 ]; then
      read -r -p "Add a \"Geonix Music Player\" menu entry? [y/N] " answer || answer=""
      case "$answer" in [yY]*) DESKTOP=yes ;; esac
    fi
  fi
  if [ "$DESKTOP" = yes ]; then
    APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    mkdir -p "$APPS"
    cat >"$APPS/geonix.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Geonix Music Player
Comment=Search, download and play music
Exec="$REPO/launch.sh"
Icon=multimedia-audio-player
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=com.geonix.geonix_music_player
EOF
    echo "==> Menu entry: $APPS/geonix.desktop"
  fi
fi

echo
echo "Done. Start it with ./launch.sh"
if [ "$OS" = "Darwin" ]; then
  echo "(The app bundle is in app/build/macos/Build/Products/Release/; start it"
  echo " through ./launch.sh so the backend runs too.)"
fi
