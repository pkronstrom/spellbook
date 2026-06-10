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

b64()   { openssl base64 -A; }
unb64() { openssl base64 -d -A; }
hmac_hex() { openssl dgst -sha256 -hmac "$1" | awk '{print $NF}'; }

encrypt_msg() { # $1=incantation $2=plaintext -> v1.<iv_hex>.<ct_b64>.<mac_hex>
    ek="$(enc_key_for "$1")"; mk="$(mac_key_for "$1")"
    iv="$(openssl rand -hex 16)"
    ct="$(printf '%s' "$2" | openssl enc -aes-256-cbc -K "$ek" -iv "$iv" | b64)"
    mac="$(printf '%s%s' "$iv" "$ct" | hmac_hex "$mk")"
    printf 'v1.%s.%s.%s' "$iv" "$ct" "$mac"
}

decrypt_msg() { # $1=incantation $2=wire -> plaintext on stdout; return 1 on any failure
    case "$2" in v1.*.*.*) ;; *) return 1 ;; esac
    ek="$(enc_key_for "$1")"; mk="$(mac_key_for "$1")"
    rest="${2#v1.}"; iv="${rest%%.*}"; rest="${rest#*.}"; ct="${rest%%.*}"; mac="${rest#*.}"
    want="$(printf '%s%s' "$iv" "$ct" | hmac_hex "$mk")"
    [ "$want" = "$mac" ] || return 1
    printf '%s' "$ct" | unb64 | openssl enc -d -aes-256-cbc -K "$ek" -iv "$iv" 2>/dev/null
}

json_escape() { printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

do_send() { # $1=incantation $2=text $3=from(optional)
    need openssl
    inc="$1"; text="$2"; from="${3:-$(id -un)}"
    mid="$(openssl rand -hex 8)"; ts="$(date +%s)"
    plaintext="$(printf '{"id":"%s","from":"%s","ts":%s,"text":"%s"}' "$mid" "$from" "$ts" "$(json_escape "$text")")"
    wire="$(encrypt_msg "$inc" "$plaintext")"
    if [ "${PORTAL_DRYRUN:-0}" = "1" ]; then echo "status: dryrun"; echo "wire: $wire"; return 0; fi
    need curl
    topic="$(topic_for "$inc")"
    code="$(printf '%s' "$wire" | curl -s --data-binary @- "$NTFY_BASE/$topic" -o /dev/null -w '%{http_code}')"
    [ "$code" = "200" ] || die "publish failed (http $code)"
    echo "status: sent"
    echo "to_topic: $topic"
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
    send)
        [ "$#" -ge 2 ] || die "usage: portal.sh send <incantation> <text> [--from <name>]"
        s_inc="$1"; s_text="$2"; shift 2
        s_from=""
        case "${1:-}" in --from) s_from="${2:-}" ;; esac
        do_send "$s_inc" "$s_text" "$s_from" ;;
    _topic)  [ "$#" -ge 1 ] || die "usage: _topic <inc>";  need openssl; topic_for "$1" ;;
    _enckey) [ "$#" -ge 1 ] || die "usage: _enckey <inc>"; need openssl; enc_key_for "$1" ;;
    _mackey) [ "$#" -ge 1 ] || die "usage: _mackey <inc>"; need openssl; mac_key_for "$1" ;;
    _encrypt) [ "$#" -ge 2 ] || die "usage: _encrypt <inc> <plaintext>"; need openssl; encrypt_msg "$1" "$2" ;;
    _decrypt) [ "$#" -ge 2 ] || die "usage: _decrypt <inc> <wire>"; need openssl; decrypt_msg "$1" "$2" ;;
    *)   die "unknown command: ${cmd:-(none)}" ;;
esac
