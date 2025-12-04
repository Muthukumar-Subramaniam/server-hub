#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl build-golden-image

Description:
  Creates a golden image disk by installing a VM via PXE boot.
  The VM will be automatically removed after the disk is created.

Options:
  -h, --help           Show this help message

Note: This script does not take any arguments.
"
}

# Check if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    fn_show_help
    exit 0
fi

# Check if any arguments are passed
if [ "$#" -ne 0 ]; then
    print_error "[ERROR] $(basename $0) does not take any arguments."
    fn_show_help
    exit 1
fi

print_info "[INFO] Invoking ksmanager to create PXE environment for golden image..."

# Run ksmanager for golden image creation
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/run-ksmanager.sh
if ! run_ksmanager "" "--qemu-kvm --create-golden-image"; then
    print_error "[FAILED] Something went wrong while executing ksmanager!"
    print_info "[INFO] Please check your Lab Infra Server for the root cause."
    exit 1
fi

qemu_kvm_hostname="$EXTRACTED_HOSTNAME"

mkdir -p /kvm-hub/golden-images-disk-store

golden_image_path="/kvm-hub/golden-images-disk-store/${qemu_kvm_hostname}.qcow2"

# Check if golden image already exists
if [ -f "${golden_image_path}" ]; then
    print_warning "[WARNING] Golden image \"${qemu_kvm_hostname}\" already exists!"
    read -p "Do you want to delete and recreate it? (yes/no): " answer
    echo -ne "\033[1A\033[2K"  # Move up one line and clear it
    case "$answer" in
        yes|YES)
            print_info "[INFO] Deleting existing golden image..."
            if sudo rm -f "${golden_image_path}"; then
                print_success "[SUCCESS] Existing golden image deleted."
            else
                print_error "[FAILED] Could not delete existing golden image."
                exit 1
            fi
            ;;
        * )
            print_info "[INFO] Keeping existing golden image \"${qemu_kvm_hostname}\". Exiting..."
            exit 0
            ;;
    esac
fi

print_info "[INFO] Starting installation of VM \"${qemu_kvm_hostname}\" to create golden image disk..."

# Set custom paths for golden image creation
DISK_PATH="${golden_image_path}"
NVRAM_PATH="/kvm-hub/golden-images-disk-store/${qemu_kvm_hostname}_VARS.fd"
CONSOLE_MODE="--console pty,target_type=serial"

if ! virt_install_output=$(source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/default-vm-install.sh 2>&1); then
    print_error "[FAILED] VM installation failed."
    if [[ -n "$virt_install_output" ]]; then
        print_error "$virt_install_output"
    fi
    exit 1
fi

print_info "[INFO] VM installation completed."

# Cleanup: destroy and undefine the temporary VM
print_info "[INFO] Cleaning up temporary VM..."

# Destroy VM if running
if sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    if error_msg=$(sudo virsh destroy "$qemu_kvm_hostname" 2>&1); then
        print_info "[INFO] Temporary VM stopped."
    else
        print_warning "[WARNING] Could not stop temporary VM: $error_msg"
    fi
fi

# Undefine VM
if error_msg=$(sudo virsh undefine "$qemu_kvm_hostname" --nvram 2>&1); then
    print_info "[INFO] Temporary VM cleaned up successfully."
else
    print_warning "[WARNING] Could not cleanup temporary VM: $error_msg"
fi

print_success "[SUCCESS] Golden image disk created successfully: ${golden_image_path}"