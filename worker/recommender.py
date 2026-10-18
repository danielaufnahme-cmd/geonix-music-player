"""Taste-based recommendations.

For each seed song (most played + most recently added) we ask YouTube Music
what it would play next. Songs that show up for several seeds are the
strongest matches; position in each list breaks ties. Songs already in the
library are removed, and no artist may take over the list.
"""

from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Callable, Iterable

import ytm

log = logging.getLogger("geonix.recommender")

RelatedFetcher = Callable[[str], tuple[dict[str, Any] | None, list[dict[str, Any]]]]

MAX_PER_ARTIST = 4


def rank(
    related_by_seed: dict[str, tuple[dict[str, Any] | None, list[dict[str, Any]]]],
    exclude: Iterable[str],
    limit: int,
    max_per_artist: int = MAX_PER_ARTIST,
) -> list[dict[str, Any]]:
    """Score candidates across seeds.

    Each appearance is worth 1 point plus up to 0.5 for being early in that
    seed's list. The seed where a song ranked best is its "because".
    """
    excluded = set(exclude) | set(related_by_seed)
    scores: dict[str, float] = {}
    tracks: dict[str, dict[str, Any]] = {}
    best_pos: dict[str, tuple[float, str]] = {}

    for seed_id, (seed_track, candidates) in related_by_seed.items():
        n = max(len(candidates), 1)
        seen_here: set[str] = set()
        for pos, track in enumerate(candidates):
            vid = track.get("video_id")
            if not vid or vid in excluded or vid in seen_here:
                continue
            seen_here.add(vid)
            closeness = 1.0 - pos / n
            scores[vid] = scores.get(vid, 0.0) + 1.0 + 0.5 * closeness
            tracks.setdefault(vid, track)
            if vid not in best_pos or closeness > best_pos[vid][0]:
                best_pos[vid] = (closeness, seed_id)

    ordered = sorted(scores, key=lambda v: (-scores[v], -best_pos[v][0], v))
    per_artist: dict[str, int] = {}
    out: list[dict[str, Any]] = []
    for vid in ordered:
        track = dict(tracks[vid])
        artist_key = (track.get("artist") or "").split(",")[0].strip().lower()
        if per_artist.get(artist_key, 0) >= max_per_artist:
            continue
        per_artist[artist_key] = per_artist.get(artist_key, 0) + 1
        because = best_pos[vid][1]
        seed_track = related_by_seed[because][0]
        track["score"] = round(scores[vid], 3)
        track["because_video_id"] = because
        track["because_artist"] = (seed_track or {}).get("artist") or None
        out.append(track)
        if len(out) >= limit:
            break
    return out


def recommend(
    seed_ids: list[str],
    exclude_ids: list[str],
    limit: int = 30,
    fetch: RelatedFetcher = ytm.related,
) -> list[dict[str, Any]]:
    """Fetch related songs for every seed in parallel and rank them."""
    seeds = list(dict.fromkeys(s for s in seed_ids if s))
    if not seeds:
        return []

    def safe_fetch(seed: str) -> tuple[str, tuple[dict[str, Any] | None, list[dict[str, Any]]] | None]:
        try:
            return seed, fetch(seed)
        except Exception as exc:  # noqa: BLE001 - one bad seed must not sink the rest
            log.warning("related songs for %s failed: %s", seed, exc)
            return seed, None

    with ThreadPoolExecutor(max_workers=min(6, len(seeds))) as pool:
        results = list(pool.map(safe_fetch, seeds))
    related_by_seed = {seed: res for seed, res in results if res is not None}
    if not related_by_seed:
        raise RuntimeError("Could not reach YouTube Music for recommendations")
    return rank(related_by_seed, exclude_ids, limit)
