import secrets
from functools import lru_cache
from pathlib import Path

_WORDLIST = Path(__file__).parent / "data" / "wordlist.txt"


@lru_cache(maxsize=1)
def load_words() -> tuple[str, ...]:
    words = []
    for line in _WORDLIST.read_text(encoding="utf-8").splitlines():
        w = line.strip().lower()
        if w and "-" not in w and w.isalpha():
            words.append(w)
    if len(words) < 12:
        raise RuntimeError(f"wordlist too small: {len(words)} words in {_WORDLIST}")
    return tuple(words)


def gen_incantation(n: int = 4) -> str:
    """Return an n-word, dash-joined code chosen with a CSPRNG. Never model-chosen."""
    words = load_words()
    return "-".join(secrets.choice(words) for _ in range(n))
