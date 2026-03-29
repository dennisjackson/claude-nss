#!/bin/bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- Colours & helpers -------------------------------------------------------
bold=$'\033[1m'
dim=$'\033[2m'
green=$'\033[32m'
yellow=$'\033[33m'
red=$'\033[31m'
cyan=$'\033[36m'
reset=$'\033[0m'

section() { printf '\n%s=== %s ===%s\n' "$bold$cyan" "$1" "$reset"; }
warn()    { printf '  %s⚠  %s%s\n' "$yellow" "$1" "$reset"; }
ok()      { printf '  %s✓  %s%s\n' "$green" "$1" "$reset"; }
err()     { printf '  %s✗  %s%s\n' "$red" "$1" "$reset"; }

# --- Check for uncommitted changes ------------------------------------------
section "Repository Status"

git_status=$(git -C "$PROJ_DIR" status --porcelain 2>/dev/null || true)
if [ -n "$git_status" ]; then
    warn "Uncommitted changes in host repo:"
    echo ""
    echo "$git_status" | while IFS= read -r line; do
        printf '    %s\n' "$line"
    done
    echo ""
else
    ok "Host repo working tree is clean"
fi

# --- Inventory what will be destroyed ----------------------------------------
section "The following will be destroyed"

# Container
CONTAINER_ID=$(docker ps -aq --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)
if [ -n "$CONTAINER_ID" ]; then
    state=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
    printf '  Container:  %s (%s)\n' "${CONTAINER_ID:0:12}" "$state"
else
    printf '  Container:  %snone found%s\n' "$dim" "$reset"
fi

# Volumes
for vol in nss-dev-nss nss-dev-nspr nss-dev-ccache; do
    info=$(docker volume inspect "$vol" --format '{{.CreatedAt}}' 2>/dev/null || true)
    if [ -n "$info" ]; then
        printf '  Volume:     %s  %s(created: %s)%s\n' "$vol" "$dim" "$info" "$reset"
    else
        printf '  Volume:     %s  %snot found%s\n' "$vol" "$dim" "$reset"
    fi
done

# Bugs directory
bugs_dir="$PROJ_DIR/bugs"
if [ -d "$bugs_dir" ]; then
    bug_count=$(find "$bugs_dir" -maxdepth 1 -type d -name 'bug-*' 2>/dev/null | wc -l)
    bugs_size=$(du -sh "$bugs_dir" 2>/dev/null | cut -f1 || echo "?")
    printf '  bugs/:      %s bug(s), %s\n' "$bug_count" "$bugs_size"
else
    printf '  bugs/:      %snot found%s\n' "$dim" "$reset"
fi

# --- Confirm -----------------------------------------------------------------
echo ""
printf '%s%sThis will permanently delete all container state, volumes, and bug data.%s\n' "$bold" "$red" "$reset"
printf 'Type "nuke" to confirm: '
read -r confirm

if [ "$confirm" != "nuke" ]; then
    echo "Aborted."
    exit 1
fi

echo ""

# --- Destroy container -------------------------------------------------------
section "Removing container"

if [ -n "$CONTAINER_ID" ]; then
    docker rm -f "$CONTAINER_ID" >/dev/null 2>&1
    ok "Container removed"
else
    ok "No container to remove"
fi

# --- Destroy volumes ---------------------------------------------------------
section "Removing volumes"

for vol in nss-dev-nss nss-dev-nspr nss-dev-ccache; do
    if docker volume rm "$vol" >/dev/null 2>&1; then
        ok "Removed $vol"
    else
        ok "$vol already absent"
    fi
done

# --- Wipe bugs directory -----------------------------------------------------
section "Wiping bugs/"

if [ -d "$bugs_dir" ]; then
    rm -rf "$bugs_dir"
    mkdir -p "$bugs_dir"
    ok "bugs/ wiped"
else
    ok "bugs/ already absent"
fi

echo ""
ok "All container state has been destroyed."
echo ""
