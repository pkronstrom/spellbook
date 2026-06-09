import shutil
import tempfile
from pathlib import Path

from summon_core import manifest as m
from summon_core.paths import user_skills_dir

PARCEL_NAME = "summon_parcel"
_SKILL_EXCLUDE = shutil.ignore_patterns(".git", "__pycache__", ".DS_Store", "*.pyc")


def resolve_skill(name_or_path: str) -> Path:
    """Find a skill dir. Search order: ./.claude/skills, then ~/.claude/skills."""
    candidate = Path(name_or_path).expanduser()
    if candidate.is_dir() and (candidate / "SKILL.md").exists():
        return candidate
    for root in (Path.cwd() / ".claude" / "skills", user_skills_dir()):
        hit = root / name_or_path
        if hit.is_dir() and (hit / "SKILL.md").exists():
            return hit
    raise FileNotFoundError(
        f"no skill named {name_or_path!r} (looked in ./.claude/skills, ~/.claude/skills)"
    )


def build_bundle(*, kind: str, value, sender: str, recipient: str, note: str,
                 created_at: str) -> Path:
    """Create <tmp>/summon_parcel/{manifest.json, payload/...} and return the parcel dir."""
    root = Path(tempfile.mkdtemp(prefix="summon-bundle-"))
    parcel = root / PARCEL_NAME
    payload = parcel / m.PAYLOAD_DIRNAME
    payload.mkdir(parents=True)

    if kind == "text":
        name = "message.md"
        suggested = "./message.md"
        (payload / name).write_text(str(value), encoding="utf-8")
    elif kind == "file":
        src = Path(value).expanduser()
        if not src.is_file():
            raise FileNotFoundError(f"not a file: {src}")
        name = src.name
        suggested = f"./{name}"
        shutil.copy2(src, payload / name)
    elif kind == "folder":
        src = Path(value).expanduser()
        if not src.is_dir():
            raise FileNotFoundError(f"not a folder: {src}")
        name = src.name
        suggested = f"./{name}"
        shutil.copytree(src, payload / name, ignore=_SKILL_EXCLUDE, symlinks=False)
    elif kind == "skill":
        src = resolve_skill(str(value))
        name = src.name
        suggested = f"{user_skills_dir()}/{name}/"
        shutil.copytree(src, payload / name, ignore=_SKILL_EXCLUDE, symlinks=False)
    else:
        raise ValueError(f"unknown kind: {kind}")

    sha, size, count = m.payload_digest(payload)
    man = m.Manifest(
        type=kind, name=name, suggested_path=suggested, sender=sender,
        recipient=recipient, created_at=created_at, note=note,
        payload_sha256=sha, size_bytes=size, file_count=count,
    )
    m.write_manifest(parcel, man)
    return parcel
