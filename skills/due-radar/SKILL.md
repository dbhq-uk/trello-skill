---
name: due-radar
description: Show what is due, overdue, or coming up across your Trello boards, sorted by date. Trigger on phrases like "what's due", "what's overdue", "trello deadlines", "due radar", "what's coming up on trello".
---

# Due Radar - deadlines across your Trello boards

A cross-board triage view: every card with a due date, sorted by when it is due, with overdue items surfaced first. Answers "what needs my attention?" in one command. Built on the `trello` skill in this pack.

## Prerequisites

- Credentials configured in `~/.trello/` (run the trello skill's setup if not done)
- `jq`, `curl` installed

## Usage

```bash
# Across every open board (upcoming window defaults to 14 days)
${CLAUDE_SKILL_DIR}/scripts/due-radar.sh all

# Look further ahead
${CLAUDE_SKILL_DIR}/scripts/due-radar.sh all 30

# One board only
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh find "<board name>"
${CLAUDE_SKILL_DIR}/scripts/due-radar.sh board <board-id> 14
```

All overdue cards are always shown; the day window only limits how far ahead upcoming items reach. Cards already marked complete are excluded.

## Turning the radar into a briefing

1. **Overdue first, in plain terms** - "Three cards are overdue, the oldest by nine days."
2. **Then the near horizon** - what is due today and in the next few days.
3. **Group by board when it helps** - if items span several boards, note where the pressure is concentrated.
4. **Offer to act** - reschedule, mark complete, comment, or move cards via the `trello` skill - only after the user confirms.

## Notes

- "all" scans each open board you can see, so on a very large account it makes one request per board. Use `board <id>` to scope to one board when you only care about that.
- Due dates and completion come straight from Trello; overdue means the due time has passed and the card is not marked complete.
