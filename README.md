<div align="center">

<img src="assets/logo.svg" alt="trello skill pack for Claude Code, by DBHQ" width="560">

# trello

**A pack of Trello skills for Claude Code and Codex - manage boards, sort your shopping, and stay on top of what's due, in plain language**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)](https://code.claude.com/docs/en/plugins)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey)]()

A free, open-source tool by [DBHQ](https://dbhq.uk) - documented at [skills.dbhq.uk](https://skills.dbhq.uk/trello/)

</div>

---

Five Trello skills that work together, all driven in plain language and powered by the Trello REST API.

## The pack

| Skill | What it does |
|-------|--------------|
| 📋 **trello** | Core board, list, and card management - create, move, position, label, comment, archive. Every card gets categorised. |
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

`jq` and `curl`, which is the whole of it - these are bash skills against
the Trello REST API.

A Trello API key and token, kept in `~/.dbhq/trello/config.json` at mode
600. `trello-setup.sh` walks you through getting them.

## Setup

Run the trello skill's setup once to add your Trello API key and token:

```bash
scripts/trello-setup.sh    # from skills/trello/
```

You will create a free Trello Power-Up to generate the key and token. They are stored locally in `~/.dbhq/trello/config.json` (permissions `600`) and never leave your machine. Full walkthrough in [`skills/trello/references/setup.md`](skills/trello/references/setup.md).

## Development

Want to hack on the pack, add a skill, or run it from source with live edits? See [`docs/dev-setup.md`](docs/dev-setup.md).

## Extending the pack

`store-sort` reads its aisle order from a **preset** in `skills/store-sort/references/`. Copy `tesco.md` to add your own store. The pack is designed to grow - a board templater, quick-capture, and sprint reports are on the roadmap.

## Credentials and privacy

No secrets live in this repository. Your Trello key and token are stored locally under `~/.dbhq/trello/` and used only to talk to the Trello API directly from your machine. The token grants full access to your account - keep it secret.

## Also from DBHQ

Fifteen free agent skills, all of them installable from the same marketplace and
all documented at **[skills.dbhq.uk](https://skills.dbhq.uk)**.

| Skill | What it does |
|---|---|
| [outlook](https://skills.dbhq.uk/outlook/) | Microsoft 365 mail and calendar, from the terminal |
| [legwork](https://skills.dbhq.uk/legwork/) | Research that settles a decision, and says when it cannot |
| [dovetail](https://skills.dbhq.uk/dovetail/) | Checks whether your repository still agrees with itself |
| [verve](https://skills.dbhq.uk/verve/) | Strips AI tells from prose and puts a voice back |
| [vela](https://skills.dbhq.uk/vela/) | Compiler-exact code search, in any language you index |
| [garmin](https://skills.dbhq.uk/garmin/) | Your Garmin data, answered in the terminal |
| [imager](https://skills.dbhq.uk/imager/) | Images from GPT Image 2, costed before it spends |
| [gitview](https://skills.dbhq.uk/gitview/) | Which branches are finished, and safe to delete |
| [atlassian](https://skills.dbhq.uk/atlassian/) | Jira issues and Confluence pages |
| [pennyblack](https://skills.dbhq.uk/pennyblack/) | A physical letter, posted from the terminal |
| [buildwork](https://skills.dbhq.uk/buildwork/) | Your open issues, run as parallel agents |
| [deskwork](https://skills.dbhq.uk/deskwork/) | What an agent noticed, tracked as real work |
| [groupwork](https://skills.dbhq.uk/groupwork/) | A second agent on the work, adversary or partner |

Plus [heliograph](https://skills.dbhq.uk/heliograph/), for a machine you cannot log into.

## Licence

[MIT](LICENSE) © 2026 DBHQ Consulting Ltd
