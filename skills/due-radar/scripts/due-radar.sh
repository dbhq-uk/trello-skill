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
# {name, due, url, board} objects. Always shows all overdue, plus anything
# due within the window (days).
render() {
    local cards="$1" days="$2"
    local now window
    now=$(date -u +%s)
    window=$((now + days * 86400))

    local rows
    rows=$(echo "$cards" | jq -r --argjson now "$now" --argjson window "$window" '
        map(. + {epoch: (.due | sub("\\..*Z"; "Z") | fromdateiso8601)})
        | map(select(.epoch < $now or .epoch <= $window))
        | sort_by(.epoch)
        | .[]
        | "\(if .epoch < $now then "OVERDUE" else .due[0:10] end)\t\(.name)\t\(.board)"')

    if [ -z "$rows" ]; then
        echo "  (nothing overdue or due in the next $days days)"
        return
    fi

    local overdue soon
    overdue=$(echo "$rows" | grep -c '^OVERDUE' || true)
    soon=$(echo "$rows" | grep -vc '^OVERDUE' || true)
    echo "  $overdue overdue, $soon upcoming (next $days days)"
    echo
    echo "$rows" | awk -F'\t' '{printf "  %-10s  %-50s  [%s]\n", $1, $2, $3}'
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
            if ! api_get_all "/boards/$bid/cards" "fields=name,due,dueComplete,url" > "$TMP/$n.raw" \
                || ! jq --arg b "$bname" '[.[] | select(.due != null and (.dueComplete | not)) | {name, due, url, board: $b}]' \
                    "$TMP/$n.raw" > "$TMP/$n.json"; then
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
        echo "As of $(date -u +'%Y-%m-%d %H:%M UTC')"
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
        CARDS=$(api_get_all "/boards/$BOARD_ID/cards" "fields=name,due,dueComplete,url" \
            | jq --arg b "$BNAME" '[.[] | select(.due != null and (.dueComplete | not)) | {name, due, url, board: $b}]')

        echo "=== Due radar - $BNAME ==="
        echo "As of $(date -u +'%Y-%m-%d %H:%M UTC')"
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
