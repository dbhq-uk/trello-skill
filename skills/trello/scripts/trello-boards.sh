#!/bin/bash
# Trello Boards & Lists Operations

set -e

CONFIG_DIR="$HOME/.trello"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Check config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config not found. Run trello-setup.sh first."
    exit 1
fi

API_KEY=$(jq -r '.api_key' "$CONFIG_FILE")
TOKEN=$(jq -r '.token' "$CONFIG_FILE")
BASE_URL="https://api.trello.com/1"

# Helper: make API request
api_get() {
    local endpoint="$1"
    local params="${2:-}"

    if [ -n "$params" ]; then
        curl -s "$BASE_URL$endpoint?key=$API_KEY&token=$TOKEN&$params"
    else
        curl -s "$BASE_URL$endpoint?key=$API_KEY&token=$TOKEN"
    fi
}

case "$1" in
    boards)
        # List all boards
        RESPONSE=$(api_get "/members/me/boards" "fields=name,id,url,closed")

        if echo "$RESPONSE" | jq -e '.[0].id' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '.[] | select(.closed == false) | "[\(.id)] \(.name)"'
        else
            echo "Error fetching boards:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    lists)
        # List all lists in a board
        if [ -z "$2" ]; then
            echo "Usage: trello-boards.sh lists <board-id>"
            exit 1
        fi

        BOARD_ID="$2"
        RESPONSE=$(api_get "/boards/$BOARD_ID/lists" "fields=name,id,closed")

        if echo "$RESPONSE" | jq -e '.[0].id' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '.[] | select(.closed == false) | "[\(.id)] \(.name)"'
        elif echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
            echo "Error:"
            echo "$RESPONSE" | jq -r '.message'
            exit 1
        else
            echo "No lists found or empty board."
        fi
        ;;

    find)
        # Find board by name (case-insensitive partial match)
        if [ -z "$2" ]; then
            echo "Usage: trello-boards.sh find <name>"
            exit 1
        fi

        SEARCH="$2"
        RESPONSE=$(api_get "/members/me/boards" "fields=name,id,url,closed")

        if echo "$RESPONSE" | jq -e '.[0].id' > /dev/null 2>&1; then
            MATCHES=$(echo "$RESPONSE" | jq -r --arg search "$SEARCH" \
                '.[] | select(.closed == false) | select(.name | ascii_downcase | contains($search | ascii_downcase)) | "[\(.id)] \(.name)"')

            if [ -n "$MATCHES" ]; then
                echo "$MATCHES"
            else
                echo "No boards found matching: $SEARCH"
            fi
        else
            echo "Error fetching boards:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
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

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '"Board: \(.name)\nID: \(.id)\nURL: \(.url)\nDescription: \(.desc // "None")"'
        else
            echo "Error:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    list)
        # Get list details
        if [ -z "$2" ]; then
            echo "Usage: trello-boards.sh list <list-id>"
            exit 1
        fi

        LIST_ID="$2"
        RESPONSE=$(api_get "/lists/$LIST_ID" "fields=name,id,idBoard,closed")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '"List: \(.name)\nID: \(.id)\nBoard ID: \(.idBoard)"'
        else
            echo "Error:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    *)
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
        ;;
esac
