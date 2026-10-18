"""YouTube Music lookups: search, playlist contents, related songs, stream URLs.

Every function returns tracks in the shared track shape:
    {"video_id", "title", "artist", "album", "duration_sec", "thumbnail_url",
     "file_path": None, "downloaded": False}
"""

from __future__ import annotations

import logging
import re
import threading
from typing import Any
from urllib.parse import parse_qs, urlparse

log = logging.getLogger("geonix.ytm")

# Song-like video types. User uploads (UGC) and podcast episodes are not music.
MUSIC_VIDEO_TYPES = {"MUSIC_VIDEO_TYPE_ATV", "MUSIC_VIDEO_TYPE_OMV", "MUSIC_VIDEO_TYPE_OFFICIAL_SOURCE_MUSIC"}

_client: Any = None
_client_lock = threading.Lock()


def client() -> Any:
    """Shared unauthenticated YTMusic client (created lazily, thread-safe)."""
    global _client
    with _client_lock:
        if _client is None:
            from ytmusicapi import YTMusic

            _client = YTMusic()
        return _client


def parse_duration(value: Any) -> int:
    """'3:25' / '1:02:03' / 205 -> seconds. Unknown -> 0."""
    if isinstance(value, (int, float)):
        return max(int(value), 0)
    if not isinstance(value, str) or not value.strip():
        return 0
    total = 0
    try:
        for part in value.strip().split(":"):
            total = total * 60 + int(part)
    except ValueError:
        return 0
    return total


_SIZE_RE = re.compile(r"=w\d+-h\d+")


def best_thumbnail(thumbnails: Any) -> str:
    """Largest thumbnail URL, upscaled to 544px for googleusercontent images."""
    if not isinstance(thumbnails, list) or not thumbnails:
        return ""
    best = max(
        (t for t in thumbnails if isinstance(t, dict) and t.get("url")),
        key=lambda t: (t.get("width") or 0) * (t.get("height") or 0),
        default=None,
    )
    if best is None:
        return ""
    url: str = best["url"]
    if "googleusercontent.com" in url and _SIZE_RE.search(url):
        url = _SIZE_RE.sub("=w544-h544", url)
    return url


def join_artists(artists: Any) -> str:
    if isinstance(artists, list):
        names = [a.get("name", "") for a in artists if isinstance(a, dict) and a.get("name")]
        return ", ".join(names)
    if isinstance(artists, str):
        return artists
    return ""


def normalize_track(item: dict[str, Any]) -> dict[str, Any] | None:
    """Convert any ytmusicapi track-ish dict into the shared track shape."""
    video_id = item.get("videoId")
    title = item.get("title")
    if not video_id or not title:
        return None
    album = item.get("album")
    album_name = album.get("name", "") if isinstance(album, dict) else (album or "")
    duration = item.get("duration_seconds") or item.get("duration") or item.get("length")
    return {
        "video_id": video_id,
        "title": title,
        "artist": join_artists(item.get("artists")) or item.get("author") or "Unknown artist",
        "album": album_name or "",
        "duration_sec": parse_duration(duration),
        "thumbnail_url": best_thumbnail(item.get("thumbnails") or item.get("thumbnail")),
        "file_path": None,
        "downloaded": False,
    }


def is_music(item: dict[str, Any]) -> bool:
    video_type = item.get("videoType")
    return video_type is None or video_type in MUSIC_VIDEO_TYPES


def search(query: str, limit: int = 20) -> list[dict[str, Any]]:
    """Songs only — videos, podcasts and episodes are filtered out."""
    results = client().search(query, filter="songs", limit=limit)
    tracks: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in results:
        if item.get("resultType") not in (None, "song") or not is_music(item):
            continue
        track = normalize_track(item)
        if track and track["video_id"] not in seen:
            seen.add(track["video_id"])
            tracks.append(track)
    return tracks[:limit]


def extract_playlist_id(url: str) -> str:
    """Pull the `list=` id out of a YouTube / YouTube Music URL."""
    parsed = urlparse(url.strip())
    ids = parse_qs(parsed.query).get("list")
    if not ids or not ids[0]:
        raise ValueError("That link has no playlist id (list=...)")
    playlist_id = ids[0]
    if not re.fullmatch(r"[A-Za-z0-9_-]+", playlist_id):
        raise ValueError("Invalid playlist id in link")
    return playlist_id


def playlist_info(url: str) -> dict[str, Any]:
    """Title and songs (in order) of a playlist."""
    playlist_id = extract_playlist_id(url)
    try:
        data = client().get_playlist(playlist_id, limit=None)
        title = data.get("title") or "Imported playlist"
        items = data.get("tracks") or []
    except Exception as exc:  # noqa: BLE001 - fall back to yt-dlp for odd playlist types
        log.info("ytmusicapi could not read playlist %s (%s); trying yt-dlp", playlist_id, exc)
        title, items = _playlist_via_ytdlp(playlist_id)
    tracks: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in items:
        if item.get("isAvailable") is False:
            continue
        track = normalize_track(item)
        if track and track["video_id"] not in seen:
            seen.add(track["video_id"])
            tracks.append(track)
    return {"title": title, "tracks": tracks}


def _playlist_via_ytdlp(playlist_id: str) -> tuple[str, list[dict[str, Any]]]:
    import yt_dlp

    opts = {"extract_flat": "in_playlist", "quiet": True, "no_warnings": True, "logger": log}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(f"https://www.youtube.com/playlist?list={playlist_id}", download=False)
    items = []
    for entry in (info or {}).get("entries") or []:
        if not entry or not entry.get("id"):
            continue
        items.append(
            {
                "videoId": entry["id"],
                "title": entry.get("title"),
                "artists": [{"name": entry.get("channel") or entry.get("uploader") or ""}],
                "duration_seconds": entry.get("duration"),
                "thumbnails": entry.get("thumbnails") or [],
            }
        )
    return (info or {}).get("title") or "Imported playlist", items


def related(video_id: str, limit: int = 25) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    """(seed track, songs YouTube Music plays after it) via the radio/watch playlist."""
    data = client().get_watch_playlist(videoId=video_id, limit=limit, radio=True)
    seed: dict[str, Any] | None = None
    out: list[dict[str, Any]] = []
    for item in data.get("tracks") or []:
        track = normalize_track(item)
        if not track:
            continue
        if track["video_id"] == video_id:
            seed = track
            continue
        if is_music(item):
            out.append(track)
    return seed, out


def stream_url(video_id: str) -> dict[str, Any]:
    """Direct audio URL (plus required headers) for previewing a song."""
    import yt_dlp

    opts = {"format": "bestaudio[ext=m4a]/bestaudio/best", "quiet": True, "no_warnings": True, "logger": log}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(f"https://music.youtube.com/watch?v={video_id}", download=False)
    if not info or not info.get("url"):
        raise RuntimeError("No playable audio stream found")
    return {"url": info["url"], "http_headers": info.get("http_headers") or {}}
