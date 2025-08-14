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

infra_server_ipv4_address=$(cat /virtual-machines/ipv4-address-address-of-infra-server-vm)
infra_mgmt_super_username=$(cat /virtual-machines/infra-mgmt-super-username)
local_infra_domain_name=$(cat /virtual-machines/local_infra_domain_name)

# Use first argument or prompt for hostname
if [ -n "$1" ]; then
    qemu_kvm_hostname="$1"
else
    echo
    read -p "🖥️  Please enter the hostname of the VM to be installed : " qemu_kvm_hostname
    if [[ -n "${KVM_TOOL_EXECUTED_FROM:-}" && "${KVM_TOOL_EXECUTED_FROM}" == "${qemu_kvm_hostname}" ]]; then
	echo -e "\n❌ This operation is not allowed to avoid self-referential KVM actions that could destabilize the infra server."
    	echo -e "⚠️ Note:"
	echo -e "  🔹 You are running a KVM management related action for the lab infra server from the infra server itself."
	echo -e "  🔹 If you still need to perform this operation, you need to do this from the Linux workstation running the QEMU/KVM setup.\n"
	exit 1
    fi
fi

# Check if VM exists in 'virsh list --all'
if sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ VM \"$qemu_kvm_hostname\" exists already."
    echo "⚠️  Either do one of the following:"
    echo "   ➤ Remove the VM using 'kvm-remove', then try again."
    echo "   ➤ Re-image the VM using 'kvm-reimage-golden' or 'kvm-reimage-pxe'."
    exit 1
fi

echo -e "\n⚙️  Invoking ksmanager to create first boot environment for '${qemu_kvm_hostname}' . . .\n"


>/tmp/install-vm-logs-"${qemu_kvm_hostname}"

ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t ${infra_mgmt_super_username}@${infra_server_ipv4_address} "sudo ksmanager ${qemu_kvm_hostname}" --qemu-kvm --golden-image | tee -a /tmp/install-vm-logs-"${qemu_kvm_hostname}"

MAC_ADDRESS=$( grep "MAC Address  :"  /tmp/install-vm-logs-"${qemu_kvm_hostname}" | awk -F': ' '{print $2}' | tr -d '[:space:]' )
IPV4_ADDRESS=$( grep "IPv4 Address :"  /tmp/install-vm-logs-"${qemu_kvm_hostname}" | awk -F': ' '{print $2}' | tr -d '[:space:]' )
OS_DISTRO=$( grep "Requested OS :"  /tmp/install-vm-logs-"${qemu_kvm_hostname}" | awk -F': ' '{print $2}' | tr -d '[:space:]' )

if echo "$OS_DISTRO" | grep -qi "almalinux"; then
    OS_DISTRO="almalinux"
elif echo "$OS_DISTRO" | grep -qi "centos"; then
    OS_DISTRO="centos-stream"
elif echo "$OS_DISTRO" | grep -qi "rocky"; then
    OS_DISTRO="rocky"
elif echo "$OS_DISTRO" | grep -qi "oracle"; then
    OS_DISTRO="oraclelinux"
elif echo "$OS_DISTRO" | grep -qi "redhat"; then
    OS_DISTRO="rhel"
elif echo "$OS_DISTRO" | grep -qi "fedora"; then
    OS_DISTRO="fedora"
elif echo "$OS_DISTRO" | grep -qi "ubuntu"; then
    OS_DISTRO="ubuntu-lts"
elif echo "$OS_DISTRO" | grep -qi "suse"; then
    OS_DISTRO="opensuse-leap"
fi

if [ -z ${MAC_ADDRESS} ]; then
	echo -e "\n❌ Something went wrong while executing ksmanager ! "
	echo -e "🛠️ Please check your Infra Server VM at ${infra_server_ipv4_address} for the root cause. \n"
	exit 1
fi

mkdir -p /virtual-machines/${qemu_kvm_hostname}

echo -n -e "\n📎 Updating hosts file for ${qemu_kvm_hostname}.${local_infra_domain_name} . . . "

sudo sed -i "/${qemu_kvm_hostname}.${local_infra_domain_name}/d" /etc/hosts

echo "${IPV4_ADDRESS} ${qemu_kvm_hostname}.${local_infra_domain_name} ${qemu_kvm_hostname}" | sudo tee -a /etc/hosts &>/dev/null

echo -e "✅"

echo -n -e "\n📎 Creating alias '${qemu_kvm_hostname}' to assist with future SSH logins . . . "

sed -i "/${qemu_kvm_hostname}.${local_infra_domain_name}/d" /virtual-machines/ssh-assist-aliases-for-vms-on-qemu-kvm

echo "alias ${qemu_kvm_hostname}=\"ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${infra_mgmt_super_username}@${qemu_kvm_hostname}.${local_infra_domain_name}\"" >> /virtual-machines/ssh-assist-aliases-for-vms-on-qemu-kvm

source "${HOME}/.bashrc"

echo -e "✅"

if [ ! -f /virtual-machines/golden-images-disk-store/${OS_DISTRO}-golden-image.qcow2 ]; then
	echo -e "\n🚫 Golden Image Disk Not Found ! "
	echo -e "➡️  Expected at: /virtual-machines/golden-images-disk-store/${OS_DISTRO}-golden-image.qcow2"
	echo -e "🛠️ To build the golden image disk, run: \e[1;32mkvm-build-golden-qcow2-disk\e[0m\n"
	exit
fi

echo -n -e "\n🚀 Copy golden image disk /virtual-machines/golden-images-disk-store/${OS_DISTRO}-golden-image.qcow2 to install '${qemu_kvm_hostname}' . . . "

sudo cp -p /virtual-machines/golden-images-disk-store/${OS_DISTRO}-golden-image.qcow2 /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2

echo -e "✅"

echo -e "\n🚀 Starting installation of VM '${qemu_kvm_hostname}' . . .\n"

sudo virt-install \
  --name ${qemu_kvm_hostname} \
  --features acpi=on,apic=on \
  --memory 2048 \
  --vcpus 2 \
  --disk path=/virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2,bus=virtio,boot.order=1 \
  --os-variant almalinux9 \
  --network network=default,model=virtio,mac=${MAC_ADDRESS},boot.order=2 \
  --graphics none \
  --console pty,target_type=serial \
  --machine q35 \
  --cpu host-model \
  --boot loader=/usr/share/edk2/ovmf/OVMF_CODE.fd,\
nvram.template=/usr/share/edk2/ovmf/OVMF_VARS.fd,\
nvram=/virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}_VARS.fd,menu=on \

if sudo virsh list | grep -q "${qemu_kvm_hostname}"; then
    echo -e "\n✅ Successfully installed the VM ${qemu_kvm_hostname} ! \n"
else
    echo -e "\n❌ Failed to install the VM ${qemu_kvm_hostname} ! \n"
    echo "🔍 Please check what went wrong."
    echo
fi
