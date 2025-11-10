#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

if [[ -n "${KVM_TOOL_EXECUTED_FROM:-}" ]]; then
    echo -e "\n❌ Detected execution from the lab infra server."
    echo -e "👉 Please run the 'dnsbinder' utility directly with sudo to manage lab infra DNS.\n"
    exit 1
fi

echo -n -e "\n⚙️  Enabling DNS of lab infra with resolvectl . . . "

if grep -q "${lab_infra_server_ipv4_address}" <<< $(resolvectl); then
    echo -e "\e[32m[ ok ]\e[0m"
else
    if ip link show labbr0 &>/dev/null; then
       sudo resolvectl dns labbr0 ${lab_infra_server_ipv4_address}
       sudo resolvectl domain labbr0 ~${lab_infra_domain_name} 
       echo -e "\e[32m[ done ]\e[0m"
    else
       echo -e "\n❌ labbr0 interface is not yet available! \n" 
       exit 1
    fi
fi

echo -e "\n⚙️  Invoking dnsbinder utility from lab infra server . . ."

if $lab_infra_server_mode_is_host; then
    sudo dnsbinder "$@"
else
    ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "sudo dnsbinder $@"
fi
