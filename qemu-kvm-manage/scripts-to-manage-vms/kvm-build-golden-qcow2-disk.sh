#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh

# Check if any arguments are passed
if [ "$#" -ne 0 ]; then
    echo -e "\n❌ $(basename $0) does not take any arguments.\n"
    exit 1
fi

echo -e "\n⚙️  Invoking ksmanager to create PXE environment to build a golden image . . .\n"

>/tmp/kvm-build-golden-qcow2-disk.log

if $lab_infra_server_mode_is_host; then
    sudo ksmanager ${qemu_kvm_hostname} --qemu-kvm --create-golden-image | tee -a /tmp/kvm-build-golden-qcow2-disk.log
else
    ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "sudo ksmanager ${qemu_kvm_hostname}" --qemu-kvm --create-golden-image | tee -a /tmp/kvm-build-golden-qcow2-disk.log
fi

MAC_ADDRESS=$( grep "MAC Address  :"  /tmp/kvm-build-golden-qcow2-disk.log | awk -F': ' '{print $2}' | tr -d '[:space:]' )
qemu_kvm_hostname=$( grep "Hostname     :"  /tmp/kvm-build-golden-qcow2-disk.log | awk -F': ' '{print $2}' | tr -d '[:space:]' | cut -d "." -f 1 )

if [ -z ${MAC_ADDRESS} ]; then
	echo -e "\n❌ Something went wrong while executing ksmanager ! "
	echo -e "🛠️ Please check your Lab Infra Server for the root cause. \n"
	exit 1
fi

mkdir -p /kvm-hub/golden-images-disk-store

golden_image_path="/kvm-hub/golden-images-disk-store/${qemu_kvm_hostname}.qcow2"

# ✅ Check if golden image already exists
if [ -f "${golden_image_path}" ]; then
    echo -e "\n⚠️  Golden image '${qemu_kvm_hostname}' already exists ! \n"
    read -p "Do you want to delete and recreate it? [yes/NO]: " answer
    case "$answer" in
        yes|YES)
            echo -e "\n🗑️  Deleting existing golden image..."
            sudo rm -f "${golden_image_path}"
            ;;
        * )
            echo -e "\n✅ Keeping existing golden image '${qemu_kvm_hostname}'. Exiting... \n"
            exit 0
            ;;
    esac
fi

echo -e "\n🚀 Starting installation of VM '${qemu_kvm_hostname}' to create golden image disk . . .\n"

sudo virt-install \
  --name ${qemu_kvm_hostname} \
  --features acpi=on,apic=on \
  --memory 2048 \
  --vcpus 2 \
  --disk path=${golden_image_path},size=20,bus=virtio,boot.order=1 \
  --os-variant almalinux9 \
  --network network=default,model=virtio,mac=${MAC_ADDRESS},boot.order=2 \
  --graphics none \
  --watchdog none \
  --console pty,target_type=serial \
  --machine q35 \
  --cpu host-model \
  --boot loader=${OVMF_CODE_PATH},\
nvram.template=${OVMF_VARS_PATH},\
nvram=/kvm-hub/golden-images-disk-store/${qemu_kvm_hostname}_VARS.fd,menu=on \

sudo virsh destroy "${qemu_kvm_hostname}" 2>/dev/null
sudo virsh undefine "${qemu_kvm_hostname}" --nvram 2>/dev/null

echo -e "\n✅ Successfully created golden image disk ${golden_image_path} ! \n"
