#!/bin/bash
ISO_DIR="/virtual-machines/iso-files"
ISO_NAME="AlmaLinux-10-latest-x86_64-dvd.iso"

if [[ "$EUID" -eq 0 ]]; then
    echo -e "\n⛔ Running as root user is not allowed."
    echo -e "\n🔐 This script should be run as a user who has sudo privileges, but *not* using sudo.\n"
    exit 1
fi

# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    echo "❌❌❌  FATAL: WRONG PLACE, BUDDY! ❌❌❌"
    echo -e "\n⚠️  Note:"
    echo -e "  🔹 This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo -e "  🔹 You’re currently inside a QEMU guest VM, which makes absolutely no sense.\n"
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

# Check for virt-install (part of qemu-kvm/libvirt package)
if ! command -v virt-install &> /dev/null; then
    echo -e "\n❌ virt-install command not found ! Please install and setup qemu-kvm first ! "
    echo -e "🛠️ To set up QEMU/KVM, please run the script \033[1msetup-qemu-kvm.sh\033[0m ! \n"
    exit 1
fi

# Check if base directory /virtual-machines exists
if [[ ! -d /virtual-machines ]]; then
    echo -e "\n❌ Directory /virtual-machines does not exist."
    echo "🚫 Seems like your qemu-kvm environment is not yet setup."
    echo -e "🛠️ To set up QEMU/KVM, please run the script \033[1msetup-qemu-kvm.sh\033[0m ! \n"
    exit 1
fi

# Check ISO File
if [[ ! -f "${ISO_DIR}/${ISO_NAME}" ]]; then
    echo -e "\n❌ ISO file ${ISO_DIR}/${ISO_NAME} not found."
    echo -e "⬇️ Please download the above ISO using the script \033[1mdownload-almalinux-latest.sh\033[0m\n"
    exit 1
fi

#Get Server Name
while true; do
  echo
  read -rp "⌨️  Enter your local Infra Server VM name [default: server]: " infra_server_name

  # If empty, use default
  if [[ -z "$infra_server_name" ]]; then
    infra_server_name="server"
    break
  fi

  # Minimum length check
  if [[ ${#infra_server_name} -lt 6 ]]; then
    echo -e "\n❌ Server name must be at least 6 characters long.\n"
    continue
  fi

  # Validate server name characters and hyphen position
  if [[ ! "$infra_server_name" =~ ^[a-z0-9-]+$ || "$infra_server_name" =~ ^- || "$infra_server_name" =~ -$ ]]; then
    echo -e "\n❌ Invalid hostname ! \n   🔹 Use only lowercase letters, numbers, and hyphens (-).\n   🔹 Also, must not start or end with a hyphen.\n"
    continue
  fi

  break
done


# Exit if VM disk file already exists
if [[ -f "/virtual-machines/${infra_server_name}/${infra_server_name}.qcow2" ]]; then
    echo -e "\n❌ VM disk file already exists at /virtual-machines/${infra_server_name}/${infra_server_name}.qcow2. Aborting to avoid overwrite.\n"
    exit 1
fi

# Prompt for valid lowercase-only username
while true; do
  echo
  read -rp "👤 Enter your local Infra Management username: " mgmt_super_user
  if [[ "$mgmt_super_user" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    break
  else
    echo -e "❌\n Invalid username. Only lowercase letters, numbers, hyphens, and underscores allowed. Must start with a letter.\n"
  fi
done

# Prompt for password, validate length, confirm match
while true; do
  echo
  read -s -p "🔒 Enter your local Infra Management password: " user_password
  echo
  if [[ -z "$user_password" ]]; then
    echo -e "\n❌ Password cannot be empty. Please try again.\n"
    continue
  elif [[ ${#user_password} -lt 8 ]]; then
    echo -e "\n⚠️  Warning: Password is less than 8 characters. Are you sure you want to proceed? (y/N): \n"
    read confirm_weak
    if [[ ! "$confirm_weak" =~ ^[Yy]$ ]]; then
      echo -e "\n❌ Aborting. Please enter a stronger password.\n"
      continue
    fi
  fi

  # Ask for confirmation
  echo
  read -s -p "🔒 Re-enter your local Infra Management password: " confirm_password
  echo
  if [[ "$user_password" != "$confirm_password" ]]; then
    echo -e "\n❌ Passwords do not match. Please try again.\n"
    continue
  fi

  # If everything checks out, break
  break
done

# Generate a random salt
salt=$(openssl rand -base64 6)

# Generate SHA-512 shadow-compatible hash
shadow_password_super_mgmt_user=$(openssl passwd -6 -salt "$salt" "$user_password")

echo -e -n "\n🌐 Capturing network info from QEMU-KVM default network bridge . . . "

qemu_kvm_default_net_info=$(sudo virsh net-dumpxml default)
ipv4_gateway=$(echo "$qemu_kvm_default_net_info" | awk -F"'" '/<ip address=/ {print $2}')
ipv4_netmask=$(echo "$qemu_kvm_default_net_info" | awk -F"'" '/<ip address=/ {print $4}')
ipv4_address=$(echo "$ipv4_gateway" | awk -F. '{ printf "%d.%d.%d.%d", $1, $2, $3, $4+1 }')

echo -e "✅"

# Print as a neat block
echo -e "\n📡 Your Management Infra Server's Network Info:"
echo    "============================================"
echo -e "  🌐 IPv4 Address : ${ipv4_address}"
echo -e "  🌐 IPv4 Netmask : ${ipv4_netmask}"
echo -e "  🌐 IPv4 Gateway : ${ipv4_gateway}"
echo    "============================================"

mkdir -p "/virtual-machines/${infra_server_name}"

KS_FILE="/virtual-machines/${infra_server_name}/${infra_server_name}_ks.cfg"
cp -f almalinux-template-ks.cfg "${KS_FILE}" 
sudo chown $USER:qemu "${KS_FILE}"
sed -i "s/get_ipv4_address/${ipv4_address}/g" "${KS_FILE}"
sed -i "s/get_ipv4_netmask/${ipv4_netmask}/g" "${KS_FILE}"
sed -i "s/get_ipv4_gateway/${ipv4_gateway}/g" "${KS_FILE}"
sed -i "s/get_mgmt_super_user/${mgmt_super_user}/g" "${KS_FILE}"
sed -i "s/get_infra_server_name/${infra_server_name}/g" "${KS_FILE}"

awk -v val="$shadow_password_super_mgmt_user" '
{
	gsub(/get_shadow_password_super_mgmt_user/, val)
}
1
' "${KS_FILE}" > "${KS_FILE}"_tmp_ksmanager && mv "${KS_FILE}"_tmp_ksmanager "${KS_FILE}"

echo -n -e "\n📦 Mounting ISP ${ISO_DIR}/${ISO_NAME} on /mnt/iso-for-${infra_server_name} for VM installation . . . "

sudo mkdir -p /mnt/iso-for-${infra_server_name}
sudo mount -o loop "${ISO_DIR}/${ISO_NAME}" /mnt/iso-for-${infra_server_name} &>/dev/null

echo -e "✅"

echo "$ipv4_address" >/virtual-machines/ipv4-address-address-of-infra-server-vm
echo "$mgmt_super_user" >/virtual-machines/infra-mgmt-super-username

echo -e "\n📎 Creating alias '${infra_server_name}' to assist with future SSH logins...\n"

sed -i "/${ipv4_address}/d" $HOME/.bashrc

echo -e "\nalias ${infra_server_name}=\"ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${mgmt_super_user}@${ipv4_address}\"" >> $HOME/.bashrc

source $HOME/.bashrc

echo -e "✅"

echo -e "\n🚀 Buckle up ! We are about to view the Infra Server VM (${infra_server_name}) deployment from console ! \n"

sudo virt-install \
  --name ${infra_server_name} \
  --features acpi=on,apic=on \
  --memory 2048 \
  --vcpus 2 \
  --disk path=/virtual-machines/${infra_server_name}/${infra_server_name}.qcow2,size=30,bus=virtio \
  --disk path="$ISO_DIR/$ISO_NAME",device=cdrom,bus=sata \
  --os-variant almalinux9 \
  --network network=default,model=virtio \
  --initrd-inject="${KS_FILE}" \
  --location "/mnt/iso-for-${infra_server_name}" \
  --extra-args "inst.ks=file:/${infra_server_name}_ks.cfg inst.stage2=cdrom inst.repo=cdrom console=ttyS0 nomodeset inst.text quiet" \
  --graphics none \
  --console pty,target_type=serial \
  --machine q35 \
  --cpu host-model \
  --boot loader=/usr/share/edk2/ovmf/OVMF_CODE.fd,\
nvram.template=/usr/share/edk2/ovmf/OVMF_VARS.fd,\
nvram=/virtual-machines/${infra_server_name}/${infra_server_name}_VARS.fd,menu=on \

if sudo virsh list | grep -q "${infra_server_name}"; then
	echo -e "\n✅ Successfully deployed your Infra Server VM (${infra_server_name}) !\n"
else
	echo -e "\n❌ Failed to deploy your Infra Server VM (${infra_server_name})!\n🔍 Please check where it went wrong.\n"
fi

sudo umount -l /mnt/iso-for-${infra_server_name} &>/dev/null

exit
