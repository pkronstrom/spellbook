import shutil
from pathlib import Path

from summon_core import manifest as m
from summon_core.paths import safe_name, user_skills_dir


class UnsafePayload(Exception):
    pass


class UnsafeDestination(Exception):
    pass


def _payload_root(parcel_dir: Path) -> Path:
    return parcel_dir / m.PAYLOAD_DIRNAME


def scan_payload_safe(payload_dir: Path) -> list[str]:
    """Reject symlinks / escapes; return sorted relative listing of files."""
    base = payload_dir.resolve()
    listing: list[str] = []
    for p in sorted(payload_dir.rglob("*"), key=lambda x: x.as_posix()):
        if p.is_symlink():
            raise UnsafePayload(f"symlink in payload: {p.relative_to(payload_dir)}")
        real = p.resolve()
        if base != real and base not in real.parents:
            raise UnsafePayload(f"path escapes payload: {p}")
        if p.is_file():
            listing.append(p.relative_to(payload_dir).as_posix())
    return listing


def _allowed_root(manifest: m.Manifest, cwd: Path) -> Path:
    if manifest.type == "skill":
        return user_skills_dir().resolve()
    return cwd.resolve()


def default_dest(manifest: m.Manifest, cwd: Path) -> Path:
    return _allowed_root(manifest, cwd) / safe_name(manifest.name)


def _conflict_free(dest: Path) -> Path:
    if not dest.exists():
        return dest
    stem, suffix = dest.stem, dest.suffix
    n = 2
    while True:
        cand = dest.with_name(f"{stem} ({n}){suffix}")
        if not cand.exists():
            return cand
        n += 1


def _the_thing(parcel_dir: Path, manifest: m.Manifest) -> Path:
    """The path inside payload/ to move out.

    file/text -> the single file; folder/skill -> the directory.
    """
    return _payload_root(parcel_dir) / safe_name(manifest.name)


def place_parcel(parcel_dir: Path, manifest: m.Manifest, dest: Path,
                 overwrite: bool) -> Path:
    payload = _payload_root(parcel_dir)
    scan_payload_safe(payload)

    cwd = Path.cwd()
    root = _allowed_root(manifest, cwd)
    dest = dest.resolve()
    if root != dest and root not in dest.parents:
        raise UnsafeDestination(f"{dest} is outside allowed root {root}")

    root.mkdir(parents=True, exist_ok=True)
    source = _the_thing(parcel_dir, manifest)
    if not source.exists():
        raise UnsafePayload(f"expected payload entry missing: {source.name}")

    if dest.exists():
        if overwrite:
            if dest.is_dir() and not dest.is_symlink():
                shutil.rmtree(dest)
            else:
                dest.unlink()
        else:
            dest = _conflict_free(dest)

    shutil.move(str(source), str(dest))
    return dest
