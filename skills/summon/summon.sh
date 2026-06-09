#!/bin/sh
# summon.sh — thin, dependency-light wrapper around `croc` for the Summon skill.
# croc does the heavy lifting (E2E encryption, NAT traversal, folder packaging,
# integrity). This wrapper adds the ergonomics: a spoken-clean 3-word incantation,
# a supervised background send, a clipboard share line, and a
# quarantine -> detect -> safe-place receive flow.
#
# The incantation is generated here from a bundled spoken-friendly wordlist using
# /dev/urandom (the model never picks the words) and passed to croc via
# CROC_SECRET, so it is pure words (e.g. "acorn-zebra-mural") with no number.
#
# Optional shared secret: if SUMMON_SALT is set (same value on both ends), it is
# transparently prepended to every incantation. You still only speak the 3 words;
# an eavesdropper who overhears them cannot receive without also knowing the salt.
#
# Entropy note: 3 words from ~1296 ≈ 31 bits. croc's PAKE gives an attacker only
# one online guess per single-use code, so this is fine for opportunistic sharing.
# For sensitive payloads, set SUMMON_SALT.
#
# A background send self-expires after SUMMON_SEND_TIMEOUT seconds (default 3600;
# 0 = wait forever) and cleans up its own process/log/temp/state on exit.
#
# Subcommands:
#   send <path>            bind a file/folder/skill; print the incantation
#   send-text <text>       bind a chunk of text/context
#   status                 list pending (waiting) sends
#   cancel <incantation>   stop a pending send
#   receive <incantation>  fetch into a private quarantine; report what arrived
#   place <quarantine> [dest] [--overwrite]   move a verified payload into place
#   discard <quarantine>   delete a quarantine the user chose not to keep
#
# Output is simple `key: value` lines for the calling agent to parse.

set -eu
umask 077

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WORDLIST="$SCRIPT_DIR/wordlist.txt"
STATE_DIR="${SUMMON_HOME:-$HOME/.summon}/sends"
SKILLS_DIR="$HOME/.claude/skills"
SEND_TIMEOUT="${SUMMON_SEND_TIMEOUT:-3600}"

die() { echo "status: error"; echo "error: $*"; exit 1; }

need_croc() {
    command -v croc >/dev/null 2>&1 || die "croc not found. Install with: brew install croc"
}

mktempdir() { mktemp -d "${TMPDIR:-/tmp}/summon.XXXXXX"; }

state_field() { sed -n "s/^$1=//p" "$2" 2>/dev/null; }

# --- incantation -----------------------------------------------------------
pick_word() {
    n="$1"
    r="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
    sed -n "$(( (r % n) + 1 ))p" "$WORDLIST"
}

gen_incantation() {
    [ -f "$WORDLIST" ] || die "wordlist missing: $WORDLIST"
    n="$(wc -l < "$WORDLIST" | tr -d ' ')"
    [ "$n" -gt 0 ] || die "wordlist is empty"
    printf '%s-%s-%s' "$(pick_word "$n")" "$(pick_word "$n")" "$(pick_word "$n")"
}

# Prepend the optional shared salt to form the real croc secret.
apply_salt() {
    if [ -n "${SUMMON_SALT:-}" ]; then printf '%s-%s' "$SUMMON_SALT" "$1"; else printf '%s' "$1"; fi
}

# --- pruning ---------------------------------------------------------------
# Reap state for sends whose process is gone (completed/reboot) or long expired.
prune_sends() {
    [ -d "$STATE_DIR" ] || return 0
    now="$(date +%s)"
    for sf in "$STATE_DIR"/*; do
        [ -f "$sf" ] || continue
        pid="$(state_field pid "$sf")"
        log="$(state_field log "$sf")"
        tmpdir="$(state_field tmpdir "$sf")"
        started="$(state_field started "$sf")"
        timeout="$(state_field timeout "$sf")"
        dead=no
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || dead=yes
        if [ "$dead" = no ] && [ -n "$started" ] && [ -n "$timeout" ] && [ "$timeout" -gt 0 ] 2>/dev/null; then
            [ "$(( now - started ))" -gt "$(( timeout + 300 ))" ] && dead=yes
        fi
        if [ "$dead" = yes ]; then
            [ -n "$log" ] && rm -f "$log"
            [ -n "$tmpdir" ] && rm -rf "$tmpdir"
            rm -f "$sf"
        fi
    done
}

# --- detection -------------------------------------------------------------
# Inspect a received quarantine dir; print three newline-delimited fields:
#   <type>\n<name>\n<source_path>   (safe for names with spaces)
detect() {
    q="$1"
    set -- "$q"/*
    if [ "$#" -eq 1 ] && [ -d "$1" ] && [ -f "$1/SKILL.md" ]; then
        printf '%s\n%s\n%s\n' skill "$(basename "$1")" "$1"
    elif [ "$#" -eq 1 ] && [ -f "$1" ]; then
        printf '%s\n%s\n%s\n' file "$(basename "$1")" "$1"
    elif [ "$#" -eq 1 ] && [ -d "$1" ]; then
        printf '%s\n%s\n%s\n' folder "$(basename "$1")" "$1"
    else
        printf '%s\n%s\n%s\n' folder payload "$q"
    fi
}

# First payload entry that is neither a regular file nor a directory
# (symlink, device, fifo, socket). Empty output means safe.
unsafe_entry() { find "$1" ! -type d ! -type f 2>/dev/null | head -n1; }

conflict_free() {
    dest="$1"; isdir="${2:-no}"
    [ ! -e "$dest" ] && { printf '%s' "$dest"; return; }
    if [ "$isdir" = yes ]; then
        base="$dest"; ext=""
    else
        case "$dest" in
            */*.*|*.*) ext=".${dest##*.}"; base="${dest%.*}" ;;
            *) base="$dest"; ext="" ;;
        esac
    fi
    n=2
    while [ -e "${base} (${n})${ext}" ]; do n=$((n + 1)); done
    printf '%s' "${base} (${n})${ext}"
}

# --- send ------------------------------------------------------------------
do_send() {
    need_croc
    src="$1"; tmpdir="${2:-}"
    [ -e "$src" ] || die "no such path: $src"
    name="$(basename "$src")"
    type="file"; [ -d "$src" ] && type="folder"
    [ -f "$src/SKILL.md" ] && type="skill"

    code="$(gen_incantation)"
    secret="$(apply_salt "$code")"
    mkdir -p "$STATE_DIR"
    log="$(mktemp "${TMPDIR:-/tmp}/summon-send.XXXXXX")"
    nohup env CROC_SECRET="$secret" croc --yes send "$src" >"$log" 2>&1 &
    pid=$!

    # wait until croc is actually serving, so a friend can receive immediately
    i=0; ready=no
    while [ "$i" -lt 100 ]; do
        if grep -qE 'Code is:|Sending' "$log" 2>/dev/null; then ready=yes; break; fi
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1; i=$((i + 1))
    done
    if [ "$ready" != yes ]; then
        kill "$pid" 2>/dev/null || true
        cat "$log" >&2; rm -f "$log"
        [ -n "$tmpdir" ] && rm -rf "$tmpdir"
        die "croc send did not become ready (see stderr)"
    fi

    sf="$STATE_DIR/$code"
    printf 'pid=%s\nlog=%s\nname=%s\ntype=%s\ntmpdir=%s\nstarted=%s\ntimeout=%s\n' \
        "$pid" "$log" "$name" "$type" "$tmpdir" "$(date +%s)" "$SEND_TIMEOUT" >"$sf"

    # Detached watchdog: enforce the timeout and clean up (process/log/temp/state)
    # whenever croc exits — success, failure, or timeout.
    nohup sh -c '
        pid="$1"; log="$2"; sf="$3"; tmpdir="$4"; timeout="$5"; t=0
        while kill -0 "$pid" 2>/dev/null; do
            if [ "$timeout" -gt 0 ] && [ "$t" -ge "$timeout" ]; then
                kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null
                break
            fi
            sleep 5; t=$((t + 5))
        done
        rm -f "$log" "$sf"
        [ -n "$tmpdir" ] && rm -rf "$tmpdir"
    ' summon-wd "$pid" "$log" "$sf" "$tmpdir" "$SEND_TIMEOUT" >/dev/null 2>&1 &

    if [ -n "${SUMMON_SALT:-}" ]; then
        share="Summon this: $code  ($type: $name)"
    else
        share="Summon this: $code  ($type: $name) — No skill? brew install croc && croc $code"
    fi
    clip="no"
    if command -v pbcopy >/dev/null 2>&1; then printf '%s' "$share" | pbcopy && clip="yes"; fi

    echo "status: ok"
    echo "incantation: $code"
    echo "type: $type"
    echo "name: $name"
    echo "clipboard: $clip"
    echo "share_line: $share"
}

do_send_text() {
    need_croc
    tmp="$(mktempdir)"
    printf '%s' "$1" >"$tmp/message.md"
    do_send "$tmp/message.md" "$tmp"
}

# --- status / cancel -------------------------------------------------------
do_status() {
    echo "status: ok"
    [ -d "$STATE_DIR" ] || { echo "pending: none"; return; }
    found=0
    for sf in "$STATE_DIR"/*; do
        [ -f "$sf" ] || continue
        pid="$(state_field pid "$sf")"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            found=1
            echo "pending: $(basename "$sf") ($(state_field type "$sf"): $(state_field name "$sf"))"
        fi
    done
    [ "$found" -eq 0 ] && echo "pending: none"
}

do_cancel() {
    code="$1"
    sf="$STATE_DIR/$code"
    [ -f "$sf" ] || { echo "status: ok"; echo "cancelled: none"; return; }
    pid="$(state_field pid "$sf")"
    log="$(state_field log "$sf")"
    tmpdir="$(state_field tmpdir "$sf")"
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; sleep 0.5; kill -9 "$pid" 2>/dev/null || true; fi
    [ -n "$log" ] && rm -f "$log"
    [ -n "$tmpdir" ] && rm -rf "$tmpdir"
    rm -f "$sf"
    echo "status: ok"
    echo "cancelled: $code"
}

# --- receive / place / discard ---------------------------------------------
do_receive() {
    need_croc
    secret="$(apply_salt "$1")"
    q="$(mktempdir)"
    if ! CROC_SECRET="$secret" croc --yes --overwrite --out "$q" >"$q/.croc.log" 2>&1; then
        log="$(cat "$q/.croc.log" 2>/dev/null)"; rm -rf "$q"
        die "transfer failed: $log"
    fi
    rm -f "$q/.croc.log"

    bad="$(unsafe_entry "$q")"
    [ -z "$bad" ] || { rm -rf "$q"; die "unsafe payload: non-regular file present"; }

    { IFS= read -r type; IFS= read -r name; IFS= read -r source; } <<EOF
$(detect "$q")
EOF
    : "$source"  # used by place; referenced here to satisfy shellcheck-style intent

    if [ "$type" = "skill" ]; then suggested="$SKILLS_DIR/$name"; else suggested="./$name"; fi

    echo "status: ok"
    echo "type: $type"
    echo "name: $name"
    echo "quarantine: $q"
    echo "suggested_dest: $suggested"
    echo "origin: claimed only — croc encrypts transport but does NOT prove who sent it"
    echo "files:"
    (cd "$q" && find . -type f | sed 's|^\./|  |')
}

do_place() {
    q="$1"
    [ -d "$q" ] || die "no such quarantine: $q"
    dest_override="${2:-}"
    overwrite="no"
    [ "${3:-}" = "--overwrite" ] && overwrite="yes"
    [ "$dest_override" = "--overwrite" ] && { overwrite="yes"; dest_override=""; }

    bad="$(unsafe_entry "$q")"
    [ -z "$bad" ] || { rm -rf "$q"; die "unsafe payload: non-regular file present"; }

    { IFS= read -r type; IFS= read -r name; IFS= read -r source; } <<EOF
$(detect "$q")
EOF

    if [ -n "$dest_override" ]; then
        dest="$dest_override"
        case "$dest" in
            ""|"/"|"$HOME"|"$HOME/") die "refusing to use '$dest' as a destination" ;;
        esac
        parent="$(dirname "$dest")"
        [ -d "$parent" ] || die "destination parent does not exist: $parent"
    elif [ "$type" = "skill" ]; then
        mkdir -p "$SKILLS_DIR"; dest="$SKILLS_DIR/$name"
    else
        dest="$PWD/$name"
    fi

    isdir=no
    { [ "$type" = "folder" ] || [ "$type" = "skill" ]; } && isdir=yes

    if [ -e "$dest" ] && [ "$overwrite" = "yes" ]; then
        bak="$dest.summon-bak.$$"
        mv "$dest" "$bak" || die "cannot replace existing $dest"
        if mv "$source" "$dest"; then rm -rf "$bak"; else mv "$bak" "$dest"; die "placement failed; restored original"; fi
    elif [ -e "$dest" ]; then
        dest="$(conflict_free "$dest" "$isdir")"
        mv "$source" "$dest"
    else
        mv "$source" "$dest"
    fi

    rm -rf "$q"
    echo "status: ok"
    echo "placed: $dest"
    echo "type: $type"
}

do_discard() {
    q="$1"
    case "$q" in *summon.*) ;; *) die "not a summon quarantine: $q" ;; esac
    [ -d "$q" ] && rm -rf "$q"
    echo "status: ok"
    echo "discarded: $q"
}

# --- dispatch --------------------------------------------------------------
prune_sends 2>/dev/null || true

cmd="${1:-}"; [ "$#" -gt 0 ] && shift || true
case "$cmd" in
    send)       [ "$#" -ge 1 ] || die "usage: summon.sh send <path>"; do_send "$1" ;;
    send-text)  [ "$#" -ge 1 ] || die "usage: summon.sh send-text <text>"; do_send_text "$1" ;;
    status)     do_status ;;
    cancel)     [ "$#" -ge 1 ] || die "usage: summon.sh cancel <incantation>"; do_cancel "$1" ;;
    receive)    [ "$#" -ge 1 ] || die "usage: summon.sh receive <incantation>"; do_receive "$1" ;;
    place)      [ "$#" -ge 1 ] || die "usage: summon.sh place <quarantine> [dest] [--overwrite]"; do_place "$@" ;;
    discard)    [ "$#" -ge 1 ] || die "usage: summon.sh discard <quarantine>"; do_discard "$1" ;;
    *)          die "unknown command: ${cmd:-(none)}. Use send|send-text|status|cancel|receive|place|discard" ;;
esac
