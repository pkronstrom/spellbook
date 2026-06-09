from pathlib import Path

import pytest

from summon_core import paths


def test_summon_home_uses_env(isolated_summon_home):
    assert paths.summon_home() == isolated_summon_home
    assert paths.sends_dir() == isolated_summon_home / "sends"


def test_user_skills_dir(fake_home):
    assert paths.user_skills_dir() == fake_home / ".claude" / "skills"


def test_sanitize_display_strips_control_and_truncates():
    assert paths.sanitize_display("hi\nthere\x00") == "hi there"
    assert len(paths.sanitize_display("x" * 500)) <= 200


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("report.md", "report.md"),
        ("../../etc/passwd", "etc_passwd"),
        ("a/b/c", "a_b_c"),
        ("", "unnamed"),
        ("   ", "unnamed"),
        (".", "unnamed"),
        ("..", "unnamed"),
    ],
)
def test_safe_name(raw, expected):
    assert paths.safe_name(raw) == expected
