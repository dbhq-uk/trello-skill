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

An API key and token, which you create yourself at Trello and type into
`trello-setup.sh`.

- Setup runs only at a terminal, so the user types the key and token and no
  agent handles them. Run without one, it changes nothing and exits 3
- The token is read with echo off, so it is not left on the screen
- Stored at `~/.dbhq/trello/config.json`
- The file is set to `600` (owner read/write only) immediately after it is
  written
- They are never transmitted anywhere except `api.trello.com`, in an
  `Authorization: OAuth oauth_consumer_key="...", oauth_token="..."` header,
  one of the two methods Trello's API accepts
- That header is fed to `curl` on stdin, so the key and token are never curl
  arguments. Another local user can read any running process's arguments from
  `ps` or `/proc/<pid>/cmdline`, and a token in the URL would be on show there
  for as long as each request runs

**Revoking access:** the token is yours, issued by Trello. Revoke it at
<https://trello.com/my/account> under connected applications, and this skill
loses access immediately. Deleting `~/.dbhq/trello/config.json` removes the local
copy but does not revoke the token - do both.

### Scope of access

The token you issue governs what the skill can reach. Setup prints a link to
Trello's `/1/authorize` page that names the token's scope and expiry, so you
choose both:

- **Read and write** (the default) or **read only**. A read-only token is all
  board-digest and due-radar need, and with it nothing can be changed.
- **1 day, 30 days** (the default) **or never**. An expiring token stops working
  on its own if the config file goes astray.

Trello does not offer per-board tokens, so any token reaches every board your
account can see. Issue a token for an account that only has the boards you want
reachable if that breadth is a concern.

### On disk

- Installs into `~/.claude/skills/trello` or `~/.codex`, depending on the agent
- Reads and writes `~/.dbhq/trello/config.json` only

## Credential write is umask-protected

`trello-setup.sh` sets `umask 077` before writing `config.json` and restores the
previous umask afterwards, so the file never exists - not even briefly - at the
default `644`. It is then `chmod 600`, and `~/.dbhq/trello` is set to `700`.

The file is written by `jq` from values it reads on stdin, so a `"` or `\` in a
value is escaped and the file is always valid JSON, and the key and token are
never `jq` arguments either.

An earlier version chmod'd only after the write, leaving a short window in which
another local user on a shared host could read the token. That window is closed.

The same user could once read the token from the process list, because every
request put it in the URL. Since the header change above, it is not there
either.

## Note on automated scanners

Directory scanners flag the lines of this document and of `SKILL.md` that name
`~/.dbhq/trello/config.json` as "sensitive file access". Those are sentences
describing where the credential lives, not code that reads someone else's.
Documenting the location is deliberate: a credential store you cannot find is
harder to audit, not safer. The path stays.
