#!/bin/sh
# summon.sh — thin, dependency-light wrapper around `croc` for the Summon skill.
# croc does the heavy lifting (secure code generation, E2E encryption, NAT
# traversal, folder packaging, integrity). This wrapper adds the ergonomics:
# backgrounded send + code capture, a clipboard share line, and a
# quarantine -> detect -> safe-place receive flow.
#
# Subcommands:
#   send <path>            bind a file/folder/skill; print the incantation
#   send-text <text>       bind a chunk of text/context
#   status                 list pending (waiting) sends
#   cancel <incantation>   stop a pending send
#   receive <incantation>  fetch into a private quarantine; report what arrived
#   place <quarantine>     move a verified payload into its destination
#
# Output is simple `key: value` lines for the calling agent to parse.

set -eu

STATE_DIR="${SUMMON_HOME:-$HOME/.summon}/sends"
SKILLS_DIR="$HOME/.claude/skills"

die() { echo "status: error"; echo "error: $*"; exit 1; }

need_croc() {
    command -v croc >/dev/null 2>&1 || die "croc not found. Install with: brew install croc"
}

mktempdir() { mktemp -d "${TMPDIR:-/tmp}/summon.XXXXXX"; }

# --- detection -------------------------------------------------------------
# Inspect a received quarantine dir and echo: "<type> <name> <source_path>"
detect() {
    q="$1"
    skillmd="$(find "$q" -name SKILL.md -type f 2>/dev/null | head -n1)"
    if [ -n "$skillmd" ]; then
        d="$(dirname "$skillmd")"
        echo "skill $(basename "$d") $d"
        return
    fi
    # exactly one top-level entry is the norm (croc preserves the sent name)
    set -- "$q"/*
    if [ "$#" -eq 1 ] && [ -f "$1" ]; then
        echo "file $(basename "$1") $1"
    elif [ "$#" -eq 1 ] && [ -d "$1" ]; then
        echo "folder $(basename "$1") $1"
    else
        echo "folder payload $q"
    fi
}

conflict_free() {
    dest="$1"
    [ ! -e "$dest" ] && { echo "$dest"; return; }
    base="$dest"; ext=""
    case "$dest" in
        *.*) ext=".${dest##*.}"; base="${dest%.*}" ;;
    esac
    n=2
    while [ -e "${base} (${n})${ext}" ]; do n=$((n + 1)); done
    echo "${base} (${n})${ext}"
}

# --- send ------------------------------------------------------------------
do_send() {
    need_croc
    src="$1"
    [ -e "$src" ] || die "no such path: $src"
    name="$(basename "$src")"
    type="file"; [ -d "$src" ] && type="folder"
    [ -f "$src/SKILL.md" ] && type="skill"

    mkdir -p "$STATE_DIR"
    log="$(mktemp "${TMPDIR:-/tmp}/summon-send.XXXXXX.log")"
    # nohup so croc keeps serving after this script returns.
    nohup croc --yes send "$src" >"$log" 2>&1 &
    pid=$!

    code=""
    i=0
    while [ "$i" -lt 100 ]; do
        code="$(grep -oE 'Code is: [0-9A-Za-z-]+' "$log" 2>/dev/null | head -n1 | sed 's/Code is: //')"
        [ -n "$code" ] && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
        i=$((i + 1))
    done
    [ -n "$code" ] || { cat "$log" >&2; die "croc did not produce a code (see stderr)"; }

    sf="$STATE_DIR/$code"
    printf 'pid=%s\nlog=%s\nname=%s\ntype=%s\n' "$pid" "$log" "$name" "$type" >"$sf"

    share="Summon this: $code  ($type: $name) — No skill? brew install croc && croc $code"
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
    do_send "$tmp/message.md"
}

# --- status / cancel -------------------------------------------------------
do_status() {
    echo "status: ok"
    [ -d "$STATE_DIR" ] || { echo "pending: none"; return; }
    found=0
    for sf in "$STATE_DIR"/*; do
        [ -f "$sf" ] || continue
        pid="$(sed -n 's/^pid=//p' "$sf")"
        if kill -0 "$pid" 2>/dev/null; then
            found=1
            echo "pending: $(basename "$sf") ($(sed -n 's/^type=//p' "$sf"): $(sed -n 's/^name=//p' "$sf"))"
        else
            log="$(sed -n 's/^log=//p' "$sf")"; rm -f "$log" "$sf"
        fi
    done
    [ "$found" -eq 0 ] && echo "pending: none"
}

do_cancel() {
    code="$1"
    sf="$STATE_DIR/$code"
    [ -f "$sf" ] || { echo "status: ok"; echo "cancelled: none"; return; }
    pid="$(sed -n 's/^pid=//p' "$sf")"; log="$(sed -n 's/^log=//p' "$sf")"
    kill "$pid" 2>/dev/null || true
    rm -f "$log" "$sf"
    echo "status: ok"
    echo "cancelled: $code"
}

# --- receive / place -------------------------------------------------------
do_receive() {
    need_croc
    code="$1"
    q="$(mktempdir)"
    if ! CROC_SECRET="$code" croc --yes --overwrite --out "$q" >"$q/.croc.log" 2>&1; then
        log="$(cat "$q/.croc.log" 2>/dev/null)"; rm -rf "$q"
        die "transfer failed: $log"
    fi
    rm -f "$q/.croc.log"

    set -- $(detect "$q")
    type="$1"; name="$2"

    syml="$(find "$q" -type l 2>/dev/null | head -n1)"
    [ -z "$syml" ] || { rm -rf "$q"; die "unsafe payload: contains symlinks"; }

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
    overwrite="no"; [ "${3:-}" = "--overwrite" ] && overwrite="yes"
    # also allow: place <q> --overwrite
    [ "$dest_override" = "--overwrite" ] && { overwrite="yes"; dest_override=""; }

    syml="$(find "$q" -type l 2>/dev/null | head -n1)"
    [ -z "$syml" ] || die "unsafe payload: contains symlinks"

    set -- $(detect "$q")
    type="$1"; name="$2"; source="$3"

    if [ -n "$dest_override" ]; then
        dest="$dest_override"
    elif [ "$type" = "skill" ]; then
        mkdir -p "$SKILLS_DIR"; dest="$SKILLS_DIR/$name"
    else
        dest="$PWD/$name"
    fi

    if [ -e "$dest" ] && [ "$overwrite" = "yes" ]; then
        rm -rf "$dest"
    elif [ -e "$dest" ]; then
        dest="$(conflict_free "$dest")"
    fi

    mv "$source" "$dest"
    rm -rf "$q"
    echo "status: ok"
    echo "placed: $dest"
    echo "type: $type"
}

# --- dispatch --------------------------------------------------------------
cmd="${1:-}"; [ "$#" -gt 0 ] && shift || true
case "$cmd" in
    send)       [ "$#" -ge 1 ] || die "usage: summon.sh send <path>"; do_send "$1" ;;
    send-text)  [ "$#" -ge 1 ] || die "usage: summon.sh send-text <text>"; do_send_text "$1" ;;
    status)     do_status ;;
    cancel)     [ "$#" -ge 1 ] || die "usage: summon.sh cancel <incantation>"; do_cancel "$1" ;;
    receive)    [ "$#" -ge 1 ] || die "usage: summon.sh receive <incantation>"; do_receive "$1" ;;
    place)      [ "$#" -ge 1 ] || die "usage: summon.sh place <quarantine> [dest] [--overwrite]"; do_place "$@" ;;
    *)          die "unknown command: ${cmd:-（none）}. Use send|send-text|status|cancel|receive|place" ;;
esac
