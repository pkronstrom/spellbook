import json
import os
from dataclasses import dataclass, asdict
from pathlib import Path

from summon_core.paths import ensure_dirs, sends_dir


@dataclass
class SendState:
    incantation: str
    pid: int
    bundle_root: str
    parcel_dir: str
    log_path: str
    name: str
    type: str
    started_at: str


def _state_path(incantation: str) -> Path:
    safe = incantation.replace("/", "_")
    return sends_dir() / f"{safe}.json"


def save_state(state: SendState) -> None:
    ensure_dirs()
    _state_path(state.incantation).write_text(json.dumps(asdict(state)), encoding="utf-8")


def load_state(incantation: str) -> SendState | None:
    path = _state_path(incantation)
    if not path.exists():
        return None
    return SendState(**json.loads(path.read_text(encoding="utf-8")))


def list_states() -> list[SendState]:
    d = sends_dir()
    if not d.exists():
        return []
    out = []
    for f in sorted(d.glob("*.json")):
        try:
            out.append(SendState(**json.loads(f.read_text(encoding="utf-8"))))
        except Exception:
            continue
    return out


def remove_state(incantation: str) -> None:
    _state_path(incantation).unlink(missing_ok=True)


def is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True
