#!/bin/bash
# Offline tests for the five trello skills - 1,239 lines of bash that had no
# test of any kind until 18 September 2026.
#
# Two halves, and the split is deliberate:
#
#   PART 1 pulls real functions out of the live scripts and runs them, the way
#   outlook's helpers_test.sh does. That keeps the tests tracking the
#   implementation instead of a copy of it: rename a function and the
#   extraction fails loudly rather than testing nothing.
#
#   PART 2 runs each script end to end with a fake curl on PATH and a fixture
#   $HOME. That is where the things worth guarding live - every request goes to
#   api.trello.com and nowhere else, the credential comes out of the config
#   file, caller text is urlencoded rather than pasted into a query string, and
#   the ~/.trello migration moves settings exactly once.
#
#   bash skills/trello/tests/helpers_test.sh
#
# No API key, no network, no Trello account. Requires jq, awk and coreutils -
# the same tools the skill itself uses.
#
# shellcheck disable=SC2317  # functions called indirectly through the extracted code
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CARDS="$REPO_ROOT/skills/trello/scripts/trello-cards.sh"
BOARDS="$REPO_ROOT/skills/trello/scripts/trello-boards.sh"
DUE="$REPO_ROOT/skills/due-radar/scripts/due-radar.sh"
DIGEST="$REPO_ROOT/skills/board-digest/scripts/board-digest.sh"
LIFE="$REPO_ROOT/skills/life-manager/scripts/life-board.sh"
SETUP="$REPO_ROOT/skills/trello/scripts/trello-setup.sh"
LIB="$REPO_ROOT/skills/trello/scripts/lib.sh"
ALL_SCRIPTS=("$CARDS" "$BOARDS" "$DUE" "$DIGEST" "$LIFE")
# Every script a user or an agent can run. Setup is one of them, and it is the
# one a new user meets first, so the migration test covers it too.
ENTRY_SCRIPTS=("${ALL_SCRIPTS[@]}" "$SETUP")

PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf 'ok   - %s\n' "$1";
       else FAIL=$((FAIL+1)); printf 'FAIL - %s\n   expected: %s\n   got:      %s\n' "$1" "$2" "$3"; fi; }
contains() { case "$3" in *"$2"*) PASS=$((PASS+1)); printf 'ok   - %s\n' "$1";;
       *) FAIL=$((FAIL+1)); printf 'FAIL - %s\n   expected to contain: %s\n   got:                 %s\n' "$1" "$2" "$3";; esac; }
absent() { case "$3" in *"$2"*) FAIL=$((FAIL+1)); printf 'FAIL - %s\n   should NOT contain: %s\n   got:                %s\n' "$1" "$2" "$3";;
       *) PASS=$((PASS+1)); printf 'ok   - %s\n' "$1";; esac; }

# Pull a function definition (from `name() {` to the first line that is just
# `}`) out of a live script, so the test runs the shipped code.
extract_fn() {
    local out
    out=$(awk "/^$2\\(\\) \\{/{f=1} f{print} f&&/^\\}/{exit}" "$1")
    [ -n "$out" ] || { echo "FATAL: no function '$2' in $1 - renamed or removed?" >&2; exit 2; }
    printf '%s\n' "$out"
}

########################################
# PART 1 - extracted functions
########################################

# due-radar's render(): the one piece of real logic in the pack. Everything
# overdue is always shown; the day window only limits how far ahead upcoming
# items reach. It reads `date -u +%s` for "now", so the tests pin now with a
# shim and every expectation below is relative to 2026-06-15T12:00:00Z.
eval "$(extract_fn "$DUE" render)"
NOW_FIXED=1781524800   # 2026-06-15T12:00:00Z
date() { if [ "${1:-}" = "-u" ] && [ "${2:-}" = "+%s" ]; then echo "$NOW_FIXED"; else command date "$@"; fi; }

CARDS_JSON='[
  {"name":"Overdue thing","due":"2026-06-01T09:00:00.000Z","url":"u","board":"Work"},
  {"name":"Due tomorrow","due":"2026-06-16T09:00:00.000Z","url":"u","board":"Work"},
  {"name":"Due in ten days","due":"2026-06-25T09:00:00.000Z","url":"u","board":"Home"},
  {"name":"Due in ninety days","due":"2026-09-13T09:00:00.000Z","url":"u","board":"Home"}
]'

out=$(render "$CARDS_JSON" 14)
eq "render counts 1 overdue and 2 upcoming in a 14-day window" \
   "1 overdue, 2 upcoming (next 14 days)" "$(echo "$out" | sed -n '1p' | sed 's/^  //')"
contains "render labels the overdue card OVERDUE" "OVERDUE" "$out"
absent "render excludes a card beyond the window" "ninety" "$out"
contains "render shows the board name in brackets" "[Home]" "$out"

# Sort order is by due date, which is the whole point of a radar. Asserted on
# the order of the rendered rows rather than on the jq expression.
rows=$(echo "$out" | awk -F'  +' 'NR>2 && NF>2 {print $3}')
eq "render sorts by due date, overdue first" "Overdue thing
Due tomorrow
Due in ten days" "$rows"

# Narrowing the window narrows the upcoming list and never the overdue one.
# That is the behaviour the usage text promises - "all overdue cards are always
# shown; the day window only limits how far ahead upcoming items reach" - and
# it is the easiest one to break by moving the filter.
#
# The window is now + days, to the second, not to the end of that day: with now
# pinned at 12:00 on the 15th, a card due at 09:00 on the 16th is inside a
# one-day window and a card due on the 25th is not.
out=$(render "$CARDS_JSON" 1)
contains "a 1-day window keeps the overdue card" "OVERDUE" "$out"
contains "a 1-day window keeps tomorrow morning" "Due tomorrow" "$out"
absent "a 1-day window drops the card ten days out" "ten days" "$out"
eq "a 1-day window counts 1 overdue and 1 upcoming" \
   "1 overdue, 1 upcoming (next 1 days)" "$(echo "$out" | sed -n '1p' | sed 's/^  //')"

# Trello sends fractional seconds ("2026-06-01T09:00:00.000Z") and
# fromdateiso8601 rejects them, so render strips them. Prove it on a due date
# that has them and one that does not.
out=$(render '[{"name":"Fractional","due":"2026-06-01T09:00:00.000Z","url":"u","board":"B"},
               {"name":"Whole","due":"2026-06-02T09:00:00Z","url":"u","board":"B"}]' 14)
contains "render accepts a due date with fractional seconds" "Fractional" "$out"
contains "render accepts a due date without them" "Whole" "$out"

out=$(render '[]' 14)
eq "render says so when there is nothing" "  (nothing overdue or due in the next 14 days)" "$out"

unset -f date render

# days_ago_iso() lives once, in lib.sh, and carries the GNU/BSD date fallback.
# Test the real one - a broken fallback is silent on the machine the author
# used and total on the other.
eval "$(extract_fn "$LIB" days_ago_iso)"
got=$(days_ago_iso 7)
case "$got" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z)
    PASS=$((PASS+1)); printf 'ok   - days_ago_iso returns an ISO-8601 Z timestamp\n';;
  *) FAIL=$((FAIL+1)); printf 'FAIL - days_ago_iso returns an ISO-8601 Z timestamp\n   got: %s\n' "$got";;
esac
then_epoch=$(command date -u -d "$got" +%s 2>/dev/null || command date -u -jf '%Y-%m-%dT%H:%M:%SZ' "$got" +%s)
now_epoch=$(command date -u +%s)
delta=$(( now_epoch - then_epoch ))
if [ "$delta" -gt 604000 ] && [ "$delta" -lt 605400 ]; then
  PASS=$((PASS+1)); printf 'ok   - days_ago_iso 7 is seven days back, not seven of something else\n'
else
  FAIL=$((FAIL+1)); printf 'FAIL - days_ago_iso 7 is seven days back\n   got %s seconds\n' "$delta"
fi
unset -f days_ago_iso

# life-board's resolve_config() precedence. Nothing personal ships in the
# skill, so where the config is found is load-bearing: a repo-local file must
# beat the home directory, or one person's board leaks into another's checkout.
eval "$(extract_fn "$LIFE" resolve_config)"
fixture=$(mktemp -d)
mkdir -p "$fixture/work/system" "$fixture/home/.dbhq/trello"
: > "$fixture/home/.dbhq/trello/life-manager.yaml"
( cd "$fixture/work" || exit 1
  HOME="$fixture/home" LIFE_MANAGER_CONFIG="" resolve_config ) > "$fixture/got" 2>&1
eq "resolve_config falls back to ~/.dbhq/trello" "$fixture/home/.dbhq/trello/life-manager.yaml" "$(cat "$fixture/got")"

: > "$fixture/work/system/life-manager.yaml"
( cd "$fixture/work" || exit 1
  HOME="$fixture/home" LIFE_MANAGER_CONFIG="" resolve_config ) > "$fixture/got" 2>&1
eq "resolve_config prefers ./system over home" "./system/life-manager.yaml" "$(cat "$fixture/got")"

: > "$fixture/work/life-manager.yaml"
( cd "$fixture/work" || exit 1
  HOME="$fixture/home" LIFE_MANAGER_CONFIG="" resolve_config ) > "$fixture/got" 2>&1
eq "resolve_config prefers ./ over ./system" "./life-manager.yaml" "$(cat "$fixture/got")"

: > "$fixture/explicit.yaml"
( cd "$fixture/work" || exit 1
  HOME="$fixture/home" LIFE_MANAGER_CONFIG="$fixture/explicit.yaml" resolve_config ) > "$fixture/got" 2>&1
eq "LIFE_MANAGER_CONFIG beats everything" "$fixture/explicit.yaml" "$(cat "$fixture/got")"

( cd "$fixture" || exit 1
  HOME="$fixture/empty" LIFE_MANAGER_CONFIG="" resolve_config ) >/dev/null 2>&1
eq "resolve_config returns 1 when there is no config anywhere" "1" "$?"
rm -rf "$fixture"
unset -f resolve_config

########################################
# PART 2 - each script end to end, with a fake curl
########################################

# A fixture $HOME with a config, a curl that logs its arguments and prints
# canned JSON, and nothing else on PATH that could reach the network.
make_sandbox() {
    SANDBOX=$(mktemp -d)
    mkdir -p "$SANDBOX/home/.dbhq/trello" "$SANDBOX/bin"
    cat > "$SANDBOX/home/.dbhq/trello/config.json" <<'JSON'
{"api_key": "TESTKEY", "token": "TESTTOKEN"}
JSON
    cat > "$SANDBOX/bin/curl" <<'SH'
#!/bin/bash
# Records every argument, one invocation per line, and answers with JSON shaped
# enough for the callers' jq checks. Like the real curl, it prints the status
# after the body only when asked with -w, and exits 0 whatever the status.
# FAKE_BODY and FAKE_STATUS override the answer.
printf '%s\n' "$*" >> "$CURL_LOG"
default='[{"id":"CARD1","name":"a card","desc":"","pos":1,"labels":[],"due":null,"dueComplete":false,"url":"u","idList":"L1","idBoard":"B1","lists":[],"text":"c","date":"2026-06-01T00:00:00.000Z","memberCreator":{"fullName":"n"},"checkItems":[]}]'
printf '%s\n' "${FAKE_BODY-$default}"
for a in "$@"; do [ "$a" = "-w" ] && printf '%s' "${FAKE_STATUS:-200}"; done
exit 0
SH
    chmod +x "$SANDBOX/bin/curl"
    export CURL_LOG="$SANDBOX/curl.log"
    : > "$CURL_LOG"
}
run_in_sandbox() {  # run_in_sandbox <script> [args...]
    local script="$1"; shift
    env HOME="$SANDBOX/home" CURL_LOG="$CURL_LOG" PATH="$SANDBOX/bin:$PATH" \
        bash "$script" "$@" 2>&1 || true
}
# Like run_in_sandbox, but keeps stdout, stderr and the exit code apart, so a
# test can tell an error from a result. Sets OUT, ERR and RC.
capture() {  # capture <script> [args...]
    local script="$1"; shift
    OUT=$(env HOME="$SANDBOX/home" CURL_LOG="$CURL_LOG" PATH="$SANDBOX/bin:$PATH" \
        bash "$script" "$@" 2> "$SANDBOX/stderr" </dev/null)
    RC=$?
    ERR=$(cat "$SANDBOX/stderr")
}

# EVERY REQUEST GOES TO api.trello.com AND NOWHERE ELSE. This is the one
# property worth a test on its own: the credential is in the query string of
# every call, so a request built against the wrong host hands a Trello token to
# that host. Exercised across all five scripts and every verb that writes.
make_sandbox
run_in_sandbox "$CARDS" list L1 >/dev/null
run_in_sandbox "$CARDS" read CARD1 >/dev/null
run_in_sandbox "$CARDS" create L1 "a title" >/dev/null
run_in_sandbox "$CARDS" move CARD1 L2 >/dev/null
run_in_sandbox "$CARDS" archive CARD1 >/dev/null
run_in_sandbox "$CARDS" comment CARD1 "a comment" >/dev/null
run_in_sandbox "$BOARDS" list >/dev/null
run_in_sandbox "$DUE" all 14 >/dev/null
run_in_sandbox "$DIGEST" digest B1 7 >/dev/null
run_in_sandbox "$LIFE" stale B1 30 >/dev/null

calls=$(wc -l < "$CURL_LOG" | tr -d ' ')
if [ "$calls" -ge 10 ]; then
  PASS=$((PASS+1)); printf 'ok   - the sandbox actually exercised the scripts (%s requests)\n' "$calls"
else
  FAIL=$((FAIL+1)); printf 'FAIL - expected at least 10 requests, logged %s - the shim or the verbs moved\n' "$calls"
fi

offsite=$(grep -oE 'https://[^ "?]+' "$CURL_LOG" | grep -v '^https://api\.trello\.com/1' || true)
eq "every request goes to https://api.trello.com/1" "" "$offsite"

leaked=$(grep -c 'TESTKEY' "$CURL_LOG" || true)
eq "every request carries the key from config.json" "$calls" "$leaked"
leaked=$(grep -c 'TESTTOKEN' "$CURL_LOG" || true)
eq "every request carries the token from config.json" "$calls" "$leaked"

# CALLER TEXT IS URLENCODED, NOT PASTED IN. curl sends -d raw, so an & in a
# card title truncates the value and a + arrives as a space - the comment above
# api_post says exactly this, and nothing asserted it.
: > "$CURL_LOG"
run_in_sandbox "$CARDS" create L1 'Pay VAT & file CT600' 'C++ notes' >/dev/null
line=$(cat "$CURL_LOG")
contains "create sends the title with --data-urlencode" "--data-urlencode name=Pay VAT & file CT600" "$line"
contains "create sends the description with --data-urlencode" "--data-urlencode desc=C++ notes" "$line"
absent "create never puts caller text in the query string" "?key=TESTKEY&token=TESTTOKEN&name=" "$line"
: > "$CURL_LOG"
run_in_sandbox "$CARDS" comment CARD1 'see & compare' >/dev/null
contains "comment sends the text with --data-urlencode" "--data-urlencode text=see & compare" "$(cat "$CURL_LOG")"

# AN ERROR IS AN ERROR, NOT AN EMPTY RESULT. Trello sends its errors as
# text/plain - "invalid token", "invalid id", "model not found" - not JSON. The
# scripts used to look for a JSON .message, find none, and fall through: an
# expired token made a list look empty and exited 0, and label-remove printed
# "Label removed." for a label that was never there. Now every script must
# stop, exit non-zero and put Trello's own words on stderr.
check_error() {  # check_error <name> <script> [args...]
    local name="$1"; shift
    capture "$@"
    eq "$name on HTTP 401 exits non-zero" "nonzero" "$([ "$RC" -ne 0 ] && echo nonzero || echo "rc=$RC")"
    contains "$name on HTTP 401 puts Trello's message on stderr" "invalid token" "$ERR"
    contains "$name on HTTP 401 names the status" "401" "$ERR"
    absent "$name on HTTP 401 does not claim an empty result" "No " "$OUT"
    absent "$name on HTTP 401 does not claim success" "removed" "$OUT"
}
export FAKE_BODY='invalid token' FAKE_STATUS=401
check_error "list"          "$CARDS" list L1
check_error "comments"      "$CARDS" comments CARD1
check_error "label-remove"  "$CARDS" label-remove CARD1 LABEL1
check_error "lists"         "$BOARDS" lists B1
check_error "digest"        "$DIGEST" digest B1 7
check_error "due-radar all" "$DUE" all 14
check_error "stale"         "$LIFE" stale L1 30
check_error "read"          "$CARDS" read CARD1
check_error "create"        "$CARDS" create L1 "a title"
check_error "sort --apply"  "$LIFE" sort L1 "Now" --apply
unset FAKE_BODY FAKE_STATUS

# And a real empty answer is still reported as empty, and is not an error.
export FAKE_BODY='[]'
capture "$CARDS" list L1
eq "list on a real empty array says so" "No cards found." "$OUT"
eq "list on a real empty array exits 0" "0" "$RC"
capture "$CARDS" comments CARD1
eq "comments on a real empty array says so" "No comments found." "$OUT"
unset FAKE_BODY

# A 2xx with an empty body is success - Trello answers some deletes that way.
export FAKE_BODY='' FAKE_STATUS=200
capture "$CARDS" label-remove CARD1 LABEL1
eq "label-remove on a 2xx says so" "Label removed." "$OUT"
eq "label-remove on a 2xx exits 0" "0" "$RC"
unset FAKE_BODY FAKE_STATUS

# NO CONFIG MEANS NO REQUEST, AND A MESSAGE THAT NAMES THE FIX. All five
# scripts, because the first one an agent reaches for is the one a new user
# meets.
for s in "${ALL_SCRIPTS[@]}"; do
    empty=$(mktemp -d); mkdir -p "$empty/bin"; cp "$SANDBOX/bin/curl" "$empty/bin/curl"
    log="$empty/curl.log"; : > "$log"
    out=$(env HOME="$empty" CURL_LOG="$log" PATH="$empty/bin:$PATH" bash "$s" list 2>&1; echo "rc=$?")
    contains "$(basename "$s") with no config names trello-setup.sh" "trello-setup.sh" "$out"
    contains "$(basename "$s") with no config exits non-zero" "rc=1" "$out"
    eq "$(basename "$s") with no config makes no request" "0" "$(wc -l < "$log" | tr -d ' ')"
    rm -rf "$empty"
done

# THE ~/.trello MIGRATION, WHICH EVERY ENTRY SCRIPT RUNS. Whichever script an
# agent reaches for first has to be the one that migrates - the same rule that
# was broken in three of outlook's four entry scripts on 17 Sep 2026, where the
# token script migrated and the others renamed a path that never existed. The
# migration lives once, in lib.sh, and runs when lib.sh is sourced - so this
# runs every entry script, not lib.sh, to prove each one still sources it.
for s in "${ENTRY_SCRIPTS[@]}"; do
    h=$(mktemp -d); mkdir -p "$h/.trello" "$h/bin"; cp "$SANDBOX/bin/curl" "$h/bin/curl"
    echo '{"api_key":"MIGRATED","token":"MIGRATEDTOKEN"}' > "$h/.trello/config.json"
    env HOME="$h" CURL_LOG="$h/curl.log" PATH="$h/bin:$PATH" bash "$s" </dev/null >/dev/null 2>&1 || true
    eq "$(basename "$s") migrates ~/.trello to ~/.dbhq/trello" "MIGRATED" \
       "$(jq -r '.api_key' "$h/.dbhq/trello/config.json" 2>/dev/null || echo MISSING)"
    eq "$(basename "$s") leaves nothing behind at ~/.trello" "gone" \
       "$([ -e "$h/.trello" ] && echo still-there || echo gone)"
    eq "$(basename "$s") leaves ~/.dbhq/trello at 700" "700" \
       "$(stat -c '%a' "$h/.dbhq/trello" 2>/dev/null || stat -f '%Lp' "$h/.dbhq/trello")"
    rm -rf "$h"
done

# AND IT IS GUARDED. A second run must not move a live directory on top of an
# existing one - the migration is `[ ! -e "$TRELLO_CONFIG_DIR" ]` and that
# guard is what makes it safe to run from every entry script.
h=$(mktemp -d); mkdir -p "$h/.trello" "$h/.dbhq/trello" "$h/bin"; cp "$SANDBOX/bin/curl" "$h/bin/curl"
echo '{"api_key":"OLD","token":"OLD"}' > "$h/.trello/config.json"
echo '{"api_key":"CURRENT","token":"CURRENT"}' > "$h/.dbhq/trello/config.json"
env HOME="$h" CURL_LOG="$h/curl.log" PATH="$h/bin:$PATH" bash "$CARDS" list L1 >/dev/null 2>&1 || true
eq "an existing ~/.dbhq/trello is never overwritten by the migration" "CURRENT" \
   "$(jq -r '.api_key' "$h/.dbhq/trello/config.json")"
eq "and the stale ~/.trello is left alone rather than deleted" "OLD" \
   "$(jq -r '.api_key' "$h/.trello/config.json")"
rm -rf "$h"

# ONE COPY OF THE PLUMBING. Config loading, the migration and the request
# itself live in lib.sh and nowhere else. Six copies of them is how one
# error-handling bug came to be in about thirty places, so a script that grows
# its own curl call or its own migration again fails here.
for s in "${ENTRY_SCRIPTS[@]}"; do
    n=$(basename "$s")
    eq "$n makes no request of its own (every call goes through lib.sh)" "" \
       "$(grep -nE '(^|[^_[:alnum:]])curl[[:space:]]' "$s" || true)"
    eq "$n defines no api helper of its own" "" \
       "$(grep -nE '^[[:space:]]*api(_get|_post|_put|_delete)?[[:space:]]*\(\)' "$s" || true)"
    eq "$n carries no migration of its own" "" "$(grep -n '\.trello"' "$s" || true)"
    eq "$n reads no credential of its own" "" "$(grep -nE "'\\.(api_key|token)'" "$s" || true)"
done

# A PARTIAL INSTALL SAYS WHAT IS MISSING. The four other skills use lib.sh from
# the trello skill beside them. Installed on their own - the skills CLI lets a
# user pick one - they must name the missing skill and how to add it, not fail
# with "No such file or directory" from a source line.
for s in "$DIGEST" "$DUE" "$LIFE"; do
    skill=$(basename "$(dirname "$(dirname "$s")")")
    lone=$(mktemp -d); mkdir -p "$lone/skills" "$lone/bin" "$lone/home/.dbhq/trello"
    cp -R "$REPO_ROOT/skills/$skill" "$lone/skills/$skill"
    cp "$SANDBOX/bin/curl" "$lone/bin/curl"
    cp "$SANDBOX/home/.dbhq/trello/config.json" "$lone/home/.dbhq/trello/config.json"
    : > "$lone/curl.log"
    out=$(env HOME="$lone/home" CURL_LOG="$lone/curl.log" PATH="$lone/bin:$PATH" \
          bash "$lone/skills/$skill/scripts/$(basename "$s")" 2>&1; echo "rc=$?")
    contains "$skill installed alone names the missing trello skill" "needs the trello skill" "$out"
    contains "$skill installed alone gives the install command" "npx skills add dbhq-uk/trello-skill --skill trello" "$out"
    contains "$skill installed alone exits non-zero" "rc=1" "$out"
    eq "$skill installed alone makes no request" "0" "$(wc -l < "$lone/curl.log" | tr -d ' ')"
    rm -rf "$lone"
done

# USAGE WITHOUT ARGUMENTS, AND WITHOUT A REQUEST. An unknown verb must not
# reach the API: it is how a typo becomes a call against a path built from the
# typo.
: > "$CURL_LOG"
out=$(run_in_sandbox "$CARDS" definitely-not-a-verb)
contains "an unknown verb prints usage" "Usage: trello-cards.sh" "$out"
eq "an unknown verb makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"

: > "$CURL_LOG"
out=$(run_in_sandbox "$CARDS" create L1)
contains "create with a missing title prints its own usage line" "Usage: trello-cards.sh create" "$out"
eq "create with a missing title makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"

rm -rf "$SANDBOX"

########################################
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
