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

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
