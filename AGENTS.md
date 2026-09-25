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

- Every script sources `skills/trello/scripts/lib.sh`, found relative to its own path, and makes no request of its own. lib.sh holds config loading, the `~/.trello` migration, the one `api()` call, paging (`api_get_all`), local-time rendering (`trello_jq_defs`, `local_now`) and the shared helpers, so a fix to how a request is made lands once. Scripts in the other skills reach it as `../../trello/scripts/lib.sh` and, when a partial install left `trello` out, stop with a message that names it.
- The `trello` core skill owns setup, lib.sh and the shared API scripts. Other skills (e.g. `store-sort`) call the core scripts by their `${CLAUDE_SKILL_DIR}/../trello/scripts/...` path - `${CLAUDE_SKILL_DIR}` is the calling skill's own directory, so `../trello` is the sibling core skill (all skills sit side by side under the plugin / `~/.claude/skills/`).
- That holds for the plugin and `install.sh`, not for a partial install: the skills CLI lets a user pick single skills. So the README install section and each of the four other SKILL.md files say `trello` must be installed beside them and give the `npx skills add ... --skill trello --skill <name>` command, and every script call in a SKILL.md code block starts at `${CLAUDE_SKILL_DIR}`, never a bare script name. The suite checks both.
- SKILL.md references scripts via `${CLAUDE_SKILL_DIR}` (the skill's own directory), which Claude Code substitutes for personal, project, and plugin installs alike. `install.sh` therefore symlinks the whole skill directory into `~/.claude/skills/` (no rewrite). `install-codex.sh` still rewrites the variable to the install path, since Codex does not substitute it.
- Shell scripts use `set -e`; errors go to stderr, structured output to stdout. `api()` in lib.sh retries an HTTP 429 three times (waiting 2, 4 and 8 seconds), then stops the script on any non-2xx answer with Trello's status and message, because Trello sends its errors as plain text, not JSON. So a verb handles success only, and prints "nothing found" only for a real empty result.
- A request for a long list - a board's cards, its actions, a card's comments, a list's cards - goes through `api_get_all`, never `api_get`. Trello answers at most 1000 results a request and says nothing when it stops; `api_get_all` pages with `before` until a page comes back short, and says "capped at N" on stderr if it has to stop first.
- Every time a script shows goes through `local_time` or `local_date` from `trello_jq_defs`, never `.due[0:10]`: Trello stores UTC, and its first ten characters are the UTC date, which is the wrong day near midnight for anyone not on UTC. The zone is named once per output, from `local_now`, because jq's `%Z` names it wrongly.
- Whether a list is a done list is `is_done_list` in `trello_jq_defs`, and nowhere else. A card in one with its due date not ticked is finished work: due-radar and board-digest name its list and never call it OVERDUE.
- Any caller-supplied text sent to the API (card names, descriptions, comments) goes through `curl --data-urlencode`, never plain `-d` - `-d` sends the body raw, so an `&` silently truncates the value and a `+` arrives as a space.
- No secrets in the repo - credentials live under `~/.dbhq/trello/`.
- `trello-setup.sh` stays interactive. The user types the key and token; with no terminal on stdin it changes nothing, prints the command for the user and exits 3. The token is read with `read -rs`, and config.json is written by `jq` from stdin, so a `"` or `\` stays valid JSON and no credential is ever a process argument. The suite drives it through a real pseudo-terminal to prove all of this.
- House style: British English, plain hyphens.

## Adding to the pack

- New skill: add `skills/<name>/SKILL.md` (valid frontmatter, `name` matching the directory). The plugin auto-discovers it.
- New store preset for `store-sort`: copy `skills/store-sort/references/tesco.md`.

## Validating a change

```bash
bash skills/trello/tests/helpers_test.sh   # the test suite - offline
bash -n skills/*/scripts/*.sh              # scripts parse
claude plugin validate .                   # manifest + structure
```

The suite runs offline: a fake `curl` on `PATH` and a fixture `$HOME`, so it
needs no API key, no Trello account and makes no request. CI runs it on every
push. These things in it are not tidiness and should not be weakened:

- **Every request goes to `https://api.trello.com/1` and nowhere else.** The
  key and token are in the Authorization header of every call, so a request built
  against the wrong host hands a Trello token to that host.
- **The key and token never appear in curl's arguments.** They go in an
  `Authorization: OAuth` header that curl reads from stdin (`-H @-`). Anything
  in argv, a URL included, is readable by every local user through `ps`.
- **Caller text goes out with `--data-urlencode`, never `-d`.** `curl` sends
  `-d` raw: an `&` in a card title truncates the value and a `+` arrives as a
  space.
- **Every entry script runs the `~/.trello` migration, and it is guarded on
  the destination not existing.** It lives in lib.sh and runs when lib.sh is
  sourced, and the suite runs all six entry scripts to prove each one still
  does. Whichever script an agent reaches for first has to be the one that
  migrates. Three of outlook's four entry scripts got this wrong on 17 Sep 2026
  and settings were left behind.
- **No script but lib.sh calls `curl`, loads the config or migrates.** The
  suite greps for it. Six copies of that plumbing is how one error-handling bug
  came to be in about thirty places.

`render()` in `due-radar.sh`, `days_ago_iso()` and `trello_jq_defs()` in
`lib.sh` and `resolve_config()` are tested by extracting the real function out of the live
script, so renaming one fails the suite loudly instead of testing a stale copy.
