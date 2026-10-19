#!/usr/bin/env bash
# Run by the backend (GEONIX_AFTER_DOWNLOADS) shortly after downloads or
# playlist imports finish: export playlists for Navidrome, then rescan so the
# phone app sees new songs right away.
cd "$(dirname "$(readlink -f "$0")")"
python3 sync_playlists.py
python3 navidrome_rescan.py
