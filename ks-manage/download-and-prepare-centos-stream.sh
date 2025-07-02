#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

set -e

# Required variables
: "${dnsbinder_server_fqdn:?Must set dnsbinder_server_fqdn}"
: "${mgmt_super_user:?Must set mgmt_super_user}"

ISO_DIR="/iso-files"
MOUNT_DIR="/var/www/${dnsbinder_server_fqdn}/centos-stream-latest"
TFTP_DIR="/var/lib/tftpboot/centos-stream-latest"
FSTAB="/etc/fstab"

# 2. Download ISO (skip if already exists)
ISO_FILE="CentOS-Stream-10-latest-x86_64-dvd.iso"
ISO_URL="https://mirrors.centos.org/mirrorlist?path=/10-stream/BaseOS/x86_64/iso/CentOS-Stream-10-latest-x86_64-dvd1.iso&redirect=1&protocol=https"
ISO_PATH="${ISO_DIR}/${ISO_FILE}"

echo -e "📁 Ensuring ISO directory exists..."
sudo mkdir -p "$ISO_DIR"
sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$ISO_DIR"

if [[ -f "$ISO_PATH" ]]; then
  echo -e "📦 ISO already exists: $ISO_PATH\n"
else
  echo -e "🌐 Downloading ISO from $ISO_URL\n"
  wget --continue --output-document="$ISO_PATH" "$ISO_URL"
  sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$ISO_PATH"
  echo -e "\n✅ Download complete and ownership set.\n"
fi

# 3. Mount ISO using fstab
echo -e "📂 Preparing mount point: $MOUNT_DIR"
sudo mkdir -p "$MOUNT_DIR"
FSTAB_ENTRY="${ISO_PATH} ${MOUNT_DIR} iso9660 uid=${mgmt_super_user},gid=${mgmt_super_user} 0 0"

if ! grep -qF "$FSTAB_ENTRY" "$FSTAB"; then
  echo -e "🔧 Adding mount entry to /etc/fstab\n"
  echo "$FSTAB_ENTRY" | sudo tee -a "$FSTAB" > /dev/null
  sudo systemctl daemon-reload
else
  echo -e "✅ fstab already contains ISO mount entry.\n"
fi

# Mount if not mounted
if ! mountpoint -q "$MOUNT_DIR"; then
  echo -e "📁 Mounting ISO to $MOUNT_DIR\n"
  sudo mount "$MOUNT_DIR"
  echo -e "✅ ISO mounted.\n"
else
  echo -e "📎 ISO already mounted.\n"
fi

# 4. Rsync vmlinuz and initrd to TFTP directory
echo -e "📤 Syncing kernel and initrd to $TFTP_DIR\n"
sudo mkdir -p "$TFTP_DIR"
sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$TFTP_DIR"

rsync -avPh "$MOUNT_DIR/images/pxeboot/vmlinuz" "$TFTP_DIR/"
rsync -avPh "$MOUNT_DIR/images/pxeboot/initrd.img" "$TFTP_DIR/"

echo -e "\n✅ All done: ISO is downloaded, mounted, fstab updated, and PXE files prepared.\n"

exit
