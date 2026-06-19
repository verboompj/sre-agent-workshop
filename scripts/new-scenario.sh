#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/scenario-tools"
[ -d "$TOOLS_DIR/node_modules" ] || (cd "$TOOLS_DIR" && npm install --silent)
node "$TOOLS_DIR/bin/new-scenario.js" "$@"
