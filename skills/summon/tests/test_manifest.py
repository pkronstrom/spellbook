from summon_core import manifest as m


def _payload(tmp_path):
    p = tmp_path / "payload"
    (p / "sub").mkdir(parents=True)
    (p / "a.txt").write_text("hello")
    (p / "sub" / "b.txt").write_text("world")
    return p


def test_payload_digest_deterministic(tmp_path):
    p = _payload(tmp_path)
    d1 = m.payload_digest(p)
    d2 = m.payload_digest(p)
    assert d1 == d2
    sha, size, count = d1
    assert size == len("hello") + len("world")
    assert count == 2
    assert len(sha) == 64


def test_payload_digest_changes_with_content(tmp_path):
    p = _payload(tmp_path)
    before = m.payload_digest(p)[0]
    (p / "a.txt").write_text("HELLO")
    assert m.payload_digest(p)[0] != before


def test_manifest_roundtrip(tmp_path):
    man = m.Manifest(
        type="file", name="report.md", suggested_path="./report.md",
        sender="peter", recipient="jesse", created_at="2026-06-09T00:00:00Z",
        note="hi", payload_sha256="x" * 64, size_bytes=5, file_count=1,
    )
    text = man.to_json()
    back = m.Manifest.from_json(text)
    assert back == man
    assert back.schema_version == m.SCHEMA_VERSION


def test_from_json_rejects_bad_schema():
    import pytest
    with pytest.raises(ValueError):
        m.Manifest.from_json('{"schema_version": 999, "type": "file"}')


def test_write_then_read(tmp_path):
    parcel = tmp_path / "summon_parcel"
    parcel.mkdir()
    man = m.Manifest(type="text", name="message.md", suggested_path="./message.md",
                     sender="p", recipient="", created_at="t",
                     payload_sha256="y" * 64, size_bytes=1, file_count=1)
    m.write_manifest(parcel, man)
    assert m.read_manifest(parcel) == man
