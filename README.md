# Spellbook

A bundle of Claude Code skills. Each skill is self-contained under `skills/<name>/`,
so new skills can be added in parallel without coupling.

## Skills

### ✨ Summon
Securely teleport a **file**, **folder**, a whole **Claude skill**, or a chunk of
**text/context** to a teammate's Claude. End-to-end encrypted via
[croc](https://github.com/schollz/croc); each transfer is unlocked by a short
spoken **incantation** — three easy words like `brim-gloss-kite`, made to be said
out loud.

- **Send:** ask Claude *"send this file to a teammate"* / *"share this skill"*. Claude
  binds it and copies a one-line incantation to your clipboard — pass it to your
  teammate over Slack/voice.
- **Receive:** ask Claude *"summon `<incantation>`"*. It fetches into a quarantine,
  shows you what arrived (origin is *not* cryptographically proven), and only
  writes to disk after you confirm.

Requires `croc` (`brew install croc`) on both ends. A teammate without the skill can
still receive with `brew install croc && croc <incantation>`.

**Optional hardening:** set a shared `SUMMON_SALT` env var (same value for you and a
teammate) and it's mixed into every incantation automatically. You still speak only
the 3 words, but someone who overhears them can't receive without also knowing the
salt. Leave it unset for zero-setup use.

## Install

### Option A — Claude Code plugin (recommended)

```
/plugin marketplace add pkronstrom/spellbook
/plugin install spellbook@spellbook
```

The first command registers this repo as a plugin marketplace; the second installs
the `spellbook` plugin (which provides the Summon skill). Update later with
`/plugin marketplace update spellbook`.

> Replace `pkronstrom/spellbook` with your fork's `owner/repo` if different. You can
> also point at a full URL: `/plugin marketplace add https://github.com/pkronstrom/spellbook`.

### Option B — manual (single skill, no plugin)

```sh
git clone https://github.com/pkronstrom/spellbook ~/src/spellbook
mkdir -p ~/.claude/skills
cp -R ~/src/spellbook/skills/summon ~/.claude/skills/summon
brew install croc
```

Then just talk to Claude ("send this file to …").

## Layout

```
spellbook/
  .claude-plugin/
    plugin.json        # plugin metadata
    marketplace.json   # makes the repo installable as a marketplace
  skills/
    summon/
      SKILL.md         # how Claude drives the skill
      summon.sh        # thin POSIX-sh wrapper around croc
      wordlist.txt     # spoken-friendly words for incantations
```

## Design

Summon deliberately leans on `croc` for code generation, encryption, NAT
traversal, folder packaging, and integrity. `summon.sh` only adds ergonomics:
backgrounded send + code capture, a clipboard share line, and a
quarantine → review → safe-place receive flow. Runtime dependencies are just
**croc** and **sh** — nothing else.

## Credits

- [croc](https://github.com/schollz/croc) by Zack Scholl — the secure transfer engine.
- `skills/summon/wordlist.txt` is derived from the
  [EFF Short Wordlist](https://www.eff.org/dice) by the Electronic Frontier
  Foundation, licensed under [CC BY 3.0 US](https://creativecommons.org/licenses/by/3.0/us/).

## License

[MIT](LICENSE) © Peter Kronström
