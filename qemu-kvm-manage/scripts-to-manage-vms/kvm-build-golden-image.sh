#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh

OS_DISTRO=""

# Function to show help
fn_show_help() {
    print_cyan "Usage: qlabvmctl build-golden-image [OPTIONS]
Description:
  Creates a golden image disk by installing a VM via PXE boot.
  The VM will be automatically removed after the disk is created.

Options:
  -d, --distro         Specify OS distribution
                       (almalinux, rocky, oraclelinux, centos-stream, rhel, fedora, ubuntu-lts, opensuse-leap)
  -h, --help           Show this help message

Examples:
  qlabvmctl build-golden-image                       # Build golden image (will prompt for distro)
  qlabvmctl build-golden-image -d almalinux          # Build AlmaLinux golden image
  qlabvmctl build-golden-image --distro ubuntu-lts   # Build Ubuntu LTS golden image
"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            fn_show_help
            exit 0
            ;;
        -d|--distro)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "--distro/-d requires a distribution name."
                fn_show_help
                exit 1
            fi
            OS_DISTRO="$2"
            shift 2
            ;;
        -*)
            print_error "No such option: $1"
            fn_show_help
            exit 1
            ;;
        *)
            print_error "$(basename $0) does not accept positional arguments."
            fn_show_help
            exit 1
            ;;
    esac
done

print_info "Invoking ksmanager to create PXE environment for golden image..."

# Run ksmanager for golden image creation
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/run-ksmanager.sh
ksmanager_opts="--qemu-kvm --create-golden-image"
[[ -n "$OS_DISTRO" ]] && ksmanager_opts="$ksmanager_opts --distro $OS_DISTRO"
if ! run_ksmanager "" "$ksmanager_opts"; then
    print_error "Something went wrong while executing ksmanager!"
    print_info "Please check your Lab Infra Server for the root cause."
    exit 1
fi

qemu_kvm_hostname="$EXTRACTED_HOSTNAME"

mkdir -p /kvm-hub/golden-images-disk-store

golden_image_path="/kvm-hub/golden-images-disk-store/${qemu_kvm_hostname}.qcow2"

# Check if golden image already exists
if [ -f "${golden_image_path}" ]; then
    print_warning "Golden image \"${qemu_kvm_hostname}\" already exists!"
    read -p "Do you want to delete and recreate it? (yes/no): " answer
    echo -ne "\033[1A\033[2K"  # Move up one line and clear it
    case "$answer" in
        yes|YES)
            print_task "Deleting existing golden image..." nskip
            if sudo rm -f "${golden_image_path}"; then
                print_task_done
            else
                print_task_fail
                print_error "Could not delete existing golden image."
                exit 1
            fi
            ;;
        * )
            print_info "Keeping existing golden image \"${qemu_kvm_hostname}\". Exiting..."
            exit 0
            ;;
    esac
fi

print_info "Starting installation of VM \"${qemu_kvm_hostname}\" to create golden image disk..."

# Set custom paths for golden image creation
DISK_PATH="${golden_image_path}"
NVRAM_PATH="/kvm-hub/golden-images-disk-store/${qemu_kvm_hostname}_VARS.fd"

# Run virt-install with console attachment (don't use shared function to avoid complexity)
if ! sudo virt-install \
  --name ${qemu_kvm_hostname} \
  --features acpi=on,apic=on \
  --memory 2048 \
  --vcpus 2 \
  --disk path=${DISK_PATH},size=20,bus=virtio,boot.order=1 \
  --os-variant almalinux9 \
  --network network=default,model=virtio,mac=${MAC_ADDRESS},boot.order=2 \
  --graphics none \
  --console pty,target_type=serial \
  --machine q35 \
  --watchdog none \
  --cpu host-model \
  --boot loader=${OVMF_CODE_PATH},\
nvram.template=${OVMF_VARS_PATH},\
nvram=${NVRAM_PATH},\
menu=on; then
    print_error "VM installation failed."
    exit 1
fi

print_info "VM installation of \"${qemu_kvm_hostname}\" completed."

# Cleanup: destroy and undefine the temporary VM
print_info "Cleaning up temporary VM \"${qemu_kvm_hostname}\"..."

# Destroy VM if running
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
POWEROFF_VM_CONTEXT="Stopping temporary VM" poweroff_vm "$qemu_kvm_hostname"

# Undefine VM
if error_msg=$(sudo virsh undefine "$qemu_kvm_hostname" --nvram 2>&1); then
    print_info "Temporary VM \"${qemu_kvm_hostname}\" cleaned up successfully."
else
    print_warning "Could not cleanup temporary VM \"${qemu_kvm_hostname}\": $error_msg"
fi

print_success "Golden image disk created successfully: ${golden_image_path}"