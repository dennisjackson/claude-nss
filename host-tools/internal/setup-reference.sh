#!/bin/bash
# Populate the reference/ directory with git repos listed in
# reference/sources.txt. This directory is mounted read-only into the dev
# container at /workspaces/nss-dev/reference/.
#
# Usage: host-tools/internal/setup-reference.sh [--force]
#   --force   re-clone repos even if they already exist
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REF_DIR="$PROJ_DIR/reference"
SOURCES="$REF_DIR/sources.txt"

if [[ ! -f "$SOURCES" ]]; then
    echo "ERROR: $SOURCES not found." >&2
    exit 1
fi

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

# ── Clone / update repos ────────────────────────────────────────────
mkdir -p "$REF_DIR/repos"

clone_repo() {
    local url="$1"
    local name
    name="$(basename "$url" .git)"
    local target="$REF_DIR/repos/$name"

    if [[ -d "$target/.git" ]] && ! $FORCE; then
        echo "  [skip] $name (already cloned; use --force to re-clone)"
        return 0
    fi

    if [[ -d "$target" ]]; then
        echo "  [rm]   $name"
        rm -rf "$target"
    fi

    echo "  [clone] $name  ← $url"
    git clone --depth 1 "$url" "$target" 2>&1 | sed 's/^/         /'
}

echo "==> Cloning reference repos into $REF_DIR/repos/ ..."
while IFS= read -r line; do
    line="${line%%#*}"       # strip comments
    line="${line// /}"       # strip whitespace
    [[ -z "$line" ]] && continue
    clone_repo "$line" &
done < "$SOURCES"
wait
echo "    Done."
echo "==> Reference directory ready."
