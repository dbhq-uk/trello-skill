---
name: store-sort
description: Sort a Trello shopping list into a supermarket's aisle-flow order, with a food-type emoji on every card. Works for any store via presets; ships a Tesco (UK) preset by default. Trigger on phrases like "sort my shopping list", "organise shopping list", "put my list in aisle order", "tesco order", "store order".
---

# Store-Sort - shopping list into aisle order

Reorders a Trello shopping list to match how a supermarket lays out its store, prefixing a food-type emoji to every card so the list is fast to shop and easy to scan. Works for any store through a **preset** that defines the aisle order, and ships with a **Tesco (UK)** preset as the default. Built on the `trello` skill in this pack.

**Needs the `trello` skill installed beside it.** `store-sort.sh` loads `trello`'s shared helpers, and setup ships only in `trello`. The plugin and `install.sh` install both. With the skills CLI, add both by name: `npx skills add dbhq-uk/trello-skill --skill trello --skill store-sort`. If `trello` is missing, the script stops and says so, with that command.

## How it works

1. Resolve the target board and list
2. Create any missing new cards first, so the plan covers them
3. `plan` matches every card to a section of the store preset by keyword and proposes a title with the right emoji
4. Review the plan: place any card no keyword matched, and fix titles
5. Show the user the dry run of `apply`, then write the whole list with one `apply --apply`
6. Verify the displayed order

## Resolving the board and list

There are no hardcoded defaults - nothing personal is baked into this skill. If the user has not named a board and list, ask. Then resolve IDs:

```bash
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh find "<board name>"
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh lists <board-id>
```

If the user always sorts the same list, they can name it once ("the Shopping list on my Home board") and you resolve it each run - do not store personal board or list IDs in this skill.

## Store presets

A preset is a JSON file: the store's sections in aisle order, entrance to checkout. Each section has an emoji, a position range, a note on where it is, and items that pair an emoji with the keywords that name it. No keyword and no emoji belongs to two sections, so the emoji on a card says which section it is in.

- **Default - Tesco (UK):** `references/stores/tesco.json`. It is **one store's layout**, built from one real Tesco superstore. Tesco stores differ, so if the user says their store is laid out differently, believe them.
- **The user's own store:** copy a preset to `~/.dbhq/trello/stores/<store>.json` and change it - reorder the sections, move keywords. A file there is used before a shipped preset of the same name. Ask the user for their store's layout, entrance to checkout.

```bash
${CLAUDE_SKILL_DIR}/scripts/store-sort.sh stores             # the presets there are
${CLAUDE_SKILL_DIR}/scripts/store-sort.sh sections [store]   # a preset's sections, emoji and keywords
```

## Workflow

1. **Add missing cards** (one call per new card; batch them in a single message). Give each its section's emoji:
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh create <list-id> "🥫 Item name" ""
   ```
2. **Make a plan.** It reads the list and writes nothing. Save it to a file:
   ```bash
   PLAN=$(mktemp)
   ${CLAUDE_SKILL_DIR}/scripts/store-sort.sh plan <list-id> [store] > "$PLAN"
   ```
   The plan is JSON, cards in aisle order:
   ```json
   {"store": "tesco", "list": "<list-id>", "cards": [
     {"id": "<card-id>", "section": "Fruit", "name": "🍌 6 bananas", "was": "6 bananas", "matched": "banana"}
   ]}
   ```
   A card no keyword matched has `"section": null`, and stderr lists it.
3. **Review the plan.** Give every unmatched card a section and an emoji from that section (`sections` shows them). Fix titles by the conventions below. Check each `matched` keyword makes sense: a keyword can match one word of a longer name, such as "lemon" in "lemon juice". Within a section, `apply` keeps the order the plan gives.
4. **Show the dry run**, then stop and wait for approval:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/store-sort.sh apply <list-id> "$PLAN"
   ```
5. **Apply it** - one call renames and positions the whole list:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/store-sort.sh apply <list-id> "$PLAN" --apply
   ```
6. **Verify** the final order:
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh list <list-id> 50
   ```

`apply` refuses a plan that does not fit, and writes nothing: a card on the list left out of the plan, a card that is not on the list, a card with no section or a section the store does not have, or a title whose emoji belongs to another section. It spreads each section's cards through that section's position range and writes only what changes, so a list already in order gets no position write.

## Quantity and naming conventions

- Lead with quantity where helpful: `🥔 1.5kg baby potatoes`, `🍋 7 lemons`
- Use `×` for bottle/unit counts: `🍷 2 × Rioja Crianza`
- Optional items: append ` (optional)`
- Sentence-case the item name (no all-caps, no all-lowercase)
- Fix obvious typos in the user's input but flag the correction (e.g. "Pinot Noi" → "Pinot Noir", "Crement" → "Crémant"). A bare quantity with no unit is usually a missed `1 ×`
- Items the user calls cupboard staples go in the ambient sections, whatever aisle the store shelves them in
- On a shopping list the emoji at the start of each card's title is its category, so shopping cards carry no labels. Do not add one, even on a board whose other lists use labels.

## Pantry-staples check (optional)

Before adding common staples to a list, ask the user whether they already have them - people usually do, and it saves a duplicate buy. Typical staples worth checking: cooking oils, salt, black pepper, common dried herbs and spices, honey, stock cubes, sugar, plain flour, soy sauce, balsamic vinegar, tea bags, tinned tomatoes. State the candidates explicitly and let the user say which to skip. Treat this list as a starting point and adapt it to the user.

## Error recovery

- `apply --apply` checks every write. The first one Trello refuses stops the run with a non-zero exit, names the card, and says the list is only partly sorted. Tell the user, fix the cause, and run `apply --apply` again with the same plan to finish.
- If a card creation fails, retry once; if it still fails, list it for the user to handle manually.
