---
name: trello
description: Manage Trello boards, lists, and cards. Trigger on phrases like "trello", "my boards", "shopping list", "create card", "move card", "sort cards".
---

# Trello Board Management

Manage Trello boards, lists, and cards via the Trello REST API.

## Core convention - ALWAYS categorise every card

**Every card must carry a category label. No exceptions.** Whenever you create a card, sort/order, or "organise / align" a board, ensure EVERY card on the affected list(s) has a label - not just the top few you reordered. "Order the backlog" or "align with the roadmap" means **categorise the whole list**, then order it - never leave a flat, unlabelled tail.

- Read the board's existing labels first (`GET /1/boards/{boardId}/labels`); reuse them, don't invent a parallel taxonomy. Typical set: Business, Feature, Pipeline, DevOps/Infra, Data, UI/UX, Bug/Fix.
- `trello-cards.sh` only **reads** labels. To **apply** one, call the API directly: `POST https://api.trello.com/1/cards/{cardId}/idLabels?value={labelId}&key=$KEY&token=$TOKEN` (creds in `~/.trello/config.json`).
- When you create a card, label it in the same pass.
- After any board-org task, verify zero unlabelled cards remain on the lists you touched.

## Prerequisites

- Credentials configured in `~/.trello/` (run setup if not done)
- jq, curl installed

## Setup

If not configured, run:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-setup.sh
```

## Board & List Operations

```bash
# List all boards
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-boards.sh boards

# Find board by name
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-boards.sh find "Shopping"

# Get board details
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-boards.sh board <board-id>

# List all lists in a board
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-boards.sh lists <board-id>

# Get list details
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-boards.sh list <list-id>
```

## Card Operations

### Listing Cards

```bash
# List cards in a list
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh list <list-id>

# List more cards
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh list <list-id> 100

# Get JSON output (for scripting/sorting)
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh list-json <list-id>

# Read full card details
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh read <card-id>
```

### Creating & Updating Cards

```bash
# Create a card
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh create <list-id> "Card title" "Optional description"

# Update card field (name, desc, due, closed)
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh update <card-id> name "New title"

# Move card to another list
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh move <card-id> <list-id>
```

### Positioning Cards

```bash
# Move card to top of list
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh top <card-id>

# Move card to bottom of list
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh bottom <card-id>

# Set specific position (number or 'top'/'bottom')
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh position <card-id> 12345
```

### Comments

```bash
# Add comment
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh comment <card-id> "Comment text"

# List comments
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh comments <card-id>
```

### Archive & Delete

```bash
# Archive card
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh archive <card-id>

# Restore archived card
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh unarchive <card-id>

# Delete permanently
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh delete <card-id>
```

### Card Details

```bash
# Show labels
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh labels <card-id>

# Show assigned members
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh members <card-id>

# Show checklists
${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh checklist <card-id>
```

## Workflow: Smart Sorting (e.g., Shopping List by Category)

When user wants to sort cards by category (like food items by store section):

1. Get all cards in the list as JSON:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh list-json <list-id>
   ```

2. Analyze the card names and categorize them (e.g., Produce, Dairy, Meat, Bakery, Frozen, etc.)

3. Propose the new order to the user, grouped by category

4. After approval, update positions for each card:
   ```bash
   # First card gets position 1000
   ${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh position <card-id-1> 1000
   # Second card gets position 2000
   ${CLAUDE_PLUGIN_ROOT}/skills/trello/scripts/trello-cards.sh position <card-id-2> 2000
   # And so on...
   ```

This keeps the original list but reorders cards so same-category items are grouped together.

## Workflow: Adding Items

Always confirm before creating:

1. Parse user's request for: list, card title, optional description
2. Find the appropriate board/list if not specified
3. Show proposed card details to user
4. Create card only after explicit approval

## Error Handling

- **Invalid credentials**: Re-run setup
- **Board/list not found**: Check ID or use find command
- **Rate limited**: Wait a few seconds and retry (300 req/10s per key)

## Notes

- Board/List/Card IDs can be found in Trello URLs or via list commands
- The API key and token provide full access to your Trello account - keep them secret!
- Rate limits: 300 requests per 10 seconds per API key; 100 requests per 10 seconds per token
