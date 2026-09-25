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

# api <METHOD> <endpoint> [query] [extra curl args...]
#
# The one place a request is made. <query> is extra query-string parameters
# without the leading "?". Pass any caller-supplied text (names, descriptions,
# comments) as extra args with --data-urlencode, never -d: curl sends -d raw,
# so an & truncates the value and a + arrives as a space.
api() {
    local method="$1" endpoint="$2" query="${3:-}"
    if [ $# -ge 3 ]; then shift 3; else shift $#; fi
    local url="$TRELLO_BASE_URL$endpoint?key=$API_KEY&token=$TOKEN"
    [ -n "$query" ] && url="$url&$query"
    curl -s -X "$method" "$url" "$@"
}

api_get()    { api GET "$1" "${2:-}"; }
api_post()   { local e="$1"; shift; api POST "$e" "" "$@"; }
api_put()    { local e="$1"; shift; api PUT "$e" "" "$@"; }
api_delete() { api DELETE "$1"; }

# Portable "N days ago" in UTC ISO8601 (GNU date, then BSD/macOS date fallback)
days_ago_iso() {
    local d="$1"
    date -u -d "$d days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -v-"${d}"d +%Y-%m-%dT%H:%M:%SZ
}

trello_migrate
