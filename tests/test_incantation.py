from summon_core import incantation


def test_load_words_nonempty():
    words = incantation.load_words()
    assert len(words) >= 12
    assert all(w == w.strip() and w.islower() and "-" not in w for w in words)


def test_gen_incantation_shape():
    code = incantation.gen_incantation()
    parts = code.split("-")
    assert len(parts) == 4
    assert all(p in incantation.load_words() for p in parts)


def test_gen_incantation_uses_csprng(monkeypatch):
    calls = {"n": 0}
    real_choice = incantation.secrets.choice

    def counting_choice(seq):
        calls["n"] += 1
        return real_choice(seq)

    monkeypatch.setattr(incantation.secrets, "choice", counting_choice)
    incantation.gen_incantation(n=4)
    assert calls["n"] == 4  # one CSPRNG draw per word, never the model


def test_gen_incantation_custom_length():
    assert len(incantation.gen_incantation(n=3).split("-")) == 3
