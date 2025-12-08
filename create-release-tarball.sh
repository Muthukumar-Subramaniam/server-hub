#!/usr/bin/env bash

# Script to create release tarball for server-hub
# This creates a tarball excluding git files and other unnecessary files

set -euo pipefail

# Get version from project_version.json
VERSION=$(grep -o '"message": *"[^"]*"' project_version.json | cut -d'"' -f4)

if [[ -z "$VERSION" ]]; then
    echo "Error: Could not extract version from project_version.json"
    exit 1
fi

TARBALL_NAME="server-hub-${VERSION}.tar.gz"

echo "Creating release tarball: $TARBALL_NAME"

# Create tarball excluding git files and other unnecessary files
tar -czf "$TARBALL_NAME" \
    --exclude='.git' \
    --exclude='.github' \
    --exclude='*.tar.gz' \
    --exclude='.gitignore' \
    --exclude='create-release-tarball.sh' \
    --transform "s,^,server-hub/," \
    *

echo "✅ Tarball created: $TARBALL_NAME"
echo ""
echo "Upload this to the GitHub release with:"
echo "  gh release upload ${VERSION} $TARBALL_NAME"
echo ""
echo "Or manually upload it to: https://github.com/Muthukumar-Subramaniam/server-hub/releases/tag/${VERSION}"
