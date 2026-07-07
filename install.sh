#!/bin/bash
# Install the Trello skill pack into ~/.claude/skills/ as a live symlink install.
#
# SKILL.md references scripts via ${CLAUDE_SKILL_DIR}, which Claude Code
# substitutes to the skill's own directory for personal, project, and plugin
# installs alike. So this script symlinks the whole skill directory into
# ~/.claude/skills/ - every edit (scripts AND SKILL.md) is immediately live,
# with no per-file rewrite. Re-run only when you add a new skill directory.
#
# Cross-skill references (e.g. store-sort calling the trello scripts) use
# ${CLAUDE_SKILL_DIR}/../trello/..., which resolves to the sibling skill because
# all skills in the pack are symlinked side by side under ~/.claude/skills/.

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

# --- Install each skill in this pack as a full-directory symlink ---
mkdir -p "$SKILLS_ROOT"
for src in "$SCRIPT_DIR"/skills/*/; do
  src="${src%/}"
  name="$(basename "$src")"
  target="$SKILLS_ROOT/$name"
  echo "Installing '$name' -> $target"
  rm -rf "$target"            # replace any prior copy or partial-symlink install
  ln -sfn "$src" "$target"    # whole-directory symlink; ${CLAUDE_SKILL_DIR} resolves it
  chmod +x "$src"/scripts/*.sh 2>/dev/null || true
done

echo
echo "Installed as directory symlinks - all edits (scripts and SKILL.md) are live. Re-run only when adding a new skill."
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
