#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Function to show help
fn_show_help() {
    cat <<EOF
Usage: kvm-stop [hostname]

Arguments:
  hostname  Name of the VM to Power-OFF (optional, will prompt if not given)
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
    read -rp "⌨️ Please enter the Hostname of the VM to be stopped : " qemu_kvm_hostname
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

# Check if VM exists in 'virsh list'
if ! sudo virsh list  | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM \"$qemu_kvm_hostname\" is not running."
    exit 1
fi

# Proceed with Stop
sudo virsh destroy "${qemu_kvm_hostname}" 2>/dev/null

echo -e "✅ VM \"$qemu_kvm_hostname\" is stopped successfully. \n"
