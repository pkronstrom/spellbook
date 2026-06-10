#!/bin/sh
# portal.sh test suite. Run: sh skills/portal/test.sh
# Network loopback test runs only when PORTAL_TEST_NET=1.
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
P="$HERE/portal.sh"
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
if grep -qxF "$first_en" "$HERE/../summon/wordlist.en.txt"; then ok "new --en draws from the English wordlist"; else no "new --en draws from the English wordlist"; fi

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

# --- Task 4: send builds a valid encrypted payload (offline check via PORTAL_DRYRUN) ---
WIRE_OUT="$(PORTAL_DRYRUN=1 sh "$P" send kettu-lokaali-piano "hello there" --from peter | sed -n 's/^wire: //p')"
DEC="$(sh "$P" _decrypt kettu-lokaali-piano "$WIRE_OUT")"
case "$DEC" in
    *'"from":"peter"'*) ok "send payload carries from" ;;
    *) no "send payload carries from"; echo "    got: $DEC" ;;
esac
case "$DEC" in
    *'"text":"hello there"'*) ok "send payload carries text" ;;
    *) no "send payload carries text"; echo "    got: $DEC" ;;
esac

# --- Task 5: live loopback through ntfy (only with PORTAL_TEST_NET=1) ---
if [ "${PORTAL_TEST_NET:-0}" = "1" ]; then
    LINC="loopback-$(openssl rand -hex 4 | sed 's/\(..\)\(..\)\(..\)\(..\)/\1-\2-\3/')"
    sh "$P" open "$LINC" >/dev/null 2>&1 &
    OPID=$!
    sleep 3
    # tricky text: contains a quote and a brace to exercise the inbox extractor
    sh "$P" send "$LINC" 'reply {ok} say "hi"' --from tester >/dev/null
    got=""
    i=0
    while [ "$i" -lt 10 ]; do
        line="$(sh "$P" read "$LINC" 2>/dev/null || true)"
        case "$line" in *'reply {ok} say "hi"'*) got="yes"; break ;; esac
        i=$((i+1)); sleep 1
    done
    sh "$P" close "$LINC" >/dev/null 2>&1 || true
    kill "$OPID" 2>/dev/null || true
    eq "loopback message arrives decrypted in inbox" "$got" "yes"
else
    ok "skipped network loopback (set PORTAL_TEST_NET=1 to run it)"
fi

# --- Task 6: read/wait/close against a hand-seeded inbox (no network) ---
FINC="fake-portal-channel-xyz"
FDIR="${TMPDIR:-/tmp}/portal.$(sh "$P" _topic "$FINC")"
mkdir -p "$FDIR"; : > "$FDIR/inbox.log"
printf '1700000000\tesko\tfirst\n' >> "$FDIR/inbox.log"
eq "read returns new line"        "$(sh "$P" read "$FINC")" "$(printf '1700000000\tesko\tfirst')"
eq "read returns nothing second time" "$(sh "$P" read "$FINC")" ""
printf '1700000001\tesko\tsecond\n' >> "$FDIR/inbox.log"
eq "read returns only the new line" "$(sh "$P" read "$FINC")" "$(printf '1700000001\tesko\tsecond')"
( sleep 1; printf '1700000002\tesko\tthird\n' >> "$FDIR/inbox.log" ) &
eq "wait blocks then returns the appended line" "$(sh "$P" wait "$FINC")" "$(printf '1700000002\tesko\tthird')"
sh "$P" close "$FINC" >/dev/null 2>&1; ok "close exits cleanly (idempotent)"
rm -rf "$FDIR"

# --- Task 6b: inbox text extraction survives quotes and braces (offline) ---
PT='{"id":"x","from":"a","ts":1,"text":"reply {ok} say \"hi\""}'
eq "msg_text extracts text with quotes and braces" "$(sh "$P" _msgtext "$PT")" 'reply {ok} say "hi"'
PT2='{"id":"y","from":"b","ts":2,"text":"trailing brace}"}'
eq "msg_text handles text ending in a brace" "$(sh "$P" _msgtext "$PT2")" 'trailing brace}'

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
