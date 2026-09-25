#!/bin/bash
# life-manager helpers - resolve the user's config, report where a board has
# stopped being true (unlabelled cards, list sizes, cards gone stale), and
# order a list by category.
#
# Only `sort --apply` writes, and it only renames and positions cards. Nothing
# here moves a card to another list, archives or deletes one; the skill does
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
        echo "  \$LIFE_MANAGER_CONFIG, ./life-manager.yaml, ~/.dbhq/trello/life-manager.yaml" >&2
        echo "" >&2
        # ./system/life-manager.yaml was read until 25 Sep 2026. A config left
        # there is the user's, so say where it went rather than offer setup.
        if [ -f ./system/life-manager.yaml ]; then
            echo "Found ./system/life-manager.yaml, which is no longer read. Move it to ./life-manager.yaml, or set LIFE_MANAGER_CONFIG to its path." >&2
        else
            echo "This is setup mode - offer to create one." >&2
        fi
        exit 1
    fi
    echo "config: $path"
    echo ""
    cat "$path"
}

# A card is stale when nothing has happened to it since the cutoff. Trello's
# dateLastActivity cannot say that on its own: renaming a card or changing its
# position moves it too, so straight after a `sort --apply` every card on the
# list looked fresh to `stale` and to coach mode. So a card whose
# dateLastActivity is past the cutoff is checked against the board's actions
# since then, and it counts as touched only if one of them is more than a
# rename or a position change: a comment, a ticked item, a move between lists,
# a new description, a due date, a label and so on. A card created after the
# cutoff is never stale.
#
# A stale card shows the date of its last activity when that is before the
# cutoff. When a rename or a position change came later, that date says
# nothing, so the card shows "before <cutoff>".
cmd_stale() {
    local list_id="$1" days="${2:-14}" cutoff cards board actions
    [ -z "$list_id" ] && { echo "Usage: life-board.sh stale <list-id> [days]" >&2; exit 1; }
    cutoff=$(days_ago_iso "$days")
    cards=$(api_get_all "/lists/$list_id/cards" "fields=name,dateLastActivity,idBoard")

    # Only a card that shows activity since the cutoff needs its actions read.
    board=$(printf '%s\n' "$cards" | jq -r --arg c "$cutoff" \
        '[.[] | select(.dateLastActivity >= $c)] | first | .idBoard // empty')
    actions='[]'
    if [ -n "$board" ]; then
        actions=$(api_get_all "/boards/$board/actions" "since=$cutoff")
    fi

    printf '%s\n' "$cards" | jq -r --arg c "$cutoff" --argjson acts "$actions" "$(trello_jq_defs)"'
        # A card id starts with its creation time, in seconds, as 8 hex digits.
        def created_at: .[0:8] | explode
            | reduce .[] as $d (0; . * 16 + (if $d >= 97 then $d - 87 elif $d >= 65 then $d - 55 else $d - 48 end));
        ($c | fromdateiso8601) as $cut
        | ($acts
           | map(select(.data.card.id != null)
                 | select((.type == "updateCard"
                           and ((.data.old // {}) | keys - ["pos", "name"] | length) == 0)
                          | not)
                 | .data.card.id)
           | unique) as $touched
        | [ .[]
            | select((.id | created_at) < $cut)
            | select(.dateLastActivity < $c or (.id as $i | $touched | index($i) | not)) ]
        | if length == 0 then "  (nothing stale)"
          else .[] | "  \(if .dateLastActivity < $c then (.dateLastActivity | local_date)
                         else "before \($c | local_date)" end)  \(.name)" end'
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

    # One tab-separated line per card, in the planned order:
    #   id, position to write ("-" when it stays put), labels, new title, old title
    # No field is ever empty: tab is whitespace to `read`, so an empty field
    # would shift every field after it.
    #
    # Only what must change is written. A card keeps its position when it is
    # part of the longest run of cards that are already in the planned order
    # (the longest increasing run of their current positions); every other
    # card is placed in the gap between its kept neighbours. So a list that is
    # already sorted gets no position write at all, and one card out of place
    # gets one. A title is written only when it changes.
    local plan
    plan=$(api_get_all "/lists/$list_id/cards" "fields=name,labels,pos" | jq -r --argjson ord "$order_json" '
        # Strip a leading run of emoji and the whitespace around it. Repeats
        # until nothing changes, so a stamp this order uses is removed even if
        # it is not in the regex (a bare U+2764 with no U+FE0F, say).
        def strip_emoji($stamps):
            sub("^(?:\\p{Emoji_Presentation}|\\p{Extended_Pictographic}\\x{FE0F}|[\\x{FE0F}\\x{200D}\\x{20E3}\\x{E0020}-\\x{E007F}]|\\s)+"; "") as $s
            | ([$stamps[] | select(. as $e | $s | startswith($e))] | first) as $hit
            | if $hit == null then $s else ($s | ltrimstr($hit) | strip_emoji($stamps)) end;
        # The indexes of the longest strictly increasing run of .cur values.
        def keep_indexes:
            . as $a | length as $n
            | reduce range(0; $n) as $i ({len: [], prev: []};
                . as $s
                | ([range(0; $i) | select($a[.].cur < $a[$i].cur)] | max_by($s.len[.])) as $best
                | .len[$i] = (if $best == null then 1 else $s.len[$best] + 1 end)
                | .prev[$i] = $best)
            | . as $s
            | [ [range(0; $n)] | max_by($s.len[.])
                | recurse(if $s.prev[.] == null then empty else $s.prev[.] end) ]
            | sort;
        # The position to write for each card, or null to leave it where it is.
        # A card between two kept ones goes evenly into the gap; after the last
        # kept one, 1000 apart. If a gap is too small to split, every card is
        # renumbered 1000 apart and only those whose position differs are written.
        def new_positions:
            . as $a | length as $n
            | (map(.cur | type == "number") | all) as $numbered
            | (if $numbered then ($a | keep_indexes) else [] end) as $keep
            | [ range(0; $n) as $i
                | if ($keep | index($i)) != null then null
                  else ([$keep[] | select(. < $i)] | max) as $p
                  | ([$keep[] | select(. > $i)] | min) as $q
                  | (if $p == null then 0 else $a[$p].cur end) as $lo
                  | ($i - ($p // -1)) as $k
                  | if $q == null then $lo + 1000 * $k
                    else ($a[$q].cur - $lo) / ($q - ($p // -1)) as $step
                    | if $step < 0.001 then "renumber" else $lo + $step * $k end
                    end
                  end ]
            | if index("renumber") != null
              then [ range(0; $n) as $i | (($i + 1) * 1000) as $want
                     | if $a[$i].cur == $want then null else $want end ]
              else . end;
        ($ord | map(.n)) as $names
        | ($ord | map(.e) | map(select(length > 0))) as $stamps
        | [ .[]
            | ( [.labels[].name] | map(. as $n | $names | index($n)) | map(select(. != null)) | min ) as $rank
            | { id,
                cur: .pos,
                old: .name,
                lab: ([.labels[].name] | join(", ")),
                cat: ( $rank // (if (.labels | length) > 0 then 900 else 999 end) ),
                emo: ( if $rank == null then "" else ($ord[$rank].e) end ),
                bare: (.name | strip_emoji($stamps)) } ]
        | map(. + { new: (if .emo == "" then .old else "\(.emo) \(.bare)" end) })
        | sort_by(.cat, (.bare | ascii_downcase))
        | . as $sorted
        | [$sorted, ($sorted | new_positions)] | transpose[]
        | "\(.[0].id)\t\(.[1] // "-")\t\(if .[0].lab == "" then "-" else .[0].lab end)\t\(.[0].new)\t\(.[0].old)"')

    if [ -z "$plan" ]; then
        echo "  (list is empty)"
        return 0
    fi

    local total moves renames writes
    total=$(printf '%s\n' "$plan" | wc -l | tr -d ' ')
    read -r moves renames writes < <(printf '%s\n' "$plan" | awk -F'\t' '
        { m += ($2 != "-"); r += ($4 != $5); w += ($2 != "-" || $4 != $5) }
        END { print m + 0, r + 0, w + 0 }')

    if [ "$apply" != "--apply" ]; then
        echo "Proposed order (dry run - re-run with --apply to write):"
        printf '%s\n' "$plan" | awk -F'\t' '{
            printf "  %-22s %s%s\n", ($3 == "-" ? "(no label)" : $3), $4, ($4 == $5 ? "" : "   [was: " $5 "]")
        }'
        echo ""
        if [ "$writes" -eq 0 ]; then
            echo "Already in this order - --apply would write nothing."
        else
            echo "--apply would write $writes of $total cards: $moves to move, $renames to rename."
        fi
        return 0
    fi

    if [ "$writes" -eq 0 ]; then
        echo "Already in this order - nothing written."
        return 0
    fi

    # Every write is checked. The first one Trello refuses stops the run, names
    # the card, and says the list is now partly sorted, so a half-applied sort
    # is never reported as done.
    local id pos lab new old written=0 args
    while IFS=$'\t' read -r id pos lab new old; do
        [ "$pos" = "-" ] && pos=""
        if [ -n "$pos" ] || [ "$new" != "$old" ]; then
            args=()
            [ "$new" != "$old" ] && args=(--data-urlencode "name=$new")
            if ! api PUT "/cards/$id" "${pos:+pos=$pos}" "${args[@]}" > /dev/null; then
                echo "Error: sort stopped at \"$old\" ($id): Trello refused the write above." >&2
                echo "$written of $writes writes were made, so the list is only partly sorted. Fix the cause and run sort --apply again to finish." >&2
                exit 1
            fi
            written=$((written + 1))
        fi
        printf '  %-22s %s\n' "$([ "$lab" = "-" ] && echo "(no label)" || echo "$lab")" "$new"
    done <<< "$plan"
    echo ""
    echo "Wrote $writes of $total cards: $moves moved, $renames renamed. The rest were already right."
}

usage() {
    cat <<'USAGE'
Usage: life-board.sh <command>

  config                     Show the resolved config path and its contents
  audit <board-id>           List sizes, unlabelled cards, and cards that look
                             like undefined projects
  stale <list-id> [days]     Cards untouched for N days (default 14). A rename
                             or a move within the list does not count as a touch.
  sort <list-id> "<order>" [--apply]
                             Order a list by category, then alphabetically, and
                             stamp each card with its category emoji.
                             <order> is comma-separated "Label[:emoji]" entries,
                             from the user's config. Dry run without --apply.
                             --apply writes only the cards that must change, and
                             stops at the first write Trello refuses.

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
