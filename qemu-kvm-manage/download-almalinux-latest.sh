#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#
ISO_DIR="/virtual-machines/iso-files"
ISO_NAME="AlmaLinux-10-latest-x86_64-dvd.iso"
ISO_URL="https://repo.almalinux.org/almalinux/10/isos/x86_64/$ISO_NAME"
CHECKSUM_URL="https://repo.almalinux.org/almalinux/10/isos/x86_64/CHECKSUM"
sudo mkdir -p /virtual-machines
sudo chown -R $USER:qemu /virtual-machines
chmod -R g+s /virtual-machines
mkdir -p "$ISO_DIR"

# Create directory if it doesn't exist

# Download ISO
if [ -f "$ISO_DIR/$ISO_NAME" ]; then
	echo -e "\nISO File $ISO_DIR/$ISO_NAME already exists! "
else
	echo -e "\nPlease be patient until the $ISO_NAME gets downloaded . . . \n"
	wget --continue --output-document="$ISO_DIR/$ISO_NAME" "$ISO_URL"
fi

echo -e "\nISO downloaded successfully! "
echo -e "ISO File Path : $ISO_DIR/$ISO_NAME"

# Download signed CHECKSUM file
echo -e "\nDownloading CHECKSUM to validate $ISO_NAME . . . "
wget --continue --output-document="$ISO_DIR/CHECKSUM" "$CHECKSUM_URL"

# Extract the expected SHA256 checksum for the ISO
echo -e "\nPlease be patient until the CHECKSUM for the $ISO_NAME is extracted . . . "
EXPECTED_HASH=$(grep -E "SHA256.*$ISO_NAME" "$ISO_DIR/CHECKSUM" | awk -F'= ' '{print $2}')

# Calculate actual SHA256 of downloaded ISO
ACTUAL_HASH=$(sha256sum "$ISO_DIR/$ISO_NAME" | awk '{print $1}')

# Compare
echo -e "\n📋 Comparing checksums . . . "
if [[ "$EXPECTED_HASH" == "$ACTUAL_HASH" ]]; then
    echo -e "\n✅ Checksum matched. ISO file $ISO_DIR/$ISO_NAME is valid. \n"
else
    echo -e "\n❌ Checksum mismatch. ISO file $ISO_DIR/$ISO_NAME is invalid! \n"
    echo "Expected: $EXPECTED_HASH"
    echo "Actual:   $ACTUAL_HASH"
    exit 1
fi
