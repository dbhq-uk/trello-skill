#!/bin/bash
# Trello Cards Operations
#
# Every request goes through api() in lib.sh, which stops the script with
# Trello's own message on any non-2xx answer. So each verb below only has to
# handle success - and "nothing found" is printed only for a real empty result.

set -e

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trello_load_config

usage() {
    echo "Trello Cards Operations"
    echo
    echo "Usage: trello-cards.sh <command> [args]"
    echo
    echo "Listing:"
    echo "  list <list-id> [count]      List the first [count] cards in a list (default 50)"
    echo "  list-json <list-id>         List cards as JSON (for scripting)"
    echo "  read <card-id>              Read full card details"
    echo
    echo "Creating & Updating:"
    echo "  create <list-id> <title> [desc]   Create a new card"
    echo "  update <card-id> <field> <value>  Update card (name, desc, due, dueComplete, closed)"
    echo "  move <card-id> <list-id>          Move card to another list"
    echo
    echo "Labels & Checklists:"
    echo "  labels <card-id>                    Show labels on a card"
    echo "  label-add <card-id> <label-id>      Apply a board label"
    echo "  label-remove <card-id> <label-id>   Remove a label"
    echo "  checklist <card-id>                 Show checklists"
    echo "  checklist-add <card-id> <name>      Create a checklist, prints its id"
    echo "  checkitem-add <checklist-id> <name> Add an item to a checklist"
    echo "  checkitem-done <card-id> <item-id>  Tick an item (ids from checklist)"
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
    echo "  delete <card-id>            Delete card permanently (cannot be undone)"
    echo
    echo "Details:"
    echo "  members <card-id>           Show assigned members"
}

case "$1" in
    list)
        # List cards in a list
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh list <list-id> [count]"
            exit 1
        fi

        # Fetches the whole list and shows the first <count> in list order.
        # When that leaves cards out, the last line says how many, so a cut
        # list never reads as the whole one. Trello does not document a limit
        # on this endpoint, so the count is applied here rather than sent.
        LIST_ID="$2"
        COUNT="${3:-50}"
        case "$COUNT" in
            ''|*[!0-9]*) echo "Usage: trello-cards.sh list <list-id> [count] - count must be a number" >&2; exit 1 ;;
        esac
        RESPONSE=$(api_get_all "/lists/$LIST_ID/cards" "fields=name,id,desc,pos,labels")

        echo "$RESPONSE" | jq -r --argjson n "$COUNT" 'sort_by(.pos)
            | if length == 0 then "No cards found."
              else (.[0:$n][] | "[\(.id)] \(.name)\(.desc | if . != "" then " - " + (. | split("\n")[0] | .[0:50]) else "" end)"),
                   (if length > $n then "(showing \($n) of \(length) cards - pass a larger count to see the rest)" else empty end) end'
        ;;

    list-json)
        # List cards in a list (JSON output for programmatic use)
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh list-json <list-id>"
            exit 1
        fi

        LIST_ID="$2"
        RESPONSE=$(api_get_all "/lists/$LIST_ID/cards" "fields=name,id,desc,pos,labels")

        echo "$RESPONSE" | jq 'sort_by(.pos)'
        ;;

    read)
        # Read full card details
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh read <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get "/cards/$CARD_ID" "fields=name,id,desc,pos,url,labels,idList,due,dueComplete")

        echo "$RESPONSE" | jq -r "$(trello_jq_defs)"'"Card: \(.name)\nID: \(.id)\nPosition: \(.pos)\nList ID: \(.idList)\nURL: \(.url)\nDue: \(if .due then "\(.due | local_time) local time (\(.due))" else "None" end)\nDue Complete: \(.dueComplete)\n\nDescription:\n\(.desc // "None")\n\nLabels: \(if .labels | length > 0 then [.labels[].name] | join(", ") else "None" end)"'
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

        RESPONSE=$(api_post "/cards" -d "idList=$LIST_ID" \
            --data-urlencode "name=$TITLE" --data-urlencode "desc=$DESC")

        echo "Card created:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
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

        RESPONSE=$(api_put "/cards/$CARD_ID" --data-urlencode "$FIELD=$VALUE")

        echo "Card updated:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
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

        echo "Card moved:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name) -> List: \(.idList)"'
        ;;

    comment)
        # Add comment to card
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: trello-cards.sh comment <card-id> <text>"
            exit 1
        fi

        CARD_ID="$2"
        TEXT="$3"

        api_post "/cards/$CARD_ID/actions/comments" --data-urlencode "text=$TEXT" > /dev/null
        echo "Comment added."
        ;;

    comments)
        # List comments on a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh comments <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get_all "/cards/$CARD_ID/actions" "filter=commentCard")

        echo "$RESPONSE" | jq -r "$(trello_jq_defs)"'if length == 0 then "No comments found."
            else .[] | "[\(.date | local_date)] \(.memberCreator.fullName // "Unknown"): \(.data.text)" end'
        ;;

    archive)
        # Archive a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh archive <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_put "/cards/$CARD_ID" -d "closed=true")

        echo "Card archived:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        ;;

    unarchive)
        # Unarchive a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh unarchive <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_put "/cards/$CARD_ID" -d "closed=false")

        echo "Card restored:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        ;;

    delete)
        # Delete a card permanently
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh delete <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        api_delete "/cards/$CARD_ID" > /dev/null
        echo "Card deleted."
        ;;

    top)
        # Move card to top of its list
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh top <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_put "/cards/$CARD_ID" -d "pos=top")

        echo "Card moved to top:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
        ;;

    bottom)
        # Move card to bottom of its list
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh bottom <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_put "/cards/$CARD_ID" -d "pos=bottom")

        echo "Card moved to bottom:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name)"'
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

        echo "Card position updated:"
        echo "$RESPONSE" | jq -r '"[\(.id)] \(.name) -> pos: \(.pos)"'
        ;;

    labels)
        # Show labels on a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh labels <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get "/cards/$CARD_ID" "fields=labels")

        echo "$RESPONSE" | jq -r 'if (.labels | length) == 0 then "No labels on this card."
            else .labels[] | "[\(.color)] \(.name // "(no name)")" end'
        ;;

    label-add)
        # Apply an existing board label to a card. Label IDs come from
        # `trello-boards.sh labels <board-id>`.
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: trello-cards.sh label-add <card-id> <label-id>"
            exit 1
        fi

        api_post "/cards/$2/idLabels" --data-urlencode "value=$3" > /dev/null
        echo "Label applied."
        ;;

    label-remove)
        # Remove a label from a card (the label itself survives on the board).
        # "Label removed." is printed only after a 2xx - api() stops the
        # script on anything else.
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: trello-cards.sh label-remove <card-id> <label-id>"
            exit 1
        fi

        api_delete "/cards/$2/idLabels/$3" > /dev/null
        echo "Label removed."
        ;;

    checklist-add)
        # Create a checklist on a card and print its id, so the id can be fed
        # straight into checkitem-add without a second lookup.
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: trello-cards.sh checklist-add <card-id> <name>"
            exit 1
        fi

        RESPONSE=$(api_post "/cards/$2/checklists" --data-urlencode "name=$3")
        echo "$RESPONSE" | jq -r '.id'
        ;;

    checkitem-add)
        # Add an item to an existing checklist
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: trello-cards.sh checkitem-add <checklist-id> <name>"
            exit 1
        fi

        api_post "/checklists/$2/checkItems" --data-urlencode "name=$3" > /dev/null
        echo "Added: $3"
        ;;

    checkitem-done)
        # Tick a checklist item. Trello sets an item's state through the card
        # it is on, so this takes the card id and the item id, both shown by
        # `checklist <card-id>`.
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "Usage: trello-cards.sh checkitem-done <card-id> <item-id>"
            exit 1
        fi

        RESPONSE=$(api_put "/cards/$2/checkItem/$3" --data-urlencode "state=complete")
        echo "$RESPONSE" | jq -r '"Ticked: \(.name)"'
        ;;

    members)
        # Show members assigned to a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh members <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get "/cards/$CARD_ID/members")

        echo "$RESPONSE" | jq -r 'if length == 0 then "No members assigned."
            else .[] | "\(.fullName) (@\(.username))" end'
        ;;

    checklist)
        # Show checklists on a card
        if [ -z "$2" ]; then
            echo "Usage: trello-cards.sh checklist <card-id>"
            exit 1
        fi

        CARD_ID="$2"
        RESPONSE=$(api_get "/cards/$CARD_ID/checklists")

        echo "$RESPONSE" | jq -r 'if length == 0 then "No checklists on this card."
            else .[] | "=== \(.name) [\(.id)] ===\n" + ([.checkItems | sort_by(.pos)[] | "  [\(if .state == "complete" then "x" else " " end)] \(.name)  (item \(.id))"] | join("\n")) + "\n" end'
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
