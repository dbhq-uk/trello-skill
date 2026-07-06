<div align="center">

# 📋 Trello for Claude Code

**A pack of Trello skills for Claude Code and Codex - manage boards, sort your shopping, and stay on top of what's due, in plain language**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)](https://code.claude.com/docs/en/plugins)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey)]()

A free, open-source tool by [DBHQ](https://dbhq.uk)

</div>

---

Four Trello skills that work together, all driven in plain language and powered by the Trello REST API.

## The pack

| Skill | What it does |
|-------|--------------|
| 📋 **trello** | Core board, list, and card management - create, move, position, label, comment, archive. Every card gets categorised. |
| 🛒 **store-sort** | Reorders a shopping list into a supermarket's aisle flow with a food-type emoji on every card. Any store via presets; ships a Tesco (UK) preset. |
| 📰 **board-digest** | A plain-English status snapshot of a board - lists and cards, what's due or overdue, and what moved recently. Great for a standup or weekly review. |
| ⏰ **due-radar** | What's due, overdue, or coming up across all your boards, sorted by date, overdue first. |

## Install

### As a Claude Code plugin (recommended)

```
/plugin marketplace add dbhq-uk/marketplace
/plugin install trello@dbhq
```

Then talk to it: *"show my Trello boards"*, *"sort my shopping list into aisle order"*, *"give me a standup for the Roadmap board"*, *"what's due this week?"*.

### Local install (Claude Code or Codex)

```bash
git clone https://github.com/dbhq-uk/trello-skill.git
cd trello-skill
./install.sh          # Claude Code: symlinks into ~/.claude/skills (edits are live)
./install-codex.sh    # Codex: installs into ~/.codex/skills
```

## Setup

Run the trello skill's setup once to add your Trello API key and token:

```bash
scripts/trello-setup.sh    # from skills/trello/
```

You will create a free Trello Power-Up to generate the key and token. They are stored locally in `~/.trello/config.json` (permissions `600`) and never leave your machine. Full walkthrough in [`skills/trello/references/setup.md`](skills/trello/references/setup.md).

## Development

Want to hack on the pack, add a skill, or run it from source with live edits? See [`docs/dev-setup.md`](docs/dev-setup.md).

## Requirements

`jq` · `curl`

## Extending the pack

`store-sort` reads its aisle order from a **preset** in `skills/store-sort/references/`. Copy `tesco.md` to add your own store. The pack is designed to grow - a board templater, quick-capture, and sprint reports are on the roadmap.

## Credentials and privacy

No secrets live in this repository. Your Trello key and token are stored locally under `~/.trello/` and used only to talk to the Trello API directly from your machine. The token grants full access to your account - keep it secret.

## License

[MIT](LICENSE) © 2026 DBHQ Consulting Ltd
