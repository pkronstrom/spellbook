#!/bin/sh
# portal.sh — thin wrapper for end-to-end-encrypted agent-to-agent chat over ntfy.
#
# A channel is identified by a 3-word incantation (same wordlists as the summon
# skill). The incantation derives an unguessable ntfy topic plus two keys; every
# message is AES-256-CBC encrypted then HMAC-SHA256 authenticated (encrypt-then-
# MAC), so ntfy only ever relays ciphertext on a topic nobody can guess.
#
# Subcommands:
#   new [--fi|--en]            generate an incantation to share out-of-band
#   open <incantation>         stream the channel into a session inbox (BLOCKS; run in background)
#   send <incantation> <text> [--from <name>]   publish one message
#   read <incantation>         print inbox lines new since the last read
#   wait <incantation>         block until a new inbox line appears, print it, exit
#   close <incantation>        stop the background streamer for this channel
set -eu
umask 077

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WORDLIST_DIR="$SCRIPT_DIR/../summon"
NTFY_BASE="${PORTAL_NTFY_BASE:-https://ntfy.sh}"
STATE_ROOT="${TMPDIR:-/tmp}"

die() { echo "status: error"; echo "error: $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }

sha256_hex() { openssl dgst -sha256 | awk '{print $NF}'; }
topic_for()   { h="$(printf 'topic:%s' "$1" | sha256_hex)"; printf 'portal-%s' "$(printf '%s' "$h" | cut -c1-16)"; }
enc_key_for() { printf 'enc:%s' "$1" | sha256_hex; }
mac_key_for() { printf 'mac:%s' "$1" | sha256_hex; }
dir_for()     { printf '%s/portal.%s' "$STATE_ROOT" "$(topic_for "$1")"; }

pick_word() { r="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"; sed -n "$(( (r % $1) + 1 ))p" "$2"; }
gen_incantation() {
    wl="$1"
    [ -f "$wl" ] || die "wordlist missing: $wl (portal needs the summon skill alongside it)"
    n="$(wc -l < "$wl" | tr -d ' ')"
    [ "$n" -gt 0 ] || die "wordlist is empty: $wl"
    printf '%s-%s-%s' "$(pick_word "$n" "$wl")" "$(pick_word "$n" "$wl")" "$(pick_word "$n" "$wl")"
}

do_new() {
    lang=fi
    case "${1:-}" in --en) lang=en ;; --fi|"") lang=fi ;; *) die "usage: portal.sh new [--fi|--en]" ;; esac
    inc="$(gen_incantation "$WORDLIST_DIR/wordlist.$lang.txt")"
    echo "status: ok"
    echo "incantation: $inc"
}

# --- dispatch ---
cmd="${1:-}"; [ "$#" -gt 0 ] && shift || true
case "$cmd" in
    new) do_new "${1:-}" ;;
    _topic)  [ "$#" -ge 1 ] || die "usage: _topic <inc>";  need openssl; topic_for "$1" ;;
    _enckey) [ "$#" -ge 1 ] || die "usage: _enckey <inc>"; need openssl; enc_key_for "$1" ;;
    _mackey) [ "$#" -ge 1 ] || die "usage: _mackey <inc>"; need openssl; mac_key_for "$1" ;;
    *)   die "unknown command: ${cmd:-(none)}" ;;
esac
