#!/usr/bin/env bash
#
# Install git hooks for this repository
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

echo "========================================="
echo "Installing Git Hooks"
echo "========================================="
echo

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_DIR"

# Copy pre-commit hook
echo "Installing pre-commit hook..."
cp "$SCRIPT_DIR/pre-commit-hook.sh" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

echo "✅ Git hooks installed successfully!"
echo
echo "The pre-commit hook will now:"
echo "  • Block commits containing secrets (API keys, tokens, passwords)"
echo "  • Prevent .env files and private keys from being committed"
echo "  • Warn about hardcoded credentials in config files"
echo
echo "To bypass the hook (use with caution):"
echo "  git commit --no-verify"
echo
