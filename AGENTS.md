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
skills/life-manager/                # personal board setup, triage and coaching
install.sh / install-codex.sh       # local symlink installers (Claude / Codex)
```

Each skill is `skills/<name>/SKILL.md` plus optional `scripts/` and `references/`.

## Conventions

- Scripts are self-contained: they read credentials from `~/.dbhq/trello/config.json` and have no bundled-path dependencies, so they run from any location.
- The `trello` core skill owns setup and the shared API scripts. Other skills (e.g. `store-sort`) call the core scripts by their `${CLAUDE_SKILL_DIR}/../trello/scripts/...` path - `${CLAUDE_SKILL_DIR}` is the calling skill's own directory, so `../trello` is the sibling core skill (all skills sit side by side under the plugin / `~/.claude/skills/`).
- SKILL.md references scripts via `${CLAUDE_SKILL_DIR}` (the skill's own directory), which Claude Code substitutes for personal, project, and plugin installs alike. `install.sh` therefore symlinks the whole skill directory into `~/.claude/skills/` (no rewrite). `install-codex.sh` still rewrites the variable to the install path, since Codex does not substitute it.
- Shell scripts use `set -e`; errors go to stderr, structured output to stdout.
- Any caller-supplied text sent to the API (card names, descriptions, comments) goes through `curl --data-urlencode`, never plain `-d` - `-d` sends the body raw, so an `&` silently truncates the value and a `+` arrives as a space.
- No secrets in the repo - credentials live under `~/.dbhq/trello/`.
- House style: British English, plain hyphens.

## Adding to the pack

- New skill: add `skills/<name>/SKILL.md` (valid frontmatter, `name` matching the directory). The plugin auto-discovers it.
- New store preset for `store-sort`: copy `skills/store-sort/references/tesco.md`.

## Validating a change

```bash
bash skills/trello/tests/helpers_test.sh   # the test suite - offline, 63 checks
bash -n skills/*/scripts/*.sh              # scripts parse
claude plugin validate .                   # manifest + structure
```

The suite runs offline: a fake `curl` on `PATH` and a fixture `$HOME`, so it
needs no API key, no Trello account and makes no request. CI runs it on every
push. Three things in it are not tidiness and should not be weakened:

- **Every request goes to `https://api.trello.com/1` and nowhere else.** The
  key and token are in the query string of every call, so a request built
  against the wrong host hands a Trello token to that host.
- **Caller text goes out with `--data-urlencode`, never `-d`.** `curl` sends
  `-d` raw: an `&` in a card title truncates the value and a `+` arrives as a
  space.
- **All five scripts carry the `~/.trello` migration, and it is guarded on the
  destination not existing.** Whichever script an agent reaches for first has
  to be the one that migrates. Three of outlook's four entry scripts got this
  wrong on 17 Sep 2026 and settings were left behind.

`render()` in `due-radar.sh`, `days_ago_iso()` and `resolve_config()` are
tested by extracting the real function out of the live script, so renaming one
fails the suite loudly instead of testing a stale copy.
