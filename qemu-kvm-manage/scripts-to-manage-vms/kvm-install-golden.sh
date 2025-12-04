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
    print_info "Usage: qlabvmctl install-golden [OPTIONS] [hostname]

Options:
  -c, --console        Attach console during installation (single VM only)
  -H, --hosts          Specify multiple hostnames (comma-separated)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to install via golden image disk (optional, will prompt if not given)

Examples:
  qlabvmctl install-golden vm1                           # Install single VM
  qlabvmctl install-golden vm1 --console                 # Install and attach console
  qlabvmctl install-golden --hosts vm1,vm2,vm3           # Install multiple VMs
  qlabvmctl install-golden -H vm1,vm2,vm3                # Same as above
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
    ((CURRENT_VM++))
    
    if [[ $TOTAL_VMS -gt 1 ]]; then
        print_info "[INFO] Processing VM ${CURRENT_VM}/${TOTAL_VMS}: ${qemu_kvm_hostname}"
    fi

    # Check if VM exists
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/check-vm-exists.sh
    if ! check_vm_exists "$qemu_kvm_hostname" "install"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    print_info "[INFO] Creating first boot environment for '${qemu_kvm_hostname}' using ksmanager..."

    # Run ksmanager and extract VM details
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/run-ksmanager.sh
    if ! run_ksmanager "${qemu_kvm_hostname}" "--qemu-kvm --golden-image"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Normalize OS distro name
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/normalize-os-distro.sh
    if ! normalize_os_distro "${OS_DISTRO}"; then
        print_error "[ERROR] Failed to normalize OS distro for \"$qemu_kvm_hostname\"."
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi
    OS_DISTRO="$NORMALIZED_OS_DISTRO"

    # Create VM directory
    if ! mkdir -p /kvm-hub/vms/"${qemu_kvm_hostname}"; then
        print_error "[ERROR] Failed to create VM directory: /kvm-hub/vms/${qemu_kvm_hostname}"
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Update /etc/hosts
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/update-etc-hosts.sh
    if ! update_etc_hosts "${qemu_kvm_hostname}" "${IPV4_ADDRESS}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    if [ ! -f /kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2 ]; then
        print_error "[ERROR] Golden image disk not found for \"$qemu_kvm_hostname\"!"
        print_info "[INFO] Expected at: /kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2"
        print_info "[INFO] To build the golden image disk, run: qlabvmctl build-golden-image"
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    print_info "[INFO] Cloning golden image disk to /kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2..." nskip

    if error_msg=$(sudo qemu-img convert -O qcow2 \
      /kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2 \
      /kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2 2>&1); then
        # Verify the cloned disk exists and has size
        if [[ -f "/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2" ]] && \
           [[ $(stat -c%s "/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2" 2>/dev/null || echo 0) -gt 0 ]]; then
            print_success "[ SUCCESS ]"
        else
            print_error "[ FAILED ]"
            print_error "Disk file was not created properly for \"$qemu_kvm_hostname\"."
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    else
        print_error "[ FAILED ]"
        print_error "$error_msg"
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Start installation process via golden image disk
    print_info "[INFO] Starting VM installation of \"$qemu_kvm_hostname\" via golden image disk..."
    if ! virt_install_output=$(source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/default-vm-install.sh 2>&1); then
        print_error "[ERROR] Failed to start VM installation for \"$qemu_kvm_hostname\"."
        if [[ -n "$virt_install_output" ]]; then
            print_error "$virt_install_output"
        fi
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    SUCCESSFUL_VMS+=("$qemu_kvm_hostname")

    # Show completion message for single VM
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-vm-completion-message.sh
    show_vm_completion_message "${qemu_kvm_hostname}" "${ATTACH_CONSOLE}" "${TOTAL_VMS}" "installation via golden image disk" "The VM will reboot once or twice during installation (~1 minute)."
done

# Summary for multiple VMs
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-vm-operation-summary.sh
if ! show_vm_operation_summary "${TOTAL_VMS}" "SUCCESSFUL_VMS" "FAILED_VMS" "installation via golden image disk" "All VMs will reboot once or twice during installation (~1 minute each)."; then
    exit 1
fi
