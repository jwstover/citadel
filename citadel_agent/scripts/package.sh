#!/usr/bin/env bash
# Build a release tarball for the current host platform.
#
# Output: dist/citadel-agent-<version>-<os>-<arch>.tar.gz
#
# BEAM releases are not portable across (os, arch) pairs — to ship to multiple
# platforms, run this script once per target host (or in a CI matrix).

set -euo pipefail

cd "$(dirname "$0")/.."

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="x86_64" ;;
esac

VERSION="$(grep -E '^\s*@version\s+' mix.exs | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
NAME="citadel-agent-${VERSION}-${OS}-${ARCH}"

echo "Building $NAME"

rm -rf _build/prod/rel
MIX_ENV=prod mix release citadel_agent --overwrite

mkdir -p dist
tar -czf "dist/${NAME}.tar.gz" -C _build/prod/rel citadel_agent

(cd dist && shasum -a 256 "${NAME}.tar.gz" > "${NAME}.tar.gz.sha256")

echo
echo "✓ dist/${NAME}.tar.gz"
echo "✓ dist/${NAME}.tar.gz.sha256"
ls -lh "dist/${NAME}.tar.gz"
