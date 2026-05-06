#!/usr/bin/env bash
set -euo pipefail

# Build release binaries for all platforms and create a GitHub release.
# Usage: ./scripts/release.sh v0.1.0

VERSION="${1:?Usage: release.sh <version>}"
DIST="dist"

rm -rf "$DIST"
mkdir -p "$DIST"

TARGETS=(
  "aarch64-macos"
  "x86_64-macos"
  "aarch64-linux-gnu"
  "x86_64-linux-gnu"
)

for target in "${TARGETS[@]}"; do
  echo "Building zigtsc-$target..."
  zig build -Doptimize=ReleaseFast -Dtarget="$target"
  cp zig-out/bin/zigtsc "$DIST/zigtsc"
  tar -czf "$DIST/zigtsc-$target.tar.gz" -C "$DIST" zigtsc
  rm "$DIST/zigtsc"
  echo "  → dist/zigtsc-$target.tar.gz"
done

echo ""
echo "Creating GitHub release $VERSION..."
gh release create "$VERSION" \
  --title "$VERSION" \
  --notes "zigtsc $VERSION" \
  "$DIST"/zigtsc-*.tar.gz

echo ""
echo "Release $VERSION created."
echo ""
echo "Next steps:"
echo "  1. Update homebrew-zigtsc formula with new sha256 hashes:"
for target in "${TARGETS[@]}"; do
  echo "     shasum -a 256 $DIST/zigtsc-$target.tar.gz"
done
