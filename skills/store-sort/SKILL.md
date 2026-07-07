---
name: store-sort
description: Sort a Trello shopping list into a supermarket's aisle-flow order, with a food-type emoji on every card. Works for any store via presets; ships a Tesco (UK) preset by default. Trigger on phrases like "sort my shopping list", "organise shopping list", "put my list in aisle order", "tesco order", "store order".
---

# Store-Sort - shopping list into aisle order

Reorders a Trello shopping list to match how a supermarket lays out its store, prefixing a food-type emoji to every card so the list is fast to shop and easy to scan. Works for any store through a **preset** that defines the aisle order, and ships with a **Tesco (UK)** preset as the default. Built on the `trello` skill in this pack.

## How it works

1. Resolve the target board and list
2. Load the store preset (aisle order) - default Tesco, see `references/tesco.md`
3. Classify each card into a section and prefix the right emoji (see `references/emoji-reference.md`)
4. Optionally add missing items and run a pantry-staples check
5. Position every card in the preset's canonical order
6. Verify the displayed order

## Resolving the board and list

There are no hardcoded defaults - nothing personal is baked into this skill. If the user has not named a board and list, ask. Then resolve IDs:

```bash
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh find "<board name>"
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh lists <board-id>
```

If the user always sorts the same list, they can name it once ("the Shopping list on my Home board") and you resolve it each run - do not store personal board or list IDs in this skill.

## Choosing a store preset

- **Default - Tesco (UK):** the canonical aisle order, position layout, and within-section sub-ordering live in `references/tesco.md`.
- **Another store:** ask the user for their store's layout (entrance to checkout), or start from the closest preset and adjust. A new preset can be saved as `references/<store>.md` mirroring the Tesco one.

## Workflow

1. **Fetch current cards as JSON**
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh list-json <list-id>
   ```
2. **Classify each card** by section using the active preset and the emoji reference.
3. **Pantry-staples check** (optional, see below) before adding new staples.
4. **Create any missing new cards** (one Bash call per card; batch them in a single message):
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh create <list-id> "🥫 Item name" ""
   ```
5. **Rename existing cards** to prepend the correct emoji if missing or wrong:
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh update <card-id> name "🥫 Marmite"
   ```
6. **Position every card** in the preset's canonical order with explicit pos values:
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh position <card-id> <pos>
   ```
7. **Verify** and show the final ordering grouped by section:
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh list <list-id> 50
   ```

Note: Trello sometimes auto-adjusts pos values (e.g. it picks 12500 instead of 12000). Always verify the *displayed order* afterwards, and only tweak individual cards with smaller position deltas if the order is actually wrong.

## Quantity and naming conventions

- Lead with quantity where helpful: `🥔 1.5kg baby potatoes`, `🍋 7 lemons`
- Use `×` for bottle/unit counts: `🍷 2 × Rioja Crianza`
- Optional items: append ` (optional)`
- Sentence-case the item name (no all-caps, no all-lowercase)
- Fix obvious typos in the user's input but flag the correction (e.g. "Pinot Noi" → "Pinot Noir")

## Pantry-staples check (optional)

Before adding common staples to a list, ask the user whether they already have them - people usually do, and it saves a duplicate buy. Typical staples worth checking: cooking oils, salt, black pepper, common dried herbs and spices, honey, stock cubes, sugar, plain flour, soy sauce, balsamic vinegar, tea bags, tinned tomatoes. State the candidates explicitly and let the user say which to skip. Treat this list as a starting point and adapt it to the user.

## Error recovery

- If `position` returns a different pos than requested (e.g. 12000 → 12500), don't worry - Trello picks a value that fits the gap. Verify with `list` and only fix if the *order* is wrong.
- If a card creation fails, retry once; if it still fails, list it for the user to handle manually.
