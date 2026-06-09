import hashlib
import json
from dataclasses import dataclass, asdict, field
from pathlib import Path

from summon_core import __version__

SCHEMA_VERSION = 1
PAYLOAD_DIRNAME = "payload"
MANIFEST_NAME = "manifest.json"
VALID_TYPES = {"file", "folder", "skill", "text"}


def payload_digest(payload_dir: Path) -> tuple[str, int, int]:
    """Deterministic (sha256_hex, total_bytes, file_count) over a payload tree."""
    h = hashlib.sha256()
    total = 0
    count = 0
    files = sorted(
        (p for p in payload_dir.rglob("*") if p.is_file() and not p.is_symlink()),
        key=lambda p: p.relative_to(payload_dir).as_posix(),
    )
    for p in files:
        rel = p.relative_to(payload_dir).as_posix()
        data = p.read_bytes()
        h.update(rel.encode("utf-8"))
        h.update(b"\0")
        h.update(hashlib.sha256(data).digest())
        total += len(data)
        count += 1
    return h.hexdigest(), total, count


@dataclass
class Manifest:
    type: str
    name: str
    suggested_path: str
    sender: str
    recipient: str
    created_at: str
    payload_sha256: str
    size_bytes: int
    file_count: int
    note: str = ""
    payload_path: str = PAYLOAD_DIRNAME
    schema_version: int = SCHEMA_VERSION
    created_by_version: str = field(default_factory=lambda: f"summon/{__version__}")

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2, sort_keys=True)

    @classmethod
    def from_json(cls, text: str) -> "Manifest":
        data = json.loads(text)
        if data.get("schema_version") != SCHEMA_VERSION:
            raise ValueError(f"unsupported schema_version: {data.get('schema_version')}")
        if data.get("type") not in VALID_TYPES:
            raise ValueError(f"invalid type: {data.get('type')}")
        allowed = {f for f in cls.__dataclass_fields__}
        return cls(**{k: v for k, v in data.items() if k in allowed})


def write_manifest(parcel_dir: Path, manifest: Manifest) -> None:
    (parcel_dir / MANIFEST_NAME).write_text(manifest.to_json(), encoding="utf-8")


def read_manifest(parcel_dir: Path) -> Manifest:
    return Manifest.from_json((parcel_dir / MANIFEST_NAME).read_text(encoding="utf-8"))
