---
name: board-digest
description: Produce a plain-English status digest of a Trello board - lists and their cards, what is due or overdue, and what moved recently. Trigger on phrases like "board status", "trello standup", "what's happening on the board", "board digest", "summarise my board".
---

# Board Digest - a status snapshot of a Trello board

Turns a Trello board into a readable status update: what is in each list, what is due or overdue, and what has moved recently. Ideal for a standup, a weekly review, or catching up after time away. Built on the `trello` skill in this pack.

**Needs the `trello` skill installed beside it.** `board-digest.sh` loads `trello`'s shared helpers, and the board lookup and setup ship only in `trello`. The plugin and `install.sh` install both. With the skills CLI, add both by name: `npx skills add dbhq-uk/trello-skill --skill trello --skill board-digest`. If `trello` is missing, the script stops and says so, with the command to add it.

## Prerequisites

- Credentials configured in `~/.dbhq/trello/` (run the trello skill's setup if not done)
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

# Activity window 7 days, call a card idle after 30 days, show up to 25 cards per list
${CLAUDE_SKILL_DIR}/scripts/board-digest.sh digest <board-id> 7 30 25
```

The script prints five parts: a header with the open-card count, a per-list breakdown, a due-and-overdue section, the cards that have not moved, and recent activity (created, moved, commented).

- **Each list shows its first 10 cards** in board order, then a line such as `+ 8 more (trello-cards.sh list <list-id> 18 shows them all)`. The count in the list's heading is always the full count. Pass a larger `limit` (the fourth number) to see more, or run the `trello-cards.sh list` call the line gives.
- **"Not moved in 14 days or more"** lists the cards with no activity for that long, oldest first, with how many days and the list each is on, up to the same limit. Change the 14 with the third number. Cards in a done list are left out, because they are finished.

## Turning the snapshot into a digest

The script gives you the raw structure. Add value on top:

1. **Lead with the headline** - overdue items and anything due in the next three days come first. If something is overdue, say so plainly.
2. **Summarise, don't just list** - "Backlog is growing (18 cards), three items moved to Done this week, two cards are overdue."
3. **Flag blockers** - the cards in "Not moved", and lists that are piling up. Name the oldest few rather than all of them.
4. **Keep it scannable** - short lines, grouped by list or by theme, no filler.

## Workflow: standup or weekly review

1. Resolve the board id (`trello-boards.sh find`)
2. Run `board-digest.sh digest <board-id> [days] [idle-days] [limit]`
3. Write a short digest: headline (due/overdue), what moved, where the pressure is, and one or two suggested next actions
4. Offer to act on any of it (create, move, or comment on cards via the `trello` skill) - but only after the user confirms

## Notes

- Recent activity uses the Trello actions feed, which surfaces card creation, moves between lists, comments, and updates within the chosen window. Every action in the window is fetched, page by page; if it was ever cut short, stderr says "capped at N" and the digest must say it is partial.
- Due-date detection ignores cards already marked complete, and highlights anything due within three days as "due soon". Each row names the card's list in brackets.
- A card in a done list (Done, Complete, Completed or Finished, or a name in `TRELLO_DONE_LISTS`) whose due date was never ticked is shown as "in Done, due not ticked", not OVERDUE. It is finished work: do not report it as overdue.
- Every time is shown in the user's local time zone, which the header names.
- "Not moved" uses Trello's last-activity date for each card. Any change to a card counts, so a card that was only renamed or re-sorted counts as moved. On a life-manager board, `life-board.sh stale` ignores those changes.
