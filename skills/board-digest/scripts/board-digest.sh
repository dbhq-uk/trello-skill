#!/bin/bash
# Trello board digest - a plain status snapshot of a board:
# lists and their cards, what is due or overdue, and recent activity.

set -e

# The shared helpers live in the trello skill, which sits beside this one in
# the pack. A partial install without it gets told what is missing.
TRELLO_LIB="$(dirname "${BASH_SOURCE[0]}")/../../trello/scripts/lib.sh"
if [ ! -f "$TRELLO_LIB" ]; then
    echo "Error: board-digest needs the trello skill from the same pack, installed beside it." >&2
    echo "Install the whole pack, or add it with: npx skills add dbhq-uk/trello-skill --skill trello" >&2
    exit 1
fi
# shellcheck source=../../trello/scripts/lib.sh
. "$TRELLO_LIB"
trello_load_config

usage() {
    echo "Trello Board Digest"
    echo
    echo "Usage: board-digest.sh digest <board-id> [days]"
    echo
    echo "  digest <board-id> [days]   Status snapshot: lists, due/overdue, recent activity"
    echo "                             (days = recent-activity window, default 7)"
    echo
    echo "Find a board id with: trello-boards.sh find \"<name>\""
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
        NAME=$(echo "$BOARD" | jq -r '.name // "Unknown board"')

        LISTS=$(api_get "/boards/$BOARD_ID/lists" "fields=name,id&cards=none")
        CARDS=$(api_get_all "/boards/$BOARD_ID/cards" "fields=name,idList,due,dueComplete,labels,dateLastActivity")
        SINCE=$(days_ago_iso "$DAYS")
        ACTIONS=$(api_get_all "/boards/$BOARD_ID/actions" "filter=createCard,commentCard,updateCard&since=$SINCE")

        NOW=$(date -u +%s)
        SOON=$((NOW + 3 * 86400))
        TOTAL=$(echo "$CARDS" | jq 'length')

        echo "=== $NAME ==="
        echo "Status as of $(local_now) - $TOTAL open cards, times are local"
        echo

        echo "## Lists"
        echo "$LISTS" | jq -r '.[] | "\(.id)\t\(.name)"' | while IFS=$'\t' read -r lid lname; do
            count=$(echo "$CARDS" | jq --arg l "$lid" '[.[] | select(.idList == $l)] | length')
            echo "### $lname ($count)"
            echo "$CARDS" | jq -r --arg l "$lid" '.[] | select(.idList == $l) | "  - \(.name)"'
            echo
        done

        # Each row names its list. A card in a done list (see is_done_list in
        # lib.sh) is finished work whose due date was never ticked, so it is
        # labelled as that rather than OVERDUE.
        echo "## Due & overdue"
        DUE=$(echo "$CARDS" | jq -r --argjson now "$NOW" --argjson soon "$SOON" --argjson lists "$LISTS" "$(trello_jq_defs)"'
            ($lists | map({(.id): .name}) | add // {}) as $ln
            | .[]
            | select(.due != null and (.dueComplete | not))
            | (.due | sub("\\..*Z"; "Z") | fromdateiso8601) as $d
            | select($d <= $soon)
            | ($ln[.idList // ""] // "?") as $l
            | "\($d)\t\(if ($l | is_done_list) then "in \($l), due not ticked" elif $d < $now then "OVERDUE " else "due soon" end)\t\(.name)\t\(.due | local_time)\t\($l)"
            ' | sort | awk -F'\t' '{printf "  - %s: %s (%s) [%s]\n", $2, $3, $4, $5}')
        if [ -n "$DUE" ]; then echo "$DUE"; else echo "  (nothing due in the next 3 days)"; fi
        echo

        echo "## Recent activity (last $DAYS days)"
        ACT=$(echo "$ACTIONS" | jq -r "$(trello_jq_defs)"'
            .[]
            | (.date | local_date) as $d
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

    help|-h|--help)
        usage
        ;;

    *)
        # An unknown verb is an error, not a request for help: usage goes to
        # stderr and the exit code is 2, so an agent cannot read the usage
        # text as a result.
        usage >&2
        exit 2
        ;;
esac
