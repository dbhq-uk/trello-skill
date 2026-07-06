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

The committed skills are plugin-native (script paths use `${CLAUDE_PLUGIN_ROOT}`). The installers symlink each skill's `scripts/` into your skills folder and generate `SKILL.md` with those paths rewritten for a non-plugin install. Scripts are live-linked; **after editing a `SKILL.md`, re-run `./install.sh`** to regenerate the installed copy.

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

Editing a **script** under `~/dbhq-trello` is live immediately. After editing a **`SKILL.md`**, re-run `./install.sh`. If you develop on more than one machine, `git pull` before you start and `git push` when done to keep them in sync.
