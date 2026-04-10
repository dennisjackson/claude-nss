#!/usr/bin/env bash
# Set up .envrc with API keys for the dev container.
# Usage: ./setup-envrc.sh [-f]
#
# Prompts for each key interactively. Leave blank to skip.
# Skips keys that already have a value (in .envrc or environment) unless -f is given.

set -euo pipefail

ENVRC="$(dirname "$0")/../.envrc"
FORCE=false
[[ "${1:-}" == "-f" ]] && FORCE=true

# Read existing ANTHROPIC_API_KEY from .envrc if present.
existing_value=""
if [[ -f "$ENVRC" ]]; then
    line=$(grep '^export ANTHROPIC_API_KEY=' "$ENVRC" 2>/dev/null || true)
    if [[ -n "$line" ]]; then
        existing_value="${line#export ANTHROPIC_API_KEY=}"
        existing_value="${existing_value#\"}"
        existing_value="${existing_value%\"}"
    fi
fi

# Fall back to environment variable.
current_value="${existing_value:-${ANTHROPIC_API_KEY:-}}"

echo "Setting up $ENVRC"
echo "Press Enter to skip any key you don't have yet."
echo

new_value=""
if [[ -n "$current_value" ]] && ! $FORCE; then
    echo "ANTHROPIC_API_KEY: already set (use -f to overwrite)"
    new_value="$current_value"
else
    prompt="ANTHROPIC_API_KEY"
    [[ -n "$current_value" ]] && prompt="ANTHROPIC_API_KEY [current: ${current_value:0:4}...]"
    read -rp "$prompt: " input
    if [[ -n "$input" ]]; then
        new_value="$input"
    elif [[ -n "$current_value" ]]; then
        new_value="$current_value"
    fi
fi

# Write .envrc — only include keys that have values.
: > "$ENVRC"
[[ -n "$new_value" ]] && echo "export ANTHROPIC_API_KEY=\"$new_value\"" >> "$ENVRC"

echo
echo "Written to $ENVRC"
echo "Run 'direnv allow' or 'source $ENVRC' to activate."
