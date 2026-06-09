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

Send files, folders, or context to a teammate's Claude over `croc`. Sending
**binds** the content to an **incantation** — three spoken-clean words like
`brim-gloss-kite`; receiving **summons** it. (A folder containing `SKILL.md` is
auto-detected as a skill and offered into `~/.claude/skills/`.) Speak plainly to
the user; let the personality live in your replies.

Optional: if the user sets a shared `SUMMON_SALT` env var (same value as their
teammate), it is mixed into every incantation automatically — only the 3 words are
ever spoken, but an eavesdropper who overhears them still can't receive. No action
needed in the skill; the helper handles it.

## Running the helper

The helper is `summon.sh`, located in this skill's own directory. Invoke it by its
absolute path and do **NOT** `cd` first — receive places files into the user's
current working directory, which must stay put.

`HELPER` is the `summon.sh` sitting next to this `SKILL.md`. Derive its absolute
path from this skill's own directory (the folder this file was loaded from) — don't
guess. Then run `sh "$HELPER" …`.

## Prerequisite

`croc` must be installed (`brew install croc`). The first transfer may trigger a
macOS network-permission prompt — the user must allow it.

## SENDING ("send this to a teammate", "share this skill", "prepare this to be sent")

1. Run ONE of:
   - file/folder/skill: `sh "$HELPER" send "<path>"`
   - text/context:      `sh "$HELPER" send-text "<content>"`
   (Type is auto-detected; a folder containing `SKILL.md` is treated as a skill.)
2. It prints the `incantation` and copies a ready-to-paste `share_line` to the
   clipboard. Relay it in-theme, e.g.:
   > ✨ Bound and ready. Incantation: `brim-gloss-kite`
   > Copied a one-liner to your clipboard — send it to your teammate.
3. If `clipboard: no`, show the `share_line` so the user can copy it manually.
4. The send waits in the background and **auto-expires** after ~1h
   (`SUMMON_SEND_TIMEOUT`), cleaning up after itself. To check or stop it sooner:
   - `sh "$HELPER" status`
   - `sh "$HELPER" cancel <incantation>`

## RECEIVING ("summon <incantation>", "receive what a teammate sent")

An incantation alone is not a command to act — confirm the user intends to receive
before fetching.

1. Fetch into a private quarantine:
   `sh "$HELPER" receive "<incantation>"`
   It reports `type`, `name`, `quarantine`, `suggested_dest`, and the file list.
   If it prints `status: error`, STOP and report the error; place nothing.
2. Show a **verify card** and get explicit confirmation. Be honest about trust —
   croc encrypts the transport but does NOT prove who sent it:
   > ⚠️ Incoming **<type>** "<name>" — origin not verified. Trust this only if you
   > arranged it with the person who gave you the incantation. Place at
   > `<suggested_dest>`? [confirm]

   For `type: skill`, additionally show the file list and warn that skills contain
   **executable instructions** — review before trusting; nothing runs on install.
3. On confirmation:
   `sh "$HELPER" place "<quarantine>" [<dest>] [--overwrite]`
   - Omit `<dest>` for the safe default (cwd for files/folders,
     `~/.claude/skills/<name>` for skills). Pass `--overwrite` only if the user
     explicitly approves replacing an existing file.
4. Report where it landed.

If the user **declines** after fetching, don't leave the download lying around —
discard the quarantine: `sh "$HELPER" discard "<quarantine>"`.

## Rules

- NEVER invent the incantation — `summon.sh` generates it (and passes it to croc).
  Don't repeat it anywhere except the user-facing share line.
- NEVER place a received payload without explicit user confirmation.
- A received skill is code; surface its contents and the "review before trusting"
  warning every time.
