#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
DIR_PATH_SCRIPTS_TO_MANAGE_VMS='/server-hub/qemu-kvm-manage/scripts-to-manage-vms'

ATTACH_CONSOLE="no"
CLEAN_INSTALL="no"
HOSTNAMES=()
SUPPORTS_CLEAN_INSTALL="yes"

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl reimage-pxe [OPTIONS] [hostname]

Options:
  -c, --console        Attach console during reimage (single VM only)
  -C, --clean-install  Destroy VM and reinstall with default specs (2 vCPUs, 2 GiB RAM, 20 GiB disk)
  -H, --hosts          Specify multiple hostnames (comma-separated)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to reimage via PXE boot (optional, will prompt if not given)

Examples:
  qlabvmctl reimage-pxe vm1                               # Reimage single VM
  qlabvmctl reimage-pxe vm1 --console                     # Reimage and attach console
  qlabvmctl reimage-pxe vm1 --clean-install               # Reimage with default specs
  qlabvmctl reimage-pxe --hosts vm1,vm2,vm3               # Reimage multiple VMs
  qlabvmctl reimage-pxe -H vm1,vm2,vm3 --clean-install   # Reimage multiple with defaults
"
}

# Parse and validate arguments
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/parse-vm-command-args.sh
parse_vm_command_args "$@"

# Main reimage loop
CURRENT_VM=0
FAILED_VMS=()
SUCCESSFUL_VMS=()

for qemu_kvm_hostname in "${HOSTNAMES[@]}"; do
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-multi-vm-progress.sh
    show_multi_vm_progress "$qemu_kvm_hostname"

    # Check if VM exists
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/check-vm-exists.sh
    if ! check_vm_exists "$qemu_kvm_hostname" "reimage"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Prevent reimaging of lab infra server
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/check-lab-infra-protection.sh
    if ! check_lab_infra_protection "$qemu_kvm_hostname"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi
    
    # Confirm reimage operation
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/confirm-reimage-operation.sh
    confirm_reimage_operation "$qemu_kvm_hostname" "PXE boot"

    print_info "[INFO] Creating PXE environment for '${qemu_kvm_hostname}' using ksmanager..."

    # Run ksmanager and extract VM details
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/run-ksmanager.sh
    if ! run_ksmanager "${qemu_kvm_hostname}" "--qemu-kvm"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Update /etc/hosts
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/update-etc-hosts.sh
    if ! update_etc_hosts "${qemu_kvm_hostname}" "${IPV4_ADDRESS}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Shut down VM if running
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh
    shutdown_vm "$qemu_kvm_hostname"

    # If --clean-install is specified, destroy and reinstall VM with default specs
    if [[ "$CLEAN_INSTALL" == "yes" ]]; then
        print_info "[INFO] Using --clean-install: VM will be destroyed and reinstalled with default specs (2 vCPUs, 2 GiB RAM, 20 GiB disk)."
        
        # Destroy VM and delete directory
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/destroy-vm-for-clean-install.sh
        if ! destroy_vm_for_clean_install "$qemu_kvm_hostname"; then
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        # Create fresh VM directory
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/create-vm-directory.sh
        if ! create_vm_directory "${qemu_kvm_hostname}"; then
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        # Create new disk with default size
        print_info "[INFO] Creating new disk /kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2 with 20 GiB..." nskip
        if error_msg=$(sudo qemu-img create -f qcow2 /kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2 20G 2>&1); then
            print_success "[ SUCCESS ]"
        else
            print_error "[ FAILED ]"
            print_error "$error_msg"
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        # Install VM with default specs using default-vm-install function
        print_info "[INFO] Starting VM installation of \"$qemu_kvm_hostname\" with default specs via PXE boot..."
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/start-vm-installation.sh
        if ! start_vm_installation "$qemu_kvm_hostname" "PXE boot with default specs"; then
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    else
        # Default path: preserve disk size
        print_info "[INFO] Reimaging VM \"$qemu_kvm_hostname\" by replacing its qcow2 disk with a new one..."
        
        vm_qcow2_disk_path="/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2"
        
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/get-current-disk-size.sh
        get_current_disk_size "$qemu_kvm_hostname"
        current_disk_gib="${CURRENT_DISK_SIZE:-20}"
        
        # Delete existing qcow2 disk and recreate with appropriate size
        sudo rm -f "${vm_qcow2_disk_path}"
        if ! sudo qemu-img create -f qcow2 "${vm_qcow2_disk_path}" "${default_qcow2_disk_gib}G" >/dev/null 2>&1; then
            print_error "[ERROR] Failed to create qcow2 disk for \"$qemu_kvm_hostname\"."
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        if [[ "$current_disk_gib" -gt "$default_qcow2_disk_gib" ]]; then
            if sudo qemu-img resize "${vm_qcow2_disk_path}" "${current_disk_gib}G" >/dev/null 2>&1; then
                print_success "[SUCCESS] Retained disk size of ${current_disk_gib} GiB for VM \"$qemu_kvm_hostname\"."
            fi
        fi
        
        # Start reimaging process
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/start-vm-for-reimage.sh
        if ! start_vm_for_reimage "$qemu_kvm_hostname" "reimaging via PXE boot"; then
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    fi

    SUCCESSFUL_VMS+=("$qemu_kvm_hostname")

    # Show completion message for single VM
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-vm-completion-message.sh
    show_vm_completion_message "${qemu_kvm_hostname}" "${ATTACH_CONSOLE}" "${TOTAL_VMS}" "reimaging via PXE boot" "Reimaging via PXE boot takes a few minutes."
done

# Summary for multiple VMs
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-vm-operation-summary.sh
if ! show_vm_operation_summary "${TOTAL_VMS}" "SUCCESSFUL_VMS" "FAILED_VMS" "reimaging via PXE boot" "Reimaging via PXE boot takes a few minutes per VM."; then
    exit 1
fi
