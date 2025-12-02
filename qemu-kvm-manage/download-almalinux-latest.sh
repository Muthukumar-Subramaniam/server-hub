#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh

ISO_DIR="/iso-files"
ISO_NAME="AlmaLinux-10-latest-x86_64-dvd.iso"
ISO_URL="https://repo.almalinux.org/almalinux/10/isos/x86_64/$ISO_NAME"
CHECKSUM_URL="https://repo.almalinux.org/almalinux/10/isos/x86_64/CHECKSUM"
sudo mkdir -p "$ISO_DIR"
sudo chown -R $USER:$(id -g) "$ISO_DIR"

# Create directory if it doesn't exist

# Download ISO
if [ -f "$ISO_DIR/$ISO_NAME" ]; then
	print_info "[INFO] ISO File $ISO_DIR/$ISO_NAME already exists!"
else
	print_info "[INFO] Please be patient until the $ISO_NAME gets downloaded..."
	wget --continue --output-document="$ISO_DIR/$ISO_NAME" "$ISO_URL"
fi

print_success "[SUCCESS] ISO downloaded successfully!"
print_info "[INFO] ISO File Path: $ISO_DIR/$ISO_NAME"

# Download signed CHECKSUM file
print_info "[INFO] Downloading CHECKSUM to validate $ISO_NAME..."
wget --continue --output-document="$ISO_DIR/CHECKSUM" "$CHECKSUM_URL"

# Extract the expected SHA256 checksum for the ISO
print_info "[INFO] Extracting CHECKSUM for $ISO_NAME..."
EXPECTED_HASH=$(grep -E "SHA256.*$ISO_NAME" "$ISO_DIR/CHECKSUM" | awk -F'= ' '{print $2}')

# Calculate actual SHA256 of downloaded ISO
ACTUAL_HASH=$(sha256sum "$ISO_DIR/$ISO_NAME" | awk '{print $1}')

# Compare
print_info "[INFO] Comparing checksums..." nskip
if [[ "$EXPECTED_HASH" == "$ACTUAL_HASH" ]]; then
    print_success "[SUCCESS] Checksum matched. ISO file $ISO_DIR/$ISO_NAME is valid."
else
    print_error "[ERROR] Checksum mismatch. ISO file $ISO_DIR/$ISO_NAME is invalid!"
    print_info "[INFO] Expected: $EXPECTED_HASH" nskip
    print_info "[INFO] Actual:   $ACTUAL_HASH"
    exit 1
fi
