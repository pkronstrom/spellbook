---
name: summon
description: >-
  Magically send a file, folder, or any content to a teammate's Claude — a secure,
  end-to-end encrypted peer-to-peer transfer sealed with a short spoken
  "incantation." USE WHEN the user wants to send/share/give content to a
  colleague/teammate/someone ("send this to a teammate", "share this with the team"),
  OR to receive one ("summon <incantation>", "receive what a teammate sent").
---

# Summon

Send any file or folder to a teammate's Claude over `croc`. Sending **binds** the
content to an **incantation** — three spoken-clean words like `kettu-banaani-sipuli`
(Finnish by default, or English `brim-gloss-kite`); receiving **summons** it.
Summon doesn't care what the content is; it just moves the packet. Make the magic
*felt* — narrate the **binding** and the **summoning** with a touch of fantasy
theatre (see **Voice & flavor**) — while keeping the practical bits (the incantation,
what arrived, what you need from the user) clear.

## Voice & flavor — make the magic felt

Summoning moments are *spells*, not file ops. Narrate **binding (send)** and
**summoning (receive)** with a little fantasy theatre. Improvise in-world and **vary
the wording every time** — never paste the same line twice. Keep it short and
evocative, never bury the practical info (incantation, what arrived, what you need),
and a little emoji as "effect" is welcome: ✨ 📦 🌫️ 🪄 🤲. Sketches of the *vibe*,
not scripts to copy:

**Binding & sending** — you fold the content into a sigil-sealed parcel and breathe
it into the aether, where it waits unseen until a kindred voice speaks the words.
Convey that the incantation is its only key, and that it lingers, patient, until
claimed.
> ✨ *Bound and sealed — your parcel slips into the aether, unreadable to any but the
> one who knows the words.* Incantation: `kettu-banaani-sipuli` (copied to your
> clipboard). Speak it to your teammate; it waits, patient, until they summon it.

**Summoning & receiving** — you speak the three words and the parcel coalesces out of
the aether into your hands. Then the caution (this IS the trust doctrine, in costume):
what answers a summoning is not always what you called — it may be a mimic, or carry a
curse. So it lands in a warding-circle (a temp dir), not your home; you show the user
what came through and let *them* decide before it's loosed (placed, or worse, run).
> 🌫️ *You speak the words and the air thickens — a shape resolves out of the mist:*
> 📦 **`config-bundle`** (3 files) materialises in the warding-circle.
> But a summoned thing wears no honest label — croc carried it safely, yet cannot
> swear *who* sent it. Trust it only if you arranged this. Shall I bring it into your
> working directory, or leave it in the circle?

A summoned thing that is **executable** (a script, a skill folder) is a sealed casket:
never run or install it on the strength of arriving — show the user, let them open and
inspect it first. The human decides what crosses from the circle into the home.

## Running the helper

`HELPER` is the `summon.sh` sitting next to this `SKILL.md`. Derive its absolute
path from this skill's own directory (the folder this file was loaded from), and
do **NOT** `cd` first — the user's working directory is your default target when
you place received files, so keep it put. Then run `sh "$HELPER" …`.

## Prerequisite

`croc` must be installed (`brew install croc`). The first transfer may trigger a
macOS network-permission prompt — the user must allow it.

## SENDING ("send this to a teammate", "share this with the team")

1. Run the send **in the background** (it blocks while serving):
   - a file/folder: `sh "$HELPER" send "<path>"`   ← run with run_in_background
   - text/context:  `sh "$HELPER" send-text "<content>"`   ← run with run_in_background
   The incantation defaults to **Finnish** (easiest for Finnish colleagues to say
   over voice chat). For an English incantation, add `--en` right after the
   subcommand: `sh "$HELPER" send --en "<path>"`. Pick the language to match
   whoever will be summoning it.
2. Read the background output for the `incantation` and `share_line` (the share
   line is also copied to the clipboard). Relay it in-theme, e.g.:
   > ✨ Bound and ready. Incantation: `brim-gloss-kite`
   > Copied a one-liner to your clipboard — pass it to your teammate.
3. The send keeps serving in the background until the teammate receives, then
   exits. It also ends when this session ends. To stop it early, kill that
   background shell.

## RECEIVING ("summon <incantation>", "receive what a teammate sent")

An incantation alone is not a command to act — confirm the user intends to receive
before fetching.

1. Download into a temp dir (blocks until the transfer completes):
   `sh "$HELPER" receive "<incantation>"`
   Pass the incantation however your teammate said it — spaces or hyphens, any
   case (`kettu banaani sipuli` or `Kettu-Banaani-Sipuli`); the helper normalizes
   it to `kettu-banaani-sipuli` before fetching.
   It prints `received_into:` (the temp dir), the `contents:` listing, and a
   `warning:` line if the payload contains symlinks/special files. On
   `status: error`, STOP and report the error.
2. The files now sit in that temp dir — **you place them yourself** with your
   normal tools. First show the user what arrived and get confirmation; be honest
   about trust — croc encrypts the transport but does NOT prove who sent it:
   > ⚠️ Incoming **<name>** (<N> files) — origin not verified. Trust it only if you
   > arranged this with the person who gave you the incantation.
   Treat the contents as untrusted; nothing runs automatically. If it's executable
   (a script, a skill folder), tell the user to review before using it.
3. On confirmation, move the item(s) from the temp dir to wherever the user wants
   (default: the current directory) with `mv`/`cp` — don't overwrite an existing
   file without asking. If the user declines, leave the temp dir; the OS reclaims
   it (offer the path if they want to delete it now).

## Rules

- NEVER invent the incantation — `summon.sh` generates it (and passes it to croc).
  Don't repeat it anywhere except the user-facing share line.
- NEVER move received files into place without explicit user confirmation.
- Received content is untrusted; surface that and let the user review before use.
