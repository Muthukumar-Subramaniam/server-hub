#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
ETC_HOSTS_FILE='/etc/hosts'

# Function to show help
fn_show_help() {
    cat <<EOF
Usage: kvm-remove [hostname]

Arguments:
  hostname      Name of the VM to be deleted permanently (optional, will prompt if not given)
EOF
}

# Handle help and argument validation
if [[ $# -gt 1 ]]; then
    echo -e "❌ Too many arguments.\n"
    fn_show_help
    exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    fn_show_help
    exit 0
fi

if [[ "$1" == -* ]]; then
    echo -e "❌ No such option: $1\n"
    fn_show_help
    exit 1
fi

# Use first argument or prompt for hostname
if [ -n "$1" ]; then
    qemu_kvm_hostname="$1"
else
    read -rp "⌨️ Please enter the Hostname of the VM to be removed: " qemu_kvm_hostname
    if [[ -n "${KVM_TOOL_EXECUTED_FROM:-}" && "${KVM_TOOL_EXECUTED_FROM}" == "${qemu_kvm_hostname}" ]]; then
	echo -e "\n❌ This operation is not allowed to avoid self-referential KVM actions that could destabilize the infra server."
    	echo -e "⚠️ Note:"
	echo -e "  🔹 You are running a KVM management related action for the lab infra server from the infra server itself."
	echo -e "  🔹 If you still need to perform this operation, you need to do this from the Linux workstation running the QEMU/KVM setup.\n"
	exit 1
    fi
fi

if [[ ! "${qemu_kvm_hostname}" =~ ^[a-z0-9-]+$ || "${qemu_kvm_hostname}" =~ ^- || "${qemu_kvm_hostname}" =~ -$ ]]; then
    echo -e "\n❌ VM hostname '$qemu_kvm_hostname' is invalid.\n"
    exit 1
fi

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

# Confirm deletion
if [[ "$qemu_kvm_hostname" == "$lab_infra_server_shortname" ]]; then
    echo -e "\n⚠️  WARNING: You are about to delete your lab infra server VM : $lab_infra_server_shortname !"
    read -r -p "If you know what you are doing, confirm by typing 'delete-lab-infra-server' : " confirmation

    if [[ "$confirmation" != "delete-lab-infra-server" ]]; then
        echo -e "\n⛔ Aborted.\n"
        exit 1
    fi
else
    echo -e "\n⚠️ WARNING: This will permanently delete the VM \"$qemu_kvm_hostname\" and all associated files!"
    read -rp "❓ Are you sure you want to proceed? (yes/[no]): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        echo -e "\n⛔ Aborted.\n"
        exit 1
    fi
fi

# Proceed with deletion
sudo virsh destroy "${qemu_kvm_hostname}" 2>/dev/null
sudo virsh undefine "${qemu_kvm_hostname}" --nvram 2>/dev/null
if [ -n "${qemu_kvm_hostname}" ]; then
    sudo rm -rf "/kvm-hub/vms/${qemu_kvm_hostname}"
fi
dot_escaped_domain=$(echo "$lab_infra_domain_name" | sed 's/\./\\./g')
sudo sed -i "/[[:space:]]${qemu_kvm_hostname}\.${dot_escaped_domain}[[:space:]]/d" "${ETC_HOSTS_FILE}"

echo -e "✅ VM \"$qemu_kvm_hostname\" deleted successfully. \n"
