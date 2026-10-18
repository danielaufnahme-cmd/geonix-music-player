"""Geonix worker: speaks JSON lines with the Rust backend.

Requests arrive on stdin, one JSON object per line, each with an "id" and a
"cmd". Responses go to stdout with the same "id":
    {"id": ..., "type": "progress", "percent": 42.5, "speed": "1.2MiB/s"}
    {"id": ..., "type": "result", "data": {...}}
    {"id": ..., "type": "error", "message": "..."}

Commands run in a thread pool, so a long download never blocks a search.
Logs go to stderr only; stdout is reserved for the protocol.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import threading
from concurrent.futures import Executor, Future, ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable, TextIO

# Make sibling modules importable however the script is started.
sys.path.insert(0, str(Path(__file__).resolve().parent))

log = logging.getLogger("geonix.worker")

Handler = Callable[[dict[str, Any], Callable[[dict[str, Any]], None]], Any]


class Protocol:
    def __init__(self, out: TextIO, handlers: dict[str, Handler], executor: Executor) -> None:
        self.out = out
        self.handlers = handlers
        self.executor = executor
        self._lock = threading.Lock()

    def emit(self, msg: dict[str, Any]) -> None:
        line = json.dumps(msg, ensure_ascii=False, default=str)
        with self._lock:
            self.out.write(line + "\n")
            self.out.flush()

    def handle_line(self, line: str) -> Future[None] | None:
        line = line.strip()
        if not line:
            return None
        try:
            req = json.loads(line)
        except json.JSONDecodeError as exc:
            log.warning("invalid JSON from backend: %s", exc)
            return None
        if not isinstance(req, dict) or not isinstance(req.get("id"), str):
            log.warning("request without id ignored: %r", line[:200])
            return None
        req_id: str = req["id"]
        handler = self.handlers.get(req.get("cmd", ""))
        if handler is None:
            self.emit({"id": req_id, "type": "error", "message": f"unknown command: {req.get('cmd')!r}"})
            return None
        return self.executor.submit(self._run, req_id, handler, req)

    def _run(self, req_id: str, handler: Handler, req: dict[str, Any]) -> None:
        def progress(update: dict[str, Any]) -> None:
            self.emit({"id": req_id, "type": "progress", **update})

        try:
            data = handler(req, progress)
            self.emit({"id": req_id, "type": "result", "data": data})
        except Exception as exc:  # noqa: BLE001 - every failure is reported, never crashes the worker
            log.warning("%s failed: %s", req.get("cmd"), exc, exc_info=log.isEnabledFor(logging.DEBUG))
            self.emit({"id": req_id, "type": "error", "message": friendly_error(exc)})


def friendly_error(exc: Exception) -> str:
    text = str(exc).strip() or exc.__class__.__name__
    lowered = text.lower()
    if "video unavailable" in lowered or "not available" in lowered:
        return "Video unavailable"
    if any(s in lowered for s in ("urlopen error", "timed out", "name or service not known", "connection")):
        return f"Network error: {text}"
    return text


def require(req: dict[str, Any], key: str, kind: type) -> Any:
    value = req.get(key)
    if not isinstance(value, kind) or (isinstance(value, str) and not value.strip()):
        raise ValueError(f"missing or invalid '{key}'")
    return value


def build_handlers() -> dict[str, Handler]:
    import downloader
    import lyrics as lyrics_mod
    import recommender
    import ytm

    def search(req: dict[str, Any], _p: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
        limit = int(req.get("limit") or 20)
        return {"tracks": ytm.search(require(req, "query", str), max(1, min(limit, 50)))}

    def playlist_info(req: dict[str, Any], _p: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
        return ytm.playlist_info(require(req, "url", str))

    def download(req: dict[str, Any], progress: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
        meta = req.get("meta") if isinstance(req.get("meta"), dict) else None
        return downloader.download(
            require(req, "video_id", str),
            require(req, "dest_dir", str),
            progress,
            meta=meta,
            covers_dir=req.get("covers_dir"),
        )

    def recommend(req: dict[str, Any], _p: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
        seeds = [s for s in req.get("seed_video_ids") or [] if isinstance(s, str)]
        exclude = [s for s in req.get("exclude_video_ids") or [] if isinstance(s, str)]
        limit = int(req.get("limit") or 30)
        return {"tracks": recommender.recommend(seeds, exclude, max(1, min(limit, 100)))}

    def stream_url(req: dict[str, Any], _p: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
        return ytm.stream_url(require(req, "video_id", str))

    def lyrics(req: dict[str, Any], _p: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
        return lyrics_mod.lyrics(
            require(req, "video_id", str),
            str(req.get("title") or ""),
            str(req.get("artist") or ""),
            int(req.get("duration_sec") or 0),
        )

    def ping(_req: dict[str, Any], _p: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
        return {"pong": True}

    return {
        "search": search,
        "playlist_info": playlist_info,
        "download": download,
        "recommend": recommend,
        "stream_url": stream_url,
        "lyrics": lyrics,
        "ping": ping,
    }


def claim_stdout() -> TextIO:
    """Keep the real stdout for the protocol and point fd 1 at stderr, so
    stray prints from libraries or ffmpeg can never corrupt a message."""
    proto_fd = os.dup(1)
    os.dup2(2, 1)
    sys.stdout = sys.stderr
    return os.fdopen(proto_fd, "w", buffering=1, encoding="utf-8")


def main() -> None:
    logging.basicConfig(
        stream=sys.stderr,
        level=os.environ.get("GEONIX_WORKER_LOG", "INFO").upper(),
        format="worker %(levelname)s %(name)s: %(message)s",
    )
    out = claim_stdout()
    executor = ThreadPoolExecutor(max_workers=8, thread_name_prefix="geonix")
    protocol = Protocol(out, build_handlers(), executor)
    log.info("ready")
    for line in sys.stdin:
        protocol.handle_line(line)
    # The backend is gone: nobody can receive results, so stop right away
    # instead of finishing in-flight downloads.
    log.info("stdin closed, exiting")
    executor.shutdown(wait=False, cancel_futures=True)
    os._exit(0)


if __name__ == "__main__":
    main()
