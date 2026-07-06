#!/bin/bash
# Install the Trello skill pack into ~/.claude/skills/ as a live symlink install.
#
# The committed skills are plugin-native: SKILL.md references scripts via
# ${CLAUDE_PLUGIN_ROOT}, which Claude Code substitutes for marketplace/plugin
# installs. For a local symlink install (edit-and-see-live), this script rewrites
# that variable to the installed path and symlinks the scripts so your edits are
# immediately live. Re-run this script after editing a SKILL.md.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$HOME/.claude/skills"

echo "=== Trello skill pack installer (Claude Code) ==="
echo

# --- Dependencies ---
MISSING=""
command -v jq >/dev/null 2>&1   || MISSING="$MISSING jq"
command -v curl >/dev/null 2>&1 || MISSING="$MISSING curl"
if [ -n "$MISSING" ]; then
  echo "Missing required dependencies:$MISSING"
  echo "  macOS:  brew install$MISSING"
  echo "  Ubuntu: sudo apt install$MISSING"
  exit 1
fi
echo "Dependencies OK."
echo

# --- Install each skill in this pack ---
for src in "$SCRIPT_DIR"/skills/*/; do
  src="${src%/}"
  name="$(basename "$src")"
  target="$SKILLS_ROOT/$name"
  echo "Installing '$name' -> $target"
  mkdir -p "$target"
  [ -d "$src/scripts" ]    && ln -sfn "$src/scripts"    "$target/scripts"
  [ -d "$src/references" ] && ln -sfn "$src/references" "$target/references"
  chmod +x "$src"/scripts/*.sh 2>/dev/null || true
  # Rewrite the plugin-root variable to the install path (generic, so cross-skill
  # references within the pack - e.g. store-sort calling the trello scripts - resolve).
  sed 's#\${CLAUDE_PLUGIN_ROOT}/skills/#$HOME/.claude/skills/#g' \
    "$src/SKILL.md" > "$target/SKILL.md"
done

echo
echo "Installed. Scripts are symlinked (edits are live); re-run after editing a SKILL.md."
echo

# --- Setup / credentials ---
if [ -f "$HOME/.trello/config.json" ]; then
  echo "Existing Trello credentials found. Re-run setup any time with:"
  echo "  $SKILLS_ROOT/trello/scripts/trello-setup.sh"
else
  echo "No credentials found. Launching setup..."
  echo
  "$SKILLS_ROOT/trello/scripts/trello-setup.sh" || echo "Setup skipped; run trello-setup.sh when ready."
fi

echo
echo "Done. Try: 'show my Trello boards' or 'sort my shopping list'"
