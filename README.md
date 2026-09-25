<div align="center">

<img src="assets/logo.svg" alt="trello skill pack for Claude Code, by DBHQ" width="560">

# trello

**Five Trello skills for Claude Code and Codex: trello manages boards, lists and cards, store-sort puts a shopping list in aisle order, board-digest summarises a board, due-radar shows what is due across boards, and life-manager runs a personal board that gets things done.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)](https://code.claude.com/docs/en/plugins)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey)]()

A free, open-source tool by [DBHQ](https://dbhq.uk) - documented at [skills.dbhq.uk](https://skills.dbhq.uk/trello/)

</div>

---

All five are driven in plain language, over the Trello REST API with your own key.

## The pack

| Skill | What it does |
|-------|--------------|
| 📋 **trello** | Core board, list and card management - create, move, position, label, comment, archive - and the setup the other four use. |
| 🛒 **store-sort** | Reorders a shopping list into a supermarket's aisle flow with a food-type emoji on every card. Any store via presets; ships a Tesco (UK) preset. |
| 📰 **board-digest** | A plain-English status snapshot of a board - lists and cards, what's due or overdue, and what moved recently. Great for a standup or weekly review. |
| ⏰ **due-radar** | What's due, overdue, or coming up across all your boards, sorted by date, overdue first. |
| 🎯 **life-manager** | Sets up a personal board built to resist rotting, triages whatever you dump into it, and coaches you through what has stalled. Three modes - setup, triage, coach. |

## Install

### As a Claude Code plugin (recommended)

```
/plugin marketplace add dbhq-uk/marketplace
/plugin install trello@dbhq
```

### Any agent (Cursor, Copilot, Windsurf, Gemini, Cline and more)

```bash
npx skills add dbhq-uk/trello-skill
```

The [skills.sh](https://skills.sh) CLI installs into whichever agent directories
it finds, so this works outside Claude Code and Codex too.

**`trello` is the core, and the other four need it.** It holds setup and the
shared helpers and scripts that store-sort, board-digest, due-radar and life-manager use, so
each of those four must have `trello` installed beside it. The command above
installs all five. If you pick single skills, add `trello` with them:

```bash
npx skills add dbhq-uk/trello-skill --skill trello --skill due-radar
```

A script whose `trello` is missing stops and says so, with the command to add it.

### Local install (Claude Code or Codex)

```bash
git clone https://github.com/dbhq-uk/trello-skill.git
cd trello-skill
./install.sh          # Claude Code: symlinks into ~/.claude/skills (edits are live)
./install-codex.sh    # Codex: installs into ~/.codex/skills
```

[`install.sh`](install.sh) and [`install-codex.sh`](install-codex.sh) are the
same install two ways: Claude Code substitutes `${CLAUDE_SKILL_DIR}`, so the
whole skill directory is symlinked untouched, while Codex does not, so its
`SKILL.md` is rewritten at install time. Re-run the Codex one after editing
`SKILL.md`.

## Requirements

`jq` and `curl` (7.55 or later, which reads a header from stdin), which is
the whole of it - these are bash skills against the Trello REST API.

A Trello API key and token, kept in `~/.dbhq/trello/config.json` at mode
600. `trello-setup.sh` walks you through getting them.

## Setup

Run the trello skill's setup once to add your Trello API key and token:

```bash
scripts/trello-setup.sh    # from skills/trello/
```

Run it in a terminal, or with `! ` at the Claude Code prompt: you type the key and token yourself, so an agent cannot run it for you. You create a free Trello Power-Up for the key. Setup then prints a link that issues the token, read and write or read only, expiring after 1 day, 30 days or never. They are stored locally in `~/.dbhq/trello/config.json` (permissions `600`) and never leave your machine. Full walkthrough in [`skills/trello/references/setup.md`](skills/trello/references/setup.md).

## Development

Want to hack on the pack, add a skill, or run it from source with live edits? See [`docs/dev-setup.md`](docs/dev-setup.md).

## Extending the pack

`store-sort` reads its aisle order from a **preset**, a JSON file in `skills/store-sort/references/stores/`. To add your own store, copy `tesco.json` to `~/.dbhq/trello/stores/<store>.json` and change it.

## Credentials and privacy

No secrets live in this repository. Your Trello key and token are stored locally under `~/.dbhq/trello/` and used only to talk to the Trello API directly from your machine. A read-write token can change anything your account can - keep it secret, or choose a read-only token at setup.

## Also from DBHQ

Every DBHQ agent skill is free, open source and installable from the same
marketplace, and all of them are documented at
**[skills.dbhq.uk](https://skills.dbhq.uk)**. The marketplace itself is
[dbhq-uk/marketplace](https://github.com/dbhq-uk/marketplace) - one
`/plugin marketplace add` and every one of them is available.

| Skill | What it does |
|---|---|
| [outlook](https://skills.dbhq.uk/outlook/) | Microsoft 365 mail and calendar, from the terminal |
| [legwork](https://skills.dbhq.uk/legwork/) | Research that settles a decision, and says when it cannot |
| [dovetail](https://skills.dbhq.uk/dovetail/) | Checks whether your repository still agrees with itself |
| [verve](https://skills.dbhq.uk/verve/) | Strips AI tells from prose and puts a voice back |
| [vela](https://skills.dbhq.uk/vela/) | Compiler-exact code search, in any language you index |
| [garmin](https://skills.dbhq.uk/garmin/) | Your Garmin data, answered in the terminal |
| [imager](https://skills.dbhq.uk/imager/) | Images from OpenAI, costed before it spends |
| [gitview](https://skills.dbhq.uk/gitview/) | Which branches are finished, and which only look like it |
| [atlassian](https://skills.dbhq.uk/atlassian/) | It edits a real page without losing what it does not understand |
| [pennyblack](https://skills.dbhq.uk/pennyblack/) | A physical letter, posted from the terminal |
| [buildwork](https://skills.dbhq.uk/buildwork/) | Your open issues, run as parallel agents |
| [deskwork](https://skills.dbhq.uk/deskwork/) | What an agent noticed, tracked as real work |
| [groupwork](https://skills.dbhq.uk/groupwork/) | A second agent on the work, and a result you can cite |
| [headwork](https://skills.dbhq.uk/headwork/) | One decision at a time, with a recommendation |

Plus [heliograph](https://skills.dbhq.uk/heliograph/), for a machine you cannot log into.

## Licence

[MIT](LICENSE) © 2026 DBHQ Consulting Ltd
