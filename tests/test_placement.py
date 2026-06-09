import os

import pytest

from summon_core import placement, manifest as m


def _parcel(tmp_path, kind="file", name="report.md", make=None):
    parcel = tmp_path / "summon_parcel"
    payload = parcel / m.PAYLOAD_DIRNAME
    payload.mkdir(parents=True)
    if make:
        make(payload)
    else:
        (payload / name).write_text("data")
    sha, size, count = m.payload_digest(payload)
    man = m.Manifest(type=kind, name=name, suggested_path=f"./{name}",
                     sender="p", recipient="", created_at="t",
                     payload_sha256=sha, size_bytes=size, file_count=count)
    m.write_manifest(parcel, man)
    return parcel, man


def test_default_dest_file_is_cwd(tmp_path, chtmp):
    _, man = _parcel(tmp_path)
    assert placement.default_dest(man, chtmp) == chtmp / "report.md"


def test_default_dest_skill_is_user_skills(tmp_path, fake_home, chtmp):
    _, man = _parcel(tmp_path, kind="skill", name="cool",
                     make=lambda p: (p / "cool").mkdir())
    dest = placement.default_dest(man, chtmp)
    assert dest == fake_home / ".claude" / "skills" / "cool"


def test_scan_payload_safe_rejects_symlink(tmp_path):
    def make(payload):
        (payload / "ok.txt").write_text("x")
        os.symlink("/etc/passwd", payload / "evil")
    parcel, _ = _parcel(tmp_path, make=make)
    with pytest.raises(placement.UnsafePayload):
        placement.scan_payload_safe(parcel / m.PAYLOAD_DIRNAME)


def test_place_file_into_cwd(tmp_path, chtmp):
    parcel, man = _parcel(tmp_path)
    dest = placement.place_parcel(parcel, man, placement.default_dest(man, chtmp), overwrite=False)
    assert dest == chtmp / "report.md"
    assert dest.read_text() == "data"


def test_place_no_overwrite_picks_conflict_name(tmp_path, chtmp):
    (chtmp / "report.md").write_text("existing")
    parcel, man = _parcel(tmp_path)
    dest = placement.place_parcel(parcel, man, chtmp / "report.md", overwrite=False)
    assert dest == chtmp / "report (2).md"
    assert (chtmp / "report.md").read_text() == "existing"


def test_place_overwrite_replaces(tmp_path, chtmp):
    (chtmp / "report.md").write_text("existing")
    parcel, man = _parcel(tmp_path)
    dest = placement.place_parcel(parcel, man, chtmp / "report.md", overwrite=True)
    assert dest.read_text() == "data"


def test_place_rejects_dest_outside_allowed_root(tmp_path, chtmp):
    parcel, man = _parcel(tmp_path)
    with pytest.raises(placement.UnsafeDestination):
        placement.place_parcel(parcel, man, tmp_path / "elsewhere" / "report.md", overwrite=False)
