#!/bin/bash

################################################################################
# Script Name: qlabdnsbinder
# Description: Standalone DNS management tool for lab infrastructure
# Usage:       qlabdnsbinder [options]
# Author:      Lab Infrastructure Team
# Version:     1.0.0
################################################################################

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Execute the underlying kvm-dnsbinder.sh script with all arguments
exec "$SCRIPT_DIR/kvm-dnsbinder.sh" "$@"
