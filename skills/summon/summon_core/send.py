import sys as _sys
import pathlib as _pathlib

# Make `import summon_core` work when this file is run by absolute path
# (e.g. `python3 ~/.claude/skills/summon/summon_core/send.py ...`) from the
# user's own working directory.
_sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1]))

import argparse
import datetime as _dt
import json
import os
import shutil
import signal
import subprocess
import tempfile
from pathlib import Path

from summon_core import bundle, croc, state
from summon_core import manifest as m
from summon_core.incantation import gen_incantation
from summon_core.paths import sanitize_display


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def copy_clipboard(text: str) -> bool:
    pb = shutil.which("pbcopy")
    if not pb:
        return False
    try:
        subprocess.run([pb], input=text.encode("utf-8"), check=True)
        return True
    except Exception:
        return False


def share_line(incantation: str, *, sender: str, recipient: str, kind: str,
               name: str) -> str:
    who = f" for {sanitize_display(recipient)}" if recipient else ""
    return (
        f"Summon this from {sanitize_display(sender) or 'a teammate'}{who}: "
        f"{incantation}  ({kind}: {sanitize_display(name)})\n"
        f"No skill? brew install croc && croc {incantation}\n"
        f"(sensitive? the raw command lands in your shell history)"
    )


def _start(args) -> int:
    croc.ensure_croc()
    if args.text is not None:
        kind, value = "text", args.text
    elif args.file is not None:
        kind, value = "file", args.file
    elif args.folder is not None:
        kind, value = "folder", args.folder
    elif args.skill is not None:
        kind, value = "skill", args.skill
    else:
        print("error: one of --text/--file/--folder/--skill required", file=_sys.stderr)
        return 2

    parcel = bundle.build_bundle(
        kind=kind, value=value, sender=args.sender, recipient=args.recipient,
        note=args.note or "", created_at=_now(),
    )
    man = m.read_manifest(parcel)

    incantation = gen_incantation()
    log_path = Path(tempfile.mkstemp(prefix="summon-send-", suffix=".log")[1])
    pid = croc.start_send(incantation, parcel, log_path)

    st = state.SendState(
        incantation=incantation, pid=pid, bundle_root=str(parcel.parent),
        parcel_dir=str(parcel), log_path=str(log_path), name=man.name,
        type=man.type, started_at=_now(),
    )
    state.save_state(st)

    line = share_line(incantation, sender=args.sender, recipient=args.recipient,
                      kind=man.type, name=man.name)
    clip = copy_clipboard(line)
    print(json.dumps({
        "incantation": incantation, "type": man.type, "name": man.name,
        "share_line": line, "clipboard": clip, "pid": pid,
    }, indent=2))
    return 0


def _cancel(args) -> int:
    st = state.load_state(args.incantation)
    if st is None:
        print(json.dumps({"cancelled": False, "reason": "no such pending send"}))
        return 0
    try:
        os.kill(st.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    shutil.rmtree(st.bundle_root, ignore_errors=True)
    Path(st.log_path).unlink(missing_ok=True)
    state.remove_state(st.incantation)
    print(json.dumps({"cancelled": True, "incantation": st.incantation}))
    return 0


def _status(_args) -> int:
    pending = []
    for st in state.list_states():
        alive = state.is_alive(st.pid)
        if not alive:
            shutil.rmtree(st.bundle_root, ignore_errors=True)
            Path(st.log_path).unlink(missing_ok=True)
            state.remove_state(st.incantation)
            continue
        pending.append({"incantation": st.incantation, "name": st.name,
                        "type": st.type, "alive": alive, "started_at": st.started_at})
    print(json.dumps({"pending": pending}, indent=2))
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="summon_core.send")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("start")
    g = s.add_mutually_exclusive_group(required=True)
    g.add_argument("--text")
    g.add_argument("--file")
    g.add_argument("--folder")
    g.add_argument("--skill")
    s.add_argument("--sender", default="")
    s.add_argument("--recipient", default="")
    s.add_argument("--note", default="")
    s.set_defaults(fn=_start)

    c = sub.add_parser("cancel")
    c.add_argument("incantation")
    c.set_defaults(fn=_cancel)

    st = sub.add_parser("status")
    st.set_defaults(fn=_status)

    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
