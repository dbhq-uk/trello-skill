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
    echo "Usage: board-digest.sh digest <board-id> [days] [idle-days] [limit]"
    echo
    echo "  digest <board-id> [days] [idle-days] [limit]"
    echo "      Status snapshot: lists, due/overdue, cards not moved, recent activity"
    echo "      days       recent-activity window (default 7)"
    echo "      idle-days  a card with no activity for this long is listed as not moved (default 14)"
    echo "      limit      cards shown per list, and in the not-moved section (default 10)"
    echo
    echo "Find a board id with: trello-boards.sh find \"<name>\""
}

cmd="${1:-digest}"

case "$cmd" in
    digest)
        BOARD_ID="$2"
        DAYS="${3:-7}"
        IDLE_DAYS="${4:-14}"
        LIMIT="${5:-10}"
        if [ -z "$BOARD_ID" ]; then
            echo "Usage: board-digest.sh digest <board-id> [days] [idle-days] [limit]" >&2
            exit 1
        fi
        for n in "$DAYS" "$IDLE_DAYS" "$LIMIT"; do
            case "$n" in
                ''|*[!0-9]*|0) echo "Usage: board-digest.sh digest <board-id> [days] [idle-days] [limit] - each must be a whole number above 0" >&2; exit 1 ;;
            esac
        done

        BOARD=$(api_get "/boards/$BOARD_ID" "fields=name,url")
        NAME=$(echo "$BOARD" | jq -r '.name // "Unknown board"')

        LISTS=$(api_get "/boards/$BOARD_ID/lists" "fields=name,id&cards=none")
        CARDS=$(api_get_all "/boards/$BOARD_ID/cards" "fields=name,idList,pos,due,dueComplete,labels,dateLastActivity")
        SINCE=$(days_ago_iso "$DAYS")
        ACTIONS=$(api_get_all "/boards/$BOARD_ID/actions" "filter=createCard,commentCard,updateCard&since=$SINCE")

        NOW=$(date -u +%s)
        SOON=$((NOW + 3 * 86400))
        TOTAL=$(echo "$CARDS" | jq 'length')

        echo "=== $NAME ==="
        echo "Status as of $(local_now) - $TOTAL open cards, times are local"
        echo

        # Each list shows its first <limit> cards in board order. A big board
        # printed every card on every list, which floods the reader; the rest
        # are counted, with the call that shows them.
        echo "## Lists"
        echo "$CARDS" | jq -r --argjson lists "$LISTS" --argjson n "$LIMIT" '
            . as $cards
            | $lists[]
            | .id as $lid
            | ([$cards[] | select(.idList == $lid)] | sort_by(.pos)) as $cs
            | "### \(.name) (\($cs | length))",
              ($cs[0:$n][] | "  - \(.name)"),
              (if ($cs | length) > $n
               then "  + \(($cs | length) - $n) more (trello-cards.sh list \($lid) \($cs | length) shows them all)"
               else empty end),
              ""'

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

        # Cards with no activity for <idle-days>, oldest first. Trello's
        # dateLastActivity moves on any change to a card, so a card that was
        # only renamed or re-sorted counts as moved. A card in a done list is
        # finished work, so it is never listed here.
        echo "## Not moved in $IDLE_DAYS days or more"
        echo "$CARDS" | jq -r --argjson now "$NOW" --argjson idle "$IDLE_DAYS" --argjson n "$LIMIT" \
            --argjson lists "$LISTS" "$(trello_jq_defs)"'
            ($lists | map({(.id): .name}) | add // {}) as $ln
            | [ .[]
                | select(.dateLastActivity != null)
                | ($ln[.idList // ""] // "?") as $l
                | select($l | is_done_list | not)
                | (($now - (.dateLastActivity | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) / 86400 | floor) as $age
                | select($age >= $idle)
                | {name, list: $l, age: $age, last: (.dateLastActivity | local_date)} ]
            | sort_by(-.age)
            | if length == 0 then "  (none - every open card has had activity in the last \($idle) days)"
              else (.[0:$n][] | "  - \(.age) days, since \(.last): \(.name) [\(.list)]"),
                   (if length > $n then "  + \(length - $n) more, not shown (pass a larger limit to see them)" else empty end)
              end'
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
