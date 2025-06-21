#!/bin/bash

set -e

# Required variables
: "${dnsbinder_server_fqdn:?Must set dnsbinder_server_fqdn}"
: "${mgmt_super_user:?Must set mgmt_super_user}"

ISO_DIR="/iso-files"
MOUNT_DIR="/var/www/${dnsbinder_server_fqdn}/ubuntu-lts-latest"
TFTP_DIR="/var/lib/tftpboot/ubuntu-lts-latest"
FSTAB="/etc/fstab"

# 1. Fetch latest Ubuntu LTS version from cdimage
echo -e "\n🔍 Fetching latest Ubuntu Server LTS version..."
CDIMAGE_URL="https://cdimage.ubuntu.com/releases/"
LATEST_LTS=$(curl -s "$CDIMAGE_URL" | \
  grep -oP 'href="\K(2[0-9]|[3-9][0-9])(?:\.04(?:\.\d+)?)?(?=/")' | \
  grep -P '^([0-9]{2})\.04(\.\d+)?$' | \
  awk -F. 'int($1) % 2 == 0' | \
  sort -Vr | head -n1)

if [[ -z "$LATEST_LTS" ]]; then
  echo -e "\n❌ Failed to determine latest LTS version.\n"
  exit 1
fi

echo -e "✅ Latest LTS version: $LATEST_LTS\n"

# 2. Download ISO (skip if already exists)
ISO_FILE="ubuntu-${LATEST_LTS}-live-server-amd64.iso"
ISO_URL="https://releases.ubuntu.com/${LATEST_LTS}/${ISO_FILE}"
ISO_PATH="${ISO_DIR}/${ISO_FILE}"

echo -e "📁 Ensuring ISO directory exists..."
sudo mkdir -p "$ISO_DIR"
sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$ISO_PATH"

if [[ -f "$ISO_PATH" ]]; then
  echo -e "📦 ISO already exists: $ISO_PATH\n"
else
  echo -e "🌐 Downloading ISO from $ISO_URL\n"
  curl -L -o "$ISO_PATH" "$ISO_URL"
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

rsync -avPh "$MOUNT_DIR/casper/vmlinuz" "$TFTP_DIR/"
rsync -avPh "$MOUNT_DIR/casper/initrd" "$TFTP_DIR/"

echo -e "\n✅ All done: ISO is downloaded, mounted, fstab updated, and PXE files prepared.\n"

exit
