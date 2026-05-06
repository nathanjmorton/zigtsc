#!/usr/bin/env bash
set -euo pipefail

# zigtsc init — scaffold a new zigtsc project
# Usage: zigtsc-init.sh [directory]

DIR="${1:-.}"

if [ "$DIR" != "." ]; then
  mkdir -p "$DIR"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "$SCRIPT_DIR/main.ts" "$DIR/main.ts"

echo "Created $DIR/main.ts"
echo ""
echo "Try it out:"
echo "  zigtsc $DIR/main.ts -target js $DIR/output.js    # transpile to JS"
echo "  zigtsc $DIR/main.ts -target cpp $DIR/out          # transpile to C++ (multi-file)"
echo "  zigtsc $DIR/main.ts $DIR/output.c                 # transpile to C"
