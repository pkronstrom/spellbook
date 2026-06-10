#!/bin/sh
# portal.sh test suite. Run: sh tests/portal/test.sh
# Lives outside skills/ so it is never bundled with the plugin or synced into a tool's skills dir.
# Network loopback test runs only when PORTAL_TEST_NET=1.
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$HERE/../.." && pwd)"
P="$ROOT/skills/portal/portal.sh"
# Isolate all portal state (active pointer, channel dirs) under a per-run TMPDIR so
# tests don't see leftovers from previous runs or real usage. We delete nothing —
# the OS reaps it (consistent with the skill's own no-rm policy).
export TMPDIR="${TMPDIR:-/tmp}/portal-test-$$"
mkdir -p "$TMPDIR"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   - $1"; }
no()  { fail=$((fail+1)); echo "NOT  - $1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else no "$1"; echo "    expected: [$3]"; echo "    got:      [$2]"; fi; }

# --- Task 1: new ---
INC="$(sh "$P" new | sed -n 's/^incantation: //p')"
words="$(printf '%s' "$INC" | tr '-' ' ' | wc -w | tr -d ' ')"
eq "new produces a 3-word incantation" "$words" "3"

INC_EN="$(sh "$P" new --en | sed -n 's/^incantation: //p')"
first_en="$(printf '%s' "$INC_EN" | cut -d- -f1)"
if grep -qxF "$first_en" "$ROOT/skills/summon/wordlist.en.txt"; then ok "new --en draws from the English wordlist"; else no "new --en draws from the English wordlist"; fi

# --- Task 2: derivation (golden values for "kettu-lokaali-piano") ---
eq "topic derivation"   "$(sh "$P" _topic  kettu-lokaali-piano)" "portal-3726580a874f8ae2"
eq "enc key derivation" "$(sh "$P" _enckey kettu-lokaali-piano)" "3f8c9b86950f696d9dc457b4167dd8bbfd528a06c9e3a6d1145427372da9972a"
eq "mac key derivation" "$(sh "$P" _mackey kettu-lokaali-piano)" "6ddac5c69f2a7f36984f770e8b25f6b3580fd42e2f623f8b6fed466867178c6f"

# --- Task 3: crypto round-trip + rejection ---
PLAIN='{"id":"abc","from":"peter","ts":1,"text":"hei Esko"}'
WIRE="$(sh "$P" _encrypt kettu-lokaali-piano "$PLAIN")"
eq "decrypt with right incantation" "$(sh "$P" _decrypt kettu-lokaali-piano "$WIRE")" "$PLAIN"

if sh "$P" _decrypt vaara-sana-tassa "$WIRE" >/dev/null 2>&1; then no "wrong incantation rejected"; else ok "wrong incantation rejected"; fi

TAMP="$(printf '%s' "$WIRE" | sed 's/.$/X/')"
if sh "$P" _decrypt kettu-lokaali-piano "$TAMP" >/dev/null 2>&1; then no "tampered ciphertext rejected"; else ok "tampered ciphertext rejected"; fi

eq "wire format is v1 with 4 dot fields" "$(printf '%s' "$WIRE" | awk -F. '{print $1, NF}')" "v1 4"

# --- Task 4: send uses the active channel after open/bind (no incantation on send) ---
# send before any open has no active channel -> must error
if PORTAL_DRYRUN=1 sh "$P" send "x" --from peter >/dev/null 2>&1; then no "send without an open channel is rejected"; else ok "send without an open channel is rejected"; fi

# bind the channel once (the open-once model); afterwards send needs no incantation
sh "$P" _bind kettu-lokaali-piano >/dev/null
WIRE_OUT="$(PORTAL_DRYRUN=1 sh "$P" send "hello there" --from peter | sed -n 's/^wire: //p')"
DEC="$(sh "$P" _decrypt kettu-lokaali-piano "$WIRE_OUT")"
case "$DEC" in
    *'"from":"peter"'*) ok "send (active channel) payload carries from" ;;
    *) no "send (active channel) payload carries from"; echo "    got: $DEC" ;;
esac
case "$DEC" in
    *'"text":"hello there"'*) ok "send (active channel) payload carries text" ;;
    *) no "send (active channel) payload carries text"; echo "    got: $DEC" ;;
esac

# --channel targets a specific channel by its (non-secret) topic, without the incantation
KTOPIC="$(sh "$P" _topic kettu-lokaali-piano)"
WIRE_CH="$(PORTAL_DRYRUN=1 sh "$P" send "via handle" --from peter --channel "$KTOPIC" | sed -n 's/^wire: //p')"
case "$(sh "$P" _decrypt kettu-lokaali-piano "$WIRE_CH")" in
    *'"text":"via handle"'*) ok "send --channel <topic> targets the channel by handle" ;;
    *) no "send --channel <topic> targets the channel by handle" ;;
esac

# --to is a directed-message hint carried in the payload
WIRE_TO="$(PORTAL_DRYRUN=1 sh "$P" send "ping" --from peter --to esko | sed -n 's/^wire: //p')"
DEC_TO="$(sh "$P" _decrypt kettu-lokaali-piano "$WIRE_TO")"
case "$DEC_TO" in
    *'"to":"esko"'*) ok "send --to carries the directed-at handle" ;;
    *) no "send --to carries the directed-at handle"; echo "    got: $DEC_TO" ;;
esac
WIRE_NOTO="$(PORTAL_DRYRUN=1 sh "$P" send "ping" --from peter | sed -n 's/^wire: //p')"
case "$(sh "$P" _decrypt kettu-lokaali-piano "$WIRE_NOTO")" in
    *'"to":""'*) ok "send without --to leaves an empty directed-at field" ;;
    *) no "send without --to leaves an empty directed-at field" ;;
esac

# --- Task 5: live loopback through ntfy (only with PORTAL_TEST_NET=1) ---
if [ "${PORTAL_TEST_NET:-0}" = "1" ]; then
    LINC="loopback-$(openssl rand -hex 4 | sed 's/\(..\)\(..\)\(..\)\(..\)/\1-\2-\3/')"
    sh "$P" open "$LINC" >/dev/null 2>&1 &
    OPID=$!
    sleep 3
    # tricky text: contains a quote and a brace to exercise the inbox extractor;
    # also directed --to esko, so the inbox line must carry both the to-hint and text
    # open set the active channel; send/read need no incantation
    sh "$P" send 'reply {ok} say "hi"' --from tester --to esko >/dev/null
    got=""
    i=0
    while [ "$i" -lt 10 ]; do
        line="$(sh "$P" read 2>/dev/null || true)"
        case "$line" in *"	esko	"*'reply {ok} say "hi"'*) got="yes"; break ;; esac
        i=$((i+1)); sleep 1
    done
    sh "$P" close >/dev/null 2>&1 || true
    kill "$OPID" 2>/dev/null || true
    eq "loopback message arrives decrypted in inbox" "$got" "yes"
else
    ok "skipped network loopback (set PORTAL_TEST_NET=1 to run it)"
fi

# --- Task 6: read/wait/close against a hand-seeded inbox, addressed by --channel (no network) ---
# Unique fake channel per run -> fresh dir, no stale read.offset, and nothing to clean up
# (the test deletes NOTHING; the OS reaps $TMPDIR).
FINC="fake-$(openssl rand -hex 4)-channel"
FTOPIC="$(sh "$P" _topic "$FINC")"
FDIR="${TMPDIR:-/tmp}/portal.$FTOPIC"
mkdir -p "$FDIR"; : > "$FDIR/inbox.log"
printf '1700000000\tesko\t\tfirst\n' >> "$FDIR/inbox.log"
eq "read returns new line"        "$(sh "$P" read --channel "$FTOPIC")" "$(printf '1700000000\tesko\t\tfirst')"
eq "read returns nothing second time" "$(sh "$P" read --channel "$FTOPIC")" ""
printf '1700000001\tesko\t\tsecond\n' >> "$FDIR/inbox.log"
eq "read returns only the new line" "$(sh "$P" read --channel "$FTOPIC")" "$(printf '1700000001\tesko\t\tsecond')"
( sleep 1; printf '1700000002\tesko\t\tthird\n' >> "$FDIR/inbox.log" ) &
eq "wait blocks then returns the appended line" "$(sh "$P" wait --channel "$FTOPIC")" "$(printf '1700000002\tesko\t\tthird')"
sh "$P" close --channel "$FTOPIC" >/dev/null 2>&1; ok "close exits cleanly (idempotent)"

# --- Task 6b: inbox text extraction survives quotes and braces (offline) ---
PT='{"id":"x","from":"a","ts":1,"text":"reply {ok} say \"hi\""}'
eq "msg_text extracts text with quotes and braces" "$(sh "$P" _msgtext "$PT")" 'reply {ok} say "hi"'
PT2='{"id":"y","from":"b","ts":2,"text":"trailing brace}"}'
eq "msg_text handles text ending in a brace" "$(sh "$P" _msgtext "$PT2")" 'trailing brace}'

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
