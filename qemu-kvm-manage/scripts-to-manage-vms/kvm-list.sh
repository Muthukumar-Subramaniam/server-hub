#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#
set -uo pipefail

# Prevent running as root
if [[ "$EUID" -eq 0 ]]; then
    echo -e "\n⛔ Running as root user is not allowed."
    echo -e "\n🔐 This script should be run as a user who has sudo privileges, but *not* using sudo.\n"
    exit 1
fi

# Prevent running inside a QEMU guest
if sudo dmidecode -s system-manufacturer 2>/dev/null | grep -qi 'QEMU'; then
    echo "❌❌❌  FATAL: WRONG PLACE, BUDDY! ❌❌❌"
    echo -e "\n⚠️ Note:"
    echo -e "  🔹 This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo -e "  🔹 You’re currently inside a QEMU guest VM, which makes absolutely no sense.\n"
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

# Load infra variables
infra_mgmt_super_username=$(< /virtual-machines/infra-mgmt-super-username)
local_infra_domain_name=$(< /virtual-machines/local_infra_domain_name)

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET"

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# Header
printf "%-20s %-12s %-12s\n" "VM-Name" "VM-State" "OS-State"
printf '%s\n' "------------------------------------------"

# Collect VM list safely
mapfile -t vms < <(sudo virsh list --all | awk 'NR>2 && $2 != "" {print $2}')

for vm in "${vms[@]}"; do
    vm_state="[ N/A ]"
    os_state="[ N/A ]"

    # VM state
    vm_state=$(sudo virsh domstate "$vm" 2>/dev/null || echo "[ N/A ]")

    if [[ "$vm_state" == "running" ]]; then
        state_out=$(ssh $SSH_OPTS "${infra_mgmt_super_username}@${vm}.${local_infra_domain_name}" \
            "systemctl is-system-running --quiet && echo Ready || echo Not-Ready" \
        2>/dev/null </dev/null || true)

        if [[ -n "$state_out" ]]; then
            os_state="$state_out"
        else
            os_state="Not-Ready"
        fi
    fi

    # Decide row color
    row_color="$RESET"
    case "$os_state" in
        Ready)      row_color="$GREEN" ;;
        Not-Ready)  row_color="$YELLOW" ;;
        "[ N/A ]")  row_color="$RED" ;;
    esac

    printf "${row_color}%-20s %-12s %-12s${RESET}\n" "$vm" "$vm_state" "$os_state"
done
