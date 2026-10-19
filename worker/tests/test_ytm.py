"""Track normalisation and URL parsing (pure functions, no network)."""

import pytest

import downloader
import ytm


def test_normalize_search_result():
    item = {
        "resultType": "song", "videoId": "wU26xVT_vBU", "title": "One More Time",
        "artists": [{"name": "Daft Punk"}, {"name": "Romanthony"}],
        "album": {"name": "Discovery"}, "duration": "5:21", "duration_seconds": 321,
        "thumbnails": [{"url": "https://lh3.googleusercontent.com/x=w60-h60-l90-rj", "width": 60, "height": 60},
                       {"url": "https://lh3.googleusercontent.com/x=w120-h120-l90-rj", "width": 120, "height": 120}],
    }
    assert ytm.normalize_track(item) == {
        "video_id": "wU26xVT_vBU", "title": "One More Time", "artist": "Daft Punk, Romanthony",
        "album": "Discovery", "duration_sec": 321,
        "thumbnail_url": "https://lh3.googleusercontent.com/x=w544-h544-l90-rj",
        "file_path": None, "downloaded": False,
    }


def test_normalize_watch_playlist_item_uses_length():
    item = {"videoId": "abc", "title": "T", "artists": [{"name": "A"}], "album": None, "length": "1:02:03",
            "thumbnail": []}
    track = ytm.normalize_track(item)
    assert track["duration_sec"] == 3723
    assert track["album"] == ""
    assert track["thumbnail_url"] == ""


def test_normalize_rejects_items_without_id():
    assert ytm.normalize_track({"title": "x"}) is None


@pytest.mark.parametrize("url,expected", [
    ("https://music.youtube.com/playlist?list=PLabc_123-x", "PLabc_123-x"),
    ("https://www.youtube.com/watch?v=xyz&list=OLAK5uy_k", "OLAK5uy_k"),
])
def test_extract_playlist_id(url, expected):
    assert ytm.extract_playlist_id(url) == expected


@pytest.mark.parametrize("url", ["https://youtube.com/watch?v=abc", "https://x.com/?list=../../etc"])
def test_extract_playlist_id_rejects_bad_links(url):
    with pytest.raises(ValueError):
        ytm.extract_playlist_id(url)


def test_safe_paths_and_speed():
    assert downloader.safe_name('AC/DC: "Live"?') == "AC_DC_ _Live__"
    assert downloader.safe_name("...") == "Unknown"
    # Names Windows can't store: device names and a trailing dot after cutting.
    assert downloader.safe_name("con") == "_con"
    assert downloader.safe_name("NUL.mp3") == "_NUL.mp3"
    assert downloader.safe_name("Console") == "Console"
    assert downloader.safe_name("a" * 119 + ". tail") == "a" * 119
    assert downloader.human_speed(1_258_291) == "1.2MiB/s"
    assert downloader.human_speed(None) is None


def test_target_path_keeps_both_when_title_exists(tmp_path):
    first = downloader.target_path(tmp_path, "Artist", "", "Song", "id1")
    assert first == tmp_path / "Artist" / "Singles" / "Song.mp3"
    first.parent.mkdir(parents=True)
    first.write_bytes(b"x")
    second = downloader.target_path(tmp_path, "Artist", "", "Song", "id2")
    assert second.name == "Song [id2].mp3"


def test_download_errors_retry_only_when_transient():
    from downloader import is_retryable

    assert is_retryable("unable to download video data: HTTP Error 403: Forbidden")
    assert is_retryable("HTTP Error 429: Too Many Requests")
    assert is_retryable("Read timed out.")
    assert not is_retryable("Video unavailable. This video is private")
    assert not is_retryable("This video is unavailable")


def test_each_retry_uses_different_player_clients():
    from downloader import MAX_ATTEMPTS, attempt_options

    base = {"format": "bestaudio/best"}
    first = attempt_options(base, 1)
    assert "extractor_args" not in first, "first try uses yt-dlp defaults"
    clients = [tuple(attempt_options(base, n)["extractor_args"]["youtube"]["player_client"]) for n in range(2, MAX_ATTEMPTS + 1)]
    assert len(set(clients)) == len(clients) == MAX_ATTEMPTS - 1
    assert base == {"format": "bestaudio/best"}, "base options are not mutated"


def test_album_browse_id_detection():
    from ytm import extract_album_browse_id

    assert extract_album_browse_id("https://music.youtube.com/browse/MPREb_4pL8gzRtw1p") == "MPREb_4pL8gzRtw1p"
    assert extract_album_browse_id("https://music.youtube.com/playlist?list=OLAK5uy_x") is None


def test_album_tracks_inherit_album_name_and_cover(monkeypatch):
    import ytm

    class Fake:
        def get_album(self, browse_id):
            return {
                "title": "Discovery",
                "artists": [{"name": "Daft Punk"}],
                "thumbnails": [{"url": "https://img/cover=w120-h120", "width": 120}],
                "tracks": [
                    {"videoId": "aaaaaaaaaaa", "title": "One More Time", "artists": None, "album": None, "duration": "5:20"},
                    {"videoId": "bbbbbbbbbbb", "title": "Gone", "isAvailable": False},
                    {"videoId": "aaaaaaaaaaa", "title": "dupe"},
                ],
            }

    monkeypatch.setattr(ytm, "client", lambda: Fake())
    info = ytm.playlist_info("https://music.youtube.com/browse/MPREb_abc")
    assert info["title"] == "Discovery"
    assert [t["video_id"] for t in info["tracks"]] == ["aaaaaaaaaaa"]
    t = info["tracks"][0]
    assert t["album"] == "Discovery" and t["artist"] == "Daft Punk" and t["duration_sec"] == 320
    assert t["thumbnail_url"].startswith("https://img/cover")


def test_song_info_uses_watch_playlist(monkeypatch):
    import ytm

    class Fake:
        def get_watch_playlist(self, videoId, limit):
            return {"tracks": [{"videoId": videoId, "title": "Song", "artists": [{"name": "A"}], "length": "3:00"}]}

    monkeypatch.setattr(ytm, "client", lambda: Fake())
    t = ytm.song_info("ccccccccccc")
    assert (t["title"], t["artist"], t["duration_sec"]) == ("Song", "A", 180)
