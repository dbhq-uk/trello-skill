# AGENTS.md

Guidance for AI agents (and people) working in this repository.

## What this is

The **Trello** skill pack for AI coding agents - a set of skills for working with Trello via the REST API. It follows the [Agent Skills](https://agentskills.io) layout (`skills/<name>/SKILL.md`) and ships as a [Claude Code plugin](https://code.claude.com/docs/en/plugins).

## Layout

```
.claude-plugin/plugin.json          # plugin manifest (bundles all skills below)
skills/trello/                      # core board/list/card management + setup
skills/store-sort/                  # shopping list into store-aisle order (Tesco preset)
skills/board-digest/                # board status snapshot
skills/due-radar/                   # due/overdue across boards
install.sh / install-codex.sh       # local symlink installers (Claude / Codex)
```

Each skill is `skills/<name>/SKILL.md` plus optional `scripts/` and `references/`.

## Conventions

- Scripts are self-contained: they read credentials from `~/.trello/config.json` and have no bundled-path dependencies, so they run from any location.
- The `trello` core skill owns setup and the shared API scripts. Other skills (e.g. `store-sort`) call the core scripts by their `${CLAUDE_SKILL_DIR}/../trello/scripts/...` path - `${CLAUDE_SKILL_DIR}` is the calling skill's own directory, so `../trello` is the sibling core skill (all skills sit side by side under the plugin / `~/.claude/skills/`).
- SKILL.md references scripts via `${CLAUDE_SKILL_DIR}` (the skill's own directory), which Claude Code substitutes for personal, project, and plugin installs alike. `install.sh` therefore symlinks the whole skill directory into `~/.claude/skills/` (no rewrite). `install-codex.sh` still rewrites the variable to the install path, since Codex does not substitute it.
- Shell scripts use `set -e`; errors go to stderr, structured output to stdout.
- No secrets in the repo - credentials live under `~/.trello/`.
- House style: British English, plain hyphens.

## Adding to the pack

- New skill: add `skills/<name>/SKILL.md` (valid frontmatter, `name` matching the directory). The plugin auto-discovers it.
- New store preset for `store-sort`: copy `skills/store-sort/references/tesco.md`.

## Validating a change

```bash
bash -n skills/*/scripts/*.sh     # scripts parse
claude plugin validate .          # manifest + structure
```
