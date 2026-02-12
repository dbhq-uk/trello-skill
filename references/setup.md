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

## Step 3: Generate Token

1. On the same page, click the **"Token"** hyperlink next to your API key
2. Review the permissions (read/write access to your account)
3. Click **"Allow"** to authorize
4. Copy the **Token** (a 64-character string)

> **Note:** The token grants access to **all boards and workspaces** your account can access.

## Step 4: Run Setup

```bash
~/.claude/skills/trello/scripts/trello-setup.sh
```

Enter your API key and token when prompted. The script will:
- Validate your credentials
- Save them to `~/.trello/config.json`

## Step 5: Verify

```bash
~/.claude/skills/trello/scripts/trello-boards.sh boards
```

You should see a list of your Trello boards.

## Manual Configuration

If you prefer to configure manually:

```bash
mkdir -p ~/.trello
cat > ~/.trello/config.json << 'EOF'
{
  "api_key": "YOUR_API_KEY_HERE",
  "token": "YOUR_TOKEN_HERE"
}
EOF
chmod 600 ~/.trello/config.json
```

## Security Notes

- Your API key and token provide **full access** to your Trello account
- Keep `~/.trello/config.json` secure (permissions should be 600)
- Never commit credentials to version control
- The token works across all workspaces you have access to

## Troubleshooting

### "Invalid credentials" error

- Double-check your API key and token
- Make sure there are no extra spaces or newlines
- Try regenerating the token from the Power-Up admin page

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
rm -rf ~/.trello
```
