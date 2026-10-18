"""Worker protocol: parsing, dispatch by id, progress, errors."""

import io
import json
from concurrent.futures import Executor, Future

import worker


class InlineExecutor(Executor):
    """Runs submitted work immediately so tests are deterministic."""

    def submit(self, fn, *args, **kwargs):
        f = Future()
        f.set_result(fn(*args, **kwargs))
        return f


def make(handlers):
    out = io.StringIO()
    return worker.Protocol(out, handlers, InlineExecutor()), out


def messages(out):
    return [json.loads(line) for line in out.getvalue().splitlines()]


def test_result_carries_request_id():
    proto, out = make({"echo": lambda req, p: {"q": req["query"]}})
    proto.handle_line('{"id": "r1", "cmd": "echo", "query": "daft punk"}\n')
    assert messages(out) == [{"id": "r1", "type": "result", "data": {"q": "daft punk"}}]


def test_progress_events_then_result():
    def handler(req, progress):
        progress({"percent": 42.5, "speed": "1.2MiB/s"})
        progress({"percent": 100.0, "speed": None})
        return {"done": True}

    proto, out = make({"download": handler})
    proto.handle_line(json.dumps({"id": "d1", "cmd": "download"}))
    msgs = messages(out)
    assert [m["type"] for m in msgs] == ["progress", "progress", "result"]
    assert msgs[0] == {"id": "d1", "type": "progress", "percent": 42.5, "speed": "1.2MiB/s"}
    assert all(m["id"] == "d1" for m in msgs)


def test_handler_exception_becomes_error_message():
    def boom(req, p):
        raise RuntimeError("ERROR: Video unavailable. This video is private")

    proto, out = make({"download": boom})
    proto.handle_line('{"id": "x", "cmd": "download"}')
    assert messages(out) == [{"id": "x", "type": "error", "message": "Video unavailable"}]


def test_unknown_command_and_bad_lines():
    proto, out = make({})
    proto.handle_line("this is not json")
    proto.handle_line('{"cmd": "search"}')  # no id: ignored
    proto.handle_line("")
    proto.handle_line('{"id": "u", "cmd": "fly"}')
    assert messages(out) == [{"id": "u", "type": "error", "message": "unknown command: 'fly'"}]


def test_require_validates_fields():
    assert worker.require({"q": "x"}, "q", str) == "x"
    for bad in ({}, {"q": ""}, {"q": 5}):
        try:
            worker.require(bad, "q", str)
        except ValueError:
            continue
        raise AssertionError(f"{bad} should be rejected")


def test_network_errors_are_labelled():
    assert worker.friendly_error(OSError("<urlopen error timed out>")).startswith("Network error")
