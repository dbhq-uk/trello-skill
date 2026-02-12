#!/bin/bash
# Trello Setup - Configure API credentials

set -e

CONFIG_DIR="$HOME/.trello"
CONFIG_FILE="$CONFIG_DIR/config.json"

echo "=== Trello API Setup ==="
echo
echo "You'll need an API Key and Token from a Trello Power-Up."
echo
echo "If you don't have these yet:"
echo "1. Go to: https://trello.com/power-ups/admin"
echo "2. Create a new Power-Up (any name, any workspace)"
echo "3. Go to the 'API Key' tab and generate a key"
echo "4. Click 'Token' link next to the key to generate a token"
echo
echo "See ~/.claude/skills/trello/references/setup.md for detailed instructions."
echo

# Check if already configured
if [ -f "$CONFIG_FILE" ]; then
    echo "Existing configuration found."
    read -p "Overwrite? (y/N): " OVERWRITE
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
        echo "Keeping existing configuration."
        exit 0
    fi
fi

# Get API Key
echo
read -p "Enter your Trello API Key: " API_KEY

if [ -z "$API_KEY" ]; then
    echo "Error: API Key is required."
    exit 1
fi

# Get Token
echo
read -p "Enter your Trello Token: " TOKEN

if [ -z "$TOKEN" ]; then
    echo "Error: Token is required."
    exit 1
fi

# Test credentials
echo
echo "Testing credentials..."

RESPONSE=$(curl -s "https://api.trello.com/1/members/me?key=$API_KEY&token=$TOKEN")

if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    USERNAME=$(echo "$RESPONSE" | jq -r '.username')
    FULLNAME=$(echo "$RESPONSE" | jq -r '.fullName')
    echo "Success! Connected as: $FULLNAME (@$USERNAME)"
else
    echo "Error: Invalid credentials."
    if echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
        echo "$RESPONSE" | jq -r '.message'
    fi
    exit 1
fi

# Save configuration
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << EOF
{
  "api_key": "$API_KEY",
  "token": "$TOKEN"
}
EOF

chmod 600 "$CONFIG_FILE"

echo
echo "Configuration saved to: $CONFIG_FILE"
echo
echo "You're all set! Try: trello-boards.sh boards"
