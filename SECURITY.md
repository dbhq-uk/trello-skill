# Security

## Reporting a vulnerability

Email <dan@dbhq.uk> rather than opening a public issue. Include what you found,
how to reproduce it, and what an attacker could do with it. You will get a first
response within 48 hours.

## What this skill does

The skill talks to your Trello account over Trello's public REST API. It holds a
credential, so this section matters.

### Network

**One host: `api.trello.com`.** Every request goes there and nowhere else. There
is no DBHQ server in the path, no proxy, and no telemetry - your board data goes
between your machine and Trello directly.

### Credentials

An API key and token, which you create yourself at Trello and paste into
`trello-setup.sh`.

- Stored at `~/.dbhq/trello/config.json`
- The file is set to `600` (owner read/write only) immediately after it is
  written
- They are never transmitted anywhere except `api.trello.com`, as query
  parameters, which is the authentication method Trello's API requires

**Revoking access:** the token is yours, issued by Trello. Revoke it at
<https://trello.com/my/account> under connected applications, and this skill
loses access immediately. Deleting `~/.dbhq/trello/config.json` removes the local
copy but does not revoke the token - do both.

### Scope of access

The token you issue governs what the skill can reach. Trello does not offer
per-board tokens, so a standard token grants access to every board your account
can see. Issue a token for an account that only has the boards you want reachable
if that breadth is a concern.

### On disk

- Installs into `~/.claude/skills/trello` or `~/.codex`, depending on the agent
- Reads and writes `~/.dbhq/trello/config.json` only

## Credential write is umask-protected

`trello-setup.sh` sets `umask 077` before writing `config.json` and restores the
previous umask afterwards, so the file never exists - not even briefly - at the
default `644`. It is then `chmod 600`, and `~/.dbhq/trello` is set to `700`.

An earlier version chmod'd only after the write, leaving a short window in which
another local user on a shared host could read the token. That window is closed.

## Note on automated scanners

Directory scanners flag the lines of this document and of `SKILL.md` that name
`~/.dbhq/trello/config.json` as "sensitive file access". Those are sentences
describing where the credential lives, not code that reads someone else's.
Documenting the location is deliberate: a credential store you cannot find is
harder to audit, not safer. The path stays.
