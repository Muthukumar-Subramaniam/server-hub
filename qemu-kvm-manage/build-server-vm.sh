#!/bin/bash
ISO_DIR="/virtual-machines/iso-files"
ISO_NAME="AlmaLinux-10-latest-x86_64-dvd.iso"
# Check for virt-install (part of qemu-kvm/libvirt package)
if ! command -v virt-install &> /dev/null; then
    echo "❌ virt-install command not found! Please install and setup qemu-kvm first! "
    exit 1
fi

# Check if base directory /virtual-machines exists
if [[ ! -d /virtual-machines ]]; then
    echo "❌ Directory /virtual-machines does not exist."
    echo "🚫 Seems like your qemu-kvm environment is not yet setup."
    exit 1
fi

# Check ISO File
if [[ ! -f "${ISO_DIR}/${ISO_NAME}" ]]; then
    echo "❌ ISO file ${ISO_DIR}/${ISO_NAME} not found."
    echo "Please download the above ISO using script download-almalinux-latest.sh"
    exit 1
fi

#Get Server Name
while true; do
  echo "(Note: same name will be used as hostname)"
  read -rp "Enter Your Local Infra Server VM Name [default: server]: " infra_server_name

  # If empty, use default
  if [[ -z "$infra_server_name" ]]; then
    infra_server_name="server"
    break
  fi

  # Minimum length check
  if [[ ${#infra_server_name} -lt 6 ]]; then
    echo "❌ Server name must be at least 6 characters long."
    continue
  fi

  # Allowed characters and hyphen position check
  if [[ ! "$infra_server_name" =~ ^[a-z0-9-]+$ ]]; then
    echo "❌ Only lowercase letters, numbers, and hyphens (-) are allowed."
    continue
  fi

  if [[ "$infra_server_name" =~ ^- || "$infra_server_name" =~ -$ ]]; then
    echo "❌ Server name cannot start or end with a hyphen (-)."
    continue
  fi

  break
done


# Exit if VM disk file already exists
if [[ -f "/virtual-machines/${infra_server_name}/${infra_server_name}.qcow2" ]]; then
    echo "❌ VM disk file already exists at /virtual-machines/${infra_server_name}/${infra_server_name}.qcow2. Aborting to avoid overwrite."
    exit 1
fi

# Prompt for valid lowercase-only username
while true; do
  read -p "Enter Your Local Infra Management Username: " mgmt_super_user
  if [[ "$mgmt_super_user" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    break
  else
    echo "❌ Invalid username. Only lowercase letters, numbers, hyphens, and underscores allowed. Must start with a letter."
  fi
done

# Prompt for password, validate length, confirm match
while true; do
  read -s -p "Enter Your Local Infra Management Password: " user_password
  echo
  if [[ -z "$user_password" ]]; then
    echo "❌ Password cannot be empty. Please try again."
    continue
  elif [[ ${#user_password} -lt 8 ]]; then
    echo -n "⚠️  Warning: Password is less than 8 characters. Are you sure you want to proceed? (y/N): "
    read confirm_weak
    if [[ ! "$confirm_weak" =~ ^[Yy]$ ]]; then
      echo "❌ Aborting. Please enter a stronger password."
      continue
    fi
  fi

  # Ask for confirmation
  read -s -p "Confirm Your Local Infra Management Password: " confirm_password
  echo
  if [[ "$user_password" != "$confirm_password" ]]; then
    echo "❌ Passwords do not match. Please try again."
    continue
  fi

  # If everything checks out, break
  break
done

# Generate a random salt
salt=$(openssl rand -base64 6)

# Generate SHA-512 shadow-compatible hash
shadow_password_super_mgmt_user=$(openssl passwd -6 -salt "$salt" "$user_password")

echo -n "Capturing Network Info from QEMU-KVM default Network Bridge . . ."

qemu_kvm_default_net_info=$(sudo virsh net-dumpxml default)
ipv4_gateway=$(echo "$qemu_kvm_default_net_info" | awk -F"'" '/<ip address=/ {print $2}')
ipv4_netmask=$(echo "$qemu_kvm_default_net_info" | awk -F"'" '/<ip address=/ {print $4}')
ipv4_address=$(echo "$ipv4_gateway" | awk -F. '{ printf "%d.%d.%d.%d", $1, $2, $3, $4+1 }')

echo "[ done ]"

# Print as a neat block
echo "Your Management Infra Server's Network Info :"
echo "============================================"
echo "  IP Address : $ipv4_address"
echo "  Netmask    : $ipv4_netmask"
echo "  Gateway    : $ipv4_gateway"
echo "============================================="

#sudo mkdir -p /virtual-machines
#sudo chown -R $USER:qemu /virtual-machines
#chmod -R g+s /virtual-machines
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

echo -e "\nBuckle Up! We are going to deploy the server VM ( ${infra_server_name} ) . . . \n"

echo -e "Mount ISP $ISO_DIR/$ISO_NAME on /mnt/iso-for-${infra_server_name} for VM installation . . ."
sudo mkdir /mnt/iso-for-${infra_server_name}
sudo mount -o loop "${ISO_DIR}/${ISO_NAME}" /mnt/iso-for-${infra_server_name}

echo "$ipv4_address" >/virtual-machines/ipv4-address-address-of-infra-server-vm
echo "$mgmt_super_user" >/virtual-machines/infra-mgmt-super-username

sudo virt-install \
  --name ${infra_server_name} \
  --features acpi=on,apic=on \
  --memory 4096 \
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
	echo -e "\nSuccessfully depoyed your infra server VM ( ${infra_server_name} ) running on qemu-kvm ! \n" 
else
	echo -e "\nFailed to depoy your infra server VM ( ${infra_server_name} ) on qemu-kvm ! Please check where it went wrong\n !" 
fi
