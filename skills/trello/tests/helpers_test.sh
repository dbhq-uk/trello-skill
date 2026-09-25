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
STORE="$REPO_ROOT/skills/store-sort/scripts/store-sort.sh"
ALL_SCRIPTS=("$CARDS" "$BOARDS" "$DUE" "$DIGEST" "$LIFE" "$STORE")
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
# render shows times through lib.sh's jq definitions, so take the real ones.
eval "$(extract_fn "$LIB" trello_jq_defs)"
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

# DUE TIMES ARE LOCAL. Trello stores UTC, and the radar used to print the first
# ten characters of it - the UTC date. In UK summer time a card due at 00:30 on
# the 26th showed as due on the 25th. Pinned TZ, so the answer does not depend
# on where the suite runs.
LATE='[{"name":"Just after midnight","due":"2026-09-25T23:30:00.000Z","url":"u","board":"B"}]'
out=$(export TZ=Europe/London; render "$LATE" 120)
contains "in BST a card due 23:30 UTC shows as 00:30 the next day" "2026-09-26 00:30" "$out"
absent "and not as the UTC date" "2026-09-25" "$out"
out=$(export TZ=America/New_York; render "$LATE" 120)
contains "in New York the same card shows at 19:30 that evening" "2026-09-25 19:30" "$out"
out=$(export TZ=Europe/London; render '[{"name":"Christmas","due":"2026-12-25T09:00:00.000Z","url":"u","board":"B"}]' 200)
contains "in GMT the hour is the UTC hour" "2026-12-25 09:00" "$out"

# EACH ROW NAMES ITS LIST, AND DONE IS NOT OVERDUE. A card dragged to Done
# without its due date ticked used to count as OVERDUE, with no list shown to
# explain it. It is finished work: counted as neither overdue nor upcoming, and
# shown apart, after the rest.
out=$(render '[{"name":"Still to do","due":"2026-06-01T09:00:00.000Z","url":"u","board":"Work","list":"To do","done":false},
               {"name":"Finished it","due":"2026-06-02T09:00:00.000Z","url":"u","board":"Work","list":"Done","done":true}]' 14)
eq "a card in a done list is not counted as overdue" \
   "1 overdue, 0 upcoming (next 14 days)" "$(echo "$out" | sed -n '1p' | sed 's/^  //')"
contains "each row names its board and list" "[Work / To do]" "$out"
contains "the done card is shown apart, and says why" "1 in a done list with the due date not ticked" "$out"
contains "with its list named" "[Work / Done]" "$out"
eq "and is not labelled OVERDUE" "" "$(grep 'Finished it' <<< "$out" | grep OVERDUE || true)"
eq "the done group comes after the rest" "Finished it" "$(grep -E 'Still to do|Finished it' <<< "$out" | tail -1 | awk -F'  +' '{print $3}')"

unset -f date render

# is_done_list: which list names count as done. Letters and digits only, so an
# emoji or a ! does not hide Done, and TRELLO_DONE_LISTS adds a board's own.
for name in "Done" "✅ Done" "DONE!" "Completed" "finished"; do
    eq "\"$name\" is a done list" "true" "$(jq -rn --arg n "$name" "$(trello_jq_defs)"'$n | is_done_list')"
done
for name in "Doing" "Not done" "Shipped" ""; do
    eq "\"$name\" is not a done list" "false" "$(jq -rn --arg n "$name" "$(trello_jq_defs)"'$n | is_done_list')"
done
eq "TRELLO_DONE_LISTS adds a name of the user's own" "true" \
   "$(TRELLO_DONE_LISTS="Shipped, Live" jq -rn "$(trello_jq_defs)"'"shipped" | is_done_list')"
unset -f trello_jq_defs

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

# ./system/life-manager.yaml was one user's layout, in a skill that says
# nothing personal lives in it. It is no longer read.
: > "$fixture/work/system/life-manager.yaml"
( cd "$fixture/work" || exit 1
  HOME="$fixture/home" LIFE_MANAGER_CONFIG="" resolve_config ) > "$fixture/got" 2>&1
eq "resolve_config no longer reads ./system/life-manager.yaml" "$fixture/home/.dbhq/trello/life-manager.yaml" "$(cat "$fixture/got")"

: > "$fixture/work/life-manager.yaml"
( cd "$fixture/work" || exit 1
  HOME="$fixture/home" LIFE_MANAGER_CONFIG="" resolve_config ) > "$fixture/got" 2>&1
eq "resolve_config prefers ./ over home" "./life-manager.yaml" "$(cat "$fixture/got")"

: > "$fixture/explicit.yaml"
( cd "$fixture/work" || exit 1
  HOME="$fixture/home" LIFE_MANAGER_CONFIG="$fixture/explicit.yaml" resolve_config ) > "$fixture/got" 2>&1
eq "LIFE_MANAGER_CONFIG beats everything" "$fixture/explicit.yaml" "$(cat "$fixture/got")"

( cd "$fixture" || exit 1
  HOME="$fixture/empty" LIFE_MANAGER_CONFIG="" resolve_config ) >/dev/null 2>&1
eq "resolve_config returns 1 when there is no config anywhere" "1" "$?"
rm -rf "$fixture"
unset -f resolve_config

# A config left at the old ./system path is named, rather than setup offered
# over the top of it. Run end to end: config makes no request, so no sandbox.
# A curl that refuses on PATH, so nothing here can reach the network.
fixture=$(mktemp -d)
mkdir -p "$fixture/work/system" "$fixture/home/.dbhq/trello" "$fixture/bin"
printf '#!/bin/bash\nexit 99\n' > "$fixture/bin/curl"; chmod +x "$fixture/bin/curl"
echo '{"api_key":"K","token":"T"}' > "$fixture/home/.dbhq/trello/config.json"
: > "$fixture/work/system/life-manager.yaml"
life_in_fixture() { (cd "$fixture/work" && HOME="$fixture/home" PATH="$fixture/bin:$PATH" LIFE_MANAGER_CONFIG="" bash "$LIFE" "$@" 2>&1); }
out=$(life_in_fixture config; echo "rc=$?")
contains "config names a file left at ./system/life-manager.yaml" "no longer read" "$out"
contains "and says how to use it" "LIFE_MANAGER_CONFIG" "$out"
absent "and does not offer setup over it" "setup mode" "$out"
contains "and exits non-zero" "rc=1" "$out"
rm -f "$fixture/work/system/life-manager.yaml"
out=$(life_in_fixture config)
contains "with no config anywhere, config offers setup" "This is setup mode" "$out"
LIFE_HELP=$(life_in_fixture help)
rm -rf "$fixture"
unset -f life_in_fixture

# life-manager's docs say what its script does. SKILL.md said audit reported
# stale cards, which it never has; it offered "ticks since the last run", when
# nothing records a run; it listed the personal ./system path; and it asked for
# "--data-urlencode-safe" values in a YAML file. It had also grown to repeat
# default-board.md, so its prose is held under a ceiling.
LIFE_MD=$(cat "$REPO_ROOT/skills/life-manager/SKILL.md")
LIFE_REFS=$(cat "$REPO_ROOT/skills/life-manager/references/"*.md)
eq "life-manager/SKILL.md does not say audit finds stale cards" "" \
   "$(grep -n 'life-board.sh audit' <<< "$LIFE_MD" | grep -i stale || true)"
contains "life-board.sh help lists audit" "  audit <board-id>" "$LIFE_HELP"
absent "life-board.sh help does not say audit finds stale cards" "stale" "$(grep -A1 '^  audit' <<< "$LIFE_HELP")"
for claim in "since the last run" "since last time" "system/life-manager.yaml" "data-urlencode"; do
    eq "life-manager's docs do not say \"$claim\"" "" \
       "$(printf '%s\n%s\n' "$LIFE_MD" "$LIFE_REFS" | grep -n -- "$claim" || true)"
done
contains "the config example has a Long Burn threshold" "long_burn: 30" "$LIFE_MD"
absent "SKILL.md leaves the emoji rationale to default-board.md" "Why stamp the emoji" "$LIFE_MD"
words=$(awk '/^---$/{n++; next} n>=2' <<< "$LIFE_MD" | awk '/^```/{f=!f; next} !f' | wc -w | tr -d ' ')
if [ "$words" -le 1300 ]; then
    PASS=$((PASS+1)); printf 'ok   - life-manager/SKILL.md prose is %s words, under 1,300\n' "$words"
else
    FAIL=$((FAIL+1)); printf 'FAIL - life-manager/SKILL.md prose is %s words, over 1,300 - move rationale to references/\n' "$words"
fi
unset LIFE_MD LIFE_REFS LIFE_HELP words

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
# FAKE_BODY and FAKE_STATUS override the answer. Headers read from stdin
# (-H @-) go to $CURL_LOG.headers, one line per request, so a test can see
# what travelled in a header rather than on the command line.
printf '%s\n' "$*" >> "$CURL_LOG"
prev=""
for a in "$@"; do
    if [ "$prev" = "-H" ] && [ "$a" = "@-" ]; then
        printf '%s\n' "$(cat)" >> "$CURL_LOG.headers"
    fi
    prev="$a"
done
default='[{"id":"CARD1","name":"a card","desc":"","pos":1,"labels":[],"due":null,"dueComplete":false,"url":"u","idList":"L1","idBoard":"B1","lists":[],"text":"c","date":"2026-06-01T00:00:00.000Z","memberCreator":{"fullName":"n"},"checkItems":[]}]'
# FAKE_DIR answers by path, for tests that need a different answer per
# endpoint or answers too big for an environment variable. The file is the
# path after /1/ with / turned to _, so /boards/B1/actions is
# boards_B1_actions.json; a request with before= in it reads
# boards_B1_actions.before.json instead. A path with no file falls through to
# FAKE_BODY.
#
# <key>.status, if there, scripts the answers to that path one request at a
# time: each line is "<status> [body]" and is used up by one request, so
# "429 ...", "429 ...", "200" is two refusals and then the real answer. Once
# the lines run out the path answers as it would with no .status file.
url=""
for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
key="${url#https://api.trello.com/1/}"; key="${key%%\?*}"; key="${key//\//_}"
case "$url" in *before=*) key="$key.before" ;; esac
status="${FAKE_STATUS:-200}" errbody=""
script="${FAKE_DIR:-/nonexistent}/$key.status"
if [ -s "$script" ]; then
    read -r status errbody < "$script"
    tail -n +2 "$script" > "$script.next"; mv "$script.next" "$script"
fi
if [ -n "$errbody" ]; then
    printf '%s\n' "$errbody"
elif [ -n "${FAKE_DIR:-}" ] && [ -f "$FAKE_DIR/$key.json" ]; then
    cat "$FAKE_DIR/$key.json"; echo
else
    printf '%s\n' "${FAKE_BODY-$default}"
fi
for a in "$@"; do [ "$a" = "-w" ] && printf '%s' "$status"; done
exit 0
SH
    chmod +x "$SANDBOX/bin/curl"
    # sleep is the 429 backoff. The fake records how long it was asked to wait
    # and returns at once, so the retry tests take no time.
    cat > "$SANDBOX/bin/sleep" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$CURL_LOG.sleep"
SH
    chmod +x "$SANDBOX/bin/sleep"
    export CURL_LOG="$SANDBOX/curl.log"
    : > "$CURL_LOG"; : > "$CURL_LOG.headers"
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
# property worth a test on its own: the credential is in the Authorization
# header of every call, so a request built against the wrong host hands a
# Trello token to that host. Exercised across all six scripts and every verb
# that writes.
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
run_in_sandbox "$STORE" plan L1 >/dev/null
printf '{"store":"tesco","cards":[{"id":"CARD1","section":"Snacks","name":"🍫 a card"}]}' > "$SANDBOX/host-plan.json"
run_in_sandbox "$STORE" apply L1 "$SANDBOX/host-plan.json" --apply >/dev/null

calls=$(wc -l < "$CURL_LOG" | tr -d ' ')
if [ "$calls" -ge 10 ]; then
  PASS=$((PASS+1)); printf 'ok   - the sandbox actually exercised the scripts (%s requests)\n' "$calls"
else
  FAIL=$((FAIL+1)); printf 'FAIL - expected at least 10 requests, logged %s - the shim or the verbs moved\n' "$calls"
fi

offsite=$(grep -oE 'https://[^ "?]+' "$CURL_LOG" | grep -v '^https://api\.trello\.com/1' || true)
eq "every request goes to https://api.trello.com/1" "" "$offsite"

# THE KEY AND TOKEN NEVER REACH THE COMMAND LINE. Every local user can read a
# running process's arguments from `ps` or /proc/<pid>/cmdline, so a token in
# the URL is a token on show for as long as the request runs. They go in an
# Authorization header that curl reads from stdin instead.
eq "no request has the key in its curl arguments" "0" "$(grep -c 'TESTKEY' "$CURL_LOG" || true)"
eq "no request has the token in its curl arguments" "0" "$(grep -c 'TESTTOKEN' "$CURL_LOG" || true)"
eq "every request reads its headers from stdin" "$calls" "$(grep -c -- '-H @-' "$CURL_LOG" || true)"
eq "every request sends the key from config.json in the header" "$calls" \
   "$(grep -c 'oauth_consumer_key="TESTKEY"' "$CURL_LOG.headers" || true)"
eq "every request sends the token from config.json in the header" "$calls" \
   "$(grep -c 'oauth_token="TESTTOKEN"' "$CURL_LOG.headers" || true)"
contains "the header is Trello's OAuth form" \
   'Authorization: OAuth oauth_consumer_key="TESTKEY", oauth_token="TESTTOKEN"' "$(head -1 "$CURL_LOG.headers")"

# And no script, setup included, builds a URL with the key or token in it.
for s in "${ENTRY_SCRIPTS[@]}" "$LIB"; do
    eq "$(basename "$s") builds no URL with key= or token= in it" "" \
       "$(grep -nE '(key|token)=\$' "$s" || true)"
done

# CALLER TEXT IS URLENCODED, NOT PASTED IN. curl sends -d raw, so an & in a
# card title truncates the value and a + arrives as a space - the comment above
# api_post says exactly this, and nothing asserted it.
: > "$CURL_LOG"
run_in_sandbox "$CARDS" create L1 'Pay VAT & file CT600' 'C++ notes' >/dev/null
line=$(cat "$CURL_LOG")
contains "create sends the title with --data-urlencode" "--data-urlencode name=Pay VAT & file CT600" "$line"
contains "create sends the description with --data-urlencode" "--data-urlencode desc=C++ notes" "$line"
absent "create never puts caller text in the query string" "name=" "$(echo "$line" | grep -oE 'https://[^ ]+')"
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

# life-board sort LEAVES TITLES ALONE UNLESS IT STAMPS THEM. It used to strip
# a leading \p{So}/\p{Sk} run from every title and write the result, so with
# the order "Now:🔥,Health" a Health card and an unlabelled card lost their
# own emoji, and a stamped card lost a leading ` ^ © ™ or °. There is no undo
# on Trello, so the writes are what is asserted: the exact name each PUT sends,
# and that a card whose title should not change sends none.
export FAKE_BODY='[
  {"id":"C1","name":"🦷 Book the dentist","labels":[{"name":"Health"}]},
  {"id":"C2","name":"🚗 MOT due","labels":[]},
  {"id":"C3","name":"`make` fails","labels":[{"name":"Now"}]},
  {"id":"C4","name":"^ raise","labels":[{"name":"Now"}]},
  {"id":"C5","name":"©2026 renewal","labels":[{"name":"Now"}]},
  {"id":"C6","name":"™ brand","labels":[{"name":"Now"}]},
  {"id":"C7","name":"°C thermostat","labels":[{"name":"Now"}]},
  {"id":"C8","name":"🔥 already stamped","labels":[{"name":"Now"}]},
  {"id":"C9","name":"🏠 recategorised","labels":[{"name":"Now"}]},
  {"id":"C10","name":"👩🏽‍💻 pair on it","labels":[{"name":"Now"}]}
]'
: > "$CURL_LOG"
capture "$LIFE" sort L1 "Now:🔥,Health" --apply
eq "sort --apply exits 0" "0" "$RC"
# The PUT for one card, with or without a query string after its id.
put_for() { grep -E "/cards/$1(\\?| |\$)" "$CURL_LOG" || true; }
absent "sort leaves a Health card (no emoji in the order) untouched" "name=" "$(put_for C1)"
absent "sort leaves an unlabelled card untouched" "name=" "$(put_for C2)"
contains "sort still positions the untouched cards" "pos=" "$(put_for C2)"
contains "sort keeps a leading backtick" 'name=🔥 `make` fails' "$(put_for C3)"
contains "sort keeps a leading ^" "name=🔥 ^ raise" "$(put_for C4)"
contains "sort keeps a leading ©" "name=🔥 ©2026 renewal" "$(put_for C5)"
contains "sort keeps a leading ™" "name=🔥 ™ brand" "$(put_for C6)"
contains "sort keeps a leading °" "name=🔥 °C thermostat" "$(put_for C7)"
absent "sort does not rewrite a title that already carries its stamp" "name=" "$(put_for C8)"
contains "sort swaps an old emoji for the category's" "name=🔥 recategorised" "$(put_for C9)"
contains "sort strips a whole emoji sequence, skin tone and joiner included" "name=🔥 pair on it" "$(put_for C10)"

capture "$LIFE" sort L1 "Now:🔥,Health"
contains "the dry run keeps the Health card's title" "🦷 Book the dentist" "$OUT"
absent "the dry run proposes no rename for cards it leaves alone" "was: 🦷" "$OUT"
absent "the dry run proposes no rename for the unlabelled card" "was: 🚗" "$OUT"

# A stamp the regex does not know as emoji - U+2764 without U+FE0F - is still
# recognised as this order's own, so a re-run never doubles it up.
export FAKE_BODY='[{"id":"C1","name":"❤ Book the dentist","labels":[{"name":"Health"}]}]'
: > "$CURL_LOG"
capture "$LIFE" sort L1 "Health:❤" --apply
absent "sort does not double a text-style stamp from the order" "name=" "$(put_for C1)"
unset FAKE_BODY

# sort --apply WRITES ONLY WHAT MUST CHANGE, AND CHECKS EVERY WRITE. It used
# to send a PUT for every card on the list, whether or not its place or title
# changed, and printed every line as done. Each write moves the card's
# dateLastActivity and lands in the board's activity, so re-sorting a sorted
# list made every card look fresh; and a write Trello refused part way through
# left a half-sorted list with no word of which card it stopped at.
export FAKE_BODY='[
  {"id":"S1","name":"🔥 Alpha","pos":1000,"labels":[{"name":"Now"}]},
  {"id":"S2","name":"🔥 Beta","pos":2000,"labels":[{"name":"Now"}]},
  {"id":"S3","name":"Gamma","pos":3000,"labels":[{"name":"Health"}]},
  {"id":"S4","name":"Delta","pos":4000,"labels":[]}
]'
: > "$CURL_LOG"
capture "$LIFE" sort L1 "Now:🔥,Health" --apply
eq "sort --apply on a sorted list exits 0" "0" "$RC"
eq "sort --apply on a sorted list makes no write request" "0" "$(grep -c -- '-X PUT' "$CURL_LOG" || true)"
contains "sort --apply on a sorted list says it wrote nothing" "nothing written" "$OUT"
capture "$LIFE" sort L1 "Now:🔥,Health"
contains "the dry run on a sorted list says --apply would write nothing" "would write nothing" "$OUT"

# One card out of place is one write, into the gap, and no rename.
export FAKE_BODY='[
  {"id":"S1","name":"🔥 Alpha","pos":1000,"labels":[{"name":"Now"}]},
  {"id":"S4","name":"Delta","pos":1500,"labels":[]},
  {"id":"S2","name":"🔥 Beta","pos":2000,"labels":[{"name":"Now"}]},
  {"id":"S3","name":"Gamma","pos":3000,"labels":[{"name":"Health"}]}
]'
: > "$CURL_LOG"
capture "$LIFE" sort L1 "Now:🔥,Health" --apply
eq "one card out of place is one write" "1" "$(grep -c -- '-X PUT' "$CURL_LOG" || true)"
contains "the card out of place goes after the last card it follows" "/cards/S4?pos=4000" "$(put_for S4)"
absent "moving a card does not rename it" "name=" "$(put_for S4)"
contains "sort --apply counts what it wrote" "Wrote 1 of 4 cards: 1 moved, 0 renamed." "$OUT"
capture "$LIFE" sort L1 "Now:🔥,Health"
contains "the dry run counts what --apply would write" "--apply would write 1 of 4 cards: 1 to move, 0 to rename." "$OUT"

# A card that belongs between two kept ones lands between them.
export FAKE_BODY='[
  {"id":"S2","name":"🔥 Beta","pos":1000,"labels":[{"name":"Now"}]},
  {"id":"S1","name":"🔥 Alpha","pos":2000,"labels":[{"name":"Now"}]},
  {"id":"S3","name":"Gamma","pos":3000,"labels":[{"name":"Health"}]}
]'
: > "$CURL_LOG"
capture "$LIFE" sort L1 "Now:🔥,Health" --apply
eq "a swapped pair is one write" "1" "$(grep -c -- '-X PUT' "$CURL_LOG" || true)"
# Either card of the pair may be the one kept. Both answers put Alpha first.
case "$(grep -- '-X PUT' "$CURL_LOG")" in
    *"/cards/S1?pos=500"|*"/cards/S2?pos=2500") swap="into the gap" ;;
    *) swap="$(grep -- '-X PUT' "$CURL_LOG")" ;;
esac
eq "the moved card goes into the gap beside its kept neighbour" "into the gap" "$swap"
unset swap
unset FAKE_BODY

# A write Trello refuses stops the run, names the card and says the list is
# only partly sorted. The fake answers the second card's PUT with a 500 once.
export FAKE_DIR="$SANDBOX/sortfail"; mkdir -p "$FAKE_DIR"
echo '[
  {"id":"F1","name":"Zulu","pos":1000,"labels":[{"name":"Now"}]},
  {"id":"F2","name":"Yankee","pos":2000,"labels":[{"name":"Now"}]},
  {"id":"F3","name":"X-ray","pos":3000,"labels":[{"name":"Now"}]}
]' > "$FAKE_DIR/lists_L1_cards.json"
echo '500 Internal Server Error' > "$FAKE_DIR/cards_F2.status"
: > "$CURL_LOG"
capture "$LIFE" sort L1 "Now:🔥" --apply
eq "a refused write makes sort --apply exit non-zero" "1" "$RC"
contains "a refused write names the card sort stopped at" 'sort stopped at "Yankee" (F2)' "$ERR"
contains "a refused write says the list is partly sorted" "only partly sorted" "$ERR"
contains "a refused write passes on Trello's status" "HTTP 500" "$ERR"
eq "sort --apply makes no write after the refused one" "" "$(put_for F1)"
absent "sort --apply does not report the refused card as written" "Yankee" "$OUT"
unset FAKE_DIR

# stale IGNORES A RENAME OR A MOVE. Trello's dateLastActivity moves on both,
# so straight after sort --apply every card on the list looked fresh. A card
# now counts as touched only by an action that is more than a rename or a
# position change.
export FAKE_DIR="$SANDBOX/stale"; mkdir -p "$FAKE_DIR"
new_id="$(printf '%08x' "$(command date +%s)")0000000000000000"
recent="$(command date -u +%Y-%m-%dT%H:%M:%S.000Z)"
cat > "$FAKE_DIR/lists_L1_cards.json" <<JSON
[
  {"id":"5f0000000000000000000001","name":"Only sorted","dateLastActivity":"$recent","idBoard":"B1"},
  {"id":"5f0000000000000000000002","name":"Only renamed","dateLastActivity":"$recent","idBoard":"B1"},
  {"id":"5f0000000000000000000003","name":"Commented","dateLastActivity":"$recent","idBoard":"B1"},
  {"id":"5f0000000000000000000004","name":"New description","dateLastActivity":"$recent","idBoard":"B1"},
  {"id":"5f0000000000000000000005","name":"Long idle","dateLastActivity":"2025-01-01T12:00:00.000Z","idBoard":"B1"},
  {"id":"$new_id","name":"Just created","dateLastActivity":"$recent","idBoard":"B1"}
]
JSON
cat > "$FAKE_DIR/boards_B1_actions.json" <<JSON
[
  {"id":"A1","type":"updateCard","date":"$recent","data":{"card":{"id":"5f0000000000000000000001"},"old":{"pos":1000}}},
  {"id":"A2","type":"updateCard","date":"$recent","data":{"card":{"id":"5f0000000000000000000002"},"old":{"name":"x"}}},
  {"id":"A3","type":"commentCard","date":"$recent","data":{"card":{"id":"5f0000000000000000000003"}}},
  {"id":"A4","type":"updateCard","date":"$recent","data":{"card":{"id":"5f0000000000000000000004"},"old":{"desc":""}}}
]
JSON
: > "$CURL_LOG"
capture "$LIFE" stale L1 14
eq "stale exits 0" "0" "$RC"
contains "stale reads the board's actions since the cutoff" "/boards/B1/actions?since=" "$(cat "$CURL_LOG")"
contains "stale counts a card that was only repositioned" "Only sorted" "$OUT"
contains "stale counts a card that was only renamed" "Only renamed" "$OUT"
contains "stale says a card touched only by a sort is idle since before the cutoff" "before " \
   "$(printf '%s\n' "$OUT" | grep 'Only sorted')"
absent "stale does not count a card with a new comment" "Commented" "$OUT"
absent "stale does not count a card with a new description" "New description" "$OUT"
absent "stale does not count a card created after the cutoff" "Just created" "$OUT"
contains "stale still dates a card idle since before the cutoff" "  2025-01-01  Long idle" "$OUT"
# When no card shows activity since the cutoff, no actions are fetched.
echo '[{"id":"5f0000000000000000000005","name":"Long idle","dateLastActivity":"2025-01-01T12:00:00.000Z","idBoard":"B1"}]' \
    > "$FAKE_DIR/lists_L1_cards.json"
: > "$CURL_LOG"
capture "$LIFE" stale L1 14
absent "stale fetches no actions when every card is plainly idle" "/actions" "$(cat "$CURL_LOG")"
unset FAKE_DIR new_id recent

# STORE PRESETS ARE DATA, AND THE SUITE CHECKS THEM. store-sort kept its aisle
# order as prose the agent read card by card, and the prose had errors a check
# would have caught: a section 100 positions wide asked to space its items
# about 100 apart, prawns and blueberries listed twice, and one emoji each for
# lemons and limoncello, oils and sake, yoghurt and ice cream. Every preset
# shipped in references/stores/ is checked here.
PRESETS=("$REPO_ROOT"/skills/store-sort/references/stores/*.json)
eq "at least one store preset ships as data" "yes" "$([ -f "${PRESETS[0]}" ] && echo yes || echo no)"
for f in "${PRESETS[@]}"; do
    [ -f "$f" ] || continue
    n="preset $(basename "$f")"
    eq "$n is valid JSON" "ok" "$(jq -e '.sections | length > 0' "$f" >/dev/null 2>&1 && echo ok || echo invalid)"
    eq "$n: every section has a name, an emoji and items" "" \
       "$(jq -r '.sections[] | select((.name | type) != "string" or (.emoji | type) != "string"
            or (.emoji | length) == 0 or (.items | type) != "array" or (.items | length) == 0) | .name // "?"' "$f")"
    eq "$n: no two sections share a name" "" \
       "$(jq -r '[.sections[].name | ascii_downcase] | group_by(.)[] | select(length > 1) | .[0]' "$f")"
    eq "$n: every item has an emoji and a keyword" "" \
       "$(jq -r '.sections[] | .name as $s | .items[] | select((.emoji | type) != "string" or (.emoji | length) == 0
            or (.keywords | type) != "array" or (.keywords | length) == 0) | $s' "$f")"
    eq "$n: every range is two whole numbers, low then high" "" \
       "$(jq -r '.sections[] | select((.range | length) != 2 or (.range | map(type == "number" and . == floor) | all | not)
            or .range[0] >= .range[1]) | .name' "$f")"
    eq "$n: ranges rise in aisle order and do not overlap" "" \
       "$(jq -r '.sections as $a | range(1; $a | length) | select($a[.].range[0] <= $a[. - 1].range[1])
            | "\($a[. - 1].name) / \($a[.].name)"' "$f")"
    eq "$n: no keyword is listed twice, in one section or in two" "" \
       "$(jq -r '[.sections[] | .name as $s | .items[].keywords[] | {k: ascii_downcase, s: $s}]
            | group_by(.k)[] | select(length > 1) | "\(.[0].k): \(map(.s) | join(", "))"' "$f")"
    eq "$n: no emoji belongs to two sections" "" \
       "$(jq -r '[.sections[] | .name as $s | ([.emoji] + [.items[].emoji]) | map(gsub("\ufe0f"; "")) | unique[]
            | {e: ., s: $s}] | group_by(.e)[] | select(length > 1) | "\(.[0].e): \(map(.s) | join(", "))"' "$f")"
    eq "$n: every keyword is plain words" "" \
       "$(jq -r '.sections[].items[].keywords[] | select(test("^[\\p{L}\\p{N}][\\p{L}\\p{N} '"'"'-]*$") | not)' "$f")"
done
contains "the Tesco preset says it is one store's layout" "One store's layout" \
   "$(jq -r '.about' "$REPO_ROOT/skills/store-sort/references/stores/tesco.json" 2>/dev/null)"
STORE_MD=$(cat "$REPO_ROOT/skills/store-sort/SKILL.md")
absent "store-sort/SKILL.md positions no card one call at a time" "trello-cards.sh position" "$STORE_MD"
absent "store-sort/SKILL.md renames no card one call at a time" "trello-cards.sh update" "$STORE_MD"
contains "store-sort/SKILL.md applies the whole list in one call" 'store-sort.sh apply <list-id> "$PLAN" --apply' "$STORE_MD"
unset STORE_MD PRESETS

# plan MATCHES EVERY CARD, AND WRITES NOTHING. The longest keyword wins, so
# "black pepper" is a spice and not a bell pepper, and "coconut milk" is world
# food and not fruit. An emoji from another section is replaced: fresh chillies
# are Veg's 🌶️, chilli flakes are a spice.
export FAKE_BODY='[
  {"id":"G1","name":"Crackers","pos":1},
  {"id":"G2","name":"bananas","pos":2},
  {"id":"G3","name":"🥔 1.5kg baby potatoes","pos":3},
  {"id":"G4","name":"Black pepper","pos":4},
  {"id":"G5","name":"Mystery item","pos":5},
  {"id":"G6","name":"Butter","pos":6},
  {"id":"G7","name":"🌶️ Chilli flakes","pos":7},
  {"id":"G8","name":"coconut milk","pos":8}
]'
: > "$CURL_LOG"
capture "$STORE" plan L1
eq "plan exits 0" "0" "$RC"
eq "plan makes one request" "1" "$(wc -l < "$CURL_LOG" | tr -d ' ')"
eq "plan writes nothing" "0" "$(grep -c -- '-X PUT' "$CURL_LOG" || true)"
eq "plan puts every card in a section, in aisle order, with that section's emoji" "Fruit|🍌 bananas
Veg|🥔 1.5kg baby potatoes
Spices, Seasonings, Oils & Vinegars|🧂 Chilli flakes
Spices, Seasonings, Oils & Vinegars|🧂 Black pepper
Spices, Seasonings, Oils & Vinegars|🧈 Butter
Pasta, Rice, Noodles & World Foods|🥢 coconut milk
Snacks|🥨 Crackers
-|Mystery item" "$(printf '%s\n' "$OUT" | jq -r '.cards[] | "\(.section // "-")|\(.name)"')"
eq "plan records the store" "tesco" "$(printf '%s\n' "$OUT" | jq -r '.store')"
contains "plan names the card no keyword matched" "Mystery item" "$ERR"

# apply WRITES THE WHOLE LIST IN ONE CALL. It was one update and one position
# call per card, so a 40-item list took up to 80 tool calls.
PLAN_FILE="$SANDBOX/store-plan.json"
printf '%s\n' "$OUT" \
    | jq '.cards |= map(if .section == null then .section = "Snacks" | .name = "🍫 Mystery item" else . end)' \
    > "$PLAN_FILE"
: > "$CURL_LOG"
capture "$STORE" apply L1 "$PLAN_FILE"
eq "the apply dry run exits 0" "0" "$RC"
eq "the apply dry run writes nothing" "0" "$(grep -c -- '-X PUT' "$CURL_LOG" || true)"
contains "the apply dry run says what --apply would write" \
   "--apply would write 8 of 8 cards: 8 to move, 7 to rename." "$OUT"
contains "the apply dry run heads each section" "🍓 Fruit" "$OUT"
: > "$CURL_LOG"
capture "$STORE" apply L1 "$PLAN_FILE" --apply
eq "apply --apply exits 0" "0" "$RC"
eq "one apply call writes every card that changes" "8" "$(grep -c -- '-X PUT' "$CURL_LOG" || true)"
contains "apply sends a new title with --data-urlencode" "--data-urlencode name=🍌 bananas" "$(put_for G2)"
absent "apply does not rename a card whose title is already right" "name=" "$(put_for G3)"
contains "apply places a card inside its section's range" "/cards/G2?pos=1499" "$(put_for G2)"
contains "apply spreads a section's cards through its range, in plan order" "/cards/G4?pos=8499" "$(put_for G4)"
cat "$PLAN_FILE" > "$SANDBOX/store-plan-stdin.json"
: > "$CURL_LOG"
OUT=$(env HOME="$SANDBOX/home" CURL_LOG="$CURL_LOG" PATH="$SANDBOX/bin:$PATH" \
      bash "$STORE" apply L1 - < "$SANDBOX/store-plan-stdin.json" 2>&1)
contains "apply reads a plan from stdin with -" "--apply would write 8 of 8" "$OUT"

# A list already in order gets no write.
export FAKE_BODY='[{"id":"G2","name":"🍌 bananas","pos":10},{"id":"G1","name":"🥨 Crackers","pos":20}]'
printf '%s' '{"store":"tesco","cards":[{"id":"G2","section":"Fruit","name":"🍌 bananas"},
  {"id":"G1","section":"Snacks","name":"🥨 Crackers"}]}' > "$PLAN_FILE"
: > "$CURL_LOG"
capture "$STORE" apply L1 "$PLAN_FILE" --apply
eq "apply on a list already in order exits 0" "0" "$RC"
eq "apply on a list already in order makes no write" "0" "$(grep -c -- '-X PUT' "$CURL_LOG" || true)"
contains "apply on a list already in order says so" "nothing written" "$OUT"

# A plan that does not fit the list or the store is refused before any write.
export FAKE_BODY='[{"id":"G1","name":"Crackers","pos":1},{"id":"G2","name":"bananas","pos":2}]'
check_refused() {  # check_refused <what> <plan json> <expected on stderr>
    printf '%s' "$2" > "$PLAN_FILE"
    : > "$CURL_LOG"
    capture "$STORE" apply L1 "$PLAN_FILE" --apply
    eq "apply refuses $1, exit 1" "1" "$RC"
    contains "apply refuses $1, and says why" "$3" "$ERR"
    eq "apply refuses $1, with no write" "0" "$(grep -c -- '-X PUT' "$CURL_LOG" || true)"
}
G1_OK='{"id":"G1","section":"Snacks","name":"🥨 Crackers"}'
check_refused "a plan that leaves a card out" "{\"cards\":[$G1_OK]}" 'not in the plan: "bananas" (G2)'
check_refused "a card not on the list" \
    "{\"cards\":[$G1_OK,{\"id\":\"G2\",\"section\":\"Fruit\",\"name\":\"🍌 bananas\"},{\"id\":\"ZZ\",\"section\":\"Fruit\",\"name\":\"🍎 x\"}]}" \
    "not on this list: ZZ"
check_refused "a card with no section" "{\"cards\":[$G1_OK,{\"id\":\"G2\",\"section\":null,\"name\":\"bananas\"}]}" \
    'no section: "bananas" (G2)'
check_refused "a section the store does not have" \
    "{\"cards\":[$G1_OK,{\"id\":\"G2\",\"section\":\"Garden centre\",\"name\":\"🍌 bananas\"}]}" \
    'no section called "Garden centre"'
check_refused "an emoji from another section" \
    "{\"cards\":[$G1_OK,{\"id\":\"G2\",\"section\":\"Fruit\",\"name\":\"🥨 bananas\"}]}" \
    "is planned for Fruit but starts with an emoji from Snacks"
check_refused "a plan that is not a plan" "nope" "not JSON with a cards array"
unset -f check_refused
unset G1_OK

# A write Trello refuses stops the run, names the card, and makes no more.
export FAKE_DIR="$SANDBOX/storefail"; mkdir -p "$FAKE_DIR"
echo '[{"id":"G1","name":"Crackers","pos":1},{"id":"G2","name":"bananas","pos":2}]' > "$FAKE_DIR/lists_L1_cards.json"
echo '500 Internal Server Error' > "$FAKE_DIR/cards_G2.status"
printf '%s' "{\"cards\":[{\"id\":\"G2\",\"section\":\"Fruit\",\"name\":\"🍌 bananas\"},
  {\"id\":\"G1\",\"section\":\"Snacks\",\"name\":\"🥨 Crackers\"}]}" > "$PLAN_FILE"
: > "$CURL_LOG"
capture "$STORE" apply L1 "$PLAN_FILE" --apply
eq "a refused write makes apply exit 1" "1" "$RC"
contains "a refused write names the card apply stopped at" 'store-sort stopped at "bananas" (G2)' "$ERR"
contains "a refused write says the list is partly sorted" "only partly sorted" "$ERR"
eq "apply makes no write after the refused one" "" "$(put_for G1)"
unset FAKE_DIR FAKE_BODY PLAN_FILE

# THE USER'S OWN STORE, AND THE SHIPPED ONES. ~/.dbhq/trello/stores/ is read
# first, and a store name cannot climb out of either directory.
mkdir -p "$SANDBOX/home/.dbhq/trello/stores"
echo '{"name":"Corner shop","about":"One small shop.","sections":[{"name":"Everything","emoji":"🛒","range":[1000,1999],"items":[{"emoji":"🛒","keywords":["milk"]}]}]}' \
    > "$SANDBOX/home/.dbhq/trello/stores/corner.json"
capture "$STORE" sections corner
contains "sections reads the user's own store" "1. 🛒 Everything" "$OUT"
capture "$STORE" stores
eq "stores lists the user's stores and the shipped ones" "corner
tesco" "$OUT"
capture "$STORE" sections
contains "sections defaults to the Tesco preset" "1. 🍓 Fruit" "$OUT"
contains "sections says the preset is one store's layout" "One store's layout" "$OUT"
capture "$STORE" sections ../../etc/passwd
eq "a store name with a path in it is refused" "1" "$RC"
contains "a store name with a path in it says what a name is" "lowercase letters, digits and hyphens" "$ERR"
capture "$STORE" sections nosuch
contains "an unknown store names the stores there are" "no store preset called 'nosuch'. There are: corner tesco" "$ERR"
rm -rf "$SANDBOX/home/.dbhq/trello/stores"
export FAKE_BODY='invalid token' FAKE_STATUS=401
check_error "store-sort plan" "$STORE" plan L1
unset FAKE_BODY FAKE_STATUS

# NO CONFIG MEANS NO REQUEST, AND A MESSAGE THAT NAMES THE FIX. All six
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
for s in "$DIGEST" "$DUE" "$LIFE" "$STORE"; do
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

# AND THE DOCS SAY SO BEFORE ANYTHING RUNS. A user picking skills one by one
# reads the README and the SKILL.md, not the error.
for skill in store-sort board-digest due-radar life-manager; do
    contains "$skill/SKILL.md says it needs trello, with the install command" \
       "npx skills add dbhq-uk/trello-skill --skill trello --skill $skill" \
       "$(cat "$REPO_ROOT/skills/$skill/SKILL.md")"
done
contains "the README install section says the other four need trello" \
   "each of those four must have \`trello\` installed beside it" "$(tr '\n' ' ' < "$REPO_ROOT/README.md")"
contains "the README shows installing trello alongside a single skill" \
   "npx skills add dbhq-uk/trello-skill --skill trello --skill" "$(cat "$REPO_ROOT/README.md")"

# EVERY SCRIPT A SKILL.md RUNS HAS ITS PATH. A bare `trello-cards.sh` in a code
# block works only if the agent guesses where it lives, and on a partial or
# Codex install it guesses wrong. Checked inside code fences only, where the
# lines are commands; prose may name a script on its own.
bare=$(for f in "$REPO_ROOT"/skills/*/SKILL.md; do
    awk -v f="${f#"$REPO_ROOT"/}" '/^[[:space:]]*```/{fence=!fence; next}
        fence { line=$0
                while (match(line, /[[:alnum:]_.\/${}-]*(trello-cards|trello-boards|trello-setup|board-digest|due-radar|life-board|store-sort)\.sh/)) {
                    tok=substr(line, RSTART, RLENGTH)
                    if (tok !~ /^\$\{CLAUDE_SKILL_DIR\}\//) print f ": " $0
                    line=substr(line, RSTART+RLENGTH)
                } }' "$f"
done)
eq "every script run in a SKILL.md code block starts at \${CLAUDE_SKILL_DIR}" "" "$bare"

# USAGE WITHOUT ARGUMENTS, AND WITHOUT A REQUEST. An unknown verb must not
# reach the API: it is how a typo becomes a call against a path built from the
# typo. And it must fail: usage on stdout with exit 0 reads to an agent like a
# result, which is how a call to a verb that did not exist went unnoticed.
for s in "${ALL_SCRIPTS[@]}"; do
    n=$(basename "$s")
    : > "$CURL_LOG"
    capture "$s" definitely-not-a-verb
    eq "$n: an unknown verb exits 2" "2" "$RC"
    contains "$n: an unknown verb prints usage on stderr" "Usage: $n" "$ERR"
    eq "$n: an unknown verb prints nothing on stdout" "" "$OUT"
    eq "$n: an unknown verb makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"
    capture "$s" help
    eq "$n help exits 0" "0" "$RC"
    contains "$n help prints usage on stdout" "Usage: $n" "$OUT"
done

# THE labels VERB THE DOCS SEND AGENTS TO. trello/SKILL.md, life-manager's
# SKILL.md and label-add's own comment all say label ids come from
# `trello-boards.sh labels <board-id>`, and until it existed that call fell
# through to the usage text.
export FAKE_BODY='[{"id":"LB1","name":"Health","color":"green"},{"id":"LB2","name":"","color":null}]'
: > "$CURL_LOG"
capture "$BOARDS" labels B1
eq "labels exits 0" "0" "$RC"
eq "labels prints each label as [id] name (colour)" "[LB1] Health (green)
[LB2] (no name) (no colour)" "$OUT"
contains "labels asks for the board's labels" "https://api.trello.com/1/boards/B1/labels?" "$(cat "$CURL_LOG")"
export FAKE_BODY='[]'
capture "$BOARDS" labels B1
eq "labels on a board with none says so" "No labels on this board." "$OUT"
unset FAKE_BODY
: > "$CURL_LOG"
capture "$BOARDS" labels
eq "labels with no board id prints its usage line" "Usage: trello-boards.sh labels <board-id>" "$OUT"
eq "labels with no board id makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"

# THE WRITE VERBS life-manager NEEDS. Its setup creates a board, renames and
# adds lists and agrees labels, and its coach mode ticks checklist items, but
# no script could do any of it - so the agent wrote raw curl calls with the key
# and token in its own command line. Each verb is checked for its endpoint,
# its method, and that caller text goes out with --data-urlencode rather than
# in the URL.
check_write() {  # check_write <name> <method> <url> <expected arg>... -- <script> [args...]
    local name="$1" method="$2" url="$3"; shift 3
    local want=()
    while [ "$1" != "--" ]; do want+=("$1"); shift; done; shift
    : > "$CURL_LOG"
    capture "$@"
    local line; line=$(cat "$CURL_LOG")
    eq "$name exits 0" "0" "$RC"
    eq "$name makes one request" "1" "$(wc -l < "$CURL_LOG" | tr -d ' ')"
    contains "$name uses $method" "-X $method " "$line"
    eq "$name goes to $url" "$url" "$(echo "$line" | grep -oE 'https://[^ ]+')"
    for w in "${want[@]}"; do
        contains "$name sends $w" "--data-urlencode $w" "$line"
    done
}
export FAKE_BODY='{"id":"NEW1","name":"n","url":"u","color":"green","state":"complete"}'
check_write "board-create" POST "https://api.trello.com/1/boards" \
    "name=Life & admin" "desc=C++ + notes" -- "$BOARDS" board-create "Life & admin" "C++ + notes"
check_write "list-create" POST "https://api.trello.com/1/lists" \
    "idBoard=B1" "name=Inbox & misc" "pos=top" -- "$BOARDS" list-create B1 "Inbox & misc" top
check_write "list-create at the default position" POST "https://api.trello.com/1/lists" \
    "pos=bottom" -- "$BOARDS" list-create B1 "Backlog"
check_write "list-rename" PUT "https://api.trello.com/1/lists/L1" \
    "name=Today + tomorrow" -- "$BOARDS" list-rename L1 "Today + tomorrow"
check_write "label-create" POST "https://api.trello.com/1/boards/B1/labels" \
    "name=Health & fitness" "color=green" -- "$BOARDS" label-create B1 "Health & fitness" green
check_write "label-create with no colour" POST "https://api.trello.com/1/boards/B1/labels" \
    "color=null" -- "$BOARDS" label-create B1 "Admin"
check_write "checkitem-done" PUT "https://api.trello.com/1/cards/CARD1/checkItem/ITEM1" \
    "state=complete" -- "$CARDS" checkitem-done CARD1 ITEM1
capture "$BOARDS" label-create B1 "Health" green
eq "label-create prints the new label's id" "Label created:
[NEW1] n (green)" "$OUT"
unset FAKE_BODY
unset -f check_write

# A missing argument prints the verb's usage and sends nothing.
for args in "board-create" "list-create B1" "list-rename L1" "label-create B1"; do
    : > "$CURL_LOG"
    # shellcheck disable=SC2086  # the words are the arguments
    capture "$BOARDS" $args
    contains "$args with an argument missing prints its usage" "Usage: trello-boards.sh ${args%% *}" "$OUT"
    eq "$args with an argument missing makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"
done
: > "$CURL_LOG"
capture "$CARDS" checkitem-done CARD1
contains "checkitem-done with no item id prints its usage" "Usage: trello-cards.sh checkitem-done" "$OUT"
eq "checkitem-done with no item id makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"
: > "$CURL_LOG"
capture "$BOARDS" list-create B1 "Inbox" middle
eq "list-create refuses a position other than top or bottom" "1" "$RC"
eq "list-create with a bad position makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"

# A refused write is an error, not a success line.
export FAKE_BODY='invalid token' FAKE_STATUS=401
check_error "board-create"   "$BOARDS" board-create "Life"
check_error "list-create"    "$BOARDS" list-create B1 "Inbox"
check_error "list-rename"    "$BOARDS" list-rename L1 "Today"
check_error "label-create"   "$BOARDS" label-create B1 "Health"
check_error "checkitem-done" "$CARDS" checkitem-done CARD1 ITEM1
unset FAKE_BODY FAKE_STATUS

# checkitem-done needs an item id, so checklist has to show one.
export FAKE_BODY='[{"id":"CL1","name":"Chips","checkItems":[
  {"id":"IT2","name":"Second","state":"incomplete","pos":2},
  {"id":"IT1","name":"First","state":"complete","pos":1}]}]'
capture "$CARDS" checklist CARD1
eq "checklist shows each checklist's id and each item's id, in order" "=== Chips [CL1] ===
  [x] First  (item IT1)
  [ ] Second  (item IT2)" "$OUT"
unset FAKE_BODY

# Every verb is in its script's help and in trello/SKILL.md, and life-manager
# drives setup and coaching through them, with no request of its own.
capture "$BOARDS" help; BOARDS_HELP="$OUT"
capture "$CARDS" help; CARDS_HELP="$OUT"
TRELLO_MD=$(cat "$REPO_ROOT/skills/trello/SKILL.md")
LIFE_DOCS=$(cat "$REPO_ROOT/skills/life-manager/SKILL.md" "$REPO_ROOT/skills/life-manager/references/"*.md)
for v in board-create list-create list-rename label-create; do
    contains "trello-boards.sh help lists $v" "  $v " "$BOARDS_HELP"
    contains "trello/SKILL.md documents $v" "trello-boards.sh $v " "$TRELLO_MD"
    contains "life-manager uses $v" "trello-boards.sh $v " "$LIFE_DOCS"
done
contains "trello-cards.sh help lists checkitem-done" "  checkitem-done " "$CARDS_HELP"
contains "trello/SKILL.md documents checkitem-done" "trello-cards.sh checkitem-done " "$TRELLO_MD"
contains "life-manager uses checkitem-done" "trello-cards.sh checkitem-done " "$LIFE_DOCS"
eq "life-manager's docs make no request of their own" "" \
   "$(printf '%s\n' "$LIFE_DOCS" | grep -nE 'curl +-|api\.trello\.com' || true)"

# EVERY VERB, NOT ONLY THE NEW ONES. The command list in trello/SKILL.md left
# out label-add, label-remove, checklist-add and checkitem-add, so an agent
# reading it did not know they existed. The verbs are read from each script's
# own case statement, so a verb added later has to be documented too.
verbs_of() {  # the verbs in a script's case statement, help excluded
    grep -oE '^    [a-z][a-z-]*\)' "$1" | tr -d ' )'
}
for s in "$CARDS" "$BOARDS"; do
    n=$(basename "$s")
    capture "$s" help
    [ -n "$(verbs_of "$s")" ] || { FAIL=$((FAIL+1)); printf 'FAIL - no verbs read from %s\n' "$n"; }
    for v in $(verbs_of "$s"); do
        contains "$n help lists $v" "  $v " "$OUT"
        eq "trello/SKILL.md shows how to run $n $v" "yes" \
           "$(grep -qE "\\\$\\{CLAUDE_SKILL_DIR\\}/scripts/$n $v( |\$)" "$REPO_ROOT/skills/trello/SKILL.md" && echo yes || echo no)"
    done
done
unset -f verbs_of

# update takes any card field, so the docs name the ones worth knowing, and
# dueComplete - ticking a due date - is one of them.
contains "trello-cards.sh help names dueComplete as an update field" "dueComplete" "$(grep '  update ' <<< "$CARDS_HELP")"
contains "trello/SKILL.md names dueComplete as an update field" "dueComplete" "$(grep -i 'update card field' <<< "$TRELLO_MD")"

# delete cannot be undone. trello/SKILL.md offered it with no rule, beside a
# confirm rule for creating a card.
contains "trello/SKILL.md never deletes a card the user did not name" \
   "Never delete a card unless the user names that card and asks for it to be deleted." "$TRELLO_MD"
contains "trello/SKILL.md prefers archive to delete" "Prefer \`archive\`" "$TRELLO_MD"
unset BOARDS_HELP CARDS_HELP TRELLO_MD LIFE_DOCS

: > "$CURL_LOG"
out=$(run_in_sandbox "$CARDS" create L1)
contains "create with a missing title prints its own usage line" "Usage: trello-cards.sh create" "$out"
eq "create with a missing title makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"

# PAGING. Trello answers at most 1000 results to one request and says nothing
# when it stops, so one page read as the whole answer made "the last 7 days"
# of a busy board its last few hours, and cut a card's comments at 50. The fake
# serves a full page of 1000, then 3 more to a request that carries before=.
# Ids are fixed-width, so the smallest is the oldest, as with Trello's.
export FAKE_DIR="$SANDBOX/pages"; mkdir -p "$FAKE_DIR"
# fake_actions <from> <to> <type>: one action per n, newest (highest) first.
fake_actions() {
    jq -n --argjson a "$1" --argjson b "$2" --arg t "$3" '[range($a; $b; -1)
        | { id: (tostring | ("0" * (24 - length)) + .), type: $t,
            date: "2026-06-14T10:00:00.000Z",
            data: { card: { name: "card \(.)" }, text: "comment \(.)" },
            memberCreator: { fullName: "n" } }]'
}
echo '{"name":"Busy board","url":"u"}' > "$FAKE_DIR/boards_B1.json"
echo '[]' > "$FAKE_DIR/boards_B1_lists.json"
echo '[]' > "$FAKE_DIR/boards_B1_cards.json"
fake_actions 2000 1000 createCard > "$FAKE_DIR/boards_B1_actions.json"
fake_actions 1000 997 createCard  > "$FAKE_DIR/boards_B1_actions.before.json"
: > "$CURL_LOG"
capture "$DIGEST" digest B1 7
eq "digest over two pages exits 0" "0" "$RC"
eq "digest reports every action in the window, across both pages" "1003" \
   "$(grep -c ' created: card ' <<< "$OUT")"
contains "digest asks for the maximum page of actions" "/boards/B1/actions?filter=createCard,commentCard,updateCard&since=" \
   "$(grep '/actions?' "$CURL_LOG" | head -1)"
contains "digest's first page asks for 1000" "limit=1000" "$(grep '/actions?' "$CURL_LOG" | head -1)"
contains "digest asks for the next page from the oldest id it has seen" \
   "before=000000000000000000001001" "$(grep '/actions?' "$CURL_LOG" | sed -n 2p)"
eq "digest stops at the short page" "2" "$(grep -c '/actions?' "$CURL_LOG")"
absent "an answer that fitted is not called capped" "capped" "$ERR"

fake_actions 2000 1000 commentCard > "$FAKE_DIR/cards_CARD1_actions.json"
fake_actions 1000 997 commentCard  > "$FAKE_DIR/cards_CARD1_actions.before.json"
capture "$CARDS" comments CARD1
eq "comments returns every comment on a card with more than 1000" "1003" \
   "$(grep -c 'n: comment ' <<< "$OUT")"

# Still more after the last page it will fetch: the result says it was cut.
export TRELLO_MAX_PAGES=1
capture "$CARDS" comments CARD1
eq "a capped result is still printed" "1000" "$(grep -c 'n: comment ' <<< "$OUT")"
contains "a capped result says so" "capped at 1000 results" "$ERR"
unset TRELLO_MAX_PAGES

# A full page whose cursor never moves - an endpoint that ignores before= -
# must end, and say it was capped, not loop.
cp "$FAKE_DIR/cards_CARD1_actions.json" "$FAKE_DIR/cards_CARD1_actions.before.json"
: > "$CURL_LOG"
capture "$CARDS" comments CARD1
eq "a page that repeats ends the paging" "2" "$(grep -c '/actions?' "$CURL_LOG")"
contains "and the result says it was capped" "capped at 1000 results" "$ERR"

# list shows <count> cards in list order, and says when that left some out.
jq -n '[range(73) | {id: "C\(.)", name: "card \(.)", desc: "", pos: (73 - .), labels: []}]' \
    > "$FAKE_DIR/lists_L1_cards.json"
capture "$CARDS" list L1
eq "list shows 50 cards by default" "50" "$(grep -c '^\[C' <<< "$OUT")"
contains "list says how many it left out" "(showing 50 of 73 cards" "$OUT"
eq "list shows them in list order" "[C72] card 72" "$(head -1 <<< "$OUT")"
capture "$CARDS" list L1 100
eq "a larger count shows them all" "73" "$(grep -c '^\[C' <<< "$OUT")"
absent "and does not claim any were left out" "showing" "$OUT"
capture "$CARDS" list L1 lots
eq "a count that is not a number is refused" "1" "$RC"
unset FAKE_DIR

# A BOARD THAT COULD NOT BE READ IS NAMED, NOT DROPPED. due-radar all used to
# turn a failed board into an empty list: it printed the others, said nothing
# about the gap and exited 0, so "nothing due" covered a board it never saw.
export FAKE_DIR="$SANDBOX/radar"; mkdir -p "$FAKE_DIR"
echo '[{"id":"B1","name":"Home"},{"id":"B2","name":"Work"}]' > "$FAKE_DIR/members_me_boards.json"
echo '[{"id":"X1","name":"Renew passport","due":"2020-01-01T09:00:00.000Z","dueComplete":false,"url":"u"}]' \
    > "$FAKE_DIR/boards_B1_cards.json"
echo '[{"id":"X2","name":"Invoice client","due":"2020-01-01T09:00:00.000Z","dueComplete":false,"url":"u"}]' \
    > "$FAKE_DIR/boards_B2_cards.json"
limited='429 {"error":"API_TOKEN_LIMIT_EXCEEDED","message":"Rate limit exceeded"}'
printf '%s\n' "$limited" "$limited" "$limited" "$limited" > "$FAKE_DIR/boards_B2_cards.status"
: > "$CURL_LOG"; : > "$CURL_LOG.sleep"
capture "$DUE" all 14
eq "due-radar all exits non-zero when a board could not be read" "1" "$RC"
contains "the boards it did read are still shown" "Renew passport" "$OUT"
contains "the output says the radar is incomplete" "could not read 1 of 2 boards" "$OUT"
contains "and names the board it could not read" "    - Work" "$OUT"
contains "Trello's reason is on stderr" "HTTP 429" "$ERR"
contains "and says it was retried first" "after 3 retries" "$ERR"

# A 429 IS RETRIED. Three more tries, waiting 2, 4 and 8 seconds, which spans
# Trello's whole 10-second window, before it counts as a failure.
eq "a 429 that persists is tried four times in all" "4" "$(grep -c '/boards/B2/cards' "$CURL_LOG")"
eq "with a doubling wait between tries" "2 4 8" "$(tr '\n' ' ' < "$CURL_LOG.sleep" | sed 's/ $//')"

# And a 429 that clears is not a failure at all.
printf '%s\n' "$limited" "$limited" > "$FAKE_DIR/boards_B2_cards.status"
: > "$CURL_LOG"; : > "$CURL_LOG.sleep"
capture "$DUE" all 14
eq "a 429 that clears on retry leaves due-radar exiting 0" "0" "$RC"
contains "and the board it retried is in the radar" "Invoice client" "$OUT"
absent "and nothing is called incomplete" "Incomplete" "$OUT"
eq "it asked three times: two refusals, then the answer" "3" "$(grep -c '/boards/B2/cards' "$CURL_LOG")"

# Any other error is not retried: a 401 will not be different in 2 seconds.
echo '401 invalid token' > "$FAKE_DIR/boards_B2_cards.status"
: > "$CURL_LOG"; : > "$CURL_LOG.sleep"
capture "$DUE" all 14
eq "a 401 is not retried" "1" "$(grep -c '/boards/B2/cards' "$CURL_LOG")"
eq "and is reported like any failed board" "1" "$RC"
contains "with Trello's own words" "invalid token" "$ERR"
unset FAKE_DIR

# LOCAL TIME END TO END: every script that shows a time, in a pinned zone.
export TZ=Europe/London FAKE_DIR="$SANDBOX/tz"; mkdir -p "$FAKE_DIR"
echo '{"id":"CARD1","name":"Late one","due":"2025-09-25T23:30:00.000Z","dueComplete":false,"labels":[]}' \
    > "$FAKE_DIR/cards_CARD1.json"
capture "$CARDS" read CARD1
contains "read shows the due time in local time, and the stored value" \
   "Due: 2025-09-26 00:30 local time (2025-09-25T23:30:00.000Z)" "$OUT"
echo '[{"id":"A1","date":"2025-09-25T23:30:00.000Z","data":{"text":"late note"},"memberCreator":{"fullName":"n"}}]' \
    > "$FAKE_DIR/cards_CARD1_actions.json"
capture "$CARDS" comments CARD1
eq "comments are dated in local time" "[2025-09-26] n: late note" "$OUT"
echo '{"name":"Board","url":"u"}' > "$FAKE_DIR/boards_B1.json"
echo '[{"id":"L1","name":"To do"}]' > "$FAKE_DIR/boards_B1_lists.json"
echo '[{"id":"X1","name":"Late one","idList":"L1","due":"2025-09-25T23:30:00.000Z","dueComplete":false,"labels":[]}]' \
    > "$FAKE_DIR/boards_B1_cards.json"
echo '[{"id":"A1","type":"createCard","date":"2025-09-25T23:30:00.000Z","data":{"card":{"name":"Late one"}}}]' \
    > "$FAKE_DIR/boards_B1_actions.json"
capture "$DIGEST" digest B1 7
contains "digest shows a due time in local time" "Late one (2025-09-26 00:30)" "$OUT"
contains "digest dates activity in local time" "2025-09-26 created: Late one" "$OUT"
contains "digest says its times are local" "times are local" "$OUT"
absent "digest no longer reports in UTC" "UTC" "$OUT"
echo '[{"id":"B1","name":"Board"}]' > "$FAKE_DIR/members_me_boards.json"
capture "$DUE" all 14
contains "due-radar says its times are local" "times are local" "$OUT"
absent "due-radar no longer reports in UTC" "UTC" "$OUT"
echo '[{"id":"X1","name":"Idle","dateLastActivity":"2025-09-25T23:30:00.000Z"}]' > "$FAKE_DIR/lists_L1_cards.json"
capture "$LIFE" stale L1 1
eq "stale dates the last activity in local time" "  2025-09-26  Idle" "$OUT"
unset TZ FAKE_DIR

# DONE IS NOT OVERDUE, END TO END. The list names come from the board's lists,
# fetched only when there is a due card to name.
export FAKE_DIR="$SANDBOX/done"; mkdir -p "$FAKE_DIR"
echo '{"name":"Board","url":"u"}' > "$FAKE_DIR/boards_B1.json"
echo '[{"id":"L1","name":"To do"},{"id":"L2","name":"✅ Done"},{"id":"L3","name":"Shipped"}]' > "$FAKE_DIR/boards_B1_lists.json"
echo '[{"id":"X1","name":"Still to do","idList":"L1","due":"2020-01-01T09:00:00.000Z","dueComplete":false,"url":"u","labels":[]},
       {"id":"X2","name":"Finished it","idList":"L2","due":"2020-01-02T09:00:00.000Z","dueComplete":false,"url":"u","labels":[]},
       {"id":"X3","name":"Went live","idList":"L3","due":"2020-01-03T09:00:00.000Z","dueComplete":false,"url":"u","labels":[]}]' \
    > "$FAKE_DIR/boards_B1_cards.json"
echo '[]' > "$FAKE_DIR/boards_B1_actions.json"
: > "$CURL_LOG"
capture "$DUE" board B1 14
eq "due-radar board exits 0" "0" "$RC"
contains "due-radar counts only the card that is not done" "2 overdue, 0 upcoming" "$OUT"
contains "due-radar names each card's list" "[Board / To do]" "$OUT"
contains "due-radar shows the Done card apart" "1 in a done list with the due date not ticked" "$OUT"
eq "and never calls it OVERDUE" "" "$(grep 'Finished it' <<< "$OUT" | grep OVERDUE || true)"
contains "due-radar asks for the board's lists to name them" "/boards/B1/lists?" "$(cat "$CURL_LOG")"
export TRELLO_DONE_LISTS="Shipped"
capture "$DUE" board B1 14
contains "TRELLO_DONE_LISTS makes a list of the user's own count as done" "1 overdue, 0 upcoming" "$OUT"
contains "and its card is shown apart" "2 in a done list" "$OUT"
unset TRELLO_DONE_LISTS
capture "$DIGEST" digest B1 7
contains "digest names the list of an overdue card" "OVERDUE : Still to do" "$OUT"
contains "digest names it in brackets" "[To do]" "$OUT"
contains "digest says a Done card's due date was not ticked" "in ✅ Done, due not ticked: Finished it" "$OUT"
eq "and never calls it OVERDUE" "" "$(grep 'Finished it' <<< "$OUT" | grep OVERDUE || true)"
echo '[{"id":"X9","name":"No date","idList":"L1","due":null,"dueComplete":false,"url":"u"}]' > "$FAKE_DIR/boards_B1_cards.json"
: > "$CURL_LOG"
capture "$DUE" board B1 14
eq "a board with nothing due costs no lists request" "0" "$(grep -c '/lists' "$CURL_LOG")"
unset FAKE_DIR

# board-digest CAPS EACH LIST AND SAYS WHAT HAS NOT MOVED. SKILL.md told the
# agent to flag cards that had not moved, but the script fetched
# dateLastActivity and never printed it - and it printed every card on every
# list, which floods the reader on a big board. Now each list shows its first
# <limit> cards in board order and counts the rest, and a section lists the
# cards with no activity for <idle-days>, oldest first, leaving out done lists.
export FAKE_DIR="$SANDBOX/digest-big"; mkdir -p "$FAKE_DIR"
now_s=$(command date -u +%s)
ago() { jq -rn --argjson t "$((now_s - $1 * 86400))" '$t | todate'; }
echo '{"name":"Big board","url":"u"}' > "$FAKE_DIR/boards_B1.json"
echo '[{"id":"L1","name":"Backlog"},{"id":"L2","name":"Done"}]' > "$FAKE_DIR/boards_B1_lists.json"
# Thirteen Backlog cards, served in reverse board order so the sort is tested.
# Card 03 and card 05 are long idle, card 07 idle for 5 days, the rest fresh;
# the Done card is the oldest of all and must never be called idle.
jq -n --arg fresh "$(ago 1)" --arg five "$(ago 5)" '
    [range(13; 0; -1) | {id: "K\(.)", name: ("card " + (if . < 10 then "0" else "" end) + tostring),
        idList: "L1", pos: (. * 100), due: null, dueComplete: false, labels: [],
        dateLastActivity: (if . == 3 then "2020-01-01T12:00:00.000Z"
                           elif . == 5 then "2021-06-01T12:00:00.000Z"
                           elif . == 7 then $five else $fresh end)}]
    + [{id: "KD", name: "finished long ago", idList: "L2", pos: 1, due: null, dueComplete: false,
        labels: [], dateLastActivity: "2019-01-01T12:00:00.000Z"}]' > "$FAKE_DIR/boards_B1_cards.json"
echo '[]' > "$FAKE_DIR/boards_B1_actions.json"
section() {  # section <heading start> - the lines of one ## section of $OUT
    printf '%s\n' "$OUT" | awk -v h="## $1" 'index($0, h) == 1 {f=1; next} /^## /{f=0} f && NF'
}
: > "$CURL_LOG"
capture "$DIGEST" digest B1
eq "digest on a big board exits 0" "0" "$RC"
contains "digest asks for each card's position" "pos" "$(grep '/boards/B1/cards' "$CURL_LOG")"
LISTS_OUT=$(section "Lists")
contains "a list still says how many cards it has" "### Backlog (13)" "$LISTS_OUT"
eq "a list shows 10 cards by default" "10" "$(grep -c '^  - card' <<< "$LISTS_OUT")"
eq "in board order, not the order Trello sent" "  - card 01" "$(grep -m1 '^  - card' <<< "$LISTS_OUT")"
absent "the cards past the cap are not listed" "card 11" "$LISTS_OUT"
contains "the rest are counted, with the call that shows them" \
   "  + 3 more (trello-cards.sh list L1 13 shows them all)" "$LISTS_OUT"
contains "a short list is shown whole" "  - finished long ago" "$LISTS_OUT"
IDLE_OUT=$(section "Not moved")
contains "digest has a not-moved section, 14 days by default" "## Not moved in 14 days or more" "$OUT"
eq "it lists the idle cards, oldest first, with their age and list" \
   "  - $(( (now_s - $(jq -rn '"2020-01-01T12:00:00Z" | fromdateiso8601')) / 86400 )) days, since 2020-01-01: card 03 [Backlog]
  - $(( (now_s - $(jq -rn '"2021-06-01T12:00:00Z" | fromdateiso8601')) / 86400 )) days, since 2021-06-01: card 05 [Backlog]" \
   "$IDLE_OUT"
absent "a card in a done list is never called idle" "finished long ago" "$IDLE_OUT"
capture "$DIGEST" digest B1 7 3
contains "idle-days lowers the bar" "5 days, since" "$(section "Not moved")"
contains "and the heading names it" "## Not moved in 3 days or more" "$OUT"
capture "$DIGEST" digest B1 7 14 1
eq "limit caps the not-moved section too" "  - card 03 [Backlog]|  + 1 more, not shown (pass a larger limit to see them)" \
   "$(section "Not moved" | sed 's/^  - [0-9]* days, since [0-9-]*: /  - /' | paste -sd '|' -)"
eq "and each list" "1" "$(grep -c '^  - card' <<< "$(section "Lists")")"
capture "$DIGEST" digest B1 7 14 20
absent "a limit above the list size shows the list whole" "more (trello-cards.sh" "$OUT"
echo '[{"id":"KD","name":"fresh","idList":"L1","pos":1,"dateLastActivity":"'"$(ago 1)"'"}]' > "$FAKE_DIR/boards_B1_cards.json"
capture "$DIGEST" digest B1
contains "a board where everything moved says so" "(none - every open card has had activity in the last 14 days)" "$OUT"
for bad in "7 soon" "7 14 0" "x"; do
    : > "$CURL_LOG"
    # shellcheck disable=SC2086  # the words are the arguments
    capture "$DIGEST" digest B1 $bad
    eq "digest refuses \"$bad\"" "1" "$RC"
    eq "digest with \"$bad\" makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"
done
unset FAKE_DIR now_s LISTS_OUT IDLE_OUT
unset -f ago section

# HOW TO WRITE ONE. Nothing told the agent, so the zone on a new due date was a
# guess. trello/SKILL.md now states the rule.
contains "trello/SKILL.md says to write a due date with an offset" "full ISO 8601 time with an offset" \
   "$(cat "$REPO_ROOT/skills/trello/SKILL.md")"
contains "and to default to 09:00 local" "09:00" "$(cat "$REPO_ROOT/skills/trello/SKILL.md")"

# SETUP NEEDS A TERMINAL, AND SAYS SO. Run by an agent, with no terminal on
# stdin, `read -p` met end of input and set -e ended the script with exit 1
# straight after the banner - no word of why, so the agent could not tell the
# user what to do. Now it exits 3 with the command for the user to run, and
# changes nothing. Both with and without an existing config, because the old
# script failed at a different prompt in each case.
: > "$CURL_LOG"
before=$(cat "$SANDBOX/home/.dbhq/trello/config.json")
capture "$SETUP"
eq "setup with no terminal exits 3" "3" "$RC"
contains "setup with no terminal tells the agent to have the user run it" "Ask the user to run it" "$ERR"
contains "and gives the command, with its full path, for the Claude Code prompt" "! $SETUP" "$ERR"
absent "and prints no prompt that nobody can answer" "Overwrite?" "$OUT$ERR"
eq "setup with no terminal makes no request" "0" "$(wc -l < "$CURL_LOG" | tr -d ' ')"
eq "setup with no terminal leaves an existing config alone" "$before" "$(cat "$SANDBOX/home/.dbhq/trello/config.json")"
fresh=$(mktemp -d)
env HOME="$fresh" CURL_LOG="$CURL_LOG" PATH="$SANDBOX/bin:$PATH" bash "$SETUP" </dev/null >/dev/null 2>&1
eq "setup with no terminal and no config also exits 3" "3" "$?"
eq "and writes no config" "absent" "$([ -e "$fresh/.dbhq/trello/config.json" ] && echo present || echo absent)"
rm -rf "$fresh"

# SETUP AT A TERMINAL. A real pseudo-terminal, driven the way a person would:
# wait for each prompt, then type the answer. Python's pty module is the one
# portable way to give the script a terminal on stdin; CI has python3.
#
# The key and token carry a " and a \. The old script wrote config.json
# through an unquoted heredoc, so a " made the file invalid JSON, and read
# without -r ate the \. The pty's echo comes back in the transcript, so the
# test can also see that the token is not shown as it is typed: the key is
# echoed, which proves the check can see echo at all.
cat > "$SANDBOX/pty_drive.py" <<'PY'
import os, pty, re, select, subprocess, sys, termios, time
# pty_drive.py <script> [expect:<regex> | send:<text> | secret:<text>]...
# expect waits up to 5 s for a regex (case-insensitive) after the last match;
# a prompt that never comes is skipped along with the answer after it.
# secret waits for the terminal's echo to go off before typing.
script, steps = sys.argv[1], sys.argv[2:]
master, slave = pty.openpty()
proc = subprocess.Popen(["bash", script], stdin=slave, stdout=slave, stderr=slave,
                        start_new_session=True)
buf, pos, skip = b"", 0, False
def pump(t):
    global buf
    r, _, _ = select.select([master], [], [], t)
    if r:
        try:
            buf += os.read(master, 65536)
        except OSError:
            pass
for step in steps:
    kind, _, arg = step.partition(":")
    if kind == "expect":
        pat, end, skip = re.compile(arg.encode(), re.I), time.time() + 5, True
        while time.time() < end and proc.poll() is None:
            m = pat.search(buf, pos)
            if m:
                pos, skip = m.end(), False
                break
            pump(0.05)
        continue
    if skip:
        continue
    if kind == "secret":
        end = time.time() + 2
        while time.time() < end and termios.tcgetattr(slave)[3] & termios.ECHO:
            time.sleep(0.02)
    os.write(master, arg.encode() + b"\n")
end = time.time() + 10
while proc.poll() is None and time.time() < end:
    pump(0.05)
pump(0.2)
sys.stdout.write(buf.decode("utf-8", "replace"))
sys.exit(proc.returncode if proc.returncode is not None else 99)
PY
if command -v python3 >/dev/null 2>&1; then
    export FAKE_DIR="$SANDBOX/setup"; mkdir -p "$FAKE_DIR"
    echo '{"username":"sam","fullName":"Sam Test"}' > "$FAKE_DIR/members_me.json"
    drive_setup() {  # drive_setup <home> <access> <expiry>; sets OUT and RC
        OUT=$(env HOME="$1" CURL_LOG="$CURL_LOG" PATH="$SANDBOX/bin:$PATH" FAKE_DIR="$FAKE_DIR" \
            python3 "$SANDBOX/pty_drive.py" "$SETUP" \
            'expect:api key: ' 'send:KEY"with\slash' \
            'expect:read only\?' "send:$2" \
            'expect:how long' "send:$3" \
            'expect:token[^\n]*: ' 'secret:TOK"with\slash')
        RC=$?
    }
    fresh=$(mktemp -d)
    : > "$CURL_LOG"
    drive_setup "$fresh" "" ""
    cfg="$fresh/.dbhq/trello/config.json"
    eq "setup at a terminal exits 0" "0" "$RC"
    eq "a \" or \\ in the key and token still makes a valid config file" "valid" \
       "$(jq -e . "$cfg" >/dev/null 2>&1 && echo valid || echo invalid)"
    eq "and the key is stored exactly as typed" 'KEY"with\slash' "$(jq -r '.api_key' "$cfg" 2>/dev/null)"
    eq "and the token is stored exactly as typed" 'TOK"with\slash' "$(jq -r '.token' "$cfg" 2>/dev/null)"
    eq "config.json is 600" "600" "$(stat -c '%a' "$cfg" 2>/dev/null || stat -f '%Lp' "$cfg")"
    contains "the key is echoed as it is typed (so the next check can see echo)" 'KEY"with\slash' "$OUT"
    absent "the token is not echoed as it is typed" "TOK" "$OUT"
    contains "setup tests the credentials before saving them" "Connected as: Sam Test (@sam)" "$OUT"
    contains "setup prints Trello's authorize link" "https://trello.com/1/authorize?" "$OUT"
    contains "the link asks for read and write by default" "scope=read,write&" "$OUT"
    contains "the link names an expiry, 30 days by default" "expiration=30days&" "$OUT"
    contains "the link names the application" "name=trello-skill&" "$OUT"
    contains "the link carries the key, urlencoded" 'key=KEY%22with%5Cslash' "$OUT"
    contains "setup offers a read-only token" "read only" "$OUT"
    eq "the key and token never reach a command line" "0" "$(grep -c 'TOK\|KEY' "$CURL_LOG" || true)"
    rm -rf "$fresh"

    fresh=$(mktemp -d)
    drive_setup "$fresh" "r" "never"
    contains "choosing read only asks for scope=read" "scope=read&" "$OUT"
    contains "and says what a read-only token cannot do" "This token is read only" "$OUT"
    contains "choosing never asks for a token that does not expire" "expiration=never&" "$OUT"
    rm -rf "$fresh"

    fresh=$(mktemp -d)
    drive_setup "$fresh" "maybe" ""
    eq "an answer that is not w or r stops setup" "1" "$RC"
    eq "and writes no config" "absent" "$([ -e "$fresh/.dbhq/trello/config.json" ] && echo present || echo absent)"
    rm -rf "$fresh"
    unset FAKE_DIR
    unset -f drive_setup
else
    printf 'skip - setup at a terminal: python3 not found\n'
fi

# TRIGGER PHRASES ARE SCOPED TO TRELLO. An agent picks a skill by the phrases
# in its description, so a bare phrase another skill also claims can load the
# wrong one: `trello` claimed "shopping list" and "sort cards", which are
# store-sort's job, life-manager claimed "I'm stuck" and "what should I do
# next", which decision skills claim, and due-radar claimed a bare "what's
# due", which a calendar claims. Checked on the quoted phrases in each
# description, case-insensitively, with a curly apostrophe read as straight.
phrases_of() {  # the quoted phrases in a SKILL.md description, one per line
    awk '/^---$/{n++; next} n==1 && /^description:/' "$REPO_ROOT/skills/$1/SKILL.md" \
        | grep -oE '"[^"]+"' | tr -d '"' | sed "s/’/'/g" | tr '[:upper:]' '[:lower:]'
}
for skill in trello store-sort board-digest due-radar life-manager; do
    [ -n "$(phrases_of "$skill")" ] || { FAIL=$((FAIL+1)); printf 'FAIL - %s has no quoted trigger phrases to check\n' "$skill"; }
    for bare in "shopping list" "sort cards" "i'm stuck" "what's due" "what's overdue" \
                "what should i do next" "sort my inbox" "help me get stuff done"; do
        eq "$skill does not claim the bare phrase \"$bare\"" "" \
           "$(phrases_of "$skill" | grep -Fx -- "$bare" || true)"
    done
done
eq "every due-radar phrase names trello or the radar" "" \
   "$(phrases_of due-radar | grep -v -e trello -e 'due radar' || true)"
eq "every life-manager phrase names a board, trello or the skill" "" \
   "$(phrases_of life-manager | grep -v -e board -e trello -e 'life manager' || true)"
contains "life-manager says it is not for general decisions" "Not for general decisions" \
   "$(cat "$REPO_ROOT/skills/life-manager/SKILL.md")"
contains "trello hands shopping-list sorting to store-sort" "that is store-sort" \
   "$(awk '/^---$/{n++; next} n==1' "$REPO_ROOT/skills/trello/SKILL.md")"
# trello/SKILL.md had its own shopping-sort workflow - list-json, categorise,
# then one position call per card - which bypassed store-sort's preset.
absent "trello/SKILL.md has no Smart Sorting workflow" "Smart Sorting" "$(cat "$REPO_ROOT/skills/trello/SKILL.md")"
eq "trello/SKILL.md positions no run of cards itself" "" \
   "$(grep -n 'position <card-id-[0-9]' "$REPO_ROOT/skills/trello/SKILL.md" || true)"
eq "no SKILL.md or reference offers \"I'm stuck\" as a trigger" "" \
   "$(grep -rn -i "\"I'm stuck\"" "$REPO_ROOT/skills" --include='*.md' || true)"
unset -f phrases_of

# THE LABEL RULE ONLY BINDS A BOARD THAT USES LABELS. trello/SKILL.md said
# every card on any board must carry a label, "No exceptions", with a
# developer label set and "align with the roadmap" as the example - so the
# agent labelled grocery items that store-sort categorises by emoji. The two
# skills now carry the same shopping-list sentence, word for word.
TRELLO_MD=$(cat "$REPO_ROOT/skills/trello/SKILL.md")
STORE_MD=$(cat "$REPO_ROOT/skills/store-sort/SKILL.md")
absent "trello/SKILL.md does not demand a label on every card" "No exceptions" "$TRELLO_MD"
contains "trello/SKILL.md limits the label rule to boards that use labels" \
   "On a board that uses labels, every card on a list you touch carries one." "$TRELLO_MD"
contains "trello/SKILL.md leaves an unlabelled board unlabelled" \
   "A board whose cards carry no labels stays that way" "$TRELLO_MD"
for name in "Typical set" "Business, Feature" "DevOps" "UI/UX" "Bug/Fix" "roadmap"; do
    absent "trello/SKILL.md suggests no label name or roadmap wording: $name" "$name" "$TRELLO_MD"
done
SHOPPING_RULE="On a shopping list the emoji at the start of each card's title is its category, so shopping cards carry no labels."
contains "trello/SKILL.md gives the shopping-list label rule" "$SHOPPING_RULE" "$TRELLO_MD"
contains "store-sort/SKILL.md gives the same shopping-list label rule" "$SHOPPING_RULE" "$STORE_MD"
unset TRELLO_MD STORE_MD SHOPPING_RULE

# ONE DESCRIPTION OF THE PACK. plugin.json, the README and the listings each
# worded the pack differently, and some left out store-sort or life-manager.
# The two in this repo are now one sentence, and it names every skill.
PLUGIN_DESC=$(jq -r '.description' "$REPO_ROOT/.claude-plugin/plugin.json")
eq "the README tagline is plugin.json's description" "**$PLUGIN_DESC**" \
   "$(grep -m1 -E '^\*\*.+\*\*$' "$REPO_ROOT/README.md")"
for d in "$REPO_ROOT"/skills/*/; do
    contains "plugin.json's description names $(basename "$d")" " $(basename "$d") " "$PLUGIN_DESC"
done
eq "the description fits GitHub's 350-character limit" "ok" \
   "$([ "${#PLUGIN_DESC}" -le 350 ] && echo ok || echo "${#PLUGIN_DESC} characters")"
unset PLUGIN_DESC

# THE REPO DOCS SAY WHAT THE REPO DOES. They had a clone path nobody uses, a
# skill count and a test count that had moved on, credentials in ~/.trello, a
# roadmap with nothing behind it, a pre-PR list without the test suite, and two
# different ways to revoke a token.
CONTRIB=$(cat "$REPO_ROOT/CONTRIBUTING.md")
contains "CONTRIBUTING's pre-PR list runs the test suite" "bash skills/trello/tests/helpers_test.sh" "$CONTRIB"
absent "CONTRIBUTING does not say to re-run install.sh after a SKILL.md edit" \
   "After editing a \`SKILL.md\`, re-run \`./install.sh\`" "$CONTRIB"
DOCS=$(cd "$REPO_ROOT" && cat README.md CONTRIBUTING.md SECURITY.md AGENTS.md docs/*.md .gitignore \
       skills/trello/references/setup.md)
for stale in "dbhq-trello" "four skills" "in ~/.trello" "trello.com/my/account" "on the roadmap" "63 checks"; do
    eq "no repo doc says \"$stale\"" "" "$(grep -n -F -- "$stale" <<< "$DOCS" || true)"
done
for f in SECURITY.md skills/trello/references/setup.md; do
    contains "$f revokes a token on Trello's account page" "trello.com/u/{username}/account" "$(cat "$REPO_ROOT/$f")"
done
eq "setup.md's revoke steps do not send the user to the Power-Up admin page" "" \
   "$(awk '/^## Revoking/{f=1} f' "$REPO_ROOT/skills/trello/references/setup.md" | grep -n 'power-ups' || true)"
absent "SECURITY.md does not claim one file is all the skill reads" "config.json\` only" "$(cat "$REPO_ROOT/SECURITY.md")"
contains "SECURITY.md names store-sort's own layouts" ".dbhq/trello/stores/" "$(cat "$REPO_ROOT/SECURITY.md")"
contains "SECURITY.md names life-manager's config" "life-manager.yaml" "$(cat "$REPO_ROOT/SECURITY.md")"
unset CONTRIB DOCS

rm -rf "$SANDBOX"

########################################
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
