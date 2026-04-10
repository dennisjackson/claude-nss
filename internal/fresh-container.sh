#!/bin/bash
set -euo pipefail
PROJ_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
devcontainer up --workspace-folder "$PROJ_DIR" --remove-existing-container && \
devcontainer exec --workspace-folder "$PROJ_DIR" bash
