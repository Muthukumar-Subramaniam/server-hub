#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh

ATTACH_CONSOLE="no"
HOSTNAMES=()

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl install-pxe [OPTIONS] [hostname]

Options:
  -c, --console        Attach console during installation (single VM only)
  -H, --hosts          Specify multiple hostnames (comma-separated)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to install via PXE boot (optional, will prompt if not given)

Examples:
  qlabvmctl install-pxe vm1                           # Install single VM
  qlabvmctl install-pxe vm1 --console                 # Install and attach console
  qlabvmctl install-pxe --hosts vm1,vm2,vm3           # Install multiple VMs
  qlabvmctl install-pxe -H vm1,vm2,vm3                # Same as above
"
}

# Parse and validate arguments
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/parse-vm-command-args.sh
parse_vm_command_args "$@"

# Main installation loop
CURRENT_VM=0
FAILED_VMS=()
SUCCESSFUL_VMS=()

for qemu_kvm_hostname in "${HOSTNAMES[@]}"; do
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-multi-vm-progress.sh
    show_multi_vm_progress "$qemu_kvm_hostname"

    # Check if VM exists
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/check-vm-exists.sh
    if ! check_vm_exists "$qemu_kvm_hostname" "install"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    print_info "[INFO] Creating PXE environment for '${qemu_kvm_hostname}' using ksmanager..."

    # Run ksmanager and extract VM details
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/run-ksmanager.sh
    if ! run_ksmanager "${qemu_kvm_hostname}" "--qemu-kvm"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Create VM directory
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/create-vm-directory.sh
    if ! create_vm_directory "${qemu_kvm_hostname}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Update /etc/hosts
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/update-etc-hosts.sh
    if ! update_etc_hosts "${qemu_kvm_hostname}" "${IPV4_ADDRESS}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Start installation process via PXE boot
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/start-vm-installation.sh
    if ! start_vm_installation "$qemu_kvm_hostname" "PXE boot"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    SUCCESSFUL_VMS+=("$qemu_kvm_hostname")

    # Show completion message for single VM
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-vm-completion-message.sh
    show_vm_completion_message "${qemu_kvm_hostname}" "${ATTACH_CONSOLE}" "${TOTAL_VMS}" "installation via PXE boot" "The VM will download OS files and install (this may take a few minutes)."
done

# Summary for multiple VMs
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-vm-operation-summary.sh
if ! show_vm_operation_summary "${TOTAL_VMS}" "SUCCESSFUL_VMS" "FAILED_VMS" "installation via PXE boot" "Installation via PXE boot may take a few minutes per VM."; then
    exit 1
fi


