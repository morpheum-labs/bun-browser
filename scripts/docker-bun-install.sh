#!/usr/bin/env bash
# Try bun install against multiple npm registry mirrors when tarball fetches fail.
# bun.lock may pin tarball URLs to one mirror; on failure we rewrite hosts and retry.
set -uo pipefail

LOCKFILE="${1:-bun.lock}"
ORIG="$(mktemp)"
cp "$LOCKFILE" "$ORIG"

MIRRORS=(
  registry.npmmirror.com
  registry.npmjs.org
  mirrors.cloud.tencent.com/npm
)

cleanup() {
  rm -f "$ORIG"
}
trap cleanup EXIT

for mirror in "${MIRRORS[@]}"; do
  cp "$ORIG" "$LOCKFILE"
  if [ "$mirror" != registry.npmmirror.com ]; then
    sed -i 's|https://registry\.npmmirror\.com/|https://'"${mirror}"'/|g' "$LOCKFILE"
    sed -i 's|https://registry\.npmjs\.org/|https://'"${mirror}"'/|g' "$LOCKFILE"
  fi
  echo ">>> bun install --frozen-lockfile (mirror: ${mirror})"
  if bun install --frozen-lockfile; then
    exit 0
  fi
  echo ">>> mirror ${mirror} failed, trying next..."
done

echo "error: bun install failed on all npm mirrors" >&2
exit 1
