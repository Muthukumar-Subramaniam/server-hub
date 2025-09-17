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

infra_server_ipv4_address=$(cat /kvm-hub/ipv4-address-address-of-infra-server-vm)
infra_mgmt_super_username=$(cat /kvm-hub/infra-mgmt-super-username)
local_infra_domain_name=$(cat /kvm-hub/local_infra_domain_name)

ATTACH_CONSOLE="no"
qemu_kvm_hostname=""

# Fail fast if more than 2 args given
if [[ $# -gt 2 ]]; then
  echo "❌ Too many arguments."
  echo "ℹ️  Usage: $(basename $0) [hostname] [--console|-c]"
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --console|-c)
      if [[ "$ATTACH_CONSOLE" == "yes" ]]; then
        echo "❌ Duplicate --console/-c option."
        exit 1
      fi
      ATTACH_CONSOLE="yes"
      shift
      ;;
    --help|-h)
      echo "Usage: $(basename $0) [hostname] [--console|-c]"
      echo
      echo "Arguments:"
      echo "  hostname      Name of the VM to be installed (optional, will prompt if not given)"
      echo "  --console,-c  Attach console during install (optional, can appear before or after hostname)"
      exit 0
      ;;
    *)
      if [[ -z "$qemu_kvm_hostname" ]]; then
        qemu_kvm_hostname="$1"
      else
        echo "❌ Unexpected argument: $1"
        echo "ℹ️  Usage: $(basename $0) [hostname] [--console|-c]"
        exit 1
      fi
      shift
      ;;
  esac
done

# If hostname still not set, prompt
if [ -z "$qemu_kvm_hostname" ]; then
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

if [[ ! "${qemu_kvm_hostname}" =~ ^[a-z0-9-]+$ || "${qemu_kvm_hostname}" =~ ^- || "${qemu_kvm_hostname}" =~ -$ ]]; then
    echo -e "\n❌ VM hostname '$qemu_kvm_hostname' is invalid.\n"
    exit 1
fi

# Check if VM exists in 'virsh list --all'
if sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ VM \"$qemu_kvm_hostname\" exists already."
    echo "⚠️  Either do one of the following:"
    echo "   ➤ Remove the VM using 'kvm-remove', then try again."
    echo "   ➤ Re-image the VM using 'kvm-reimage-golden' or 'kvm-reimage-pxe'."
    exit 1
fi

echo -e "\n⚙️  Invoking ksmanager to create PXE environment for '${qemu_kvm_hostname}' . . .\n"


>/tmp/install-vm-logs-"${qemu_kvm_hostname}"

ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t ${infra_mgmt_super_username}@${infra_server_ipv4_address} "sudo ksmanager ${qemu_kvm_hostname}" --qemu-kvm | tee -a /tmp/install-vm-logs-"${qemu_kvm_hostname}"

MAC_ADDRESS=$( grep "MAC Address  :"  /tmp/install-vm-logs-"${qemu_kvm_hostname}" | awk -F': ' '{print $2}' | tr -d '[:space:]' )
IPV4_ADDRESS=$( grep "IPv4 Address :"  /tmp/install-vm-logs-"${qemu_kvm_hostname}" | awk -F': ' '{print $2}' | tr -d '[:space:]' )

if [ -z ${MAC_ADDRESS} ]; then
	echo -e "\n❌ Something went wrong while executing ksmanager ! "
	echo -e "🛠️ Please check your Infra Server VM at ${infra_server_ipv4_address} for the root cause. \n"
	exit 1
fi

mkdir -p /kvm-hub/vms/${qemu_kvm_hostname}

echo -n -e "\n📎 Updating hosts file for ${qemu_kvm_hostname}.${local_infra_domain_name} . . . "

echo "${IPV4_ADDRESS} ${qemu_kvm_hostname}.${local_infra_domain_name} ${qemu_kvm_hostname}" | sudo tee -a /etc/hosts &>/dev/null

echo -e "✅"

echo -n -e "\n📎 Creating alias '${qemu_kvm_hostname}' to assist with future SSH logins . . . "

echo "alias ${qemu_kvm_hostname}=\"ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${infra_mgmt_super_username}@${qemu_kvm_hostname}.${local_infra_domain_name}\"" >> /kvm-hub/ssh-assist-aliases-for-vms-on-qemu-kvm

source "${HOME}/.bashrc"

echo -e "✅"

echo -e "\n🚀 Starting installation of VM '${qemu_kvm_hostname}'...\n"

VIRT_INSTALL_CMD="sudo virt-install \
  --name ${qemu_kvm_hostname} \
  --features acpi=on,apic=on \
  --memory 2048 \
  --vcpus 2 \
  --disk path=/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2,size=20,bus=virtio,boot.order=1 \
  --os-variant almalinux9 \
  --network network=default,model=virtio,mac=${MAC_ADDRESS},boot.order=2 \
  --graphics none \
  --machine q35 \
  --cpu host-model \
  --boot loader=/usr/share/edk2/ovmf/OVMF_CODE.fd,\
nvram.template=/usr/share/edk2/ovmf/OVMF_VARS.fd,\
nvram=/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}_VARS.fd,menu=on"

if [ "$ATTACH_CONSOLE" = "yes" ]; then
  VIRT_INSTALL_CMD+=" --console pty,target_type=serial"
else
  VIRT_INSTALL_CMD+=" --noautoconsole"
fi

echo -e "\n🚀 Starting installation of VM '${qemu_kvm_hostname}' . . .\n"
eval "$VIRT_INSTALL_CMD"

if sudo virsh list | grep -q "${qemu_kvm_hostname}"; then
    if [ "$ATTACH_CONSOLE" != "yes" ]; then
        echo -e "\n✅ Successfully initiated installtion of VM ${qemu_kvm_hostname} ! "
	echo " It might take sometime for installation to complete and OS to get Ready."
        echo  " You could monitor the status with kvm-list."
        echo -e " If you want to access console, Run 'kvm-console ${qemu_kvm_hostname}'."
    else
	echo -e "\n✅ Successfully completed installation of VM ${qemu_kvm_hostname} ! "
    fi
else
    echo -e "\n❌ Failed to initiate installation of VM ${qemu_kvm_hostname} ! \n"
    echo "🔍 Please check what went wrong."
    echo
fi
