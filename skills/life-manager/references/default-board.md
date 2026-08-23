# The default board preset

The structure `life-manager` builds at setup. It is a **preset**, not a law - a user can drop or rename lists. But each list earns its place, and the rationale matters more than the layout. Explain the *why* at setup; a user who does not understand why Inbox is separate from Today will merge them within a fortnight and be back where they started.

## The lists, left to right

| # | List | What belongs in it |
|---|------|--------------------|
| 1 | 🐢 Long Burn | Things that matter and can never be finished in a day. One parent card each, checklist inside. Ordered by priority. |
| 2 | 📥 Inbox | Every new capture. Nothing else. |
| 3 | 🔥 Today | Chosen for today. Not yet started. |
| 4 | ⚡ In Progress | Actually started. |
| 5 | ⏸ Dependant | Blocked on another human. Not the user's move. |
| 6 | ⏭ Next | The on-deck queue, ordered. |
| 7 | 📋 Backlog | Everything else that is real. Labelled and grouped. |
| 8 | ✅ Done | Completed, swept to archive periodically. |
| 9 | 📚 Useful Knowledge | Reference. Things you look up, not things you do. Nothing here is ever "done". |
| 10 | 💡 Ideas & Reading | Books, links, half-thoughts. Not a queue. |
| 11 | 🎁 Gift Ideas | Present ideas as they occur, for whenever they are needed. |

Lists 9-11 are reference, not workflow. Park them on the right, out of the working path. A user with no interest in a reading list should not be given one.

## Why each design choice exists

**Inbox is separate from Today.** This is the single most important list. When capture lands directly in the working queue, the queue stops meaning anything - it becomes a dumping ground wearing the word "Today". An Inbox costs one extra move and preserves the meaning of every list downstream.

**Today and In Progress are different lists.** "Chosen" and "started" are different states, and collapsing them hides the most useful signal on the board: how many things are genuinely open at once.

**Dependant is not a parking bay.** It is specifically *blocked on another human*. If it is waiting on the user, it is not Dependant, it is avoided - and that distinction is exactly what a coaching pass needs to see. A Dependant card nobody has chased in three weeks is not blocked, it is abandoned.

**Three horizons, not four.** Today / Next / Backlog. Adding a fourth ("this week", "this month") multiplies the re-sorting a user must do to keep the board true, and re-sorting is the first thing to be dropped.

**Long Burn exists because task queues kill long-term work.** A queue rewards things that can be finished. Anything that cannot - fitness, a business, an estate to put in order - sinks to the bottom and rots, which quietly teaches the user that the board lies. Giving those things their own list, with progress visible as `3/7` on the card front, is how they stay alive without competing against a five-minute errand.

**Useful Knowledge exists because reference is not work.** A card holding an account number or a car's fault history is not a task and will never be "done". Left in a queue it reads as a permanent, unfinishable failure. Given its own list, it is just a fact you can find.

## Caps

Caps on Today and In Progress are the main defence against silting. Typical values are five and three.

**But an unwanted cap is worse than no cap.** A user who ignores a cap learns to ignore the structure, and then nothing in it has authority. Ask. `null` is a legitimate answer, and if they choose it, say plainly what they are giving up - the cap is what stops Today becoming a second backlog - and then respect the decision without relitigating it.

## Labels

Ship **no** default domain labels. What a person's life is made of is not guessable, and a wrong label set is worse than none - it teaches them the categories do not fit.

Ask for them in three tiers:

1. **Priority** - one label, for genuinely-now work. One is enough; a three-tier ladder needs constant regrading and rots.
2. **Entity** - their clients, employers, ventures, side projects. These are usually the most useful filters for anyone who works for themselves.
3. **Domain** - their life areas. Health, money, home, family, and whatever else is actually true for them.

Guidance worth passing on:

- **Cap the set at about fifteen.** Past that, labels stop being a filter and become decoration.
- **A label on most cards is not a label.** If something ends up on 40% of the board it carries no information and should be split or dropped.
- **Entity labels usually make domain equivalents redundant.** If someone has labels for each of their clients, a generic "Work" label adds nothing.
- **Retire labels that have stopped meaning anything**, but ask first - an unused label sometimes marks something dormant rather than dead.

## The three rules to state at setup

1. **Capture goes to Inbox, never to Today.** Today is chosen, not dumped.
2. **Dependant means waiting on a person.** Waiting on yourself is not blocked.
3. **Every card carries a label.** No exceptions - an unlabelled card is invisible to every filter you will ever use.

## Ordering within a list

Position is priority: top of the list wins.

**Group by category first, then order alphabetically within the group.** A list of thirty ungrouped cards cannot be read - the eye has nowhere to land, so the user skims it, sees nothing, and closes the tab. The same thirty in labelled blocks can be scanned in seconds.

Grouping also surfaces things no individual card does: that eight open items belong to one client, that a domain has gone untouched for months, that "miscellaneous" has quietly become the largest block on the board. Those are the observations a coaching pass is built on, and they are invisible in an unsorted list.

The category order belongs to the user and lives in `label_order` in their config. Entities before domains usually reads best for someone who works for themselves, but it is their call, not the skill's.

```bash
# entries are "Label" or "Label:emoji", from label_order + label_emoji in config
${CLAUDE_SKILL_DIR}/scripts/life-board.sh sort <list-id> "Now:🔥,Health:❤️,Home:🏠"
${CLAUDE_SKILL_DIR}/scripts/life-board.sh sort <list-id> "Now:🔥,Health:❤️,Home:🏠" --apply
```

An emoji per category, stamped on the card title, makes the grouping legible in every view - including on a phone, where a label colour is a thin stripe and nothing else. Ask the user for their emoji rather than choosing for them; they will see it every day.

Unlabelled cards sink to the bottom deliberately. They are not finished work, they are undone categorisation, and burying them mid-list hides that.

Re-sort after any pass that changed labels or moved cards in. Grouping that has gone stale is worse than none - it looks authoritative and is not.

Due dates are for **real external deadlines only** - a court date, a filing deadline, a booked event. Inventing dates to force urgency breeds alarm fatigue, and once a user starts ignoring red dates they ignore the real ones too.
