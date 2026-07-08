# Developer setup - Trello skill pack

Set the pack up from source with a **live symlink install**, so your edits are active immediately in Claude Code (and Codex). End users don't need this - they install via the [DBHQ marketplace](../README.md#install).

## Prerequisites

- `git` (and the GitHub CLI `gh` if you'll push changes)
- `jq` and `curl`

## 1. Clone

```bash
git clone https://github.com/dbhq-uk/trello-skill.git ~/dbhq-trello
cd ~/dbhq-trello
```

## 2. Install (symlink)

```bash
./install.sh          # Claude Code: symlinks all four skills into ~/.claude/skills (edits are live)
./install-codex.sh    # Codex: installs into ~/.codex/skills
```

The committed skills reference their scripts via `${CLAUDE_SKILL_DIR}` (each skill's own directory), which Claude Code substitutes for personal, project and plugin installs alike. So `install.sh` symlinks **each whole skill directory** into `~/.claude/skills/` - `SKILL.md`, `scripts/` and `references/` are all live, and every edit (including `SKILL.md`) takes effect with no re-run. Re-run `install.sh` only when you add a new skill. Codex does not substitute `${CLAUDE_SKILL_DIR}`, so `install-codex.sh` rewrites it to the install path - **re-run `./install-codex.sh` after editing a `SKILL.md`** for Codex.

## 3. Credentials

Complete the setup the installer offers, or run it directly:

```bash
~/.claude/skills/trello/scripts/trello-setup.sh
```

Create a free Trello Power-Up at https://trello.com/power-ups/admin to generate an API key and token. They're stored in `~/.trello/config.json` (permissions `600`), never in the repo. If you've already set this up on another machine, you can copy `~/.trello/` across instead.

## 4. Verify

```bash
~/.claude/skills/trello/scripts/trello-boards.sh boards
```

Then, in Claude Code, try *"show my Trello boards"* or *"what's due this week?"*.

## Adding to the pack

- New skill: add `skills/<name>/SKILL.md` (valid frontmatter, `name` matching the directory) plus optional `scripts/` and `references/`. Re-run `./install.sh`.
- New store preset for `store-sort`: copy `skills/store-sort/references/tesco.md`.

## Working across machines

Editing **anything** under `~/dbhq-trello` (scripts or `SKILL.md`) is live immediately in Claude Code - each skill directory is symlinked whole. For Codex, re-run `./install-codex.sh` after a `SKILL.md` edit. If you develop on more than one machine, `git pull` before you start and `git push` when done to keep them in sync.
