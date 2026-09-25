#!/bin/bash
# Trello due radar - what is due, overdue, or coming up across your boards.

set -e

# The shared helpers live in the trello skill, which sits beside this one in
# the pack. A partial install without it gets told what is missing.
TRELLO_LIB="$(dirname "${BASH_SOURCE[0]}")/../../trello/scripts/lib.sh"
if [ ! -f "$TRELLO_LIB" ]; then
    echo "Error: due-radar needs the trello skill from the same pack, installed beside it." >&2
    echo "Install the whole pack, or add it with: npx skills add dbhq-uk/trello-skill --skill trello" >&2
    exit 1
fi
# shellcheck source=../../trello/scripts/lib.sh
. "$TRELLO_LIB"
trello_load_config

# Print a combined, annotated, sorted due list from a JSON array of
# {name, due, url, board, list, done} objects. Always shows all overdue, plus
# anything due within the window (days). Each row names its board and list.
#
# A card in a done list (done: true) is finished work whose due date was never
# ticked. It is not overdue and not upcoming, so it is counted in neither and
# shown apart, after the rest, with its date rather than OVERDUE.
render() {
    local cards="$1" days="$2"
    local now window
    now=$(date -u +%s)
    window=$((now + days * 86400))

    local rows
    rows=$(echo "$cards" | jq -r --argjson now "$now" --argjson window "$window" "$(trello_jq_defs)"'
        map(. + {epoch: (.due | sub("\\..*Z"; "Z") | fromdateiso8601)})
        | map(select(.epoch < $now or .epoch <= $window))
        | sort_by(.epoch)
        | .[]
        | "\(if .done then "DONE" elif .epoch < $now then "OVERDUE" else "SOON" end)\t\(if .epoch < $now and (.done | not) then "OVERDUE" else (.due | local_time) end)\t\(.name)\t\(.board)\(if (.list // "") != "" then " / \(.list)" else "" end)"')

    if [ -z "$rows" ]; then
        echo "  (nothing overdue or due in the next $days days)"
        return
    fi

    local overdue soon done_rows
    overdue=$(echo "$rows" | grep -c '^OVERDUE' || true)
    soon=$(echo "$rows" | grep -c '^SOON' || true)
    done_rows=$(echo "$rows" | grep '^DONE' || true)
    echo "  $overdue overdue, $soon upcoming (next $days days)"
    echo
    echo "$rows" | grep -v '^DONE' | awk -F'\t' '{printf "  %-16s  %-50s  [%s]\n", $2, $3, $4}' || true
    if [ -n "$done_rows" ]; then
        echo
        echo "  $(echo "$done_rows" | grep -c .) in a done list with the due date not ticked - not counted above:"
        echo "$done_rows" | awk -F'\t' '{printf "  %-16s  %-50s  [%s]\n", $2, $3, $4}'
    fi
}

# The due, unticked cards on one board as a JSON array for render, each with
# its list's name and whether that list is a done list. Returns 1 if Trello
# could not be read. The board's lists are fetched only when there is a due
# card to name, so a board with none still costs one request.
board_due_cards() {
    local bid="$1" bname="$2" cards lists='[]'
    cards=$(api_get_all "/boards/$bid/cards" "fields=name,due,dueComplete,url,idList" \
        | jq '[.[] | select(.due != null and (.dueComplete | not))]') || return 1
    if [ "$(jq 'length' <<< "$cards")" -gt 0 ]; then
        lists=$(api_get "/boards/$bid/lists" "fields=name&filter=all") || return 1
    fi
    jq --arg b "$bname" --argjson lists "$lists" "$(trello_jq_defs)"'
        ($lists | map({(.id): .name}) | add // {}) as $ln
        | [.[] | ($ln[.idList // ""] // "") as $l
               | {name, due, url, board: $b, list: $l, done: ($l | is_done_list)}]' <<< "$cards"
}

usage() {
    echo "Trello Due Radar"
    echo
    echo "Usage: due-radar.sh <command> [args]"
    echo
    echo "  all [days]                Due/overdue/upcoming across all your open boards (default 14 days)"
    echo "  board <board-id> [days]   Same, scoped to one board"
    echo
    echo "All overdue cards are always shown; the day window only limits how far ahead upcoming items reach."
}

cmd="${1:-all}"

case "$cmd" in
    all)
        DAYS="${2:-14}"
        BOARDS=$(api_get "/members/me/boards" "filter=open&fields=name,id")
        if [ "$(echo "$BOARDS" | jq 'length')" -eq 0 ]; then
            echo "No open boards."
            exit 0
        fi

        # A board that cannot be read is named, not skipped. It used to become
        # an empty list, so the radar said nothing was due on a board it never
        # saw and exited 0. Trello's own message for each one goes to stderr
        # as it happens; the boards are listed again after the results, and
        # the exit code is 1.
        TMP=$(mktemp -d)
        trap 'rm -rf "$TMP"' EXIT
        : > "$TMP/failed"
        n=0
        while IFS=$'\t' read -r bid bname; do
            n=$((n + 1))
            if ! board_due_cards "$bid" "$bname" > "$TMP/$n.json"; then
                rm -f "$TMP/$n.json"
                printf '%s\n' "$bname" >> "$TMP/failed"
            fi
        done < <(echo "$BOARDS" | jq -r '.[] | "\(.id)\t\(.name)"')
        if compgen -G "$TMP/*.json" > /dev/null; then
            CARDS=$(jq -s 'add' "$TMP"/*.json)
        else
            CARDS='[]'
        fi

        echo "=== Due radar - all boards ==="
        echo "As of $(local_now) - times are local"
        echo
        render "$CARDS" "$DAYS"

        FAILED=$(grep -c . "$TMP/failed" || true)
        if [ "$FAILED" -gt 0 ]; then
            echo
            echo "  Incomplete: could not read $FAILED of $n boards. The radar above does not cover:"
            sed 's/^/    - /' "$TMP/failed"
            exit 1
        fi
        ;;

    board)
        BOARD_ID="$2"
        DAYS="${3:-14}"
        if [ -z "$BOARD_ID" ]; then
            echo "Usage: due-radar.sh board <board-id> [days]" >&2
            exit 1
        fi
        BOARD=$(api_get "/boards/$BOARD_ID" "fields=name")
        BNAME=$(echo "$BOARD" | jq -r '.name // "board"')
        CARDS=$(board_due_cards "$BOARD_ID" "$BNAME")

        echo "=== Due radar - $BNAME ==="
        echo "As of $(local_now) - times are local"
        echo
        render "$CARDS" "$DAYS"
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
