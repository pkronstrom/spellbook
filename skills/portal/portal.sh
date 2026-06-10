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
# NOTE: the key is the 64-char ASCII hex digest used verbatim as the HMAC string
# key (64 bytes = HMAC-SHA256's block size, carrying the full 256 bits of entropy).
# This is intentional and portable across OpenSSL/LibreSSL. Do NOT "improve" it to
# `-macopt hexkey:` — that interprets the key as raw bytes and changes every MAC,
# breaking the v1 wire format and the golden test values.
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

do_send() { # $1=incantation $2=text $3=from(optional) $4=to(optional, a directed-message hint)
    need openssl
    inc="$1"; text="$2"; from="${3:-$(id -un)}"; to="${4:-}"
    mid="$(openssl rand -hex 8)"; ts="$(date +%s)"
    # `to` is a routing/display hint only — every room member shares the key and
    # can read it. text stays the LAST field so msg_text's "}$ anchor holds.
    plaintext="$(printf '{"id":"%s","from":"%s","to":"%s","ts":%s,"text":"%s"}' \
        "$mid" "$(json_escape "$from")" "$(json_escape "$to")" "$ts" "$(json_escape "$text")")"
    wire="$(encrypt_msg "$inc" "$plaintext")"
    if [ "${PORTAL_DRYRUN:-0}" = "1" ]; then echo "status: dryrun"; echo "wire: $wire"; return 0; fi
    need curl
    topic="$(topic_for "$inc")"
    code="$(printf '%s' "$wire" | curl -s --data-binary @- "$NTFY_BASE/$topic" -o /dev/null -w '%{http_code}')"
    [ "$code" = "200" ] || die "publish failed (http $code)"
    echo "status: sent"
    echo "to_topic: $topic"
}

json_field() { sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p"; }
json_unescape() { sed -e 's/\\"/"/g' -e 's/\\\\/\\/g'; }
# Extract the trailing "text" field from one of our plaintext JSON lines (stdin).
# text is always the last field, so the greedy capture anchored on the final "}
# is exact even when the text itself contains } or (escaped) quotes.
msg_text() { sed -n 's/.*"text":"\(.*\)"}$/\1/p' | json_unescape; }

do_open() { # $1=incantation — BLOCKS streaming; run in background
    need openssl; need curl
    inc="$1"; topic="$(topic_for "$inc")"; d="$(dir_for "$inc")"
    mkdir -p "$d"; inbox="$d/inbox.log"; seen="$d/seen.ids"
    : >> "$inbox"; : >> "$seen"; echo "$$" > "$d/listener.pid"
    { echo "status: open"; echo "topic: $topic"; echo "inbox: $inbox"; } >&2
    while :; do
        url="$NTFY_BASE/$topic/json"
        last="$(cat "$d/last.id" 2>/dev/null || true)"
        [ -n "$last" ] && url="$url?since=$last"
        curl -sN "$url" 2>/dev/null | while IFS= read -r line; do
            case "$line" in *'"event":"message"'*) ;; *) continue ;; esac
            nid="$(printf '%s' "$line" | json_field id)"
            [ -n "$nid" ] && printf '%s' "$nid" > "$d/last.id"
            blob="$(printf '%s' "$line" | sed -n 's/.*"message":"\(v1\.[^"]*\)".*/\1/p')"
            [ -n "$blob" ] || continue
            pt="$(decrypt_msg "$inc" "$blob")" || continue
            mid="$(printf '%s' "$pt" | json_field id)"
            [ -n "$mid" ] && grep -qxF "$mid" "$seen" 2>/dev/null && continue
            [ -n "$mid" ] && printf '%s\n' "$mid" >> "$seen"
            from="$(printf '%s' "$pt" | json_field from)"
            to="$(printf '%s' "$pt" | json_field to)"
            txt="$(printf '%s' "$pt" | msg_text)"
            # inbox columns: epoch \t from \t to \t text  (to is empty if undirected)
            printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$from" "$to" "$txt" >> "$inbox"
        done
        sleep 2
    done
}

do_read() { # $1=incantation — print inbox lines new since last read
    inc="$1"; d="$(dir_for "$inc")"; inbox="$d/inbox.log"
    [ -f "$inbox" ] || die "no portal inbox for that incantation (is it open?)"
    off="$d/read.offset"; n="$(cat "$off" 2>/dev/null || echo 0)"
    total="$(wc -l < "$inbox" | tr -d ' ')"
    # If the inbox was recreated/truncated (e.g. TMPDIR reaped, channel reopened),
    # a stale offset could exceed the line count and silently hide everything.
    [ "$n" -gt "$total" ] && n=0
    [ "$total" -gt "$n" ] && sed -n "$((n+1)),\$p" "$inbox"
    printf '%s' "$total" > "$off"
}

do_wait() { # $1=incantation — block until a new inbox line appears, print it, exit
    inc="$1"; d="$(dir_for "$inc")"; inbox="$d/inbox.log"
    [ -f "$inbox" ] || die "no portal inbox for that incantation (is it open?)"
    start="$(wc -l < "$inbox" | tr -d ' ')"
    while :; do
        cur="$(wc -l < "$inbox" | tr -d ' ')"
        if [ "$cur" -gt "$start" ]; then sed -n "$((start+1)),\$p" "$inbox"; return 0; fi
        sleep 2
    done
}

do_close() { # $1=incantation — stop the background streamer
    need openssl
    inc="$1"; d="$(dir_for "$inc")"; topic="$(topic_for "$inc")"
    pid="$(cat "$d/listener.pid" 2>/dev/null || true)"
    if [ -n "$pid" ]; then pkill -P "$pid" 2>/dev/null || true; kill "$pid" 2>/dev/null || true; fi
    # Belt-and-suspenders: kill the streaming curl directly. Under some shells the
    # curl in `curl | while` is a grandchild of $$ that pkill -P / kill $$ miss
    # (orphans reparent to init rather than dying). Its argv carries the unique
    # topic, so match on that.
    pkill -f "$topic" 2>/dev/null || true
    echo "status: closed"
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
        [ "$#" -ge 2 ] || die "usage: portal.sh send <incantation> <text> [--from <name>] [--to <name>]"
        s_inc="$1"; s_text="$2"; shift 2
        s_from=""; s_to=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --from) s_from="${2:-}"; shift 2 ;;
                --to)   s_to="${2:-}"; shift 2 ;;
                *)      die "unknown send option: $1 (use --from / --to)" ;;
            esac
        done
        do_send "$s_inc" "$s_text" "$s_from" "$s_to" ;;
    open) [ "$#" -ge 1 ] || die "usage: portal.sh open <incantation>"; do_open "$1" ;;
    read)  [ "$#" -ge 1 ] || die "usage: portal.sh read <incantation>";  do_read "$1" ;;
    wait)  [ "$#" -ge 1 ] || die "usage: portal.sh wait <incantation>";  do_wait "$1" ;;
    close) [ "$#" -ge 1 ] || die "usage: portal.sh close <incantation>"; do_close "$1" ;;
    _topic)  [ "$#" -ge 1 ] || die "usage: _topic <inc>";  need openssl; topic_for "$1" ;;
    _enckey) [ "$#" -ge 1 ] || die "usage: _enckey <inc>"; need openssl; enc_key_for "$1" ;;
    _mackey) [ "$#" -ge 1 ] || die "usage: _mackey <inc>"; need openssl; mac_key_for "$1" ;;
    _encrypt) [ "$#" -ge 2 ] || die "usage: _encrypt <inc> <plaintext>"; need openssl; encrypt_msg "$1" "$2" ;;
    _decrypt) [ "$#" -ge 2 ] || die "usage: _decrypt <inc> <wire>"; need openssl; decrypt_msg "$1" "$2" ;;
    _msgtext) [ "$#" -ge 1 ] || die "usage: _msgtext <plaintext-json>"; printf '%s' "$1" | msg_text ;;
    *)   die "unknown command: ${cmd:-(none)}" ;;
esac
