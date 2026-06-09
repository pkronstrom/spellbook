#!/bin/sh
# summon.sh — thin wrapper around `croc` for the Summon skill.
#
# croc does the real work (E2E encryption, NAT traversal, folder zipping,
# integrity). This wrapper only adds: a spoken 3-word incantation, a clipboard
# share line, and a quarantine -> review -> place receive flow. It transfers any
# file or folder and does NOT care what the contents are.
#
# The incantation is 3 words from a bundled wordlist via /dev/urandom (the model
# never picks them), passed to croc as CROC_SECRET so the code is pure words with
# no number. Optional: set SUMMON_SALT (same value on both ends) to harden against
# someone overhearing the spoken words — it's mixed in transparently.
#
# `send` serves until the peer connects, then exits. Run it in the background
# (the agent's background shell); it ends when that shell / the session ends —
# there is nothing to daemonize, track, or clean up.
#
# Subcommands:
#   send <path>            serve a file/folder (blocks until received)
#   send-text <text>       serve a chunk of text/context
#   receive <incantation>  fetch into a private quarantine; report what arrived
#   place <quarantine> [--overwrite]   move the received item into the current dir
#   discard <quarantine>   delete a quarantine you don't want
#
# Output is simple `key: value` lines. `send` writes them to stderr (unbuffered,
# so they show immediately while it keeps serving); the rest write to stdout.

set -eu
umask 077

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WORDLIST="$SCRIPT_DIR/wordlist.txt"

die() { echo "status: error"; echo "error: $*"; exit 1; }
need_croc() { command -v croc >/dev/null 2>&1 || die "croc not found. Install with: brew install croc"; }
mktempdir() { mktemp -d "${TMPDIR:-/tmp}/summon.XXXXXX"; }

pick_word() { r="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"; sed -n "$(( (r % $1) + 1 ))p" "$WORDLIST"; }

gen_incantation() {
    [ -f "$WORDLIST" ] || die "wordlist missing: $WORDLIST"
    n="$(wc -l < "$WORDLIST" | tr -d ' ')"
    [ "$n" -gt 0 ] || die "wordlist is empty"
    printf '%s-%s-%s' "$(pick_word "$n")" "$(pick_word "$n")" "$(pick_word "$n")"
}

apply_salt() {
    if [ -n "${SUMMON_SALT:-}" ]; then printf '%s-%s' "$SUMMON_SALT" "$1"; else printf '%s' "$1"; fi
}

# First payload entry that is neither a regular file nor a directory
# (symlink, device, fifo, socket). Empty output means safe.
unsafe_entry() { find "$1" ! -type d ! -type f 2>/dev/null | head -n1; }

# Delete the quarantine and abort if it holds any non-regular file.
reject_unsafe() { [ -z "$(unsafe_entry "$1")" ] || { rm -rf "$1"; die "unsafe payload: non-regular file present"; }; }

# The single top-level item croc delivered into a quarantine dir (empty if 0 or >1).
received_entry() {
    set -- "$1"/*
    { [ "$#" -eq 1 ] && [ -e "$1" ]; } && printf '%s' "$1"
}

conflict_free() {
    dest="$1"
    [ ! -e "$dest" ] && { printf '%s' "$dest"; return; }
    case "$dest" in *.*) ext=".${dest##*.}"; base="${dest%.*}" ;; *) base="$dest"; ext="" ;; esac
    n=2
    while [ -e "${base} (${n})${ext}" ]; do n=$((n + 1)); done
    printf '%s' "${base} (${n})${ext}"
}

# --- send (blocks while serving; run it in the background) ------------------
do_send() {
    need_croc
    src="$1"
    [ -e "$src" ] || die "no such path: $src"
    name="$(basename "$src")"
    code="$(gen_incantation)"
    secret="$(apply_salt "$code")"
    if [ -n "${SUMMON_SALT:-}" ]; then
        share="Summon this: $code  ($name)"
    else
        share="Summon this: $code  ($name) — receive with: croc $code"
    fi
    clip="no"
    command -v pbcopy >/dev/null 2>&1 && printf '%s' "$share" | pbcopy && clip="yes"
    # On stderr: this process blocks on croc and never returns to flush a
    # block-buffered stdout pipe, but stderr is unbuffered — so the agent's
    # background reader sees the incantation immediately while croc serves.
    {
        echo "status: serving"
        echo "incantation: $code"
        echo "name: $name"
        echo "clipboard: $clip"
        echo "share_line: $share"
    } >&2
    CROC_SECRET="$secret" croc --yes send "$src" >&2
}

do_send_text() {
    need_croc
    tmp="$(mktempdir)"
    trap 'rm -rf "$tmp"' EXIT INT TERM
    printf '%s' "$1" > "$tmp/message.md"
    do_send "$tmp/message.md"
}

# --- receive / place / discard ---------------------------------------------
do_receive() {
    need_croc
    secret="$(apply_salt "$1")"
    q="$(mktempdir)"
    if ! CROC_SECRET="$secret" croc --yes --overwrite --out "$q" >"$q/.log" 2>&1; then
        msg="$(cat "$q/.log" 2>/dev/null)"; rm -rf "$q"; die "transfer failed: $msg"
    fi
    rm -f "$q/.log"
    reject_unsafe "$q"
    entry="$(received_entry "$q")"
    name="payload"; [ -n "$entry" ] && name="$(basename "$entry")"
    echo "status: ok"
    echo "name: $name"
    echo "quarantine: $q"
    echo "origin: not verified — croc encrypts the transfer but does not prove who sent it"
    echo "files:"
    (cd "$q" && find . -type f | sed 's|^\./|  |')
}

do_place() {
    q="$1"
    [ -d "$q" ] || die "no such quarantine: $q"
    overwrite="no"; [ "${2:-}" = "--overwrite" ] && overwrite="yes"
    reject_unsafe "$q"
    entry="$(received_entry "$q")"
    [ -n "$entry" ] || die "expected one received item; inspect $q manually"
    dest="$PWD/$(basename "$entry")"
    if [ -e "$dest" ] && [ "$overwrite" = "yes" ]; then rm -rf "$dest"
    elif [ -e "$dest" ]; then dest="$(conflict_free "$dest")"; fi
    mv "$entry" "$dest"
    rm -rf "$q"
    echo "status: ok"
    echo "placed: $dest"
}

do_discard() {
    q="$1"
    # guard rm -rf: the basename must be one of our mktemp quarantines
    case "${q##*/}" in summon.*) ;; *) die "not a summon quarantine: $q" ;; esac
    [ -d "$q" ] && rm -rf "$q"
    echo "status: ok"
    echo "discarded: $q"
}

# --- dispatch --------------------------------------------------------------
cmd="${1:-}"; [ "$#" -gt 0 ] && shift || true
case "$cmd" in
    send)       [ "$#" -ge 1 ] || die "usage: summon.sh send <path>"; do_send "$1" ;;
    send-text)  [ "$#" -ge 1 ] || die "usage: summon.sh send-text <text>"; do_send_text "$1" ;;
    receive)    [ "$#" -ge 1 ] || die "usage: summon.sh receive <incantation>"; do_receive "$1" ;;
    place)      [ "$#" -ge 1 ] || die "usage: summon.sh place <quarantine> [--overwrite]"; do_place "$@" ;;
    discard)    [ "$#" -ge 1 ] || die "usage: summon.sh discard <quarantine>"; do_discard "$1" ;;
    *)          die "unknown command: ${cmd:-(none)}. Use send|send-text|receive|place|discard" ;;
esac
