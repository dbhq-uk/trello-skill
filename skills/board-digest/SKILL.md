---
name: board-digest
description: Produce a plain-English status digest of a Trello board - lists and their cards, what is due or overdue, and what moved recently. Trigger on phrases like "board status", "trello standup", "what's happening on the board", "board digest", "summarise my board".
---

# Board Digest - a status snapshot of a Trello board

Turns a Trello board into a readable status update: what is in each list, what is due or overdue, and what has moved recently. Ideal for a standup, a weekly review, or catching up after time away. Built on the `trello` skill in this pack.

## Prerequisites

- Credentials configured in `~/.trello/` (run the trello skill's setup if not done)
- `jq`, `curl` installed

## Usage

Resolve the board id if you only have a name, then run the digest:

```bash
# Find the board
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh find "<board name>"

# Status snapshot (recent-activity window defaults to 7 days)
${CLAUDE_SKILL_DIR}/scripts/board-digest.sh digest <board-id>

# Widen the activity window to, say, 14 days
${CLAUDE_SKILL_DIR}/scripts/board-digest.sh digest <board-id> 14
```

The script prints four parts: a header with the open-card count, a per-list breakdown, a due-and-overdue section, and recent activity (created, moved, commented).

## Turning the snapshot into a digest

The script gives you the raw structure. Add value on top:

1. **Lead with the headline** - overdue items and anything due in the next three days come first. If something is overdue, say so plainly.
2. **Summarise, don't just list** - "Backlog is growing (18 cards), three items moved to Done this week, two cards are overdue."
3. **Flag blockers** - cards that have not moved in a long time, or lists that are piling up.
4. **Keep it scannable** - short lines, grouped by list or by theme, no filler.

## Workflow: standup or weekly review

1. Resolve the board id (`trello-boards.sh find`)
2. Run `board-digest.sh digest <board-id> [days]`
3. Write a short digest: headline (due/overdue), what moved, where the pressure is, and one or two suggested next actions
4. Offer to act on any of it (create, move, or comment on cards via the `trello` skill) - but only after the user confirms

## Notes

- Recent activity uses the Trello actions feed, which surfaces card creation, moves between lists, comments, and updates within the chosen window.
- Due-date detection ignores cards already marked complete, and highlights anything due within three days as "due soon".
