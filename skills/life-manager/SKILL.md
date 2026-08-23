---
name: life-manager
description: Set up and run a Trello board that actually gets things done - capture ideas, triage them into a working queue, and coach the user through what has stalled. Three modes - setup, triage, coach. Trigger on phrases like "set up my life board", "help me get stuff done", "sort my inbox", "what should I do next", "I'm stuck", "nothing is moving", "life manager", "manage my todo board".
---

# Life-Manager - a Trello board that gets things done

Most personal Trello boards fail the same way: everything lands in "Today", nothing leaves, and six months later the board is a museum. This skill sets up a board designed against that failure, then keeps it honest.

Three modes, chosen by what the user asks for:

| Mode | They say | You do |
|------|----------|--------|
| **setup** | "set up my life board" | Build the lists, agree their labels, write their config |
| **triage** | "sort my inbox", or they dump a pile of thoughts | Classify, label, break down, place - on approval |
| **coach** | "help me get stuff done", "I'm stuck" | Find the friction, work it one thing at a time |

Built on the `trello` skill in this pack.

## Nothing personal lives in this skill

There are no hardcoded boards, lists, labels, clients or people here, and none may be added. Everything specific to a user lives in **their** config file, in **their** repo.

When you need a board, list or label, resolve it from their config or ask. Never assume. Never write a user's board ID, list ID, label name, client name or contact name into this skill or its references.

## The config file

Personal settings live in a YAML file the user owns. Look for it in this order and use the first that exists:

1. `$LIFE_MANAGER_CONFIG`
2. `./life-manager.yaml`
3. `./system/life-manager.yaml`
4. `~/.trello/life-manager.yaml`

If none exists, you are in **setup** mode - offer to create one.

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
label_order:                    # category order used when sorting a list.
  - Now                         # highest priority first. Entities before
  - Health                      # domains usually reads best, but it is the
  - Finance                     # user's call - this is their ordering, not ours.
label_emoji:                    # optional. stamped on the card title by `sort`,
  Now: 🔥                       # so the category is readable on the board
  Health: ❤️                    # itself, not only through a label filter.
  Finance: 💷                   # omit a label to leave its cards unstamped.
caps:                           # optional. omit or null for no cap
  today: null
  in_progress: null
stale_days:                     # when to call a card out as rotting
  today: 7
  in_progress: 14
  dependant: 21
  next: 60
coaching:
  tone: direct                  # direct | gentle
  max_findings_per_run: 3
```

Write the config with `--data-urlencode`-safe values only, and never commit credentials to it - Trello auth stays in `~/.trello/config.json`.

## Mode 1 - setup

Read `references/default-board.md` first; it explains the structure and, more importantly, *why each list exists*. Do not skip the rationale - a user who does not understand why Inbox is separate from Today will collapse them within a fortnight.

1. **Resolve or create the board.** Ask which board to use, or create one.
   ```bash
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh find "<board name>"
   ${CLAUDE_SKILL_DIR}/../trello/scripts/trello-boards.sh lists <board-id>
   ```
2. **Reuse before you create.** If the board already has lists, map the existing ones onto the preset rather than making duplicates - an empty or near-empty list is almost always the right home for a new role. Renaming beats creating.
3. **Agree the labels.** Ship no domain labels. Ask what the user's life is actually made of, in two tiers:
   - **entity labels** - their clients, employers, ventures, side projects
   - **domain labels** - their life areas
   Plus one priority label. Cap the total at around fifteen; past that, labels stop being a filter.
4. **Set the caps.** Ask whether they want a cap on Today and In Progress. Caps are the main defence against silting, but an unwanted cap gets ignored and then the whole structure loses credibility. `null` means no cap, and that is a legitimate choice.
5. **Write the config** to the path they choose.
6. **Show the finished board** and state the three rules that keep it working (see the preset).

## Mode 2 - triage

For a raw dump, an Inbox with cards in it, or "sort this out for me".

1. **Everything lands in Inbox first.** Never write a new capture straight into Today. If the user dumps ten thoughts, ten cards go to Inbox.
2. **Read every card** before proposing anything - title *and* description. A three-word title routinely hides a paragraph.
3. **Classify each card**: destination list, label(s), and whether the title is comprehensible in six weeks' time. Rewrite cryptic titles; fix spelling.
4. **Break down anything vague.** A card that cannot be started in one sitting is not a task, it is a project - it needs a checklist or it will not move. See "Breaking things down" below.
5. **Show a pre-flight plan** - every card, its destination, its label, and whether it needs action. Then stop.
6. **Apply only on explicit approval.** Nothing moves before that. Never archive without being asked.
7. **Order every list you touched by category** (see below). A list grouped into blocks is scannable; the same cards shuffled are noise.
8. **Verify**: no card left unlabelled, no card left in Inbox.

## Mode 3 - coach

For "help me get stuff done", "I'm stuck", "nothing's moving". Read `references/coaching.md` for the full playbook.

The short version:

1. **Read the board** - every list, card ages, checklist progress.
2. **Find the friction** - not everything that is undone, only what is *stuck*. Stale cards, multi-step cards with no checklist, silted lists, Dependant items nobody has chased, Long Burn cards with no ticks since last time.
3. **Bring at most `max_findings_per_run`.** A list of forty problems is not motivating, it is paralysing. That is how the board got this way.
4. **One thing at a time.** Ask a single question, wait, then the next. Never hand over a numbered list to answer at once.
5. **Convert talk into cards.** Anything decided in the conversation gets written back - a chip ticked, a checklist added, a card moved, a title fixed. A coaching session that changes nothing on the board was a chat.

### Breaking things down

A stalled card is usually not a motivation problem. It is an undefined-next-action problem. "Sort the garage" has no first move; "put the bikes on the wall hooks" does.

When a card has not moved and has no checklist:
- Ask what the *first ten minutes* look like, not what the whole job looks like
- Turn the answer into checklist items on that card
- Make the first chip small enough to be embarrassing

```bash
CL=$(trello-cards.sh checklist-add <card-id> "Chips")
trello-cards.sh checkitem-add "$CL" "<first small step>"
```

### Long-burn cards

Things that matter but can never be finished in a day - health, a business, an estate to put in order - do not belong in a task queue. They rot there, and their rotting teaches the user the board is a lie.

They live as **one parent card each** in the Long Burn list: a description saying what "done" looks like, and a checklist of chips inside. The card never moves. Progress shows as `3/7` on the card front. Order within the list is the user's stated priority.

When coaching, check every Long Burn card for ticks since the last run. One that has not moved in a month is either not a priority or not broken down - say so, and make them pick which.

## Using the rest of the pack

Do not reimplement what already exists:

- **`board-digest`** - status snapshot of a board. Use for the read-the-board step.
- **`due-radar`** - what is due or overdue across boards. Use for deadline pressure.
- **`trello`** - all board, list and card operations, and setup.

```bash
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh list-json <list-id>
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh create <list-id> "Title" "Description"
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh move <card-id> <list-id>
${CLAUDE_SKILL_DIR}/../trello/scripts/trello-cards.sh position <card-id> <pos>
```

Apply a label with `trello-cards.sh`. Label IDs come from
`trello-boards.sh labels <board-id>`:

```bash
trello-cards.sh label-add <card-id> <label-id>
```

The script reads credentials from the config itself, so no key or token ever
reaches the command line, the shell history, or `ps` output.

## Helper script

```bash
${CLAUDE_SKILL_DIR}/scripts/life-board.sh config                 # show the resolved config path and contents
${CLAUDE_SKILL_DIR}/scripts/life-board.sh audit <board-id>       # unlabelled cards, stale cards, list sizes
${CLAUDE_SKILL_DIR}/scripts/life-board.sh stale <list-id> <days> # cards untouched for N days
${CLAUDE_SKILL_DIR}/scripts/life-board.sh sort <list-id> "<order>" [--apply]
```

## Ordering a list by category

A list of thirty ungrouped cards cannot be read. The same thirty grouped into labelled blocks can be scanned in seconds, and the shape of the block tells the user something the cards alone do not - that eight of their open items are one client, or that a whole domain has quietly gone untouched.

Order **by category first, then alphabetically within each category**. Position is priority: top of the list wins.

The category order is the user's, from `label_order` in their config. Pass it in - never assume one, and never hardcode a set of label names into this skill.

```bash
# dry run first - always
${CLAUDE_SKILL_DIR}/scripts/life-board.sh sort <list-id> "Now:🔥,Health:❤️,Finance:💷,Home:🏠"
# then write
${CLAUDE_SKILL_DIR}/scripts/life-board.sh sort <list-id> "Now:🔥,Health:❤️,Finance:💷,Home:🏠" --apply
```

Each entry is `Label` or `Label:emoji`, composed from `label_order` and `label_emoji` in their config. An entry with no emoji leaves its cards' titles alone.

Cards carrying a label that is not in the order sit after those that are; unlabelled cards sink to the bottom, where they stay visible as work still to do rather than hiding in the middle.

### Why stamp the emoji on the title

A label colour is only legible once you already know the scheme, and on a phone it is a thin stripe. An emoji in the title survives every view, every export, and every search - the category travels with the card instead of living in the board's metadata.

The stamp is idempotent: any emoji already leading a title is stripped before the new one goes on, so re-running never doubles up and a recategorised card picks up its new emoji automatically. Only titles that actually change are written. Currency symbols and brackets are left alone - `£500 to pay` keeps its `£`.

Do not invent an emoji set. Ask the user, or offer suggestions they can veto - an emoji that means the wrong thing to them is worse than none, and they will be looking at it every day.

Re-sort a list after any pass that changed labels or moved cards into it - otherwise the grouping silently goes stale and the user stops trusting it.

## Rules that hold in every mode

- **Nothing moves without approval.** Show the plan, wait, then act.
- **Never auto-archive and never delete.** Archiving is reversible; deleting is not. Prefer archive, and ask first.
- **Every card carries a label.** Verify after any pass that none are left bare.
- **One question at a time.** Always.
- **Do not invent a review ritual.** Some people do weekly reviews; most do not, and proposing one to someone who does not is how a system gets abandoned. Ask before assuming a cadence.
- **Say what you cannot decode.** Boards are full of private two-word shorthand that means nothing to you. Ask, do not guess a label onto it.
