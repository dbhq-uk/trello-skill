#!/bin/bash
# Trello Cards Operations

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

# Helper: make GET request
api_get() {
    local endpoint="$1"
    local params="${2:-}"

    if [ -n "$params" ]; then
        curl -s "$BASE_URL$endpoint?key=$API_KEY&token=$TOKEN&$params"
    else
        curl -s "$BASE_URL$endpoint?key=$API_KEY&token=$TOKEN"
    fi
}

# Helper: make POST request
api_post() {
    local endpoint="$1"
    shift
    curl -s -X POST "$BASE_URL$endpoint?key=$API_KEY&token=$TOKEN" "$@"
}

# Helper: make PUT request
api_put() {
    local endpoint="$1"
    shift
    curl -s -X PUT "$BASE_URL$endpoint?key=$API_KEY&token=$TOKEN" "$@"
}

# Helper: make DELETE request
api_delete() {
    local endpoint="$1"
    curl -s -X DELETE "$BASE_URL$endpoint?key=$API_KEY&token=$TOKEN"
}

case "$1" in
    list)
        # List cards in a list
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh list <list-id> [count]"
            exit 1
        fi

        LIST_ID="$2"
        COUNT="${3:-50}"
        RESPONSE=$(api_get "/lists/$LIST_ID/cards" "fields=name,id,desc,pos,labels&limit=$COUNT")

        if echo "$RESPONSE" | jq -e '.[0].id' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '.[] | "[\(.id)] \(.name)\(.desc | if . != "" then " - " + (. | split("\n")[0] | .[0:50]) else "" end)"'
        elif echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
            echo "Error:"
            echo "$RESPONSE" | jq -r '.message'
            exit 1
        else
            echo "No cards found."
        fi
        ;;

    list-json)
        # List cards in a list (JSON output for programmatic use)
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh list-json <list-id>"
            exit 1
        fi

        LIST_ID="$2"
        RESPONSE=$(api_get "/lists/$LIST_ID/cards" "fields=name,id,desc,pos,labels")

        echo "$RESPONSE" | jq '.'
        ;;

    read)
        # Read full card details
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh read <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get "/cards/$CARD_ID" "fields=name,id,desc,pos,url,labels,idList,due,dueComplete")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '"Card: \(.name)\nID: \(.id)\nPosition: \(.pos)\nList ID: \(.idList)\nURL: \(.url)\nDue: \(.due // "None")\nDue Complete: \(.dueComplete)\n\nDescription:\n\(.desc // "None")\n\nLabels: \(if .labels | length > 0 then [.labels[].name] | join(", ") else "None" end)"'
        else
            echo "Error:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    create)
        # Create a new card
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: trello-cards.sh create <list-id> <title> [description]"
            exit 1
        fi

        LIST_ID="$2"
        TITLE="$3"
        DESC="${4:-}"

        RESPONSE=$(api_post "/cards" -d "idList=$LIST_ID" -d "name=$TITLE" -d "desc=$DESC")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "Card created:"
            echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        else
            echo "Error creating card:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    update)
        # Update a card field
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            echo "Usage: trello-cards.sh update <card-id> <field> <value>"
            echo "Fields: name, desc, due, dueComplete, closed"
            exit 1
        fi

        CARD_ID="$2"
        FIELD="$3"
        VALUE="$4"

        RESPONSE=$(api_put "/cards/$CARD_ID" -d "$FIELD=$VALUE")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "Card updated:"
            echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        else
            echo "Error updating card:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    move)
        # Move card to another list
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: trello-cards.sh move <card-id> <list-id>"
            exit 1
        fi

        CARD_ID="$2"
        LIST_ID="$3"

        RESPONSE=$(api_put "/cards/$CARD_ID" -d "idList=$LIST_ID")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "Card moved:"
            echo "$RESPONSE" | jq -r '"[\(.id)] \(.name) -> List: \(.idList)"'
        else
            echo "Error moving card:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    comment)
        # Add comment to card
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: trello-cards.sh comment <card-id> <text>"
            exit 1
        fi

        CARD_ID="$2"
        TEXT="$3"

        RESPONSE=$(api_post "/cards/$CARD_ID/actions/comments" -d "text=$TEXT")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "Comment added."
        else
            echo "Error adding comment:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    comments)
        # List comments on a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh comments <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get "/cards/$CARD_ID/actions" "filter=commentCard")

        if echo "$RESPONSE" | jq -e '.[0].id' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '.[] | "[\(.date | split("T")[0])] \(.memberCreator.fullName // "Unknown"): \(.data.text)"'
        elif echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
            echo "Error:"
            echo "$RESPONSE" | jq -r '.message'
            exit 1
        else
            echo "No comments found."
        fi
        ;;

    archive)
        # Archive a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh archive <card-id>"
            exit 1
        fi

        CARD_ID="$2"

        RESPONSE=$(api_put "/cards/$CARD_ID" -d "closed=true")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "Card archived:"
            echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        else
            echo "Error archiving card:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    unarchive)
        # Unarchive a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh unarchive <card-id>"
            exit 1
        fi

        CARD_ID="$2"

        RESPONSE=$(api_put "/cards/$CARD_ID" -d "closed=false")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "Card restored:"
            echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        else
            echo "Error restoring card:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    delete)
        # Delete a card permanently
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh delete <card-id>"
            exit 1
        fi

        CARD_ID="$2"

        RESPONSE=$(api_delete "/cards/$CARD_ID")

        if [ -z "$RESPONSE" ] || echo "$RESPONSE" | jq -e '.limits' > /dev/null 2>&1; then
            echo "Card deleted."
        else
            echo "Error deleting card:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    top)
        # Move card to top of its list
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh top <card-id>"
            exit 1
        fi

        CARD_ID="$2"

        RESPONSE=$(api_put "/cards/$CARD_ID" -d "pos=top")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "Card moved to top:"
            echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        else
            echo "Error moving card:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    bottom)
        # Move card to bottom of its list
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh bottom <card-id>"
            exit 1
        fi

        CARD_ID="$2"

        RESPONSE=$(api_put "/cards/$CARD_ID" -d "pos=bottom")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "Card moved to bottom:"
            echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        else
            echo "Error moving card:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    position)
        # Set card to specific position
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: trello-cards.sh position <card-id> <pos>"
            echo "Position can be 'top', 'bottom', or a positive number"
            exit 1
        fi

        CARD_ID="$2"
        POS="$3"

        RESPONSE=$(api_put "/cards/$CARD_ID" -d "pos=$POS")

        if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            echo "Card position updated:"
            echo "$RESPONSE" | jq -r '"[\(.id)] \(.name) -> pos: \(.pos)"'
        else
            echo "Error updating position:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    labels)
        # Show labels on a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh labels <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get "/cards/$CARD_ID" "fields=labels")

        if echo "$RESPONSE" | jq -e '.labels' > /dev/null 2>&1; then
            LABELS=$(echo "$RESPONSE" | jq -r '.labels')
            if [ "$(echo "$LABELS" | jq 'length')" -gt 0 ]; then
                echo "$LABELS" | jq -r '.[] | "[\(.color)] \(.name // "(no name)")"'
            else
                echo "No labels on this card."
            fi
        else
            echo "Error:"
            echo "$RESPONSE" | jq -r '.message // .'
            exit 1
        fi
        ;;

    members)
        # Show members assigned to a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh members <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get "/cards/$CARD_ID/members")

        if echo "$RESPONSE" | jq -e '.[0].id' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '.[] | "\(.fullName) (@\(.username))"'
        elif echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
            echo "Error:"
            echo "$RESPONSE" | jq -r '.message'
            exit 1
        else
            echo "No members assigned."
        fi
        ;;

    checklist)
        # Show checklists on a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh checklist <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get "/cards/$CARD_ID/checklists")

        if echo "$RESPONSE" | jq -e '.[0].id' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '.[] | "=== \(.name) ===\n" + ([.checkItems[] | "  [\(if .state == "complete" then "x" else " " end)] \(.name)"] | join("\n")) + "\n"'
        elif echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
            echo "Error:"
            echo "$RESPONSE" | jq -r '.message'
            exit 1
        else
            echo "No checklists on this card."
        fi
        ;;

    *)
        echo "Trello Cards Operations"
        echo
        echo "Usage: trello-cards.sh <command> [args]"
        echo
        echo "Listing:"
        echo "  list <list-id> [count]      List cards in a list"
        echo "  list-json <list-id>         List cards as JSON (for scripting)"
        echo "  read <card-id>              Read full card details"
        echo
        echo "Creating & Updating:"
        echo "  create <list-id> <title> [desc]   Create a new card"
        echo "  update <card-id> <field> <value>  Update card (name, desc, due)"
        echo "  move <card-id> <list-id>          Move card to another list"
        echo
        echo "Positioning:"
        echo "  top <card-id>               Move card to top of list"
        echo "  bottom <card-id>            Move card to bottom of list"
        echo "  position <card-id> <pos>    Set specific position"
        echo
        echo "Comments:"
        echo "  comment <card-id> <text>    Add comment to card"
        echo "  comments <card-id>          List comments on card"
        echo
        echo "Archive & Delete:"
        echo "  archive <card-id>           Archive a card"
        echo "  unarchive <card-id>         Restore archived card"
        echo "  delete <card-id>            Delete card permanently"
        echo
        echo "Details:"
        echo "  labels <card-id>            Show labels on card"
        echo "  members <card-id>           Show assigned members"
        echo "  checklist <card-id>         Show checklists on card"
        ;;
esac
