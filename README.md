# Spellbook

A bundle of Claude Code skills. Each skill is self-contained under `skills/<name>/`,
so new skills can be added in parallel without coupling.

## Skills

### ✨ Summon
Securely send a **file**, **folder**, or any **content** to a teammate's Claude.
End-to-end encrypted via [croc](https://github.com/schollz/croc); each transfer is
unlocked by a short spoken **incantation** — three easy words like `brim-gloss-kite`,
made to be said out loud.

- **Send:** ask Claude *"send this file to a teammate"* / *"share this with the team"*.
  Claude serves it and copies a one-line incantation to your clipboard — pass it to
  your teammate over Slack/voice.
- **Receive:** ask Claude *"summon `<incantation>`"*. It downloads into a temp dir,
  shows you what arrived (origin is *not* cryptographically proven), and — once you
  confirm — places it where you want.

Requires `croc` (`brew install croc`) on both ends. A teammate without the skill can
still receive with `brew install croc && croc <incantation>`.

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

Summon deliberately leans on `croc` for everything croc already does — encryption,
NAT traversal, folder packaging, integrity. `summon.sh` (~100 lines) only adds
ergonomics: a spoken 3-word incantation, a clipboard share line, and a `receive`
that stages the download into a temp dir and hands the path back to Claude, which
places the files wherever you want. It never writes to your working directory and
never deletes anything. Runtime dependencies are just **croc** and **sh**.

## Credits

- [croc](https://github.com/schollz/croc) by Zack Scholl — the secure transfer engine.
- `skills/summon/wordlist.txt` is derived from the
  [EFF Short Wordlist](https://www.eff.org/dice) by the Electronic Frontier
  Foundation, licensed under [CC BY 3.0 US](https://creativecommons.org/licenses/by/3.0/us/).

## License

[MIT](LICENSE) © Peter Kronström
