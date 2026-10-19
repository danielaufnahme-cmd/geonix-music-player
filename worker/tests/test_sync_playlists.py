import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

from sync_playlists import MARKER, load_config, sync  # noqa: E402


def make_db(path: Path, music: Path) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE tracks (video_id TEXT PRIMARY KEY, file_path TEXT);
        CREATE TABLE playlists (id INTEGER PRIMARY KEY, name TEXT, kind TEXT);
        CREATE TABLE playlist_tracks (playlist_id INTEGER, video_id TEXT, position INTEGER);
        """
    )
    conn.executemany(
        "INSERT INTO tracks VALUES (?, ?)",
        [("a", str(music / "A/Al/a.mp3")), ("b", str(music / "B/Bl/b.mp3")), ("c", None)],
    )
    conn.executemany(
        "INSERT INTO playlists VALUES (?, ?, ?)",
        [(1, "Road/Trip", "user"), (2, "Discover Mix", "discover")],
    )
    conn.executemany(
        "INSERT INTO playlist_tracks VALUES (?, ?, ?)",
        [(1, "b", 0), (1, "c", 1), (1, "a", 2), (2, "a", 0)],
    )
    conn.commit()
    conn.close()


def test_exports_downloaded_songs_in_order_with_relative_paths(tmp_path):
    music = tmp_path / "music"
    db = tmp_path / "lib.db"
    make_db(db, music)
    changes = sync(db, music)
    files = list((music / "Playlists").glob("*.m3u8"))
    assert [f.name for f in files] == ["Road_Trip.m3u8"]  # discover skipped, name made safe
    lines = files[0].read_text().splitlines()
    assert lines[:2] == ["#EXTM3U", MARKER]
    assert lines[3:] == ["../B/Bl/b.mp3", "../A/Al/a.mp3"]  # order kept, undownloaded skipped
    assert changes == ["wrote Road_Trip.m3u8 (2 songs)"]
    assert sync(db, music) == []  # unchanged content is not rewritten


def test_removes_only_its_own_stale_files(tmp_path):
    music = tmp_path / "music"
    db = tmp_path / "lib.db"
    make_db(db, music)
    pdir = music / "Playlists"
    pdir.mkdir(parents=True)
    (pdir / "Old.m3u8").write_text(f"#EXTM3U\n{MARKER}\n")
    (pdir / "Mine.m3u8").write_text("#EXTM3U\nsong.mp3\n")
    changes = sync(db, music)
    assert "removed Old.m3u8" in changes
    assert (pdir / "Mine.m3u8").exists()


def test_navidrome_login_parsing_and_token(tmp_path):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
    import hashlib
    from urllib.parse import parse_qs

    from navidrome_rescan import auth_query, read_login

    f = tmp_path / "LOGIN.txt"
    f.write_text("Navidrome / Amperfy login\nServer:   https://x:4533\nUsername: alice\nPassword: s3cret\n")
    assert read_login(f) == ("alice", "s3cret")
    assert read_login(tmp_path / "missing.txt") is None
    q = parse_qs(auth_query("alice", "s3cret"))
    assert "s3cret" not in auth_query("alice", "s3cret")
    assert q["t"][0] == hashlib.md5(("s3cret" + q["s"][0]).encode()).hexdigest()


def test_config_file_with_environment_winning(tmp_path):
    home = str(Path.home())
    cfg = tmp_path / "geonix.env"
    cfg.write_text(
        "# comment\n\nGEONIX_PORT=7802\nexport GEONIX_DATA_DIR=\"$HOME/data\"\n"
        "GEONIX_MUSIC_DIR=~/Music/Mine\nOTHER=ignored\nbroken line\n"
    )
    settings = load_config(cfg, environ={"GEONIX_PORT": "9000", "GEONIX_MUSIC_DIR": "", "PATH": "/bin"})
    assert settings == {
        "GEONIX_PORT": "9000",  # a real env var wins
        "GEONIX_DATA_DIR": f"{home}/data",
        "GEONIX_MUSIC_DIR": f"{home}/Music/Mine",  # empty env var doesn't override
    }
    assert load_config(tmp_path / "missing.env", environ={}) == {}
