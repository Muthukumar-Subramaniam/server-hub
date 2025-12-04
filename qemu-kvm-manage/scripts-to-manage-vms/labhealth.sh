#!/usr/bin/env bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#
# Script Name : labhealth
# Description : Check KVM lab infrastructure health
# Usage       : labhealth [options]

set -euo pipefail

# Script directory
SCRIPT_DIR="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"

# Execute the underlying kvm-lab-health.sh script
exec "$SCRIPT_DIR/kvm-lab-health.sh" "$@"
