# Trello API Setup Guide

## Prerequisites

- A Trello account
- `jq` and `curl` installed

## Step 1: Create a Power-Up

1. Go to: https://trello.com/power-ups/admin
2. Click **"New"** to create a new Power-Up
3. Fill in the form:
   - **Name:** "Claude CLI" (or any name you like)
   - **Workspace:** Select any workspace you belong to
   - **Iframe connector URL:** Leave blank
   - **Email:** Your email address
4. Click **Create**

## Step 2: Generate API Key

1. In your new Power-Up, go to the **API Key** tab
2. Click **"Generate a new API Key"**
3. Copy the **API Key** (a 32-character string)

## Step 3: Run Setup and Get the Token

Run `trello-setup.sh` from this skill's `scripts/` directory, in a terminal:

```bash
scripts/trello-setup.sh
```

In Claude Code, type `! ` and then the script's full path at the prompt. The script needs you at a terminal, because you type the key and token yourself. Run by an agent, it changes nothing, prints the command for you to run and exits 3.

The script asks for:

1. **Your API key**, from Step 2.
2. **Access.** Read and write (the default) lets every skill in the pack work. Read only is enough for board-digest and due-radar, and for reading cards; anything that changes a board then fails with HTTP 401.
3. **Expiry.** 1 day, 30 days (the default) or never. An expiring token stops working on its own if the config file goes astray. When it expires, every request answers `invalid token`, and you run setup again.

It then prints a link to Trello's authorize page, with the access and expiry you chose:

```
https://trello.com/1/authorize?expiration=30days&name=trello-skill&scope=read,write&response_type=token&key=<your key>
```

Open it, check the access it asks for, and click **Allow**. Trello shows the token (a 64-character string). Paste it at the prompt: it is not shown as you paste. The script then:
- Validates your credentials
- Saves them to `~/.dbhq/trello/config.json`, readable by you only

> **Note:** Trello has no per-board tokens. Whatever its access, the token reaches **all boards and workspaces** your account can access.

Upgrading from an older install? Settings used to live at `~/.trello`; the scripts move that directory to `~/.dbhq/trello` automatically on first run.

## Step 4: Verify

```bash
scripts/trello-boards.sh boards
```

You should see a list of your Trello boards.

## Manual Configuration

If you prefer to configure manually, get a token from the authorize link in Step 3 with your own key, scope and expiry, then:

```bash
mkdir -p ~/.dbhq/trello
chmod 700 ~/.dbhq ~/.dbhq/trello
cat > ~/.dbhq/trello/config.json << 'EOF'
{
  "api_key": "YOUR_API_KEY_HERE",
  "token": "YOUR_TOKEN_HERE"
}
EOF
chmod 600 ~/.dbhq/trello/config.json
```

## Security Notes

- A read-write token can change anything your Trello account can. A read-only one can read it all
- Keep `~/.dbhq/trello/config.json` secure (permissions should be 600)
- Never commit credentials to version control
- The token works across all workspaces you have access to

## Troubleshooting

### "Invalid credentials" error

- Double-check your API key and token
- Make sure there are no extra spaces or newlines
- The token may have expired: run setup again for a new one

### "Rate limited" error

- Trello allows 300 requests per 10 seconds per API key
- Wait a few seconds and retry

### "Board not found" error

- Use `trello-boards.sh boards` to list all your boards
- Make sure you're using the board ID, not the name
- Check if the board is archived

## Revoking Access

To revoke your token:
1. Go to https://trello.com/power-ups/admin
2. Select your Power-Up
3. Delete or regenerate the API key/token

To completely remove the skill's access:
```bash
rm -rf ~/.dbhq/trello
```
