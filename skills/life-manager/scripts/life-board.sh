#!/bin/bash
# life-manager helpers - resolve the user's config, and report where a board
# has stopped being true: unlabelled cards, list sizes, and cards gone stale.
#
# Read-only. Nothing here moves, archives or deletes a card; the skill does
# that only after showing a plan and getting approval.

set -e

CONFIG_FILE="$HOME/.trello/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config not found. Run trello-setup.sh first." >&2
    exit 1
fi

API_KEY=$(jq -r '.api_key' "$CONFIG_FILE")
TOKEN=$(jq -r '.token' "$CONFIG_FILE")
BASE_URL="https://api.trello.com/1"

api_get() {
    local endpoint="$1" params="${2:-}"
    if [ -n "$params" ]; then
        curl -s "$BASE_URL$endpoint?key=$API_KEY&token=$TOKEN&$params"
    else
        curl -s "$BASE_URL$endpoint?key=$API_KEY&token=$TOKEN"
    fi
}

# Portable "N days ago" in UTC ISO8601 (GNU date, then BSD/macOS date fallback)
days_ago_iso() {
    local d="$1"
    date -u -d "$d days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -v-"${d}"d +%Y-%m-%dT%H:%M:%SZ
}

# Resolve the user's life-manager config. Nothing personal lives in this skill,
# so every board, list and label comes from here or from asking the user.
resolve_config() {
    local candidates=(
        "$LIFE_MANAGER_CONFIG"
        "./life-manager.yaml"
        "./system/life-manager.yaml"
        "$HOME/.trello/life-manager.yaml"
    )
    local c
    for c in "${candidates[@]}"; do
        [ -n "$c" ] && [ -f "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

cmd_config() {
    local path
    if ! path=$(resolve_config); then
        echo "No config found. Looked for:" >&2
        echo "  \$LIFE_MANAGER_CONFIG, ./life-manager.yaml, ./system/life-manager.yaml, ~/.trello/life-manager.yaml" >&2
        echo "" >&2
        echo "This is setup mode - offer to create one." >&2
        exit 1
    fi
    echo "config: $path"
    echo ""
    cat "$path"
}

cmd_stale() {
    local list_id="$1" days="${2:-14}" cutoff
    [ -z "$list_id" ] && { echo "Usage: life-board.sh stale <list-id> [days]" >&2; exit 1; }
    cutoff=$(days_ago_iso "$days")
    api_get "/lists/$list_id/cards" "fields=name,dateLastActivity" \
        | jq -r --arg c "$cutoff" '
            [.[] | select(.dateLastActivity < $c)]
            | if length == 0 then "  (nothing stale)"
              else .[] | "  \(.dateLastActivity[0:10])  \(.name)" end'
}

cmd_audit() {
    local board_id="$1"
    [ -z "$board_id" ] && { echo "Usage: life-board.sh audit <board-id>" >&2; exit 1; }

    echo "=== List sizes ==="
    api_get "/boards/$board_id/lists" "cards=open&card_fields=name" \
        | jq -r '.[] | "  \(.cards | length | tostring | (" " * (4 - length)) + .)  \(.name)"'

    echo ""
    echo "=== Unlabelled cards ==="
    api_get "/boards/$board_id/lists" "cards=open&card_fields=name,labels" \
        | jq -r '
            [.[] | .name as $l | .cards[] | select(.labels | length == 0) | "  \($l): \(.name)"] as $u
            | if ($u | length) == 0 then "  (none - every card is categorised)"
              else ($u | .[]), "", "  \($u | length) unlabelled" end'

    echo ""
    echo "=== Cards with no checklist and no description ==="
    echo "    (candidates for breaking down - a bare title is often a hidden project)"
    api_get "/boards/$board_id/cards" "fields=name,desc,idList&checklists=all" \
        | jq -r '
            [.[] | select((.checklists | length) == 0 and (.desc | length) == 0) | .name] as $b
            | if ($b | length) == 0 then "  (none)"
              else ($b | .[] | "  \(.)") end' | head -40
}

case "${1:-}" in
    config) cmd_config ;;
    audit)  cmd_audit "${2:-}" ;;
    stale)  cmd_stale "${2:-}" "${3:-}" ;;
    *)
        cat >&2 <<'USAGE'
Usage: life-board.sh <command>

  config                     Show the resolved config path and its contents
  audit <board-id>           List sizes, unlabelled cards, and cards that look
                             like undefined projects
  stale <list-id> [days]     Cards untouched for N days (default 14)

Read-only. Credentials come from ~/.trello/config.json.
USAGE
        exit 1
        ;;
esac
