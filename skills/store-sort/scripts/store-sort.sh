#!/bin/bash
# store-sort - put a Trello shopping list into a store's aisle order.
#
# A store is a preset in JSON: its sections in aisle order, entrance to
# checkout, each with an emoji, a position range, and items that pair an emoji
# with the keywords that name it. The preset is data, so the agent does not
# interpret prose card by card, and a test can check it.
#
# `plan` reads the list and matches every card against the preset, `apply`
# writes a plan to the list in one call. The agent reviews the plan between the
# two: it fixes titles, and places what no keyword matched.
#
# The user's own layouts in ~/.dbhq/trello/stores/<store>.json come first, then
# the presets shipped in references/stores/.

set -e

# The shared helpers live in the trello skill, which sits beside this one in
# the pack. A partial install without it gets told what is missing.
TRELLO_LIB="$(dirname "${BASH_SOURCE[0]}")/../../trello/scripts/lib.sh"
if [ ! -f "$TRELLO_LIB" ]; then
    echo "Error: store-sort needs the trello skill from the same pack, installed beside it." >&2
    echo "Install the whole pack, or add it with: npx skills add dbhq-uk/trello-skill --skill trello" >&2
    exit 1
fi
# shellcheck source=../../trello/scripts/lib.sh
. "$TRELLO_LIB"
trello_load_config

SHIPPED_STORES="$(dirname "${BASH_SOURCE[0]}")/../references/stores"
USER_STORES="$TRELLO_CONFIG_DIR/stores"

usage() {
    cat <<'USAGE'
Usage: store-sort.sh <command>

  stores                          The store presets there are to choose from
  sections [store]                A store's sections in aisle order, with their
                                  emoji and keywords (default store: tesco)
  plan <list-id> [store]          Match every card on the list to a section and
                                  print a plan as JSON. Writes nothing.
  apply <list-id> <plan> [--apply]
                                  Show what the plan would change, or with
                                  --apply rename and position the whole list.
                                  <plan> is a file, or - for stdin.

Presets: ~/.dbhq/trello/stores/<store>.json first, then the ones shipped with
this skill. Only `apply --apply` writes.
USAGE
}

# The preset file for a store name, or stop with the names there are.
store_file() {
    local store="${1:-tesco}" f
    if ! [[ "$store" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        echo "Error: a store name is lowercase letters, digits and hyphens, not '$store'." >&2
        exit 1
    fi
    for f in "$USER_STORES/$store.json" "$SHIPPED_STORES/$store.json"; do
        if [ -f "$f" ]; then
            jq empty "$f" 2>/dev/null || { echo "Error: $f is not valid JSON." >&2; exit 1; }
            echo "$f"
            return 0
        fi
    done
    echo "Error: no store preset called '$store'. There are: $(store_names | tr '\n' ' ')" >&2
    exit 1
}

store_names() {
    local f
    for f in "$USER_STORES"/*.json "$SHIPPED_STORES"/*.json; do
        [ -f "$f" ] && basename "$f" .json
    done | sort -u
}

# jq definitions shared by plan and apply.
#
# emoji_of_section: every emoji a section uses, with U+FE0F dropped, so 🌶 and
# 🌶️ are one emoji. strip_emoji: a title without its leading emoji, trying the
# preset's own emoji first so it works whatever Unicode version jq's regex
# library knows. match_card: the item whose keyword names the card, longest
# keyword first, so "black pepper" beats "pepper" and "coconut milk" beats
# "coconut". A keyword matches a whole word, with an optional plural s or es.
store_jq_defs() {
    cat <<'JQ'
def plain: gsub("\ufe0f"; "");
def emoji_of_section: ([.emoji] + [.items[].emoji]) | map(plain) | unique;
def all_emoji($store): [$store.sections[] | emoji_of_section[]] | sort_by(-length);
def strip_emoji($known):
    (plain | ltrimstr(" ")) as $s
    | ([$known[] | select(. as $e | $s | startswith($e))] | first) as $hit
    | if $hit != null then ($s | ltrimstr($hit) | strip_emoji($known))
      else $s | sub("^(?:\\p{Emoji_Presentation}|\\p{Extended_Pictographic}|[\\x{200D}\\x{20E3}\\x{E0020}-\\x{E007F}]|\\s)+"; "")
      end;
def match_card($store):
    . as $title
    | [ $store.sections | to_entries[] | .key as $si | .value.items | to_entries[]
        | .key as $ii | .value as $item | $item.keywords[] as $kw
        | select($title | test("(^|[^\\p{L}\\p{N}])" + $kw + "(s|es)?($|[^\\p{L}\\p{N}])"; "i"))
        | {si: $si, ii: $ii, emoji: $item.emoji, kw: $kw} ]
    | sort_by(-(.kw | length), .si, .ii) | first;
JQ
}

cmd_stores() {
    local names
    names=$(store_names)
    [ -n "$names" ] || { echo "No store presets found." >&2; exit 1; }
    printf '%s\n' "$names"
}

cmd_sections() {
    local file
    file=$(store_file "${1:-}")
    jq -r '"\(.name)\n\(.about // "")\n",
        (.sections | to_entries[] | .key as $i | .value
         | "\($i + 1). \(.emoji) \(.name)  (positions \(.range[0])-\(.range[1]))",
           (if .where then "   \(.where)" else empty end),
           (.items[] | "   \(.emoji) \(.keywords | join(", "))"))' "$file"
}

cmd_plan() {
    local list_id="$1" store="${2:-tesco}" file cards plan
    [ -z "$list_id" ] && { echo "Usage: store-sort.sh plan <list-id> [store]" >&2; exit 1; }
    file=$(store_file "$store")
    cards=$(api_get_all "/lists/$list_id/cards" "fields=name,pos")

    # Cards in aisle order: by section, then by the item's place in the
    # section, then where they sit now. Cards no keyword matched come last,
    # with no section, for the agent to place.
    plan=$(printf '%s\n' "$cards" | jq --slurpfile s "$file" --arg storename "$store" --arg list "$list_id" \
        "$(store_jq_defs)"'
        $s[0] as $store | all_emoji($store) as $known
        | { store: $storename, list: $list, cards: [
            .[] | . as $c | ($c.name | strip_emoji($known)) as $bare
            | ($bare | match_card($store)) as $m
            | { id: $c.id,
                section: (if $m then $store.sections[$m.si].name else null end),
                name: (if $m then "\($m.emoji) \($bare)" else $c.name end),
                was: $c.name,
                matched: (if $m then $m.kw else null end),
                k: [($m.si // 999), ($m.ii // 0), ($c.pos // 0)] } ]
            | sort_by(.k) | map(del(.k)) }')
    printf '%s\n' "$plan"

    local unmatched
    unmatched=$(printf '%s\n' "$plan" | jq -r '.cards[] | select(.section == null) | "  \(.was)"')
    if [ -n "$unmatched" ]; then
        {
            echo "No keyword matched these cards. Give each a section and an emoji before apply:"
            printf '%s\n' "$unmatched"
        } >&2
    fi
}

cmd_apply() {
    local list_id="$1" plan_src="$2" apply="${3:-}" plan store file cards problems rows
    if [ -z "$list_id" ] || [ -z "$plan_src" ]; then
        echo "Usage: store-sort.sh apply <list-id> <plan.json|-> [--apply]" >&2
        exit 1
    fi
    if [ "$plan_src" = "-" ]; then plan=$(cat); else
        [ -f "$plan_src" ] || { echo "Error: no plan file at $plan_src" >&2; exit 1; }
        plan=$(cat "$plan_src")
    fi
    printf '%s\n' "$plan" | jq -e '.cards | type == "array"' > /dev/null 2>&1 \
        || { echo "Error: the plan is not JSON with a cards array. Make one with: store-sort.sh plan <list-id>" >&2; exit 1; }
    store=$(printf '%s\n' "$plan" | jq -r '.store // "tesco"')
    file=$(store_file "$store")
    cards=$(api_get_all "/lists/$list_id/cards" "fields=name,pos")
    if [ "$(printf '%s\n' "$cards" | jq 'length')" -eq 0 ]; then
        echo "  (list is empty)"
        return 0
    fi

    # Refuse a plan that does not match the list or the preset, before any
    # write: a card left out or unplaced, a card not on the list, a section
    # the store does not have, or a title whose emoji belongs to another
    # section - which would put the card's label and its place at odds.
    problems=$(printf '%s\n' "$plan" | jq -r --argjson list "$cards" --slurpfile s "$file" "$(store_jq_defs)"'
        $s[0] as $store
        | ($store.sections | map(.name | ascii_downcase)) as $names
        | ($list | map(.id)) as $on_list
        | (.cards | map(.id)) as $planned
        | ( ($list[] | select(.id as $i | $planned | index($i) | not)
             | "not in the plan: \"\(.name)\" (\(.id))"),
            (.cards | group_by(.id)[] | select(length > 1) | "in the plan twice: \(.[0].id)"),
            (.cards[]
             | if (.id | type) != "string" or (.id as $i | $on_list | index($i) | not) then
                 "not on this list: \(.id // "a card with no id")"
               elif (.name | type) != "string" or (.name | length) == 0 then
                 "no title: \(.id)"
               elif (.name | test("[\\t\\n]")) then
                 "a tab or line break in the title: \(.id)"
               elif .section == null then
                 "no section: \"\(.name)\" (\(.id))"
               elif (.section | ascii_downcase) as $n | $names | index($n) | not then
                 "no section called \"\(.section)\" in \($store.name): \"\(.name)\" (\(.id))"
               else
                 . as $c | ($c.section | ascii_downcase) as $n | ($c.name | plain) as $t
                 | ([ $store.sections[] | select((.name | ascii_downcase) != $n) | . as $o
                      | emoji_of_section[] | select(. as $e | $t | startswith($e)) | $o.name ] | first) as $other
                 | if $other != null
                   then "\"\($c.name)\" (\($c.id)) is planned for \($c.section) but starts with an emoji from \($other)"
                   else empty end
               end) )')
    if [ -n "$problems" ]; then
        echo "Error: the plan does not fit this list and store, so nothing was written:" >&2
        printf '%s\n' "$problems" | sed 's/^/  /' >&2
        exit 1
    fi

    # One tab-separated row per card, in aisle order:
    #   id, position to write ("-" to leave it), section, new title, old title
    # A section's cards are spread evenly through its range, in plan order. If
    # the list is already in this order, no position is written at all, so a
    # sorted list gets no write for its order.
    rows=$(printf '%s\n' "$plan" | jq -r --argjson list "$cards" --slurpfile s "$file" '
        $s[0] as $store
        | ($list | map({(.id): .}) | add // {}) as $now
        | [ .cards[] | . as $c
            | ($store.sections | map(.name | ascii_downcase) | index($c.section | ascii_downcase)) as $si
            | $c + {si: $si} ]
        | to_entries | map(.value + {order: .key}) | sort_by(.si, .order)
        | group_by(.si)
        | map( . as $g | $store.sections[$g[0].si] as $sec
               | ($sec.range[1] - $sec.range[0]) as $w
               | if ($g | length) >= $w then error("section \($sec.name) holds at most \($w - 1) cards, the plan gives it \($g | length)") else . end
               | to_entries
               | map(.value + { target: ($sec.range[0] + (($w * (.key + 1)) / (($g | length) + 1) | floor)),
                                label: "\($sec.emoji) \($sec.name)" }) )
        | add
        | ([ $list | sort_by(.pos)[] | .id ] == map(.id)) as $in_order
        | .[]
        | $now[.id] as $cur
        | "\(.id)\t\(if $in_order or $cur.pos == .target then "-" else .target end)\t\(.label)\t\(.name)\t\($cur.name)"')

    local total moves renames writes
    total=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
    read -r moves renames writes < <(printf '%s\n' "$rows" | awk -F'\t' '
        { m += ($2 != "-"); r += ($4 != $5); w += ($2 != "-" || $4 != $5) }
        END { print m + 0, r + 0, w + 0 }')

    if [ "$apply" != "--apply" ]; then
        echo "Proposed order (dry run - re-run with --apply to write):"
        printf '%s\n' "$rows" | awk -F'\t' '{
            if ($3 != last) { print $3; last = $3 }
            printf "  %s%s\n", $4, ($4 == $5 ? "" : "   [was: " $5 "]")
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
    # the card, and says the list is now partly sorted.
    local id pos label new old last="" written=0 args
    while IFS=$'\t' read -r id pos label new old; do
        [ "$pos" = "-" ] && pos=""
        if [ -n "$pos" ] || [ "$new" != "$old" ]; then
            args=()
            [ "$new" != "$old" ] && args=(--data-urlencode "name=$new")
            if ! api PUT "/cards/$id" "${pos:+pos=$pos}" "${args[@]}" > /dev/null; then
                echo "Error: store-sort stopped at \"$old\" ($id): Trello refused the write above." >&2
                echo "$written of $writes writes were made, so the list is only partly sorted. Fix the cause and run apply --apply again to finish." >&2
                exit 1
            fi
            written=$((written + 1))
        fi
        [ "$label" != "$last" ] && { echo "$label"; last="$label"; }
        echo "  $new"
    done <<< "$rows"
    echo ""
    echo "Wrote $writes of $total cards: $moves moved, $renames renamed. The rest were already right."
}

case "${1:-}" in
    stores)   cmd_stores ;;
    sections) cmd_sections "${2:-}" ;;
    plan)     cmd_plan "${2:-}" "${3:-}" ;;
    apply)    cmd_apply "${2:-}" "${3:-}" "${4:-}" ;;
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
