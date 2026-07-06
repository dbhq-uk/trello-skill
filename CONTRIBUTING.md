# Contributing

Thanks for your interest - contributions are welcome.

## Ways to help

- Report a bug or request a feature via [issues](https://github.com/dbhq-uk/trello/issues)
- Improve a skill, add a new Trello skill, or add a store preset for `store-sort`, via a pull request

## Local development

```bash
git clone https://github.com/dbhq-uk/trello.git
cd trello
./install.sh          # symlinks all skills into ~/.claude/skills (edits are live)
```

Scripts are symlinked, so edits are live immediately. After editing a `SKILL.md`, re-run `./install.sh` to regenerate the installed copy.

## Before opening a PR

- `bash -n skills/*/scripts/*.sh` - scripts parse cleanly
- `claude plugin validate .` - the plugin validates
- Keep credentials out of the repo and out of commits
- British English, plain hyphens, no trailing full stops on headings

## Licence

By contributing you agree your work is licensed under the [MIT licence](LICENSE).
