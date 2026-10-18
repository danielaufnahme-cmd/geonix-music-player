import lyrics


def test_parse_lrc_handles_fractions_multi_tags_and_sorting():
    lrc = "[ar:Someone]\n[00:12.5]Second\n[00:01.20][01:00.000]Chorus\nno tag line\n[02:03]End"
    lines = lyrics.parse_lrc(lrc)
    assert [line["time_ms"] for line in lines] == [1200, 12500, 60000, 123000]
    assert [line["text"] for line in lines] == ["Chorus", "Second", "Chorus", "End"]


def test_clean_title_strips_edit_markers_and_detects_edits():
    assert lyrics.clean_title("MEANT TO BE (HARDSTYLE ULTRA SLOWED)") == "MEANT TO BE"
    assert lyrics.clean_title("Blinding Lights (Official Audio)") == "Blinding Lights"
    assert lyrics.clean_title("Song - Sped Up") == "Song"
    assert lyrics.is_edit("Song (slowed + reverb)")
    assert not lyrics.is_edit("Blinding Lights")
    assert lyrics.first_artist("prodArvee, svdst") == "prodArvee"


def test_pick_prefers_synced_then_closest_duration():
    hits = [
        {"plainLyrics": "a", "duration": 200},
        {"syncedLyrics": "[00:01]x", "duration": 260},
        {"syncedLyrics": "[00:01]y", "duration": 205},
    ]
    assert lyrics.pick_lrclib(hits, 200)["syncedLyrics"] == "[00:01]y"
    assert lyrics.pick_lrclib([], 200) is None


def test_slowed_edit_gets_timestamps_stretched(monkeypatch):
    calls = []

    def fake_get(url, timeout=12):
        calls.append(url)
        if "/search?" in url:
            return [{"syncedLyrics": "[00:10.00]Hello\n[00:20.00]World", "duration": 100}]
        raise AssertionError("edits must not use exact /get lookups")

    monkeypatch.setattr(lyrics, "_get_json", fake_get)
    found = lyrics.from_lrclib("Song (Ultra Slowed)", "Artist", 125)
    assert found["synced"]
    assert [line["time_ms"] for line in found["lines"]] == [12500, 25000]
    assert "timed" in found["source"]
    assert "track_name=Song&" in calls[0]


def test_different_cut_falls_back_to_plain(monkeypatch):
    monkeypatch.setattr(
        lyrics,
        "_get_json",
        lambda url, timeout=12: {"syncedLyrics": "[00:10]Hi", "plainLyrics": "Hi", "duration": 300},
    )
    found = lyrics.from_lrclib("Song", "Artist", 200)
    assert found == {"synced": False, "lines": [{"time_ms": None, "text": "Hi"}], "source": "LRCLIB"}


def test_sources_fall_through_and_failures_are_transient(monkeypatch):
    monkeypatch.setattr(lyrics, "from_youtube_music", lambda vid: {"synced": False, "lines": [{"time_ms": None, "text": "p"}], "source": "YT"})
    monkeypatch.setattr(lyrics, "from_lrclib", lambda t, a, d: {"synced": True, "lines": [{"time_ms": 1, "text": "s"}], "source": "LRCLIB"})
    assert lyrics.lyrics("v", "T", "A", 100)["source"] == "LRCLIB", "synced beats plain"

    def boom(*_a):
        raise OSError("offline")

    monkeypatch.setattr(lyrics, "from_youtube_music", boom)
    monkeypatch.setattr(lyrics, "from_lrclib", lambda t, a, d: None)
    result = lyrics.lyrics("v", "T", "A", 100)
    assert result["lines"] == [] and result["transient"] is True

    monkeypatch.setattr(lyrics, "from_youtube_music", lambda vid: None)
    assert lyrics.lyrics("v", "T", "A", 100)["transient"] is False
