#!/bin/bash
# Trello Setup - Configure API credentials
#
# Interactive on purpose. The key and token are typed by the user at a
# terminal, never passed in by an agent, so they never land in a chat
# transcript or a command line. Run with no terminal on stdin - which is how
# an agent's shell runs it - it prints what the user has to do and exits 3.

set -e

# Sourcing lib.sh runs the ~/.trello migration. Setup does not load the
# config - it is the script that writes it.
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONFIG_DIR="$TRELLO_CONFIG_DIR"
CONFIG_FILE="$TRELLO_CONFIG_FILE"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# With no terminal, `read` meets end of input at the first prompt and set -e
# ends the script with exit 1 and no word of why. Say why, and say what to do.
# Exit 3, not 1, so a caller can tell "a person has to do this" from a failure.
need_terminal() {
    [ -t 0 ] && return 0
    cat >&2 <<EOF
trello-setup.sh needs a terminal. It asks for a Trello API key and token, and
the user has to type those themselves: they must not be pasted into a chat or
passed to the script by an agent.

Ask the user to run it:
  ! $SELF
at the Claude Code prompt, or
  $SELF
in a terminal of their own. Nothing has been changed.
EOF
    exit 3
}

# Strip leading and trailing spaces and tabs: a pasted key often carries one,
# and Trello then answers "invalid key" with nothing to show why.
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# The token-issuing link, from Trello's /1/authorize. Setup used to send the
# user to the Power-Up page's own Token link, which issues a read-write token
# that never expires. This names the scope and the expiry, so the user picks.
# The key reaches jq on stdin, like everything else here that holds a
# credential.
authorize_url() {  # authorize_url <key> <scope> <expiration>
    printf 'https://trello.com/1/authorize?expiration=%s&name=trello-skill&scope=%s&response_type=token&key=%s\n' \
        "$3" "$2" "$(printf '%s' "$1" | jq -sRr '@uri')"
}

# Write config.json with jq, so a " or \ in a value comes out escaped and the
# file is always valid JSON. The values go to jq on stdin, not as --arg: jq's
# arguments are readable by every local user through ps, the same as curl's,
# and printf is a builtin, so it starts no process that shows them.
#
# umask first: the file must never exist, even briefly, at the default 644.
# chmod after the write would leave a window in which another local user
# could read the token.
write_config() {  # write_config <key> <token>
    local old_umask
    mkdir -p "$CONFIG_DIR"
    old_umask=$(umask)
    umask 077
    printf '%s\n%s\n' "$1" "$2" | jq -nR '{api_key: input, token: input}' > "$CONFIG_FILE"
    umask "$old_umask"
    chmod 600 "$CONFIG_FILE"
    chmod 700 "$HOME/.dbhq" "$CONFIG_DIR"
}

need_terminal

echo "=== Trello API Setup ==="
echo
echo "You need an API key from a Trello Power-Up. If you do not have one yet:"
echo "1. Go to: https://trello.com/power-ups/admin"
echo "2. Create a new Power-Up (any name, any workspace)"
echo "3. Open its 'API Key' tab and generate a key"
echo
echo "This script then gives you a link that issues the token, with the access"
echo "and expiry you choose. See references/setup.md in this skill for the detail."
echo

# Check if already configured
if [ -f "$CONFIG_FILE" ]; then
    echo "Existing configuration found."
    read -r -p "Overwrite? (y/N): " OVERWRITE
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
        echo "Keeping existing configuration."
        exit 0
    fi
fi

# Get API Key
echo
read -r -p "Trello API key: " API_KEY
API_KEY=$(trim "$API_KEY")
if [ -z "$API_KEY" ]; then
    echo "Error: API Key is required." >&2
    exit 1
fi

# Scope. A read-only token cannot change anything, which is all board-digest
# and due-radar need. trello, store-sort and life-manager write, and a write
# with a read-only token fails with HTTP 401.
echo
echo "Access:"
echo "  w  read and write - every skill in the pack works (default)"
echo "  r  read only - board-digest, due-radar and reading cards work; nothing can be changed"
read -r -p "Read and write, or read only? (W/r): " ACCESS
case "$ACCESS" in
    r|R) SCOPE="read" ;;
    ""|w|W) SCOPE="read,write" ;;
    *) echo "Error: answer w or r." >&2; exit 1 ;;
esac

# Expiry. A token that expires stops working on its own if the laptop or the
# config file goes astray; the cost is re-running this script when it does.
echo
read -r -p "How long should the token last? 1day, 30days or never (30days): " EXPIRATION
EXPIRATION=${EXPIRATION:-30days}
case "$EXPIRATION" in
    1day|30days|never) ;;
    *) echo "Error: answer 1day, 30days or never." >&2; exit 1 ;;
esac

echo
echo "Open this link, check the access it asks for, and click Allow:"
echo
echo "  $(authorize_url "$API_KEY" "$SCOPE" "$EXPIRATION")"
echo
echo "Trello then shows the token. Copy it and paste it below."

# -s: the token is not shown as it is typed or pasted, so it is not left on
# the screen or in a terminal's scrollback.
echo
read -r -s -p "Token (hidden as you paste): " TOKEN
echo
TOKEN=$(trim "$TOKEN")
if [ -z "$TOKEN" ]; then
    echo "Error: Token is required." >&2
    exit 1
fi

# Test credentials
echo
echo "Testing credentials..."

# api() has already printed Trello's status and message if this fails.
if ! RESPONSE=$(api_get "/members/me"); then
    echo "Error: Trello did not accept these credentials." >&2
    exit 1
fi
USERNAME=$(echo "$RESPONSE" | jq -r '.username')
FULLNAME=$(echo "$RESPONSE" | jq -r '.fullName')
echo "Success! Connected as: $FULLNAME (@$USERNAME)"

write_config "$API_KEY" "$TOKEN"

echo
echo "Configuration saved to: $CONFIG_FILE"
if [ "$SCOPE" = "read" ]; then
    echo "This token is read only: board-digest and due-radar work, and any change fails with HTTP 401."
fi
if [ "$EXPIRATION" != "never" ]; then
    echo "The token expires after $EXPIRATION. Run this script again when Trello starts answering 'invalid token'."
fi
echo
echo "You're all set! Try: trello-boards.sh boards"
