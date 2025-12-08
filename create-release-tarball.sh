#!/usr/bin/env bash

# Script to create release tarball for server-hub
# This creates a tarball excluding git files and other unnecessary files

set -euo pipefail

# Create latest-release directory if it doesn't exist
mkdir -p latest-release

TARBALL_NAME="latest-release/server-hub.tar.gz"

echo "Creating release tarball: $TARBALL_NAME"

# Create tarball excluding git files and other unnecessary files
tar -czf "$TARBALL_NAME" \
    --exclude='.git' \
    --exclude='.github' \
    --exclude='.gitignore' \
    --exclude='latest-release' \
    --exclude='create-release-tarball.sh' \
    --transform "s,^,server-hub/," \
    *

echo "✅ Tarball created: $TARBALL_NAME"
