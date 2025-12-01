#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
DIR_PATH_SCRIPTS_TO_MANAGE_VMS='/server-hub/qemu-kvm-manage/scripts-to-manage-vms'

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
      echo "  hostname      Name of the VM to be reimaged (optional, will prompt if not given)"
      echo "  --console,-c  Attach console during reimage (optional, can appear before or after hostname)"
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
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$qemu_kvm_hostname"

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

# Prevent re-imaging of lab infra server VM
if [[ "$qemu_kvm_hostname" == "$lab_infra_server_hostname" ]]; then
    echo "❌❌❌  FATAL ERROR: Cannot Re-image Lab Infra Server! ❌❌❌"
    echo "You are attempting to re-image the lab infrastructure server VM: $lab_infra_server_hostname"
    echo "This VM hosts the critical services required for re-imaging operations."
    echo "All essential lab services run on this VM and must not be destroyed."
    exit 1
else
    echo -e "\n⚠️  WARNING: This will re-image VM \"$qemu_kvm_hostname\" using golden image!"
    echo -e "    All existing data on this VM will be permanently lost.\n"
    read -rp "❓ Are you sure you want to proceed? (yes/[no]): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        echo -e "\n⛔ Aborted.\n"
        exit 1
    fi
fi

echo -e "\n⚙️  Creating first boot environment for '${qemu_kvm_hostname}' using ksmanager...\n"


>/tmp/reimage-vm-logs-"${qemu_kvm_hostname}"

if $lab_infra_server_mode_is_host; then
    sudo ksmanager ${qemu_kvm_hostname} --qemu-kvm --golden-image | tee -a /tmp/reimage-vm-logs-"${qemu_kvm_hostname}"
else
    ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "sudo ksmanager ${qemu_kvm_hostname} --qemu-kvm --golden-image" | tee -a /tmp/reimage-vm-logs-"${qemu_kvm_hostname}"
fi

IPV4_ADDRESS=$( grep "IPv4 Address :"  /tmp/reimage-vm-logs-"${qemu_kvm_hostname}" | awk -F': ' '{print $2}' | tr -d '[:space:]' )
OS_DISTRO=$( grep "Requested OS :"  /tmp/reimage-vm-logs-"${qemu_kvm_hostname}" | awk -F': ' '{print $2}' | tr -d '[:space:]' )
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

if [ -z "${IPV4_ADDRESS}" ]; then
	echo -e "\n❌ Error: Failed to execute ksmanager successfully!"
	echo -e "🛠️  Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details.\n"
	exit 1
fi

echo -n -e "\n📋 Updating /etc/hosts file for ${qemu_kvm_hostname}..."

if grep -q "${qemu_kvm_hostname}" /etc/hosts; then
    HOST_FILE_IPV4=$( grep "${qemu_kvm_hostname}" /etc/hosts | awk '{print $1}' )
    if [ "${HOST_FILE_IPV4}" != "${IPV4_ADDRESS}" ]; then
        sudo sed -i.bak "/${qemu_kvm_hostname}/s/.*/${IPV4_ADDRESS} ${qemu_kvm_hostname}/" /etc/hosts
    fi
else
    echo "${IPV4_ADDRESS} ${qemu_kvm_hostname}" | sudo tee -a /etc/hosts &>/dev/null
fi

echo -e "✅"

if [ ! -f /kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2 ]; then
	echo -e "\n❌ Golden image disk not found!"
	echo -e "📂 Expected at: /kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2"
	echo -e "🛠️  To build the golden image disk, run: \e[1;32mkvm-build-golden-qcow2-disk\e[0m\n"
	exit 1
fi

# If VM is running, stop it first
if sudo virsh list  | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "ℹ️  VM \"$qemu_kvm_hostname\" is currently running. Shutting down before re-imaging..."
    sudo virsh destroy "${qemu_kvm_hostname}" 2>/dev/null
    echo "✅ VM \"$qemu_kvm_hostname\" has been shut down successfully."
fi

# Re-image by replacing qcow2 disk with golden image disk
echo -e "\n⚙️  Re-imaging VM \"$qemu_kvm_hostname\" by replacing its qcow2 disk with the golden image disk...\n"
vm_qcow2_disk_path="/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2"
current_disk_gib=$(sudo qemu-img info "${vm_qcow2_disk_path}" 2>/dev/null | grep "virtual size" | grep -o '[0-9]\+ GiB' | cut -d' ' -f1)
golden_qcow2_disk_path="/kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2"
golden_disk_gib=$(sudo qemu-img info "${golden_qcow2_disk_path}" 2>/dev/null | grep "virtual size" | grep -o '[0-9]\+ GiB' | cut -d' ' -f1)

# Use default if disk doesn't exist or size extraction failed
default_qcow2_disk_gib=20
if [[ -z "$current_disk_gib" ]]; then
    current_disk_gib="$default_qcow2_disk_gib"
fi
if [[ -z "$golden_disk_gib" ]]; then
    golden_disk_gib="$default_qcow2_disk_gib"
fi

# Delete existing qcow2 disk and recreate with appropriate size
sudo rm -f "${vm_qcow2_disk_path}"
sudo qemu-img convert -O qcow2 "${golden_qcow2_disk_path}" "${vm_qcow2_disk_path}"
if [[ "$current_disk_gib" -gt "$golden_disk_gib" ]]; then
    sudo qemu-img resize "${vm_qcow2_disk_path}" "${current_disk_gib}G"
    echo "✅ Retained disk size of ${current_disk_gib} GiB for VM \"$qemu_kvm_hostname\"." 
fi

# Start re-imaging process
echo -e "\n⚙️  Starting re-imaging of VM \"$qemu_kvm_hostname\" via golden image disk...\n"
sudo virsh start "${qemu_kvm_hostname}" 2>/dev/null

if [[ "$ATTACH_CONSOLE" == "yes" ]]; then
    echo -e "\nℹ️  Attaching to VM console. Press Ctrl+] to exit console.\n"
    echo "ℹ️  The VM may take a minute to fully boot up and configure via golden image disk."
    echo "ℹ️  The VM may reboot once or twice during the re-imaging process."
    sudo virsh console "${qemu_kvm_hostname}"
else
    echo -e "\n✅ VM \"$qemu_kvm_hostname\" is now re-imaging via golden image disk."
    echo "ℹ️  The VM may take a minute to fully boot up and configure."
    echo "ℹ️  The VM may reboot once or twice during the re-imaging process."
    echo "ℹ️  To monitor re-imaging progress, use: kvm-console $qemu_kvm_hostname"
    echo "ℹ️  To check VM status, use: kvm-list"
fi




