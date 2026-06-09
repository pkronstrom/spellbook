import os
import re
from pathlib import Path

_CONTROL = re.compile(r"[\x00-\x1f\x7f]")
_MAX_DISPLAY = 200


def summon_home() -> Path:
    return Path(os.environ.get("SUMMON_HOME", str(Path.home() / ".summon")))


def sends_dir() -> Path:
    return summon_home() / "sends"


def ensure_dirs() -> None:
    sends_dir().mkdir(parents=True, exist_ok=True)


def user_skills_dir() -> Path:
    return Path.home() / ".claude" / "skills"


def sanitize_display(text: str) -> str:
    """Make an untrusted string safe to print in a terminal verify card."""
    cleaned = _CONTROL.sub(" ", text).strip()
    if len(cleaned) > _MAX_DISPLAY:
        cleaned = cleaned[: _MAX_DISPLAY - 1] + "…"
    return cleaned


def safe_name(name: str) -> str:
    """Reduce an untrusted name to a single safe path component.

    Splits on path separators, drops traversal segments (``.`` / ``..``),
    and joins the rest with underscores.
    """
    cleaned = _CONTROL.sub("", name).strip()
    parts = []
    for seg in re.split(r"[\\/]+", cleaned):
        seg = seg.strip()
        if seg in ("", ".", ".."):
            continue
        parts.append(seg)
    return "_".join(parts) or "unnamed"
