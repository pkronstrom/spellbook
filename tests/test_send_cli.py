import json
from pathlib import Path

import pytest

from summon_core import send, state


@pytest.fixture
def fake_croc(monkeypatch):
    calls = {}

    def fake_start(incantation, parcel_dir, log_path):
        calls["incantation"] = incantation
        calls["parcel_dir"] = Path(parcel_dir)
        Path(log_path).write_text("")
        return 4242

    monkeypatch.setattr(send.croc, "start_send", fake_start)
    monkeypatch.setattr(send.croc, "ensure_croc", lambda: "croc")
    return calls


def test_share_line_includes_fallback():
    line = send.share_line("a-b-c-d", sender="peter", recipient="jesse",
                           kind="file", name="report.md")
    assert "a-b-c-d" in line
    assert "peter" in line and "jesse" in line
    assert "brew install croc && croc a-b-c-d" in line


def test_start_text_returns_json_and_state(fake_croc, monkeypatch, capsys):
    monkeypatch.setattr(send, "_now", lambda: "2026-06-09T00:00:00Z")
    monkeypatch.setattr(send, "copy_clipboard", lambda text: True)
    rc = send.main(["start", "--text", "hello world", "--sender", "peter",
                    "--recipient", "jesse"])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["incantation"].count("-") == 3
    assert out["clipboard"] is True
    st = state.load_state(out["incantation"])
    assert st is not None and st.pid == 4242 and st.type == "text"
    assert fake_croc["parcel_dir"].name == "summon_parcel"


def test_cancel_kills_and_cleans(fake_croc, monkeypatch, capsys):
    monkeypatch.setattr(send, "_now", lambda: "t")
    monkeypatch.setattr(send, "copy_clipboard", lambda text: False)
    send.main(["start", "--text", "x", "--sender", "p", "--recipient", ""])
    inc = json.loads(capsys.readouterr().out)["incantation"]
    killed = {}
    monkeypatch.setattr(send.os, "kill", lambda pid, sig: killed.setdefault("pid", pid))
    rc = send.main(["cancel", inc])
    assert rc == 0
    assert killed["pid"] == 4242
    assert state.load_state(inc) is None


def test_status_lists_pending(fake_croc, monkeypatch, capsys):
    monkeypatch.setattr(send, "_now", lambda: "t")
    monkeypatch.setattr(send, "copy_clipboard", lambda text: False)
    send.main(["start", "--text", "x", "--sender", "p", "--recipient", ""])
    capsys.readouterr()
    monkeypatch.setattr(send.state, "is_alive", lambda pid: True)
    send.main(["status"])
    out = json.loads(capsys.readouterr().out)
    assert len(out["pending"]) == 1
    assert out["pending"][0]["alive"] is True
