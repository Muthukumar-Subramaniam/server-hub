#!/usr/bin/env bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#
# Script Name : deploy_lab_infra_server.sh
# Description : Interactive script to deploy the Lab Infra Server
#               on either a dedicated KVM VM or directly on the KVM host.

# Disallow running as root
if [[ "$EUID" -eq 0 ]]; then
  echo -e "\n⛔  Running as root user is not allowed."
  echo -e "\n🔐  Please run this script as a regular user with sudo privileges,"
  echo -e "    but *not* using sudo directly.\n"
  exit 1
fi

# Disallow running inside a QEMU guest
if sudo dmidecode -s system-manufacturer 2>/dev/null | grep -qi 'QEMU'; then
  echo -e "\n❌❌❌  FATAL: WRONG PLACE, BUDDY! ❌❌❌"
  echo -e "\n⚠️  Note:"
  echo -e "  🔹 This script must be run on the *host* system managing QEMU/KVM VMs."
  echo -e "  🔹 You're currently inside a QEMU guest VM — aborting before chaos ensues.\n"
  echo "💥  ABORTING EXECUTION 💥"
  exit 1
fi

set -euo pipefail
IFS=$'\n\t'

prepare_lab_infra_config() {
  echo ""
  echo "🧰  Preparing general Lab Infra configuration..."
  echo "🔧 Common configuration steps go here..."
  # Pre-flight environment checks
  if ! command -v virt-install &>/dev/null; then
    echo -e "\n❌ 'virt-install' command not found!"
    echo -e "🛠️  Please install and set up QEMU/KVM first."
    echo -e "➡️  Run the script \033[1msetup-qemu-kvm.sh\033[0m to configure your environment.\n"
    exit 1
  fi

  if [[ ! -d /kvm-hub ]]; then
    echo -e "\n❌ Directory /kvm-hub does not exist."
    echo "🚫 Seems like your QEMU/KVM environment is not yet setup."
    echo -e "🛠️  Run the script \033[1msetup-qemu-kvm.sh\033[0m to configure your environment.\n"
    exit 1
  fi

  echo -e "\n✅ Pre-flight checks passed: QEMU/KVM environment is ready."

  # Get Infra Server VM Name
  while true; do
    echo
    read -rp "⌨️  Enter your local Infra Server VM name [default: lab-infra-server]: " lab_infra_server_shortname

    if [[ -z "$lab_infra_server_shortname" ]]; then
      lab_infra_server_shortname="lab-infra-server"
      break
    fi

    if [[ ${#lab_infra_server_shortname} -lt 6 ]]; then
      echo -e "\n❌ Server name must be at least 6 characters long.\n"
      continue
    fi

    if [[ ! "$lab_infra_server_shortname" =~ ^[a-z0-9-]+$ || "$lab_infra_server_shortname" =~ ^- || "$lab_infra_server_shortname" =~ -$ ]]; then
      echo -e "\n❌ Invalid hostname!"
      echo -e "   🔹 Use only lowercase letters, numbers, and hyphens (-)."
      echo -e "   🔹 Must not start or end with a hyphen.\n"
      continue
    fi

    break
  done

  echo -e "\n✅ Using Lab Infra Server name: \033[1m${lab_infra_server_shortname}\033[0m"
  echo ""

  lab_infra_admin_username="$USER"
  echo -e "\n👤 Using current user '${lab_infra_admin_username}' as Lab Infra Global user. '\n"

  # Prompt for password, validate length, confirm match
  while true; do
    echo
    read -s -p "🔒 Enter your Lab Infra Global password: " lab_admin_password_plain
    echo
    if [[ -z "$lab_admin_password_plain" ]]; then
      echo -e "\n❌ Password cannot be empty. Please try again.\n"
      continue
    elif [[ ${#lab_admin_password_plain} -lt 8 ]]; then
      echo -e "\n⚠️  Warning: Password is less than 8 characters ! \n"
      read -rp "❓ Are you sure you want to proceed? (y/n): " confirm_weak
      if [[ ! "$confirm_weak" =~ ^[Yy]$ ]]; then
        echo -e "\n❌ Aborting. Please enter a stronger password.\n"
        continue
      fi
    fi

    echo
    read -s -p "🔒 Re-enter your Lab Infra Global password: " confirm_password
    echo
    if [[ "$lab_admin_password_plain" != "$confirm_password" ]]; then
      echo -e "\n❌ Passwords do not match. Please try again.\n"
      continue
    fi

    break
  done

  # Generate a random salt for the lab admin password
  lab_admin_password_salt=$(openssl rand -base64 6)

  # Generate SHA-512 shadow-compatible hash
  lab_admin_shadow_password=$(openssl passwd -6 -salt "$lab_admin_password_salt" "$lab_admin_password_plain")

  echo -e "\n✅ Infra Management user credentials are ready for user: \033[1m${lab_infra_admin_username}\033[0m\n"

  # Function to instruct user on valid domain names
  fn_instruct_on_valid_domain_name() {
    echo -e "\n📘 \e[1mDomain Name Rules:\e[0m
  ─────────────────────────────
  🔹 Only allowed TLD:          \e[1mlocal\e[0m
  🔹 Max subdomains allowed:    \e[1m2\e[0m
  🔹 Allowed characters:        Letters (a-z), digits (0-9), and hyphens (-)
  🔹 Hyphens:                   Cannot be at the start or end of subdomains
  🔹 Total length:              Must be between \e[1m1\e[0m and \e[1m63\e[0m characters
  🔹 Format compliance:         Based on \e[3mRFC 1035\e[0m

  💡 \e[1mExamples of valid domain names:\e[0m
     ▪️ test.local
     ▪️ test.example.local
     ▪️ 123-example.local
     ▪️ test-lab1.local
     ▪️ 123.example.local
     ▪️ test1.lab1.local
     ▪️ test-1.example-1.local
"
  }

  # Prompt user for local infra domain name
  while true; do
    echo
    fn_instruct_on_valid_domain_name
    echo
    read -rp "🌐 Enter your local Infra Domain Name [default: lab.local]: " lab_infra_domain_name

    # Use default if empty
    if [[ -z "${lab_infra_domain_name}" ]]; then
      lab_infra_domain_name="lab.local"
    fi

    # Validate domain length and pattern
    if [[ "${#lab_infra_domain_name}" -le 63 ]] && \
       [[ "${lab_infra_domain_name}" =~ ^[[:alnum:]]+([-.][[:alnum:]]+)*(\.[[:alnum:]]+){0,2}\.local$ ]]; then
      break
    else
      echo -e "\n❌ Invalid domain name. Please follow the rules above.\n"
    fi
  done

  # Print the final validated domain name
  echo -e "\n✅ Lab Infra Domain Name set to: \033[1m${lab_infra_domain_name}\033[0m\n"

  # SSH public key logic
  echo -e "\n🔍 Checking for SSH public key on local workstation . . ."

  SSH_DIR="$HOME/.ssh"
  SSH_PUB_KEY_FILE="$SSH_DIR/id_rsa.pub"

  # Ensure ~/.ssh directory exists
  if [[ ! -d "$SSH_DIR" ]]; then
      echo -e "\n📁 .ssh directory not found. Creating..."
      mkdir -p "$SSH_DIR"
      chmod 700 "$SSH_DIR"
  fi

  # Check if SSH public key exists
  if [[ ! -f "$SSH_PUB_KEY_FILE" ]]; then
      echo -e "\n❌ SSH key not found on this local workstation."
      echo -e "\n🔐 Generating a new RSA key pair . . ."
      ssh-keygen -t rsa -b 4096 -N "" -f "$SSH_DIR/id_rsa" -C "${lab_infra_admin_username}@${lab_infra_domain_name}" &>/dev/null
      echo -e "\n✅ New SSH key generated: $SSH_PUB_KEY_FILE"
  else
      echo -e "\n✅ SSH public key already exists: $SSH_PUB_KEY_FILE"
  fi

  # Read the public key into an explanatory variable
  lab_infra_ssh_public_key=$(<"$SSH_PUB_KEY_FILE")

  # Print confirmation
  echo -e "\n✅ Lab Infra SSH public key is ready for user \033[1m${lab_infra_admin_username}\033[0m on domain \033[1m${lab_infra_domain_name}\033[0m:\n\033[1m${lab_infra_ssh_public_key}\033[0m\n"

  # Capture network info from QEMU-KVM default bridge
  echo -e -n "\n🌐 Capturing network info from QEMU-KVM default network bridge . . . "

  qemu_kvm_default_net_info=$(sudo virsh net-dumpxml default)
  lab_infra_server_ipv4_gateway=$(echo "$qemu_kvm_default_net_info" | awk -F"'" '/<ip address=/ {print $2}')
  lab_infra_server_ipv4_netmask=$(echo "$qemu_kvm_default_net_info" | awk -F"'" '/<ip address=/ {print $4}')
  lab_infra_server_ipv4_address=$(echo "$lab_infra_server_ipv4_gateway" | awk -F. '{ printf "%d.%d.%d.%d", $1, $2, $3, $4+1 }')

  echo -e "✅\n"

  # Print captured network information in user-friendly format
  echo -e "🌐 Lab Network Information:"
  echo -e "   🔹 Lab Infra Server IPv4 Gateway : \033[1m${lab_infra_server_ipv4_gateway}\033[0m"
  echo -e "   🔹 Lab Infra Server Netmask      : \033[1m${lab_infra_server_ipv4_netmask}\033[0m"
  echo -e "   🔹 Lab Infra Server IPv4 Address : \033[1m${lab_infra_server_ipv4_address}\033[0m\n"

  # Update SSH Custom Config
  echo -n -e "\n📎 Updating SSH Custom Config for '${lab_infra_domain_name}' domain to assist with future SSH logins . . . "

  SSH_CUSTOM_CONFIG_FILE="$HOME/.ssh/config.custom"
  [[ ! -f "$SSH_CUSTOM_CONFIG_FILE" ]] && touch "$SSH_CUSTOM_CONFIG_FILE"

  if ! grep -q "$lab_infra_domain_name" "$SSH_CUSTOM_CONFIG_FILE"; then
    cat <<EOF >> "$SSH_CUSTOM_CONFIG_FILE"
Host *.${lab_infra_domain_name} ${lab_infra_server_ipv4_address}
    User ${lab_infra_admin_username}
    IdentityFile ~/.ssh/id_rsa
    ServerAliveInterval 60
    ServerAliveCountMax 30
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel QUIET
EOF
  fi

  echo -e " ✅ SSH Custom Config updated.\n"

  echo -n -e "\n📎 Updating /etc/hosts for ${lab_infra_server_shortname}.${lab_infra_domain_name} . . . "

  # Remove any existing entry
  sudo sed -i "/${lab_infra_server_shortname}.${lab_infra_domain_name}/d" /etc/hosts 

  # Add new entry
  echo "${lab_infra_server_ipv4_address} ${lab_infra_server_shortname}.${lab_infra_domain_name} ${lab_infra_server_shortname}" | sudo tee -a /etc/hosts &>/dev/null

  echo -e " ✅ /etc/hosts updated successfully with ${lab_infra_server_shortname}.${lab_infra_domain_name} .\n"


  # Save all lab environment variables to file
  LAB_ENV_VARS_FILE="/kvm-hub/lab_environment_vars"

  echo -e "💾 Saving Lab Environment variables to: $LAB_ENV_VARS_FILE ..."

cat > "$LAB_ENV_VARS_FILE" <<EOF
lab_infra_server_shortname="${lab_infra_server_shortname}"
lab_infra_domain_name="${lab_infra_domain_name}"
lab_infra_admin_username="${lab_infra_admin_username}"
lab_admin_shadow_password='${lab_admin_shadow_password}'
lab_infra_ssh_public_key='${lab_infra_ssh_public_key}'
lab_infra_server_ipv4_gateway="${lab_infra_server_ipv4_gateway}"
lab_infra_server_ipv4_netmask="${lab_infra_server_ipv4_netmask}"
lab_infra_server_ipv4_address="${lab_infra_server_ipv4_address}"
EOF

  echo -e "✅ Lab environment variables saved successfully.\n"

}

#-------------------------------------------------------------
# Deployment mode functions
#-------------------------------------------------------------
deploy_lab_infra_server_vm() {
  echo ""
  prepare_lab_infra_config
  echo "🖥️  Starting deployment of lab infra server on a dedicated VM..."
  echo ""
  # ISO setup
  ISO_DIR="/iso-files"
  ISO_NAME="AlmaLinux-10-latest-x86_64-dvd.iso"

  if [[ ! -f "${ISO_DIR}/${ISO_NAME}" ]]; then
      echo -e "\n❌ ISO file not found: ${ISO_DIR}/${ISO_NAME}"
      echo -e "⬇️ Please download it using the script \033[1mdownload-almalinux-latest.sh\033[0m\n"
      exit 1
  fi

  echo -e "✅ ISO file found: ${ISO_DIR}/${ISO_NAME}\n"

  # VM directory and disk path
  VM_DIR="/kvm-hub/vms/${lab_infra_server_shortname}"
  VM_DISK_PATH="${VM_DIR}/${lab_infra_server_shortname}.qcow2"

  # Create VM directory if it doesn't exist
  mkdir -p "$VM_DIR"

  # Check if VM disk already exists
  if [[ -f "$VM_DISK_PATH" ]]; then
      echo -e "\n❌ Lab Infra VM '${lab_infra_server_shortname}' already exists at $VM_DISK_PATH. Aborting to avoid overwrite.\n"
      exit 1
  fi

  echo -e "✅ Lab Infra VM '${lab_infra_server_shortname}' does not exist. Ready to create.\n"

  lab_infra_server_mode_is_host=false

  # Ensure the variable is recorded in the lab environment file
  if [[ -f "$LAB_ENV_VARS_FILE" ]]; then
    if grep -q "^lab_infra_server_mode_is_host=" "$LAB_ENV_VARS_FILE"; then
      sed -i "s/^lab_infra_server_mode_is_host=.*/lab_infra_server_mode_is_host=${lab_infra_server_mode_is_host}/" "$LAB_ENV_VARS_FILE"
    else
      echo "lab_infra_server_mode_is_host=${lab_infra_server_mode_is_host}" >> "$LAB_ENV_VARS_FILE"
    fi
  fi

  echo -n -e "\n📦 Mounting ISO ${ISO_DIR}/${ISO_NAME} on /mnt/iso-for-${lab_infra_server_shortname} for VM installation . . . "

  sudo mkdir -p /mnt/iso-for-${lab_infra_server_shortname}
  sudo mount -o loop "${ISO_DIR}/${ISO_NAME}" /mnt/iso-for-${lab_infra_server_shortname} &>/dev/null

  echo -e " ✅ ISO mounted successfully on /mnt/iso-for-${lab_infra_server_shortname} .\n"

  # -----------------------------
  # Kickstart file preparation
  # -----------------------------
  echo -e "\n📄 Preparing Kickstart file for unattended installation of Lab Infra VM . . .\n"

  KS_FILE="${VM_DIR}/${lab_infra_server_shortname}_ks.cfg"

  cp -f almalinux-template-ks.cfg "${KS_FILE}" 
  sudo chown "$USER:qemu" "${KS_FILE}"

  sed -i "s/get_ipv4_address/${lab_infra_server_ipv4_address}/g" "${KS_FILE}"
  sed -i "s/get_ipv4_netmask/${lab_infra_server_ipv4_netmask}/g" "${KS_FILE}"
  sed -i "s/get_ipv4_gateway/${lab_infra_server_ipv4_gateway}/g" "${KS_FILE}"
  sed -i "s/get_mgmt_super_user/${lab_infra_admin_username}/g" "${KS_FILE}"
  sed -i "s/get_infra_server_name/${lab_infra_server_shortname}/g" "${KS_FILE}"
  sed -i "s/get_lab_infra_domain_name/${lab_infra_domain_name}/g" "${KS_FILE}"

  awk -v val="$lab_admin_shadow_password" '{ gsub(/get_shadow_password_super_mgmt_user/, val) } 1' \
      "${KS_FILE}" > "${KS_FILE}"_tmp_ksmanager && mv "${KS_FILE}"_tmp_ksmanager "${KS_FILE}"

  awk -v val="$lab_infra_ssh_public_key" '{ gsub(/get_ssh_public_key_of_qemu_host_machine/, val) } 1' \
      "${KS_FILE}" > "${KS_FILE}"_tmp_ksmanager && mv "${KS_FILE}"_tmp_ksmanager "${KS_FILE}"

  echo -e "✅ Kickstart file prepared at ${KS_FILE}\n"
  # -------------------------
  # Further deployment logic goes here
  # -------------------------
  # -----------------------------
  # Launch VM via virt-install
  # -----------------------------
  echo -e "\n🚀 Buckle up! We are about to view the Infra Server VM (${lab_infra_server_shortname}) deployment from console!\n"
  source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh

  sudo virt-install \
    --name "${lab_infra_server_shortname}" \
    --features acpi=on,apic=on \
    --memory 2048 \
    --vcpus 2 \
    --disk path="${VM_DIR}/${lab_infra_server_shortname}.qcow2",size=30,bus=virtio \
    --disk path="$ISO_DIR/$ISO_NAME",device=cdrom,bus=sata \
    --os-variant almalinux9 \
    --network network=default,model=virtio \
    --initrd-inject="${KS_FILE}" \
    --location "/mnt/iso-for-${lab_infra_server_shortname}" \
    --extra-args "inst.ks=file:/${lab_infra_server_shortname}_ks.cfg inst.stage2=cdrom inst.repo=cdrom console=ttyS0 nomodeset inst.text quiet" \
    --graphics none \
    --watchdog none \
    --console pty,target_type=serial \
    --machine q35 \
    --cpu host-model \
    --boot loader=${OVMF_CODE_PATH},\
nvram.template=${OVMF_VARS_PATH},\
nvram="${VM_DIR}/${lab_infra_server_shortname}_VARS.fd",menu=on

  # -----------------------------
  # Check deployment status
  # -----------------------------
  if sudo virsh list | grep -q "${lab_infra_server_shortname}"; then
    echo -e "\n✅ Successfully deployed your Infra Server VM (${lab_infra_server_shortname})!\n"
  else
    echo -e "\n❌ Failed to deploy your Infra Server VM (${lab_infra_server_shortname})!\n🔍 Please check where it went wrong.\n"
  fi

  # Cleanup ISO mount
  sudo umount -l /mnt/iso-for-${lab_infra_server_shortname} &>/dev/null

  exit
}

deploy_lab_infra_server_host() {
  echo ""
  prepare_lab_infra_config
  echo "🧩  Starting deployment of lab infra server directly on the KVM host..."
  echo ""
    # -----------------------------
  # Deployment mode flag
  # -----------------------------
  lab_infra_server_mode_is_host=true

  if [[ -f "$LAB_ENV_VARS_FILE" ]]; then
    if grep -q "^lab_infra_server_mode_is_host=" "$LAB_ENV_VARS_FILE"; then
      sed -i "s/^lab_infra_server_mode_is_host=.*/lab_infra_server_mode_is_host=${lab_infra_server_mode_is_host}/" "$LAB_ENV_VARS_FILE"
    else
      echo "lab_infra_server_mode_is_host=${lab_infra_server_mode_is_host}" >> "$LAB_ENV_VARS_FILE"
    fi
  fi

  # -----------------------------
  # Install required packages
  # -----------------------------
  echo -e "\n📦 Installing required packages on host via dnf . . .\n"

  REQUIRED_PACKAGES=(
    bash-completion vim git bind-utils bind wget tar net-tools cifs-utils zip
    tftp-server kea kea-hooks syslinux nginx nginx-mod-stream tmux
    rsync sysstat tcpdump traceroute nc samba-client lsof nfs-utils
    nmap tuned tree yum-utils
  )

  # Install packages, skipping already installed ones
  sudo dnf install -y "${REQUIRED_PACKAGES[@]}"

  echo -e "\n✅ All required packages installed on host successfully.\n"

  # -----------------------------
  # Install Ansible if not already installed
  # -----------------------------
  if command -v ansible &>/dev/null; then
      echo -e "\n✅ Ansible is already installed. Proceeding further...\n"
  else
      echo -e "\n📦 Installing Ansible on the host . . .\n"

      # Install Python dependencies
      sudo dnf install python3-pip python3-cryptography -y

      # Install Ansible and related packages
      pip3 install --user packaging
      pip3 install --user ansible
      pip3 install --user argcomplete

      # Enable global shell completion
      activate-global-python-argcomplete

      echo -e "\n✅ Ansible installation completed successfully.\n"
  fi

  # ---------------------------
  # Lab Infra DNS configuration
  # ---------------------------
  echo -e "\n🌐 Setting up Lab Infra DNS with custom utility dnsbinder . . .\n"
  sudo bash /server-hub/named-manage/dnsbinder.sh --setup "${lab_infra_domain_name}"

  # Set mgmt_super_user in environment using lab_infra_admin_username
  if ! grep -q mgmt_super_user /etc/environment; then
      echo "mgmt_super_user=\"${lab_infra_admin_username}\"" | sudo tee -a /etc/environment &>/dev/null
  fi

  # Set mgmt_interface_name in environment
  if ! grep -q mgmt_interface_name /etc/environment; then
      echo "mgmt_interface_name=\"labbr0\"" | sudo tee -a /etc/environment &>/dev/null
  fi  

  # Reload environment to include new variables
  source /etc/environment

  echo -e "\n🌐 Reserving DNS Records for DHCP lease . . .\n"

  # Loop through IPs 201–254 to create DHCP lease DNS entries
  for IPOCTET in $(seq 201 254); do
    sudo bash /server-hub/named-manage/dnsbinder.sh -ci dhcp-lease${IPOCTET} ${dnsbinder_last24_subnet}.${IPOCTET}
  done

  # -----------------------------
  # Ansible playbook execution
  # -----------------------------

  echo -e "\n🚀 Executing Ansible playbook to configure Lab Infra Services . . .\n"

  sed -i "/remote_user/c\remote_user=${lab_infra_admin_username}" /server-hub/build-almalinux-server/ansible.cfg

  ANSIBLE_HOME="/server-hub/build-almalinux-server/"

  # Run ansible-playbook that congigures the essential services
  ansible-playbook /server-hub/build-almalinux-server/build-server.yaml
  
  echo -e "\n✅ Ansible playbook execution completed successfully.\n"

  # Next steps: host-specific setup will follow
  # -----------------------------

}

#-------------------------------------------------------------
# Deployment selection prompt
#-------------------------------------------------------------
echo "-------------------------------------------------------------"
echo "⚙️  Lab Infra Server Deployment Mode Selection"
echo "-------------------------------------------------------------"
echo "Choose where to deploy your lab infra server:"
echo ""
echo "  🖥️  [vm]   → Deploy inside a dedicated KVM virtual machine"
echo "       💡  Note: Allows more customization and isolation for future setups."
echo ""
echo "  🧩  [host] → Deploy directly on the KVM host itself"
echo "       ⚠️  Note: May have certain restrictions due to shared resources"
echo "           or conflicts with existing host services."
echo "-------------------------------------------------------------"

while true; do
  read -rp "👉 Enter your choice (vm/host): " DEPLOY_TARGET
  case "$DEPLOY_TARGET" in
    vm)
      echo "✅ Confirmed: Lab Infra Server Deploymentt Mode set to 'VM'."
      deploy_lab_infra_server_vm
      break
      ;;
    host)
      echo "✅ Confirmed: Lab Infra Server Deployment Mode set to 'Host'."
      deploy_lab_infra_server_host
      break
      ;;
    *)
      echo "⚠️  Invalid choice. Please type either 'vm' or 'host'."
      ;;
  esac
done

