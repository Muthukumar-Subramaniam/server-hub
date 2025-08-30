#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

INFRA_SERVER_VM_NAME=$(< /virtual-machines/local_infra_server_name)
ALIAS_FILE_OF_LAB_NODES='/virtual-machines/ssh-assist-aliases-for-vms-on-qemu-kvm'
ETC_HOSTS_FILE='/etc/hosts'
local_infra_domain_name=$(< /virtual-machines/local_infra_domain_name)

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

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

# Confirm deletion
if [[ "$qemu_kvm_hostname" == "$INFRA_SERVER_VM_NAME" ]]; then
    echo -e "\n⚠️  WARNING: You are about to delete your lab infra server VM : $INFRA_SERVER_VM_NAME !"
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
sudo rm -f /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2 \
           /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}_VARS.fd \
           /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.xml

sudo rmdir /virtual-machines/${qemu_kvm_hostname}

sudo sed -i "/@${qemu_kvm_hostname}\.${local_infra_domain_name}/d" "${ALIAS_FILE_OF_LAB_NODES}"
sudo sed -i "/ ${qemu_kvm_hostname}\.${local_infra_domain_name}/d" "${ETC_HOSTS_FILE}"

echo -e "✅ VM \"$qemu_kvm_hostname\" deleted successfully. \n"
