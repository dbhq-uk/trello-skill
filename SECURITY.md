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

- Stored at `~/.trello/config.json`
- The file is set to `600` (owner read/write only) immediately after it is
  written
- They are never transmitted anywhere except `api.trello.com`, as query
  parameters, which is the authentication method Trello's API requires

**Revoking access:** the token is yours, issued by Trello. Revoke it at
<https://trello.com/my/account> under connected applications, and this skill
loses access immediately. Deleting `~/.trello/config.json` removes the local
copy but does not revoke the token - do both.

### Scope of access

The token you issue governs what the skill can reach. Trello does not offer
per-board tokens, so a standard token grants access to every board your account
can see. Issue a token for an account that only has the boards you want reachable
if that breadth is a concern.

### On disk

- Installs into `~/.claude/skills/trello` or `~/.codex`, depending on the agent
- Reads and writes `~/.trello/config.json` only

## Known hardening gap

`trello-setup.sh` writes `config.json` and then sets it to `600`. Between those
two operations the file exists at the default umask, typically `644`. On a
single-user machine this is immaterial; on a shared host it is a brief window in
which another local user could read the token. Setting `umask 077` before the
write would close it, and `~/.trello` itself is not set to `700` as
`~/.outlook-graph` is.

Documented rather than quietly fixed, because you should know it before deciding
whether this skill belongs on a shared machine.
