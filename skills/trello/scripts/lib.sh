# shellcheck shell=bash
# Shared by every script in the trello pack. Source it, do not run it.
#
#   . "<path to>/skills/trello/scripts/lib.sh"
#   trello_load_config
#   RESPONSE=$(api_get "/members/me/boards" "fields=name,id")
#
# Everything that talks to Trello goes through api() below, so a change to how
# a request is made - its host, its credential, how its errors are read - is
# made here once rather than in six copies that drift.
#
# Sourcing it runs the ~/.trello migration straight away. That is deliberate:
# whichever script an agent reaches for first has to be the one that migrates,
# and a migration that each script has to remember to call is one a new script
# forgets.

TRELLO_CONFIG_DIR="$HOME/.dbhq/trello"
TRELLO_CONFIG_FILE="$TRELLO_CONFIG_DIR/config.json"
TRELLO_BASE_URL="https://api.trello.com/1"

# One-time migration: settings used to live at ~/.trello. Guarded on the
# destination not existing, so a live ~/.dbhq/trello is never overwritten.
trello_migrate() {
    if [ ! -e "$TRELLO_CONFIG_DIR" ] && [ -d "$HOME/.trello" ]; then
        mkdir -p "$HOME/.dbhq"
        chmod 700 "$HOME/.dbhq"
        mv "$HOME/.trello" "$TRELLO_CONFIG_DIR"
        chmod 700 "$TRELLO_CONFIG_DIR"
    fi
}

# Read the key and token, or stop with a message that names the fix. Every
# script except setup calls this before its first request.
trello_load_config() {
    if [ ! -f "$TRELLO_CONFIG_FILE" ]; then
        echo "Error: Config not found. Run trello-setup.sh first." >&2
        exit 1
    fi
    API_KEY=$(jq -r '.api_key' "$TRELLO_CONFIG_FILE")
    TOKEN=$(jq -r '.token' "$TRELLO_CONFIG_FILE")
}

# The key and token travel in an Authorization header that curl reads from
# stdin (`-H @-`), never as a curl argument. Anything in argv - a URL with
# ?key=...&token=... included - can be read by every local user from `ps` or
# /proc/<pid>/cmdline while the request runs. printf is a bash builtin, so
# writing the header starts no process whose command line holds the token.
# Trello documents this header form alongside the query-string one.
trello_auth_header() {
    printf 'Authorization: OAuth oauth_consumer_key="%s", oauth_token="%s"\n' "$API_KEY" "$TOKEN"
}

# A failed request inside a pipeline (`api_get ... | jq ...`) must fail the
# pipeline, not hand jq an error message and carry on with whatever jq makes
# of it.
set -o pipefail

# Trello limits a token to 100 requests in 10 seconds and answers HTTP 429
# past that. due-radar makes one request per board, so a user with many boards
# is the one who meets it. api() retries a 429 three times, waiting 2, 4 and 8
# seconds - which spans a whole 10-second window - and reports it only if the
# last try is refused too.
TRELLO_RETRIES=3
TRELLO_RETRY_WAIT=2

# api <METHOD> <endpoint> [query] [extra curl args...]
#
# The one place a request is made. <query> is extra query-string parameters
# without the leading "?". Pass any caller-supplied text (names, descriptions,
# comments) as extra args with --data-urlencode, never -d: curl sends -d raw,
# so an & truncates the value and a + arrives as a space.
#
# Prints the response body on a 2xx and returns 0. On anything else it prints
# the status and Trello's message to stderr and returns 1. The status is the
# only reliable signal: Trello sends its errors as text/plain ("invalid id",
# "invalid token", "model not found"), not JSON, so a caller that looks for a
# `.message` field reads an expired token as an empty list.
api() {
    local method="$1" endpoint="$2" query="${3:-}"
    if [ $# -ge 3 ]; then shift 3; else shift $#; fi
    local url="$TRELLO_BASE_URL$endpoint"
    [ -n "$query" ] && url="$url?$query"

    local out status body tries=0 wait="$TRELLO_RETRY_WAIT"
    while :; do
        if ! out=$(trello_auth_header | curl -sS -X "$method" -H @- -w '\n%{http_code}' "$url" "$@"); then
            echo "Error: could not reach Trello for $method $endpoint" >&2
            return 1
        fi
        status="${out##*$'\n'}"
        body="${out%$'\n'*}"
        # A 429 is Trello refusing the request before doing anything, so
        # sending it again is safe for a write as well as a read.
        if [ "$status" != 429 ] || [ "$tries" -ge "$TRELLO_RETRIES" ]; then break; fi
        tries=$((tries + 1))
        sleep "$wait"
        wait=$((wait * 2))
    done
    case "$status" in
        2[0-9][0-9])
            printf '%s\n' "$body"
            ;;
        429)
            echo "Error: Trello answered HTTP 429 (rate limited) to $method $endpoint, and still did after $tries retries: ${body:0:500}" >&2
            return 1
            ;;
        *)
            echo "Error: Trello answered HTTP $status to $method $endpoint: ${body:0:500}" >&2
            return 1
            ;;
    esac
}

api_get()    { api GET "$1" "${2:-}"; }
api_post()   { local e="$1"; shift; api POST "$e" "" "$@"; }
api_put()    { local e="$1"; shift; api PUT "$e" "" "$@"; }
api_delete() { api DELETE "$1"; }

# Trello answers at most 1000 results to one request for a long list - a
# board's cards, its actions, a card's comments - and says nothing when it
# stops. So a script that trusts one page reports "the last 7 days" of a busy
# board as its last few hours. The fix is to ask again with `before` set to the
# oldest id seen, until a page comes back short.
TRELLO_PAGE_SIZE=1000
# A backstop, not a target: 25 pages is 25,000 results. Reaching it is
# reported, never silent. Tests lower it to prove the report.
TRELLO_MAX_PAGES="${TRELLO_MAX_PAGES:-25}"

# api_get_all <endpoint> [query]
#
# Every page of a list endpoint, as one JSON array in the order Trello sent it
# (newest first for cards and actions), with no id twice. Returns 1 if any page
# fails, like api(). When results are still left after TRELLO_MAX_PAGES pages,
# or Trello keeps sending the same page, it prints the result it has and a
# "capped at N" line on stderr, so a cut-off list is never passed off as whole.
#
# The ids Trello uses start with their creation time in hex, all the same
# length, so the smallest id in a page is the oldest one - which is the cursor
# `before` wants.
api_get_all() {
    local endpoint="$1" query="${2:-}" tmp pages=0 n oldest last="" capped=""
    [ -n "$query" ] && query="$query&"
    tmp=$(mktemp -d) || return 1
    while :; do
        pages=$((pages + 1))
        if ! api_get "$endpoint" "${query}limit=$TRELLO_PAGE_SIZE${last:+&before=$last}" \
                > "$tmp/$(printf '%05d' "$pages").json"; then
            rm -rf "$tmp"
            return 1
        fi
        read -r n oldest < <(jq -r '"\(length) \(map(.id // empty) | min // "")"' \
            "$tmp/$(printf '%05d' "$pages").json") || { rm -rf "$tmp"; return 1; }
        # A short page is the last one. A page longer than the limit means this
        # endpoint ignores `limit` and sent the lot in one go.
        [ "$n" -ne "$TRELLO_PAGE_SIZE" ] && break
        # Trello sent a full page but the cursor did not move: it is ignoring
        # `before` here, so asking again would loop.
        if [ -z "$oldest" ] || [ "$oldest" = "$last" ]; then capped=1; break; fi
        if [ "$pages" -ge "$TRELLO_MAX_PAGES" ]; then capped=1; break; fi
        last="$oldest"
    done
    jq -s 'add // [] | reduce .[] as $x ({seen: {}, out: []};
            ($x.id | tostring) as $k
            | if .seen[$k] then . else .seen[$k] = true | .out += [$x] end)
           | .out' "$tmp"/*.json > "$tmp/all" || { rm -rf "$tmp"; return 1; }
    if [ -n "$capped" ]; then
        echo "Note: capped at $(jq 'length' "$tmp/all") results from GET $endpoint - older ones were not fetched." >&2
    fi
    cat "$tmp/all"
    rm -rf "$tmp"
}

# Portable "N days ago" in UTC ISO8601 (GNU date, then BSD/macOS date fallback)
days_ago_iso() {
    local d="$1"
    date -u -d "$d days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -v-"${d}"d +%Y-%m-%dT%H:%M:%SZ
}

trello_migrate
