import shutil
import subprocess
from pathlib import Path


class CrocMissing(Exception):
    pass


def ensure_croc() -> str:
    path = shutil.which("croc")
    if not path:
        raise CrocMissing("croc not found. Install with: brew install croc")
    return path


def start_send(incantation: str, parcel_dir: Path, log_path: Path) -> int:
    """Launch a detached `croc send` and return its pid. Does not block."""
    ensure_croc()
    log = open(log_path, "wb")
    proc = subprocess.Popen(
        ["croc", "send", "--code", incantation, "--yes", str(parcel_dir)],
        stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
        start_new_session=True,
    )
    return proc.pid


def receive(incantation: str, out_dir: Path, timeout: int = 600) -> None:
    """Blocking `croc receive` into out_dir (an empty quarantine)."""
    ensure_croc()
    subprocess.run(
        ["croc", "--yes", "--overwrite", "--out", str(out_dir), incantation],
        check=True, timeout=timeout, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
