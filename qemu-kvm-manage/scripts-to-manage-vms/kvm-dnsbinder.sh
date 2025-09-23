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
    echo -e "\n⚠️ Note:"
    echo -e "  🔹 This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo -e "  🔹 You’re currently inside a QEMU guest VM, which makes absolutely no sense.\n"
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

infra_server_ipv4_address=$(< /kvm-hub/ipv4-address-address-of-infra-server-vm)
infra_mgmt_super_username=$(< /kvm-hub/infra-mgmt-super-username)
local_infra_domain_name=$(< /kvm-hub/local_infra_domain_name)


echo -n -e "\n⚙️  Enabling DNS of lab infra with resolvectl if required . . . "

if grep -q "${infra_server_ipv4_address}" <<< $(resolvectl); then
    echo -e "\e[32m[ ok ]\e[0m"
else
    if ip link show virbr0 &>/dev/null; then
       sudo resolvectl dns virbr0 ${infra_server_ipv4_address}
       sudo resolvectl domain virbr0 ${local_infra_domain_name} 
       echo -e "\e[32m[ done ]\e[0m"
    else
       echo -e "\n❌ virbr0 interface is not yet available! \n" 
       exit 1
    fi
fi

echo -e "\n⚙️  Invoking dnsbinder utility from lab infra server . . ."

ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t ${infra_mgmt_super_username}@${infra_server_ipv4_address} "sudo dnsbinder $@"
