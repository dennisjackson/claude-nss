#!/bin/bash
set -euo pipefail
# Resolve symlinks to find real script location (portable — no readlink -f)
SOURCE="$0"
while [ -L "$SOURCE" ]; do
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
PROJ_DIR="$(cd "$(dirname "$SOURCE")/.." && pwd)"
devcontainer up --workspace-folder "$PROJ_DIR" --remove-existing-container && \
devcontainer exec --workspace-folder "$PROJ_DIR" bash
