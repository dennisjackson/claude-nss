#!/usr/bin/env bash
# Set up .envrc with API keys for the NSS dev environment.
# Usage: ./setup-envrc.sh
#
# Prompts for each key interactively. Leave blank to skip.

set -euo pipefail

ENVRC="$(dirname "$0")/../.envrc"

echo "Setting up $ENVRC"
echo "Press Enter to skip any key you don't have yet."
echo

read -rp "ANTHROPIC_API_KEY: " anthropic_key
read -rp "BUGZILLA_API_KEY: " bugzilla_key
read -rp "PHABRICATOR_API_TOKEN: " phab_token

{
    [[ -n "$anthropic_key" ]]  && echo "export ANTHROPIC_API_KEY=\"$anthropic_key\""
    [[ -n "$bugzilla_key" ]]   && echo "export BUGZILLA_API_KEY=\"$bugzilla_key\""
    [[ -n "$phab_token" ]]     && echo "export PHABRICATOR_API_TOKEN=\"$phab_token\""
} > "$ENVRC"

echo
echo "Written to $ENVRC"
echo "Run 'direnv allow' or 'source $ENVRC' to activate."
