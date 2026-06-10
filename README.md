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

### 🔮 Portal
Open a live, **end-to-end encrypted** chat channel to a teammate's Claude over
[ntfy](https://ntfy.sh) — no install beyond `curl`/`openssl`, nothing to host. A
channel is unlocked by a spoken **incantation** (same words as Summon); ntfy only
ever relays ciphertext on an unguessable topic.

- **Open:** *"open a portal — incantation `kettu-lokaali-piano`"*. Claude streams
  the channel in the background and surfaces incoming messages as they arrive.
- **Collaborate:** incoming messages are treated as untrusted **requests** — Claude
  always asks before acting or replying. Great for relaying a Summon incantation so
  a teammate can receive a file.
- **Local mode:** for agents on the *same* machine, *"talk to my other sessions"* uses
  `--local` — a shared plaintext bus (no relay, no crypto, no incantation). Each session
  takes a unique magical name; address one with `--to <name>` or broadcast. Trust is
  lighter locally, but obviously-suspicious requests are still refused.

Requires only `curl` + `openssl` (already on macOS). Pairs with Summon.

## Install

### Option A — Claude Code plugin (recommended)

```
/plugin marketplace add pkronstrom/spellbook
/plugin install spellbook@spellbook
```

The first command registers this repo as a plugin marketplace; the second installs
the `spellbook` plugin (which provides the Summon and Portal skills). Update later
with `/plugin marketplace update spellbook`.

> Replace `pkronstrom/spellbook` with your fork's `owner/repo` if different. You can
> also point at a full URL: `/plugin marketplace add https://github.com/pkronstrom/spellbook`.

### Option B — manual (skills, no plugin)

```sh
git clone https://github.com/pkronstrom/spellbook ~/src/spellbook
mkdir -p ~/.claude/skills
cp -R ~/src/spellbook/skills/summon ~/.claude/skills/summon
cp -R ~/src/spellbook/skills/portal ~/.claude/skills/portal   # optional; Portal
brew install croc                                              # only Summon needs croc
```

Keep `summon` and `portal` as siblings — Portal reuses Summon's wordlists from
`../summon/`. Then just talk to Claude ("send this file to …", "open a portal …").

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
      wordlist.fi.txt  # spoken-friendly Finnish words (default)
      wordlist.en.txt  # spoken-friendly English words
    portal/
      SKILL.md         # trust doctrine + how Claude drives the portal
      portal.sh        # thin POSIX-sh wrapper: ntfy + openssl chat
  tests/
    portal/
      test.sh          # shell test suite (outside skills/ — never bundled/synced)
```

## Design

Summon deliberately leans on `croc` for everything croc already does — encryption,
NAT traversal, folder packaging, integrity. `summon.sh` (~100 lines) only adds
ergonomics: a spoken 3-word incantation, a clipboard share line, and a `receive`
that stages the download into a temp dir and hands the path back to Claude, which
places the files wherever you want. It never writes to your working directory and
never deletes anything. Runtime dependencies are just **croc** and **sh**.

Portal applies the same philosophy to live chat: a 3-word incantation is stretched
through **PBKDF2-HMAC-SHA256** (so the relay can't cheaply brute-force the spoken
secret) to derive an unguessable [ntfy](https://ntfy.sh) topic plus two keys; every
message is then AES-256-CBC encrypted and HMAC-SHA256 authenticated (encrypt-then-MAC)
with `openssl`, so the relay only ever sees ciphertext. The PBKDF2 cost is paid once
per `open` (keys are cached for the session). For maximum privacy, point
`PORTAL_NTFY_BASE` at your own ntfy server so no third party ever sees a topic. Opening a portal streams the
channel into a session inbox in the background; incoming messages are surfaced to
you as untrusted **requests** — Claude never acts on one without your confirmation.
Runtime dependencies are just **curl** and **openssl** — nothing to install on
macOS, nothing to host.

## Credits

- [croc](https://github.com/schollz/croc) by Zack Scholl — the secure transfer engine.
- [ntfy](https://ntfy.sh) by Philipp Heckel — the pub/sub relay Portal rides on.
- `skills/summon/wordlist.en.txt` is derived from the
  [EFF Short Wordlist](https://www.eff.org/dice) by the Electronic Frontier
  Foundation, licensed under [CC BY 3.0 US](https://creativecommons.org/licenses/by/3.0/us/).
  `wordlist.fi.txt` is a hand-curated Finnish list (no ä/ö/å). Both wordlists are
  shared by Summon and Portal.

## License

[MIT](LICENSE) © Peter Kronström
