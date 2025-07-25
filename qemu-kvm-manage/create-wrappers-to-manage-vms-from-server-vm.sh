#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

if [[ "$EUID" -eq 0 ]]; then
    echo -e "\n⛔ Running as root user is not allowed."
    echo -e "\n🔐 This script should be run as a user who has sudo privileges, but *not* using sudo.\n"
    exit 1
fi

# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    echo "❌❌❌  FATAL: WRONG PLACE, BUDDY! ❌❌❌"
    echo -e "\n⚠️  Note:"
    echo -e "  🔹 This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo -e "  🔹 You’re currently inside a QEMU guest VM, which makes absolutely no sense.\n"
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

infra_server_ipv4_address=$(cat /virtual-machines/ipv4-address-address-of-infra-server-vm)
infra_mgmt_super_username=$(cat /virtual-machines/infra-mgmt-super-username)
local_infra_domain_name=$(cat /virtual-machines/local_infra_domain_name)
kvm_host_admin_user="$USER"
scripts_location_to_manage_vms="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"
temp_dir_to_create_wrapper_scripts="/tmp/scripts-to-manage-vms"

ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${infra_mgmt_super_username}@${infra_server_ipv4_address} "cat .ssh/id_rsa.pub"

