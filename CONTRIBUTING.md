# Contributing

Thanks for your interest - contributions are welcome.

## Ways to help

- Report a bug or request a feature via [issues](https://github.com/dbhq-uk/trello-skill/issues)
- Improve a skill, add a new Trello skill, or add a store preset for `store-sort`, via a pull request

## Local development

```bash
git clone https://github.com/dbhq-uk/trello-skill.git
cd trello-skill
./install.sh          # symlinks all five skills into ~/.claude/skills (edits are live)
```

Each skill directory is symlinked whole, so every edit, `SKILL.md` included, is live at once. Re-run `./install.sh` only when you add a skill. For Codex, re-run `./install-codex.sh` after editing a `SKILL.md`. More in [`docs/dev-setup.md`](docs/dev-setup.md).

## Before opening a PR

- `bash skills/trello/tests/helpers_test.sh` - the test suite passes. It runs offline, with a fake `curl`, and needs no Trello account
- `bash -n skills/*/scripts/*.sh` - scripts parse cleanly
- `find . -name '*.sh' -print0 | xargs -0 shellcheck -S warning` - no shellcheck warnings
- `claude plugin validate .` - the plugin validates
- Keep credentials out of the repo and out of commits
- British English, plain hyphens, no trailing full stops on headings

## Licence

By contributing you agree your work is licensed under the [MIT licence](LICENSE).
