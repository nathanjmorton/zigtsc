#!/usr/bin/env bash
set -euo pipefail

# Release zigtsc: bump version, commit, tag, and push.
# CI handles building, creating the GitHub release, and updating Homebrew.
#
# Usage: ./scripts/release.sh [<version>]
#   No arg  → auto-bump minor (e.g. 0.5.0 → 0.6.0)
#   With arg → use explicit version

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Read current version from src/main.zig
CURRENT=$(grep -o 'const VERSION = "[^"]*"' "$REPO_ROOT/src/main.zig" | grep -o '[0-9][0-9.]*')

if [[ -n "${1:-}" ]]; then
  VERSION="$1"
else
  # Auto-bump: increment minor, reset patch
  IFS='.' read -r major minor patch <<< "$CURRENT"
  VERSION="${major}.$((minor + 1)).${patch}"
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be semver (e.g. 0.6.0)" >&2
  exit 1
fi

echo "Releasing: v${CURRENT} → v${VERSION}"

# Update VERSION in src/main.zig
if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s/const VERSION = \".*\";/const VERSION = \"${VERSION}\";/" "$REPO_ROOT/src/main.zig"
else
  sed -i "s/const VERSION = \".*\";/const VERSION = \"${VERSION}\";/" "$REPO_ROOT/src/main.zig"
fi

git -C "$REPO_ROOT" add src/main.zig
git -C "$REPO_ROOT" commit -m "release: v${VERSION}"
git -C "$REPO_ROOT" tag "v${VERSION}"
git -C "$REPO_ROOT" push
git -C "$REPO_ROOT" push --tags

echo ""
echo "Pushed v${VERSION}. CI will:"
echo "  1. Build release binaries"
echo "  2. Create GitHub release"
echo "  3. Update Homebrew tap"
