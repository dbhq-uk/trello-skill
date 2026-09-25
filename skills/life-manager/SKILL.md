---
name: life-manager
description: Set up and run a Trello board that actually gets things done - capture ideas, triage them into a working queue, and coach the user through what has stalled on it. Three modes - setup, triage, coach. Trigger on phrases like "set up my life board", "triage my trello inbox", "what should I do next on my board", "nothing is moving on my board", "help me get my board moving", "life manager", "manage my todo board". Not for general decisions or planning that does not involve a Trello board.
---

# life-manager - a Trello board that gets things done

Most personal Trello boards fail the same way: everything lands in "Today", nothing leaves, and six months later the board is a museum. This skill sets up a board built against that failure, then keeps it honest. Three modes:

| Mode | They say | You do |
|------|----------|--------|
| **setup** | "set up my life board" | Build the lists, agree their labels, write their config |
| **triage** | "triage my Trello inbox", or they dump a pile of thoughts | Classify, label, break down, place - on approval |
| **coach** | "nothing is moving on my board", "what should I do next on my board" | Find the friction, work it one thing at a time |

**Needs the `trello` skill installed beside it.** `life-board.sh` loads `trello`'s shared helpers, and every card and board call below is a `trello` script. The plugin and `install.sh` install both. With the skills CLI, add both by name: `npx skills add dbhq-uk/trello-skill --skill trello --skill life-manager`.

## Nothing personal lives in this skill

No board, list, label, client or person is written into this skill, and none may be added. Take them from the user's config file, or ask.

## The config file

Personal settings live in a YAML file the user owns. The first of these that exists is used:

1. `$LIFE_MANAGER_CONFIG`
2. `./life-manager.yaml`
3. `~/.dbhq/trello/life-manager.yaml`

`life-board.sh config` shows which one it found. If there is none, you are in **setup** mode - offer to create one.

```yaml
board_id: <trello board id>
lists:                          # list name -> list id, as agreed at setup
  long_burn: <id>
  inbox: <id>
  today: <id>
  in_progress: <id>
  dependant: <id>
  next: <id>
  backlog: <id>
  done: <id>
labels:                         # label name -> label id
  Health: <id>
label_order:                    # category order for sort, highest priority first.
  - Now                         # the user's order, not ours
  - Health
  - Finance
label_emoji:                    # optional. stamped on card titles by sort;
  Now: 🔥                       # leave a label out to leave its cards unstamped
  Health: ❤️
  Finance: 💷
caps:                           # optional. null for no cap
  today: null
  in_progress: null
stale_days:                     # days without activity before a card is called out
  today: 7
  in_progress: 14
  dependant: 21
  next: 60
  long_burn: 30
coaching:
  tone: direct                  # direct | gentle
  max_findings_per_run: 3
```

Quote any value that contains `: ` or ` #`, so the file stays valid YAML. Never put credentials in it - Trello auth stays in `~/.dbhq/trello/config.json`.

## Mode 1 - setup

Read `references/default-board.md` first. It gives the lists and why each exists. Pass the why on: a user who does not see why Inbox is separate from Today merges them within a fortnight.

1. **Resolve or create the board.** Ask which board to use, or create one.
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh find "<board name>"
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh board-create "<board name>"
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh lists <board-id>
   ```
2. **Reuse before you create.** Map existing lists onto the preset, and rename before you add. A new board comes with Trello's starter lists: rename those. `list-create` adds at the bottom, or at the top with `top`.
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh list-rename <list-id> "<preset list name>"
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh list-create <board-id> "<preset list name>"
   ```
3. **Agree the labels.** Ship none. Ask for one priority label, then entity labels (clients, employers, ventures) and domain labels (life areas), about fifteen in all. Reuse the board's own, then create the rest.
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh labels <board-id>
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh label-create <board-id> "<label name>" [colour]
   ```
4. **Set the caps.** Ask whether they want a cap on Today and In Progress. `null` is a legitimate answer.
5. **Write the config** to the path they choose.
6. **Show the finished board** and state the three rules in the preset.

## Mode 2 - triage

For a raw dump, an Inbox with cards in it, or "sort this out for me".

1. **Everything lands in Inbox first.** Never write a new capture straight into Today. If the user dumps ten thoughts, ten cards go to Inbox.
2. **Read every card**, title *and* description, before proposing anything.
3. **Classify each card**: destination list, label, and whether the title will make sense in six weeks. Rewrite cryptic titles.
4. **Break down anything vague.** A card that cannot be started in one sitting is a project and needs a checklist (see "Breaking a card down").
5. **Show a pre-flight plan** - every card, its destination and its label. Then stop, and apply only on explicit approval.
6. **Order every list you touched by category** (see below).
7. **Verify**: no card left unlabelled, no card left in Inbox.

## Mode 3 - coach

For a board that has stalled. Read `references/coaching.md` first: it lists the signals of friction and how to run the conversation.

1. **Read the board** with board-digest. For each list with a threshold in `stale_days`, run `life-board.sh stale <list-id> <days>`: unlike the digest, it ignores a rename or a re-sort.
2. **Find the friction** - only what is stuck, not everything undone.
3. **Bring at most `max_findings_per_run`**, one question at a time.
4. **Write the result back.** A session that changes nothing on the board was a chat. To tick a chip, get the item id from the card's checklists:
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh checklist <card-id>
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh checkitem-done <card-id> <item-id>
   ```

**Long Burn cards** never change list, so their signal is activity: `stale` on the Long Burn list with `stale_days.long_burn` finds the cards nobody has ticked, commented on or edited in that time. Such a card is either not a priority or not broken down. Let the user pick which.

### Breaking a card down

A stuck card with no checklist is usually a project. Ask what the first ten minutes look like, write the answer as checklist items, and make the first one small.

```bash
CL=$(${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh checklist-add <card-id> "Chips")
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh checkitem-add "$CL" "<first small step>"
```

## Using the rest of the pack

- **`board-digest`** - a status snapshot of a board, for the read-the-board step.
- **`due-radar`** - what is due or overdue across boards.
- **`trello`** - every board, list and card operation, and setup. Every write this skill asks for has a verb there. Never write a request of your own: the scripts keep the key and token off the command line.

```bash
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh list-json <list-id>
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh create <list-id> "Title" "Description"
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh move <card-id> <list-id>
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh labels <board-id>
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh label-add <card-id> <label-id>
```

## Helper script

```bash
${CLAUDE_SKILL_DIR}/scripts/life-board.sh config                 # the config path it found, and its contents
${CLAUDE_SKILL_DIR}/scripts/life-board.sh audit <board-id>       # list sizes, unlabelled cards, and up to 40 cards with no checklist and no description
${CLAUDE_SKILL_DIR}/scripts/life-board.sh stale <list-id> <days> # cards untouched for N days - a rename or a move does not count
${CLAUDE_SKILL_DIR}/scripts/life-board.sh sort <list-id> "<order>" [--apply]
```

`audit` does not look for stale cards: run `stale` on each list with its threshold from `stale_days`.

## Ordering a list by category

Order a list by category, then alphabetically. Top is highest priority. The order is the user's `label_order`, with emoji from `label_emoji`: never assume one. `references/default-board.md` says why grouping and the emoji stamp work.

```bash
# dry run first - always
${CLAUDE_SKILL_DIR}/scripts/life-board.sh sort <list-id> "Now:🔥,Health:❤️,Finance:💷,Home:🏠"
# then write
${CLAUDE_SKILL_DIR}/scripts/life-board.sh sort <list-id> "Now:🔥,Health:❤️,Finance:💷,Home:🏠" --apply
```

- Each entry is `Label` or `Label:emoji`. A card sorts by its highest-ranked label. Cards with other labels come next, and unlabelled cards sink to the bottom.
- An entry's emoji replaces any emoji at the front of the title, so a re-run never doubles it. Symbols such as `£`, `©` and `°` stay. A card whose entry has no emoji, or that has no label in the order, keeps its title byte for byte.
- `--apply` writes only what must change; a sorted list gets no write. The first write Trello refuses stops the run, names the card and says the list is only partly sorted. Fix the cause and run `--apply` again.
- Do not invent an emoji set. Ask, or offer suggestions the user can veto.
- Re-sort a list after any pass that changed labels or moved cards into it.

## Rules that hold in every mode

- **Nothing moves without approval.** Show the plan, wait, then act.
- **Never auto-archive and never delete.** Archiving is reversible; deleting is not. Prefer archive, and ask first.
- **Every card carries a label.** Verify after any pass that none are left bare.
- **One question at a time.** Always.
- **Do not invent a review ritual.** Ask before assuming a cadence.
- **Say what you cannot decode.** Ask about private shorthand; do not guess a label onto it.
