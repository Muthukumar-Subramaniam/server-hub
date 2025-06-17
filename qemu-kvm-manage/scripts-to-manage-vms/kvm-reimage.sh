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
    read -p "Please enter the Hostname of the VM to be re-imaged : " qemu_kvm_hostname
fi

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

/server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-remove.sh "$qemu_kvm_hostname"
/server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-install.sh "$qemu_kvm_hostname"
