#!/bin/bash
# life-manager helpers - resolve the user's config, and report where a board
# has stopped being true: unlabelled cards, list sizes, and cards gone stale.
#
# Read-only. Nothing here moves, archives or deletes a card; the skill does
# that only after showing a plan and getting approval.

set -e

# The shared helpers live in the trello skill, which sits beside this one in
# the pack. A partial install without it gets told what is missing.
TRELLO_LIB="$(dirname "${BASH_SOURCE[0]}")/../../trello/scripts/lib.sh"
if [ ! -f "$TRELLO_LIB" ]; then
    echo "Error: life-manager needs the trello skill from the same pack, installed beside it." >&2
    echo "Install the whole pack, or add it with: npx skills add dbhq-uk/trello-skill --skill trello" >&2
    exit 1
fi
# shellcheck source=../../trello/scripts/lib.sh
. "$TRELLO_LIB"
trello_load_config

# Resolve the user's life-manager config. Nothing personal lives in this skill,
# so every board, list and label comes from here or from asking the user.
resolve_config() {
    local candidates=(
        "$LIFE_MANAGER_CONFIG"
        "./life-manager.yaml"
        "./system/life-manager.yaml"
        "$HOME/.dbhq/trello/life-manager.yaml"
    )
    local c
    for c in "${candidates[@]}"; do
        [ -n "$c" ] && [ -f "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

cmd_config() {
    local path
    if ! path=$(resolve_config); then
        echo "No config found. Looked for:" >&2
        echo "  \$LIFE_MANAGER_CONFIG, ./life-manager.yaml, ./system/life-manager.yaml, ~/.dbhq/trello/life-manager.yaml" >&2
        echo "" >&2
        echo "This is setup mode - offer to create one." >&2
        exit 1
    fi
    echo "config: $path"
    echo ""
    cat "$path"
}

cmd_stale() {
    local list_id="$1" days="${2:-14}" cutoff
    [ -z "$list_id" ] && { echo "Usage: life-board.sh stale <list-id> [days]" >&2; exit 1; }
    cutoff=$(days_ago_iso "$days")
    api_get_all "/lists/$list_id/cards" "fields=name,dateLastActivity" \
        | jq -r --arg c "$cutoff" "$(trello_jq_defs)"'
            [.[] | select(.dateLastActivity < $c)]
            | if length == 0 then "  (nothing stale)"
              else .[] | "  \(.dateLastActivity | local_date)  \(.name)" end'
}

cmd_audit() {
    local board_id="$1"
    [ -z "$board_id" ] && { echo "Usage: life-board.sh audit <board-id>" >&2; exit 1; }

    echo "=== List sizes ==="
    api_get "/boards/$board_id/lists" "cards=open&card_fields=name" \
        | jq -r '.[] | "  \(.cards | length | tostring | (" " * (4 - length)) + .)  \(.name)"'

    echo ""
    echo "=== Unlabelled cards ==="
    api_get "/boards/$board_id/lists" "cards=open&card_fields=name,labels" \
        | jq -r '
            [.[] | .name as $l | .cards[] | select(.labels | length == 0) | "  \($l): \(.name)"] as $u
            | if ($u | length) == 0 then "  (none - every card is categorised)"
              else ($u | .[]), "", "  \($u | length) unlabelled" end'

    echo ""
    echo "=== Cards with no checklist and no description ==="
    echo "    (candidates for breaking down - a bare title is often a hidden project)"
    api_get_all "/boards/$board_id/cards" "fields=name,desc,idList&checklists=all" \
        | jq -r '
            [.[] | select((.checklists | length) == 0 and (.desc | length) == 0) | .name] as $b
            | if ($b | length) == 0 then "  (none)"
              else ($b | .[0:40][] | "  \(.)"),
                   (if ($b | length) > 40 then "  (+\(($b | length) - 40) more)" else empty end) end'
}

# Order a list by category, then alphabetically within each category, and
# optionally stamp each card with its category's emoji.
#
# The category order is the user's, not ours - pass it in as a comma-separated
# list, taken from `label_order` (and `label_emoji`) in their config. Each entry
# is either "Label" or "Label:emoji". A card is ranked by its highest-priority
# label; cards carrying a label absent from the order sit after those that
# don't, and unlabelled cards sink to the bottom where they are visible as work
# still to do.
#
# The emoji is a prefix on the card title, so the category is readable on the
# board itself rather than only in a label filter. A card is renamed only when
# its category has an emoji; every other title is left exactly as it is. When
# it is renamed, any emoji already leading the title is stripped first, so
# re-running never doubles up and a recategorised card picks up its new emoji.
#
# "Emoji" means emoji and nothing wider: a code point that shows as emoji by
# default, one made emoji by U+FE0F, the joiners and skin tones that build a
# sequence, and any emoji named in the order itself. Not the whole Unicode
# symbol classes, which also hold ` ^ © ™ ° and £ - "£500 to pay" keeps its £,
# "©2026 renewal" keeps its ©, and "`make` fails" keeps its backtick.
#
# Dry run by default. Writes only with --apply.
cmd_sort() {
    local list_id="$1" order_csv="$2" apply="${3:-}"
    if [ -z "$list_id" ] || [ -z "$order_csv" ]; then
        echo "Usage: life-board.sh sort <list-id> \"Label[:emoji],Label[:emoji],...\" [--apply]" >&2
        exit 1
    fi

    # "Now:🔥,Health:❤️" -> [{"n":"Now","e":"🔥"},{"n":"Health","e":"❤️"}]
    local order_json
    order_json=$(printf '%s' "$order_csv" | jq -R '
        split(",")
        | map(gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0))
        | map( (index(":")) as $i
               | if $i == null
                 then { n: ., e: "" }
                 else { n: (.[0:$i] | gsub("^\\s+|\\s+$"; "")),
                        e: (.[$i+1:] | gsub("^\\s+|\\s+$"; "")) }
                 end )')

    local plan
    plan=$(api_get_all "/lists/$list_id/cards" "fields=name,labels" | jq -r --argjson ord "$order_json" '
        # Strip a leading run of emoji and the whitespace around it. Repeats
        # until nothing changes, so a stamp this order uses is removed even if
        # it is not in the regex (a bare U+2764 with no U+FE0F, say).
        def strip_emoji($stamps):
            sub("^(?:\\p{Emoji_Presentation}|\\p{Extended_Pictographic}\\x{FE0F}|[\\x{FE0F}\\x{200D}\\x{20E3}\\x{E0020}-\\x{E007F}]|\\s)+"; "") as $s
            | ([$stamps[] | select(. as $e | $s | startswith($e))] | first) as $hit
            | if $hit == null then $s else ($s | ltrimstr($hit) | strip_emoji($stamps)) end;
        ($ord | map(.n)) as $names
        | ($ord | map(.e) | map(select(length > 0))) as $stamps
        | [ .[]
            | ( [.labels[].name] | map(. as $n | $names | index($n)) | map(select(. != null)) | min ) as $rank
            | { id,
                old: .name,
                lab: ([.labels[].name] | join(", ")),
                cat: ( $rank // (if (.labels | length) > 0 then 900 else 999 end) ),
                emo: ( if $rank == null then "" else ($ord[$rank].e) end ),
                bare: (.name | strip_emoji($stamps)) } ]
        | map(. + { new: (if .emo == "" then .old else "\(.emo) \(.bare)" end) })
        | sort_by(.cat, (.bare | ascii_downcase))
        | to_entries[]
        | "\(.value.id)\t\((.key + 1) * 1000)\t\(if .value.lab == "" then "-" else .value.lab end)\t\(.value.new)\t\(.value.old)"')

    if [ -z "$plan" ]; then
        echo "  (list is empty)"
        return 0
    fi

    if [ "$apply" != "--apply" ]; then
        echo "Proposed order (dry run - re-run with --apply to write):"
        printf '%s\n' "$plan" | awk -F'\t' '{
            printf "  %-22s %s%s\n", ($3 == "-" ? "(no label)" : $3), $4, ($4 == $5 ? "" : "   [was: " $5 "]")
        }'
        return 0
    fi

    while IFS=$'\t' read -r id pos lab new old; do
        if [ "$new" != "$old" ]; then
            api PUT "/cards/$id" "pos=$pos" --data-urlencode "name=$new" > /dev/null
        else
            api PUT "/cards/$id" "pos=$pos" > /dev/null
        fi
        printf '  %-22s %s\n' "$([ "$lab" = "-" ] && echo "(no label)" || echo "$lab")" "$new"
    done <<< "$plan"
}

usage() {
    cat <<'USAGE'
Usage: life-board.sh <command>

  config                     Show the resolved config path and its contents
  audit <board-id>           List sizes, unlabelled cards, and cards that look
                             like undefined projects
  stale <list-id> [days]     Cards untouched for N days (default 14)
  sort <list-id> "<order>" [--apply]
                             Order a list by category, then alphabetically, and
                             stamp each card with its category emoji.
                             <order> is comma-separated "Label[:emoji]" entries,
                             from the user's config. Dry run without --apply.

Only `sort --apply` writes; everything else is read-only.
Credentials come from ~/.dbhq/trello/config.json.
USAGE
}

case "${1:-}" in
    config) cmd_config ;;
    audit)  cmd_audit "${2:-}" ;;
    stale)  cmd_stale "${2:-}" "${3:-}" ;;
    sort)   cmd_sort "${2:-}" "${3:-}" "${4:-}" ;;
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
