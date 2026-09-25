#!/bin/bash
# Trello Boards & Lists Operations

set -e

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trello_load_config

usage() {
    echo "Trello Boards & Lists"
    echo
    echo "Usage: trello-boards.sh <command> [args]"
    echo
    echo "Commands:"
    echo "  boards              List all boards"
    echo "  lists <board-id>    List all lists in a board"
    echo "  find <name>         Find board by name"
    echo "  board <board-id>    Get board details"
    echo "  list <list-id>      Get list details"
    echo "  labels <board-id>   List a board's labels with their ids"
}

case "$1" in
    boards)
        # List all boards
        RESPONSE=$(api_get "/members/me/boards" "fields=name,id,url,closed")

        echo "$RESPONSE" | jq -r '[.[] | select(.closed == false)]
            | if length == 0 then "No open boards." else .[] | "[\(.id)] \(.name)" end'
        ;;

    lists)
        # List all lists in a board
        if [ -z "$2" ]; then
            echo "Usage: trello-boards.sh lists <board-id>"
            exit 1
        fi

        BOARD_ID="$2"
        RESPONSE=$(api_get "/boards/$BOARD_ID/lists" "fields=name,id,closed")

        echo "$RESPONSE" | jq -r '[.[] | select(.closed == false)]
            | if length == 0 then "No lists found or empty board." else .[] | "[\(.id)] \(.name)" end'
        ;;

    find)
        # Find board by name (case-insensitive partial match)
        if [ -z "$2" ]; then
            echo "Usage: trello-boards.sh find <name>"
            exit 1
        fi

        SEARCH="$2"
        RESPONSE=$(api_get "/members/me/boards" "fields=name,id,url,closed")

        MATCHES=$(echo "$RESPONSE" | jq -r --arg search "$SEARCH" \
            '.[] | select(.closed == false) | select(.name | ascii_downcase | contains($search | ascii_downcase)) | "[\(.id)] \(.name)"')

        if [ -n "$MATCHES" ]; then
            echo "$MATCHES"
        else
            echo "No boards found matching: $SEARCH"
        fi
        ;;

    board)
        # Get board details
        if [ -z "$2" ]; then
            echo "Usage: trello-boards.sh board <board-id>"
            exit 1
        fi

        BOARD_ID="$2"
        RESPONSE=$(api_get "/boards/$BOARD_ID" "fields=name,id,url,desc,closed")

        echo "$RESPONSE" | jq -r '"Board: \(.name)\nID: \(.id)\nURL: \(.url)\nDescription: \(.desc // "None")"'
        ;;

    list)
        # Get list details
        if [ -z "$2" ]; then
            echo "Usage: trello-boards.sh list <list-id>"
            exit 1
        fi

        LIST_ID="$2"
        RESPONSE=$(api_get "/lists/$LIST_ID" "fields=name,id,idBoard,closed")

        echo "$RESPONSE" | jq -r '"List: \(.name)\nID: \(.id)\nBoard ID: \(.idBoard)"'
        ;;

    labels)
        # List a board's labels with their ids - the ids that
        # `trello-cards.sh label-add` and `label-remove` take.
        if [ -z "$2" ]; then
            echo "Usage: trello-boards.sh labels <board-id>"
            exit 1
        fi

        BOARD_ID="$2"
        RESPONSE=$(api_get "/boards/$BOARD_ID/labels" "fields=name,color&limit=1000")

        echo "$RESPONSE" | jq -r 'if length == 0 then "No labels on this board."
            else .[] | "[\(.id)] \(if (.name // "") == "" then "(no name)" else .name end) (\(.color // "no colour"))" end'
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
