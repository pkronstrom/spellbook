import os
from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def isolated_summon_home(tmp_path, monkeypatch):
    home = tmp_path / "summon_home"
    monkeypatch.setenv("SUMMON_HOME", str(home))
    return home


@pytest.fixture
def fake_home(tmp_path, monkeypatch):
    """A fake user home so ~/.claude/skills resolves inside tmp."""
    home = tmp_path / "home"
    (home / ".claude" / "skills").mkdir(parents=True)
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: home))
    return home


@pytest.fixture
def chtmp(tmp_path, monkeypatch):
    work = tmp_path / "work"
    work.mkdir()
    monkeypatch.chdir(work)
    return work
