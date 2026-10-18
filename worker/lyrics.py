"""Song lyrics: YouTube Music first, then LRCLIB (https://lrclib.net).

Result shape (always the same keys):
    {"synced": bool, "lines": [{"time_ms": int | None, "text": str}], "source": str | None,
     "transient": bool (only when nothing was found)}
`lines` is empty when nothing was found. Synced lines are sorted by time.
"""

from __future__ import annotations

import json
import logging
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

log = logging.getLogger("geonix.lyrics")

LRCLIB = "https://lrclib.net/api"
_USER_AGENT = "Geonix Music Player (https://github.com/geonix)"

_LRC_TIME = re.compile(r"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]")
# "(Slowed)", "[sped up + reverb]", "- Nightcore", "(Hardstyle Ultra Slowed)" ...
_EDIT_MARKERS = re.compile(
    r"\s*[\(\[][^\)\]]*\b(slowed|sped\s*up|speed\s*up|nightcore|reverb|8d|bass\s*boosted|pitched)\b[^\)\]]*[\)\]]"
    r"|\s*-\s*(slowed|sped\s*up|nightcore)\b.*$",
    re.IGNORECASE,
)
_EXTRA = re.compile(r"\s*[\(\[](official|lyrics?|audio|video|visuali[sz]er|explicit|remaster(ed)?)[^\)\]]*[\)\]]", re.I)


def empty(transient: bool = False) -> dict[str, Any]:
    """No lyrics. `transient` means a source failed (network), so don't cache the miss."""
    return {"synced": False, "lines": [], "source": None, "transient": transient}


def parse_lrc(text: str) -> list[dict[str, Any]]:
    """Parse LRC text. Lines can carry several time tags: "[00:12.30][01:40.00]Hey"."""
    lines: list[dict[str, Any]] = []
    for raw in text.splitlines():
        stamps = list(_LRC_TIME.finditer(raw))
        if not stamps:
            continue
        words = raw[stamps[-1].end():].strip()
        for m in stamps:
            minutes, seconds, frac = int(m.group(1)), int(m.group(2)), m.group(3) or "0"
            ms = int(frac.ljust(3, "0")[:3])
            lines.append({"time_ms": (minutes * 60 + seconds) * 1000 + ms, "text": words})
    lines.sort(key=lambda line: line["time_ms"])
    return lines


def plain_lines(text: str) -> list[dict[str, Any]]:
    return [{"time_ms": None, "text": line.strip()} for line in text.strip().splitlines()]


def clean_title(title: str) -> str:
    """Strip edit markers like "(Ultra Slowed)" so the original song can be looked up."""
    cleaned = _EXTRA.sub("", _EDIT_MARKERS.sub("", title)).strip(" -")
    return cleaned or title


def is_edit(title: str) -> bool:
    """True for slowed / sped-up / nightcore edits whose timing differs from the original."""
    return bool(_EDIT_MARKERS.search(title))


def first_artist(artist: str) -> str:
    return re.split(r",|&| feat\.? | ft\.? | x ", artist, maxsplit=1, flags=re.I)[0].strip()


def scale_lines(lines: list[dict[str, Any]], factor: float) -> list[dict[str, Any]]:
    """Stretch timestamps (slowed edits play the same lyrics over a longer time)."""
    return [{"time_ms": round(line["time_ms"] * factor), "text": line["text"]} for line in lines]


# ---------------------------------------------------------------- sources


def from_youtube_music(video_id: str) -> dict[str, Any] | None:
    import ytm

    yt = ytm.client()
    watch = yt.get_watch_playlist(videoId=video_id, limit=1)
    browse_id = watch.get("lyrics") if isinstance(watch, dict) else None
    if not browse_id:
        return None
    data = yt.get_lyrics(browse_id, timestamps=True)
    if not data or not data.get("lyrics"):
        return None
    source = re.sub(r"^\s*Source:\s*", "", str(data.get("source") or "")).strip() or "YouTube Music"
    if data.get("hasTimestamps"):
        lines = [
            {"time_ms": int(getattr(line, "start_time", 0)), "text": str(getattr(line, "text", "")).strip()}
            for line in data["lyrics"]
        ]
        return {"synced": True, "lines": sorted(lines, key=lambda line: line["time_ms"]), "source": source}
    return {"synced": False, "lines": plain_lines(str(data["lyrics"])), "source": source}


def _get_json(url: str, timeout: float = 12) -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 - fixed https host
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code >= 500 and attempt == 1:
                time.sleep(1.5)
                continue
            raise
    return None


def pick_lrclib(candidates: list[dict[str, Any]], duration_sec: int) -> dict[str, Any] | None:
    """Best LRCLIB search hit: synced first, then closest duration."""
    usable = [c for c in candidates if isinstance(c, dict) and (c.get("syncedLyrics") or c.get("plainLyrics"))]
    if not usable:
        return None

    def rank(c: dict[str, Any]) -> tuple[int, float]:
        diff = abs(float(c.get("duration") or 0) - duration_sec) if duration_sec else 0.0
        return (0 if c.get("syncedLyrics") else 1, diff)

    return min(usable, key=rank)


def from_lrclib(title: str, artist: str, duration_sec: int) -> dict[str, Any] | None:
    edit = is_edit(title)
    track = clean_title(title)
    who = first_artist(artist)
    hit: dict[str, Any] | None = None
    if not edit and duration_sec:
        query = urllib.parse.urlencode({"track_name": track, "artist_name": who, "duration": duration_sec})
        try:
            hit = _get_json(f"{LRCLIB}/get?{query}")
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                raise
    if not hit:
        query = urllib.parse.urlencode({"track_name": track, "artist_name": who})
        results = _get_json(f"{LRCLIB}/search?{query}")
        if not results:
            results = _get_json(f"{LRCLIB}/search?{urllib.parse.urlencode({'q': f'{track} {who}'})}")
        hit = pick_lrclib(results if isinstance(results, list) else [], duration_sec)
    if not hit or hit.get("instrumental"):
        return None

    synced = parse_lrc(hit.get("syncedLyrics") or "")
    if synced:
        source = "LRCLIB"
        original = float(hit.get("duration") or 0)
        if original > 0 and duration_sec > 0:
            factor = duration_sec / original
            if edit and 0.5 <= factor <= 2.0 and abs(factor - 1) > 0.03:
                synced = scale_lines(synced, factor)
                source = "LRCLIB (timed to this edit)"
            elif abs(factor - 1) > 0.1:
                # A different cut of the song: timestamps would be misleading.
                synced = []
        if synced:
            return {"synced": True, "lines": synced, "source": source}
    if hit.get("plainLyrics"):
        return {"synced": False, "lines": plain_lines(hit["plainLyrics"]), "source": "LRCLIB"}
    return None


def lyrics(video_id: str, title: str, artist: str, duration_sec: int) -> dict[str, Any]:
    """Synced lyrics when any source has them, otherwise plain, otherwise empty."""
    plain: dict[str, Any] | None = None
    failed = False
    for name, fetch in (
        ("youtube music", lambda: from_youtube_music(video_id)),
        ("lrclib", lambda: from_lrclib(title, artist, duration_sec) if title else None),
    ):
        try:
            found = fetch()
        except Exception as exc:  # noqa: BLE001 - one source failing must not hide the other
            log.warning("lyrics from %s failed for %s: %s", name, video_id, exc)
            failed = True
            continue
        if found and found["lines"]:
            if found["synced"]:
                return found
            plain = plain or found
    return plain or empty(transient=failed)
