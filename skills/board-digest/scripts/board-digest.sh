#!/bin/bash
# Trello board digest - a plain status snapshot of a board:
# lists and their cards, what is due or overdue, and recent activity.

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

cmd="${1:-digest}"

case "$cmd" in
    digest)
        BOARD_ID="$2"
        DAYS="${3:-7}"
        if [ -z "$BOARD_ID" ]; then
            echo "Usage: board-digest.sh digest <board-id> [days]" >&2
            exit 1
        fi

        BOARD=$(api_get "/boards/$BOARD_ID" "fields=name,url")
        if ! echo "$BOARD" | jq -e '.id? // .name?' >/dev/null 2>&1; then
            echo "Error:" >&2
            echo "$BOARD" | jq -r '.message // .' >&2
            exit 1
        fi
        NAME=$(echo "$BOARD" | jq -r '.name // "Unknown board"')

        LISTS=$(api_get "/boards/$BOARD_ID/lists" "fields=name,id&cards=none")
        CARDS=$(api_get "/boards/$BOARD_ID/cards" "fields=name,idList,due,dueComplete,labels,dateLastActivity&limit=1000")
        SINCE=$(days_ago_iso "$DAYS")
        ACTIONS=$(api_get "/boards/$BOARD_ID/actions" "filter=createCard,commentCard,updateCard&limit=50&since=$SINCE")

        NOW=$(date -u +%s)
        SOON=$((NOW + 3 * 86400))
        TOTAL=$(echo "$CARDS" | jq 'length')

        echo "=== $NAME ==="
        echo "Status as of $(date -u +'%Y-%m-%d %H:%M UTC') - $TOTAL open cards"
        echo

        echo "## Lists"
        echo "$LISTS" | jq -r '.[] | "\(.id)\t\(.name)"' | while IFS=$'\t' read -r lid lname; do
            count=$(echo "$CARDS" | jq --arg l "$lid" '[.[] | select(.idList == $l)] | length')
            echo "### $lname ($count)"
            echo "$CARDS" | jq -r --arg l "$lid" '.[] | select(.idList == $l) | "  - \(.name)"'
            echo
        done

        echo "## Due & overdue"
        DUE=$(echo "$CARDS" | jq -r --argjson now "$NOW" --argjson soon "$SOON" '
            .[]
            | select(.due != null and (.dueComplete | not))
            | (.due | sub("\\..*Z"; "Z") | fromdateiso8601) as $d
            | select($d <= $soon)
            | "\($d)\t\(if $d < $now then "OVERDUE " else "due soon" end)\t\(.name)\t\(.due[0:10])"
            ' | sort | awk -F'\t' '{printf "  - %s: %s (%s)\n", $2, $3, $4}')
        if [ -n "$DUE" ]; then echo "$DUE"; else echo "  (nothing due in the next 3 days)"; fi
        echo

        echo "## Recent activity (last $DAYS days)"
        ACT=$(echo "$ACTIONS" | jq -r '
            .[]
            | (.date[0:10]) as $d
            | if .type == "createCard" then "  - \($d) created: \(.data.card.name)"
              elif .type == "commentCard" then "  - \($d) comment on: \(.data.card.name)"
              elif (.type == "updateCard" and (.data.listBefore != null) and (.data.listAfter != null))
                  then "  - \($d) moved \(.data.card.name): \(.data.listBefore.name) -> \(.data.listAfter.name)"
              elif (.type == "updateCard" and (.data.old.due != null or (.data.card.due != null and (.data.old | has("due")))))
                  then "  - \($d) due date changed: \(.data.card.name)"
              elif .type == "updateCard" then "  - \($d) updated: \(.data.card.name)"
              else empty end')
        if [ -n "$ACT" ]; then echo "$ACT"; else echo "  (no tracked activity in this window)"; fi
        ;;

    *)
        echo "Trello Board Digest"
        echo
        echo "Usage: board-digest.sh digest <board-id> [days]"
        echo
        echo "  digest <board-id> [days]   Status snapshot: lists, due/overdue, recent activity"
        echo "                             (days = recent-activity window, default 7)"
        echo
        echo "Find a board id with: trello-boards.sh find \"<name>\""
        ;;
esac
