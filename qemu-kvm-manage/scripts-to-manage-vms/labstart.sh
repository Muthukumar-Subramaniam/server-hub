#!/usr/bin/env bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#
# Script Name : labstart
# Description : Start the entire KVM lab infrastructure
# Usage       : labstart [options]

set -euo pipefail

# Script directory
SCRIPT_DIR="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"

# Execute the underlying kvm-lab-start.sh script
exec "$SCRIPT_DIR/kvm-lab-start.sh" "$@"
