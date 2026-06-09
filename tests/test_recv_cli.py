import json
import shutil
from pathlib import Path

import pytest

from summon_core import recv, bundle, manifest as m


def _mkfile(tmp_path):
    f = tmp_path / "report.md"
    f.write_text("# hi")
    return f


@pytest.fixture
def staged_parcel(tmp_path):
    """Build a real bundle to stand in for what croc would deliver."""
    return bundle.build_bundle(kind="file", value=_mkfile(tmp_path),
                               sender="peter", recipient="jesse", note="",
                               created_at="t")


def test_fetch_returns_validated_manifest(monkeypatch, staged_parcel, capsys):
    def fake_receive(incantation, out_dir, timeout=600):
        shutil.copytree(staged_parcel, Path(out_dir) / "summon_parcel")
    monkeypatch.setattr(recv.croc, "receive", fake_receive)
    monkeypatch.setattr(recv.croc, "ensure_croc", lambda: "croc")

    rc = recv.main(["fetch", "a-b-c-d"])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["verified"] is True
    assert out["manifest"]["type"] == "file"
    assert out["manifest"]["name"] == "report.md"
    assert out["manifest"]["sender_display"] == "peter"
    assert out["listing"] == ["report.md"]
    assert Path(out["parcel_dir"]).exists()


def test_fetch_detects_integrity_mismatch(monkeypatch, staged_parcel, capsys):
    def fake_receive(incantation, out_dir, timeout=600):
        dst = Path(out_dir) / "summon_parcel"
        shutil.copytree(staged_parcel, dst)
        (dst / m.PAYLOAD_DIRNAME / "report.md").write_text("TAMPERED")
    monkeypatch.setattr(recv.croc, "receive", fake_receive)
    monkeypatch.setattr(recv.croc, "ensure_croc", lambda: "croc")

    rc = recv.main(["fetch", "a-b-c-d"])
    out = json.loads(capsys.readouterr().out)
    assert rc == 1
    assert out["verified"] is False
    assert "integrity" in out["error"]


def test_place_moves_into_cwd(monkeypatch, staged_parcel, chtmp, capsys):
    rc = recv.main(["place", "--parcel", str(staged_parcel)])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert Path(out["placed_path"]) == chtmp / "report.md"
    assert (chtmp / "report.md").read_text() == "# hi"
