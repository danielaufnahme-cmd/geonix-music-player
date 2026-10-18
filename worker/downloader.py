"""Download one song as MP3 with yt-dlp, then tag it with mutagen.

Files land in <dest_dir>/<Artist>/<Album>/<Title>.mp3 with title, artist,
album and embedded cover art. The cover is also saved to covers_dir so the
backend can serve it without reading the MP3.
"""

from __future__ import annotations

import logging
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path
from typing import Any, Callable

log = logging.getLogger("geonix.downloader")

# YouTube sometimes rejects a single stream URL (403) or rate-limits briefly;
# a fresh attempt usually succeeds. Errors like "Video unavailable" are final.
# Each retry also switches YouTube player clients: a 403 is usually tied to
# the client whose stream URLs got rejected, and another client's URLs work.
PLAYER_CLIENTS: tuple[tuple[str, ...] | None, ...] = (
    None,  # yt-dlp's defaults
    ("tv_simply", "web_safari"),
    ("android_vr", "mweb"),
)
MAX_ATTEMPTS = len(PLAYER_CLIENTS)
RETRY_DELAYS = (2.0, 5.0)
_RETRYABLE = re.compile(
    r"HTTP Error (403|429|5\d\d)|timed out|Connection (reset|aborted|refused)|"
    r"Temporary failure|IncompleteRead|Remote end closed|fragment",
    re.IGNORECASE,
)


def is_retryable(message: str) -> bool:
    return bool(_RETRYABLE.search(message))


def attempt_options(base: dict[str, Any], attempt: int) -> dict[str, Any]:
    """yt-dlp options for a 1-based attempt number, with that attempt's player clients."""
    opts = dict(base)
    clients = PLAYER_CLIENTS[min(attempt, len(PLAYER_CLIENTS)) - 1]
    if clients:
        opts["extractor_args"] = {"youtube": {"player_client": list(clients)}}
    return opts

ProgressFn = Callable[[dict[str, Any]], None]

_BAD_CHARS = re.compile(r'[\\/:*?"<>|\x00-\x1f]')


def safe_name(name: str, fallback: str = "Unknown") -> str:
    """Make a string safe as a single path component."""
    cleaned = _BAD_CHARS.sub("_", name or "").strip().strip(".")
    cleaned = re.sub(r"\s+", " ", cleaned)
    return (cleaned or fallback)[:120]


def human_speed(bytes_per_sec: float | None) -> str | None:
    if not bytes_per_sec or bytes_per_sec <= 0:
        return None
    value = float(bytes_per_sec)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if value < 1024 or unit == "GiB":
            return f"{value:.1f}{unit}/s"
        value /= 1024
    return None


def target_path(dest_dir: Path, artist: str, album: str, title: str, video_id: str) -> Path:
    folder = dest_dir / safe_name(artist, "Unknown artist") / safe_name(album, "Singles")
    path = folder / f"{safe_name(title, video_id)}.mp3"
    if path.exists():
        # Same title already on disk (e.g. a live version): keep both.
        path = folder / f"{safe_name(title, video_id)} [{video_id}].mp3"
    return path


class _StderrLogger:
    """yt-dlp logger that never writes to stdout (stdout is the protocol)."""

    def debug(self, msg: str) -> None:
        if not msg.startswith("[debug]"):
            log.debug(msg)

    def info(self, msg: str) -> None:
        log.debug(msg)

    def warning(self, msg: str) -> None:
        log.info(msg)

    def error(self, msg: str) -> None:
        log.warning(msg)


def _fetch_bytes(url: str, timeout: float = 20) -> bytes | None:
    if not url:
        return None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 Geonix"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 - https thumbnails only
            return resp.read()
    except Exception as exc:  # noqa: BLE001
        log.info("cover download failed: %s", exc)
        return None


def _to_jpeg(data: bytes) -> bytes | None:
    """Covers must be JPEG for ID3; convert WebP/PNG thumbnails with ffmpeg."""
    if data[:3] == b"\xff\xd8\xff":
        return data
    try:
        proc = subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-f", "image2", "-c:v", "mjpeg", "pipe:1"],
            input=data,
            capture_output=True,
            timeout=30,
            check=True,
        )
        return proc.stdout or None
    except Exception as exc:  # noqa: BLE001
        log.info("cover conversion failed: %s", exc)
        return None


def tag_mp3(path: Path, title: str, artist: str, album: str, cover: bytes | None) -> None:
    from mutagen.id3 import APIC, ID3, TALB, TIT2, TPE1, ID3NoHeaderError

    try:
        tags = ID3(path)
    except ID3NoHeaderError:
        tags = ID3()
    tags.delall("APIC")
    tags.add(TIT2(encoding=3, text=title))
    tags.add(TPE1(encoding=3, text=artist))
    if album:
        tags.add(TALB(encoding=3, text=album))
    if cover:
        tags.add(APIC(encoding=3, mime="image/jpeg", type=3, desc="Cover", data=cover))
    tags.save(path, v2_version=3)


def download(
    video_id: str,
    dest_dir: str,
    progress: ProgressFn,
    meta: dict[str, Any] | None = None,
    covers_dir: str | None = None,
) -> dict[str, Any]:
    import yt_dlp

    dest = Path(dest_dir).expanduser()
    dest.mkdir(parents=True, exist_ok=True)
    meta = meta or {}
    last_emit = [0.0]

    def hook(d: dict[str, Any]) -> None:
        now = time.monotonic()
        if d.get("status") == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            done = d.get("downloaded_bytes") or 0
            if now - last_emit[0] < 0.25:
                return
            last_emit[0] = now
            # Downloading is 0–95 %, the MP3 conversion is the last 5 %.
            percent = (done / total * 95.0) if total else 0.0
            progress({"percent": round(percent, 1), "speed": human_speed(d.get("speed"))})
        elif d.get("status") == "finished":
            progress({"percent": 95.0, "speed": None})

    with tempfile.TemporaryDirectory(prefix=f"geonix-{video_id}-") as tmp:
        opts = {
            "format": "bestaudio/best",
            "outtmpl": str(Path(tmp) / f"{video_id}.%(ext)s"),
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "noprogress": True,
            "logger": _StderrLogger(),
            "progress_hooks": [hook],
            "postprocessors": [
                {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "0"},
            ],
        }
        info: dict[str, Any] = {}
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                # A fresh YoutubeDL per attempt re-extracts the page, so a
                # rejected stream URL is replaced by a new one.
                with yt_dlp.YoutubeDL(attempt_options(opts, attempt)) as ydl:
                    info = ydl.extract_info(f"https://music.youtube.com/watch?v={video_id}", download=True) or {}
                break
            except yt_dlp.utils.DownloadError as exc:
                message = re.sub(r"^ERROR:\s*(\[[^\]]+\]\s*)?(\S+:\s*)?", "", str(exc)).strip()
                if attempt < MAX_ATTEMPTS and is_retryable(message):
                    log.warning("download %s attempt %d failed (%s); retrying", video_id, attempt, message)
                    for leftover in Path(tmp).iterdir():
                        leftover.unlink(missing_ok=True)
                    progress({"percent": 0.0, "speed": f"retrying ({attempt + 1}/{MAX_ATTEMPTS})"})
                    time.sleep(RETRY_DELAYS[attempt - 1])
                    continue
                raise RuntimeError(message or "Download failed") from exc

        mp3 = Path(tmp) / f"{video_id}.mp3"
        if not mp3.exists():
            raise RuntimeError("Conversion to MP3 failed (is ffmpeg installed?)")

        title = meta.get("title") or info.get("track") or info.get("title") or video_id
        artist = (
            meta.get("artist")
            or info.get("artist")
            or ", ".join(info.get("artists") or [])
            or info.get("channel")
            or info.get("uploader")
            or "Unknown artist"
        )
        album = meta.get("album") or info.get("album") or ""
        duration = int(meta.get("duration_sec") or info.get("duration") or 0)
        thumbnail = meta.get("thumbnail_url") or info.get("thumbnail") or ""

        cover_raw = _fetch_bytes(thumbnail)
        cover = _to_jpeg(cover_raw) if cover_raw else None
        tag_mp3(mp3, title, artist, album, cover)

        final = target_path(dest, artist, album, title, video_id)
        final.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(mp3), final)

    cover_path: str | None = None
    if cover and covers_dir:
        cdir = Path(covers_dir).expanduser()
        cdir.mkdir(parents=True, exist_ok=True)
        cpath = cdir / f"{video_id}.jpg"
        cpath.write_bytes(cover)
        cover_path = str(cpath)

    progress({"percent": 100.0, "speed": None})
    return {
        "video_id": video_id,
        "title": title,
        "artist": artist,
        "album": album,
        "duration_sec": duration,
        "thumbnail_url": thumbnail,
        "file_path": str(final),
        "cover_path": cover_path,
        "downloaded": True,
    }
