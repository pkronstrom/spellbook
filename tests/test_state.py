import os

from summon_core import state


def _mk(incantation="a-b-c-d", pid=None):
    return state.SendState(
        incantation=incantation, pid=pid or os.getpid(),
        bundle_root="/tmp/x", parcel_dir="/tmp/x/summon_parcel",
        log_path="/tmp/x.log", name="report.md", type="file",
        started_at="2026-06-09T00:00:00Z",
    )


def test_save_load_remove():
    s = _mk()
    state.save_state(s)
    assert state.load_state("a-b-c-d") == s
    assert s in state.list_states()
    state.remove_state("a-b-c-d")
    assert state.load_state("a-b-c-d") is None


def test_is_alive_current_process_true():
    assert state.is_alive(os.getpid()) is True


def test_is_alive_bogus_pid_false():
    assert state.is_alive(2**30) is False
