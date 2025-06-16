#!/bin/bash
infra_host="server.ms.local"

read -p "Please enter the Hostname of the VM to be created : " qemu_kvm_hostname

echo -e "\nUpdating ksmanager to create PXE environment for ${qemu_kvm_hostname} . . . \n"

echo -e "Generating MAC Address for the VM, will be appiled in case of a new VM . . .\n"

MAC_ADDRESS=$(printf '52:54:00:%02x:%02x:%02x\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))

echo "If in case of new VM, Please utilize this MAC Address when prompted : ${MAC_ADDRESS} \n"

>/tmp/install-vm-logs-"${qemu_kvm_hostname}"

ssh muthuks@${infra_host} "sudo ksmanager ${qemu_kvm_hostname}" | tee -a /tmp/install-vm-logs-"${qemu_kvm_hostname}"

CURRENT_MAC_ADDRESS=$( grep "MAC Address  :"  /tmp/install-vm-logs-"${qemu_kvm_hostname}" | awk -F': ' '{print $2}' )

if [ -z ${CURRENT_MAC_ADDRESS} ]; then
	"Something went wrong while executing ksmanager, Please check in ${infra_host}"
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
  --noautoconsole \
  --machine q35 \
  --cpu host-model \
  --boot loader=/usr/share/edk2/ovmf/OVMF_CODE.fd,\
nvram.template=/usr/share/edk2/ovmf/OVMF_VARS.fd,\
nvram=/virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}_VARS.fd,\
menu=on \
  --pxe
