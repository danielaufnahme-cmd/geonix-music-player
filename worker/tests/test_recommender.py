"""Recommendation ranking (no network: related songs are faked)."""

import pytest

import recommender


def t(vid, artist="A"):
    return {"video_id": vid, "title": vid.upper(), "artist": artist, "album": "", "duration_sec": 200,
            "thumbnail_url": "", "file_path": None, "downloaded": False}


def test_songs_related_to_several_seeds_rank_first():
    related = {
        "s1": (t("s1", "Seed One"), [t("x"), t("common"), t("y")]),
        "s2": (t("s2", "Seed Two"), [t("z"), t("common")]),
    }
    out = recommender.rank(related, exclude=[], limit=10)
    assert out[0]["video_id"] == "common"
    assert out[0]["score"] > out[1]["score"]


def test_library_songs_and_seeds_are_excluded():
    related = {"s1": (t("s1"), [t("s2"), t("lib"), t("new")]), "s2": (t("s2"), [t("s1")])}
    out = recommender.rank(related, exclude=["lib"], limit=10)
    assert [r["video_id"] for r in out] == ["new"]


def test_earlier_position_breaks_ties_and_sets_because():
    related = {
        "s1": (t("s1", "Daft Punk"), [t("a"), t("b")]),
        "s2": (t("s2", "Justice"), [t("b"), t("a")]),
    }
    out = recommender.rank(related, exclude=[], limit=10)
    by_id = {r["video_id"]: r for r in out}
    assert by_id["a"]["because_artist"] == "Daft Punk"
    assert by_id["b"]["because_artist"] == "Justice"
    assert by_id["a"]["because_video_id"] == "s1"


def test_artist_cap_keeps_list_diverse():
    related = {"s1": (t("s1"), [t(f"m{i}", "Same") for i in range(10)] + [t("other", "Other")])}
    out = recommender.rank(related, exclude=[], limit=10, max_per_artist=3)
    artists = [r["artist"] for r in out]
    assert artists.count("Same") == 3
    assert "Other" in artists


def test_limit_and_duplicates_within_one_seed():
    related = {"s1": (t("s1"), [t("a"), t("a"), t("b", "B"), t("c", "C")])}
    out = recommender.rank(related, exclude=[], limit=2)
    assert len(out) == 2
    assert out[0]["score"] == pytest.approx(1.5)


def test_recommend_survives_a_failing_seed():
    def fetch(seed):
        if seed == "bad":
            raise ConnectionError("offline")
        return t(seed), [t("ok")]

    out = recommender.recommend(["bad", "good"], [], limit=5, fetch=fetch)
    assert [r["video_id"] for r in out] == ["ok"]


def test_recommend_raises_when_every_seed_fails():
    def fetch(seed):
        raise ConnectionError("offline")

    with pytest.raises(RuntimeError):
        recommender.recommend(["a", "b"], [], fetch=fetch)


def test_recommend_without_seeds_is_empty():
    assert recommender.recommend([], ["x"], fetch=lambda s: (None, [])) == []
