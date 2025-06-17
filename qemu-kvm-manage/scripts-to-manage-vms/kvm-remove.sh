#!/bin/bash
# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    echo "❌❌❌  FATAL: WRONG PLACE, BUDDY! ❌❌❌"
    echo "This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo "You’re currently inside a QEMU guest VM, which makes absolutely no sense."
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

# Use first argument or prompt for hostname
if [ -n "$1" ]; then
    qemu_kvm_hostname="$1"
else
    read -p "Please enter the Hostname of the VM to be removed : " qemu_kvm_hostname
fi

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

# Confirm deletion
echo -e "\n⚠️ WARNING: This will permanently delete the VM \"$qemu_kvm_hostname\" and all associated files!"
read -p "Are you sure you want to proceed? (yes/[no]): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# Proceed with deletion
sudo virsh destroy "${qemu_kvm_hostname}" 2>/dev/null
sudo virsh undefine "${qemu_kvm_hostname}" --nvram 2>/dev/null
sudo rm -f /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2 \
           /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}_VARS.fd \
           /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.xml

echo "✅ VM \"$qemu_kvm_hostname\" deleted successfully."
