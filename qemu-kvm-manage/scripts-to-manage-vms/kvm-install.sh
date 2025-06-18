#!/bin/bash
# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    echo "❌❌❌  FATAL: WRONG PLACE, BUDDY! ❌❌❌"
    echo "This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo "You’re currently inside a QEMU guest VM, which makes absolutely no sense."
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

infra_server_ipv4_address=$(cat /virtual-machines/ipv4-address-address-of-infra-server-vm)
infra_mgmt_super_username=$(cat /virtual-machines/infra-mgmt-super-username)

# Use first argument or prompt for hostname
if [ -n "$1" ]; then
    qemu_kvm_hostname="$1"
else
    read -p "Please enter the Hostname of the VM to be installed : " qemu_kvm_hostname
fi

# Check if VM exists in 'virsh list --all'
if sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM \"$qemu_kvm_hostname\" exists already."
    echo "Either do one of the below, "
    echo "	* Remove the VM using kvm-remove and then try ! "  
    echo "	* Re-image the VM using kvm-reimage ! "  
    exit 1
fi

echo -e "\nUpdating ksmanager to create PXE environment for ${qemu_kvm_hostname} . . . \n"

echo -e "Generating MAC Address for the VM, will be appiled in case of a new VM . . .\n"

MAC_ADDRESS=$(printf '52:54:00:%02x:%02x:%02x\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))

echo "If in case of new VM, Please utilize this MAC Address when prompted : ${MAC_ADDRESS} \n"

>/tmp/install-vm-logs-"${qemu_kvm_hostname}"

ssh -t ${infra_mgmt_super_username}@${infra_server_ipv4_address} "sudo ksmanager ${qemu_kvm_hostname}" | tee -a /tmp/install-vm-logs-"${qemu_kvm_hostname}"

CURRENT_MAC_ADDRESS=$( grep "MAC Address  :"  /tmp/install-vm-logs-"${qemu_kvm_hostname}" | awk -F': ' '{print $2}' )

if [ -z ${CURRENT_MAC_ADDRESS} ]; then
	echo -e "\nSomething went wrong while executing ksmanager ! \nPlease check what is the issue from your Infra Server VM ( ${infra_server_ipv4_address} ) ! \n"
	exit 1
fi

if [[ "${MAC_ADDRESS}" != "${CURRENT_MAC_ADDRESS}" ]]; then
	MAC_ADDRESS="${CURRENT_MAC_ADDRESS}"
	echo "Existing MAC Address from the cache ${MAC_ADDRESS} will be applied to primary interface !"
else
	echo "MAC Address to be applied for the primary interface : ${MAC_ADDRESS}"
fi

mkdir -p /virtual-machines/${qemu_kvm_hostname}

sudo virt-install \
  --name ${qemu_kvm_hostname} \
  --features acpi=on,apic=on \
  --memory 2048 \
  --vcpus 2 \
  --disk path=/virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2,size=20,bus=virtio,boot.order=1 \
  --os-variant almalinux9 \
  --network network=default,model=virtio,mac=${MAC_ADDRESS},boot.order=2 \
  --graphics none \
  --console pty,target_type=serial \
  --machine q35 \
  --cpu host-model \
  --boot loader=/usr/share/edk2/ovmf/OVMF_CODE.fd,\
nvram.template=/usr/share/edk2/ovmf/OVMF_VARS.fd,\
nvram=/virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}_VARS.fd,menu=on \
  --pxe \
