# Trello Board Management

Manage Trello boards, lists, and cards from Claude Code via the Trello REST API.

## Features

- List and search boards
- Create, update, move, and archive cards
- Add and view comments
- Reorder cards (top, bottom, or specific position)
- Smart sort: group cards by category (e.g. a shopping list by store aisle)
- View labels, members, and checklists

## Quick Start

### 1. Install Dependencies

```bash
# macOS
brew install jq curl

# Ubuntu/Debian
sudo apt install jq curl
```

### 2. Install the Skill

From the repo root:

```bash
./install.sh trello
```

### 3. Run Setup

```bash
~/.claude/skills/trello/scripts/trello-setup.sh
```

This will:
1. Prompt for your API key and token
2. Validate them against the Trello API
3. Store credentials securely in `~/.trello/config.json`

### 4. Verify

```bash
~/.claude/skills/trello/scripts/trello-boards.sh boards
```

You should see a list of your Trello boards.

## Getting API Credentials

1. Go to [trello.com/power-ups/admin](https://trello.com/power-ups/admin)
2. Click **New** to create a Power-Up (any name, any workspace)
3. Go to the **API Key** tab and generate a key
4. Click the **Token** link next to your key to authorize and get a token

See `references/setup.md` for detailed step-by-step instructions.

## Usage

### Board & List Commands

```bash
# List all boards
~/.claude/skills/trello/scripts/trello-boards.sh boards

# Find board by name (case-insensitive)
~/.claude/skills/trello/scripts/trello-boards.sh find "Shopping"

# Get board details
~/.claude/skills/trello/scripts/trello-boards.sh board <board-id>

# List all lists in a board
~/.claude/skills/trello/scripts/trello-boards.sh lists <board-id>
```

### Card Commands

```bash
# List cards
~/.claude/skills/trello/scripts/trello-cards.sh list <list-id>

# Create card
~/.claude/skills/trello/scripts/trello-cards.sh create <list-id> "Card title" "Optional description"

# Read full card details
~/.claude/skills/trello/scripts/trello-cards.sh read <card-id>

# Update card field
~/.claude/skills/trello/scripts/trello-cards.sh update <card-id> name "New title"

# Move card to another list
~/.claude/skills/trello/scripts/trello-cards.sh move <card-id> <list-id>

# Position
~/.claude/skills/trello/scripts/trello-cards.sh top <card-id>
~/.claude/skills/trello/scripts/trello-cards.sh bottom <card-id>
~/.claude/skills/trello/scripts/trello-cards.sh position <card-id> 12345

# Comments
~/.claude/skills/trello/scripts/trello-cards.sh comment <card-id> "Comment text"
~/.claude/skills/trello/scripts/trello-cards.sh comments <card-id>

# Archive & delete
~/.claude/skills/trello/scripts/trello-cards.sh archive <card-id>
~/.claude/skills/trello/scripts/trello-cards.sh unarchive <card-id>
~/.claude/skills/trello/scripts/trello-cards.sh delete <card-id>

# Details
~/.claude/skills/trello/scripts/trello-cards.sh labels <card-id>
~/.claude/skills/trello/scripts/trello-cards.sh members <card-id>
~/.claude/skills/trello/scripts/trello-cards.sh checklist <card-id>
```

## Natural Language (via Claude)

Once installed, you can use natural language:

| You say | What happens |
|---------|--------------|
| "show my trello boards" | Lists all boards |
| "what's on my shopping list" | Finds and lists cards on the matching board |
| "add milk to shopping list" | Creates a card (with confirmation) |
| "move X to Done" | Moves a card between lists |
| "sort shopping list by aisle" | Smart-sorts cards by category |
| "archive the completed cards" | Archives cards on a list |

## File Structure

```
~/.claude/skills/trello/
├── SKILL.md                    # Skill definition
├── scripts/
│   ├── trello-setup.sh         # One-time credential setup
│   ├── trello-boards.sh        # Board & list operations
│   └── trello-cards.sh         # Card operations
└── references/
    └── setup.md                # Manual setup guide

~/.trello/
└── config.json                 # API credentials (created by setup)
```

## Rate Limits

Trello enforces these limits:
- **300 requests per 10 seconds** per API key
- **100 requests per 10 seconds** per token

In practice this is generous for interactive use. Smart-sort operations on large lists (100+ cards) will stay within limits.

## Troubleshooting

### "Invalid credentials"
- Double-check your API key and token in `~/.trello/config.json`
- Make sure there are no extra spaces or newlines
- Try regenerating the token from [Power-Up admin](https://trello.com/power-ups/admin)

### "Board not found"
- Use `trello-boards.sh boards` to list all visible boards
- Make sure you're using the board ID (from the `[id]` prefix), not the name
- Check if the board is archived

### "Rate limited"
- Wait a few seconds and retry
- Avoid scripting tight loops of API calls

### Re-run setup
```bash
~/.claude/skills/trello/scripts/trello-setup.sh
```

## Security Notes

- Credentials stored with 600 permissions (owner read/write only)
- Your API key and token grant **full access** to your Trello account — keep them secret
- Never commit `~/.trello/` to version control

## Uninstall

```bash
# Remove skill
rm -rf ~/.claude/skills/trello

# Remove credentials
rm -rf ~/.trello
```

To revoke API access, delete the Power-Up at [trello.com/power-ups/admin](https://trello.com/power-ups/admin).
