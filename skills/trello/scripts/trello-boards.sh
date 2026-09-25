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
    echo
    echo "Creating & Renaming:"
    echo "  board-create <name> [desc]                Create a board, prints [id] name"
    echo "  list-create <board-id> <name> [top|bottom] Add a list (default: bottom)"
    echo "  list-rename <list-id> <name>              Rename a list"
    echo "  label-create <board-id> <name> [colour]   Add a label (default: no colour)"
    echo
    echo "Label colours: green, yellow, orange, red, purple, blue, sky, lime, pink, black."
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

    board-create)
        # Create a board. Trello gives a new board its own starter lists and
        # six unnamed colour labels; life-manager's setup renames those lists
        # rather than adding to them.
        if [ -z "${2:-}" ]; then
            echo "Usage: trello-boards.sh board-create <name> [description]"
            exit 1
        fi

        RESPONSE=$(api_post "/boards" --data-urlencode "name=$2" --data-urlencode "desc=${3:-}")

        echo "Board created:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)\nURL: \(.url // "")"'
        ;;

    list-create)
        # Add a list to a board, at the bottom unless asked for the top.
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "Usage: trello-boards.sh list-create <board-id> <name> [top|bottom]"
            exit 1
        fi
        POS="${4:-bottom}"
        case "$POS" in
            top|bottom) ;;
            *) echo "Error: position must be top or bottom, not '$POS'" >&2; exit 1 ;;
        esac

        RESPONSE=$(api_post "/lists" --data-urlencode "idBoard=$2" \
            --data-urlencode "name=$3" --data-urlencode "pos=$POS")

        echo "List created:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        ;;

    list-rename)
        # Rename a list. Renaming an existing list beats adding a new one:
        # the cards already in it keep their place.
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "Usage: trello-boards.sh list-rename <list-id> <name>"
            exit 1
        fi

        RESPONSE=$(api_put "/lists/$2" --data-urlencode "name=$3")

        echo "List renamed:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        ;;

    label-create)
        # Add a label to a board and print its id, ready for
        # `trello-cards.sh label-add`. With no colour the label has none.
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "Usage: trello-boards.sh label-create <board-id> <name> [colour]"
            exit 1
        fi
        # Trello names the colours and says null is no colour. It rejects
        # anything else with its own message, which api() passes on.
        COLOUR="${4:-null}"

        RESPONSE=$(api_post "/boards/$2/labels" --data-urlencode "name=$3" \
            --data-urlencode "color=$COLOUR")

        echo "Label created:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name) (\(.color // "no colour"))"'
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
