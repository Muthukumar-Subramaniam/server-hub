#!/bin/bash
#----------------------------------------------------------------------------------------#
# Update tarball script for server-hub releases                                          #
# Creates server-hub.tar.gz for distribution                                             #
#----------------------------------------------------------------------------------------#

set -e

VERSION_FILE="project_version.json"

echo "🚀 Server-Hub Tarball Update Script"
echo

# Update release date in version file
if [[ -f "$VERSION_FILE" ]]; then
    CURRENT_DATE=$(date +%Y-%m-%d)
    VERSION=$(jq -r '.version' "$VERSION_FILE")
    
    # Update the release_date field
    jq --arg date "$CURRENT_DATE" '.release_date = $date' "$VERSION_FILE" > "${VERSION_FILE}.tmp"
    mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
    
    echo "✓ Updated $VERSION_FILE - Version: $VERSION, Date: $CURRENT_DATE"
else
    echo "Error: $VERSION_FILE not found!"
    exit 1
fi

echo
echo "Creating server-hub.tar.gz..."

# Remove old tarball if exists
if [[ -f "server-hub.tar.gz" ]]; then
    rm -f server-hub.tar.gz
    echo "  ✓ Removed old tarball"
fi

# Create tarball excluding unnecessary files
tar -czf server-hub.tar.gz \
    --exclude='.git' \
    --exclude='.gitignore' \
    --exclude='server-hub.tar.gz' \
    --exclude='update-tarball.sh' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    .

# Get tarball size
SIZE_BYTES=$(stat -c%s "server-hub.tar.gz" 2>/dev/null || stat -f%z "server-hub.tar.gz" 2>/dev/null)
SIZE_MB=$(echo "scale=2; $SIZE_BYTES / 1024 / 1024" | bc)

echo "  ✓ Created server-hub.tar.gz (${SIZE_MB} MB)"

echo
echo "✅ Release tarball updated successfully!"
echo
echo "Version: $VERSION"
echo "File: server-hub.tar.gz"
echo
echo "Ready for release!"
