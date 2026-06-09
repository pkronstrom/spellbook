import pytest

from summon_core import bundle, manifest as m


def test_build_text_bundle(tmp_path):
    parcel = bundle.build_bundle(
        kind="text", value="some context", sender="peter", recipient="jesse",
        note="", created_at="t",
    )
    assert parcel.name == bundle.PARCEL_NAME
    man = m.read_manifest(parcel)
    assert man.type == "text"
    assert man.name == "message.md"
    body = (parcel / m.PAYLOAD_DIRNAME / "message.md").read_text()
    assert body == "some context"
    assert (man.payload_sha256, man.size_bytes, man.file_count) == m.payload_digest(parcel / m.PAYLOAD_DIRNAME)


def test_build_file_bundle(tmp_path):
    src = tmp_path / "report.md"
    src.write_text("# report")
    parcel = bundle.build_bundle(kind="file", value=src, sender="p", recipient="",
                                 note="", created_at="t")
    man = m.read_manifest(parcel)
    assert man.type == "file"
    assert man.name == "report.md"
    assert (parcel / m.PAYLOAD_DIRNAME / "report.md").read_text() == "# report"


def test_build_folder_bundle(tmp_path):
    src = tmp_path / "proj"
    (src / "x").mkdir(parents=True)
    (src / "x" / "f.txt").write_text("data")
    parcel = bundle.build_bundle(kind="folder", value=src, sender="p", recipient="",
                                 note="", created_at="t")
    man = m.read_manifest(parcel)
    assert man.type == "folder"
    assert man.name == "proj"
    assert (parcel / m.PAYLOAD_DIRNAME / "proj" / "x" / "f.txt").read_text() == "data"


def test_build_skill_bundle_resolves_name(tmp_path, fake_home):
    skill = fake_home / ".claude" / "skills" / "cool"
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text("---\nname: cool\n---\nhi")
    parcel = bundle.build_bundle(kind="skill", value="cool", sender="p",
                                 recipient="", note="", created_at="t")
    man = m.read_manifest(parcel)
    assert man.type == "skill"
    assert man.name == "cool"
    assert man.suggested_path.endswith("/.claude/skills/cool/")
    assert (parcel / m.PAYLOAD_DIRNAME / "cool" / "SKILL.md").exists()


def test_build_file_missing_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        bundle.build_bundle(kind="file", value=tmp_path / "nope", sender="p",
                            recipient="", note="", created_at="t")


def test_resolve_skill_ambiguous_raises(tmp_path, fake_home, monkeypatch):
    proj = tmp_path / "proj"
    (proj / ".claude" / "skills" / "dup").mkdir(parents=True)
    (proj / ".claude" / "skills" / "dup" / "SKILL.md").write_text("x")
    (fake_home / ".claude" / "skills" / "dup").mkdir(parents=True)
    (fake_home / ".claude" / "skills" / "dup" / "SKILL.md").write_text("x")
    monkeypatch.chdir(proj)
    # project skill wins (search order), so this resolves without error:
    assert bundle.resolve_skill("dup").parent == proj / ".claude" / "skills"
    with pytest.raises(FileNotFoundError):
        bundle.resolve_skill("does-not-exist")
