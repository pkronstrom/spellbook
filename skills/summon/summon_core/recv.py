import sys as _sys
import pathlib as _pathlib

# Make `import summon_core` work when run by absolute path from the user's cwd.
_sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1]))

import argparse
import json
import shutil
import tempfile
from pathlib import Path

from summon_core import croc, manifest as m, placement
from summon_core.bundle import PARCEL_NAME
from summon_core.paths import sanitize_display


def _find_parcel(quarantine: Path) -> Path | None:
    direct = quarantine / PARCEL_NAME
    if direct.is_dir():
        return direct
    subs = [p for p in quarantine.iterdir() if p.is_dir()]
    return subs[0] if len(subs) == 1 else None


def _fetch(args) -> int:
    croc.ensure_croc()
    quarantine = Path(tempfile.mkdtemp(prefix="summon-quarantine-"))
    try:
        croc.receive(args.incantation, quarantine)
    except Exception as e:
        shutil.rmtree(quarantine, ignore_errors=True)
        print(json.dumps({"verified": False, "error": f"transfer failed: {e}"}))
        return 1

    parcel = _find_parcel(quarantine)
    if parcel is None:
        print(json.dumps({"verified": False, "error": "no parcel found",
                          "parcel_dir": str(quarantine)}))
        return 1

    try:
        man = m.read_manifest(parcel)
    except Exception as e:
        files = [p.relative_to(parcel).as_posix() for p in parcel.rglob("*") if p.is_file()]
        print(json.dumps({"verified": False, "error": f"no/invalid manifest: {e}",
                          "type": "opaque", "parcel_dir": str(parcel),
                          "listing": sorted(files)}, indent=2))
        return 1

    payload = parcel / m.PAYLOAD_DIRNAME
    sha, size, count = m.payload_digest(payload)
    if (sha, size, count) != (man.payload_sha256, man.size_bytes, man.file_count):
        shutil.rmtree(quarantine, ignore_errors=True)
        print(json.dumps({"verified": False, "error": "integrity check failed"}))
        return 1

    try:
        listing = placement.scan_payload_safe(payload)
    except placement.UnsafePayload as e:
        shutil.rmtree(quarantine, ignore_errors=True)
        print(json.dumps({"verified": False, "error": f"unsafe payload: {e}"}))
        return 1

    print(json.dumps({
        "verified": True,
        "parcel_dir": str(parcel),
        "listing": listing,
        "manifest": {
            "type": man.type,
            "name": sanitize_display(man.name),
            "sender_display": sanitize_display(man.sender),
            "recipient_display": sanitize_display(man.recipient),
            "note_display": sanitize_display(man.note),
            "size_bytes": man.size_bytes,
            "file_count": man.file_count,
            "suggested_path": man.suggested_path,
        },
        "note": "origin NOT cryptographically verified — trust only via your side channel",
    }, indent=2))
    return 0


def _place(args) -> int:
    parcel = Path(args.parcel)
    man = m.read_manifest(parcel)
    dest = Path(args.dest).expanduser() if args.dest else placement.default_dest(man, Path.cwd())
    try:
        placed = placement.place_parcel(parcel, man, dest, overwrite=args.overwrite)
    except (placement.UnsafePayload, placement.UnsafeDestination) as e:
        print(json.dumps({"placed": False, "error": str(e)}))
        return 1
    finally:
        # parcel lives in a quarantine temp dir; clean its root after placing.
        shutil.rmtree(parcel.parent, ignore_errors=True)
    print(json.dumps({"placed": True, "placed_path": str(placed), "type": man.type}))
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="summon_core.recv")
    sub = p.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fetch")
    f.add_argument("incantation")
    f.set_defaults(fn=_fetch)

    pl = sub.add_parser("place")
    pl.add_argument("--parcel", required=True)
    pl.add_argument("--dest", default=None)
    pl.add_argument("--overwrite", action="store_true")
    pl.set_defaults(fn=_place)

    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
