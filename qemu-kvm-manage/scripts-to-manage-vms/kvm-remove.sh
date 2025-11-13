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
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$1"

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

# Confirm deletion
if [[ "$qemu_kvm_hostname" == "$lab_infra_server_hostname" ]]; then
    echo -e "\n⚠️  WARNING: You are about to delete your lab infra server VM : $lab_infra_server_hostname !"
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

if grep -q "${qemu_kvm_hostname}" "${ETC_HOSTS_FILE}"; then
    sudo sed -i.bak "/${qemu_kvm_hostname}/d" "${ETC_HOSTS_FILE}"
fi

echo -e "✅ VM \"$qemu_kvm_hostname\" deleted successfully. \n"
