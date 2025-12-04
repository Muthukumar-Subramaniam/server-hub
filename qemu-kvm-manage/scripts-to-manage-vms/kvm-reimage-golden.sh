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
FORCE_REIMAGE="false"
HOSTNAMES=()
SUPPORTS_CLEAN_INSTALL="yes"
SUPPORTS_FORCE="yes"

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl reimage-golden [OPTIONS] [hostname]

Options:
  -c, --console        Attach console during reimage (single VM only)
  -C, --clean-install  Destroy VM and reinstall with default specs (2 vCPUs, 2 GiB RAM, 20 GiB disk)
  -f, --force          Skip confirmation prompt
  -H, --hosts          Specify multiple hostnames (comma-separated)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to reimage via golden image disk (optional, will prompt if not given)

Examples:
  qlabvmctl reimage-golden vm1                               # Reimage single VM
  qlabvmctl reimage-golden vm1 --console                     # Reimage and attach console
  qlabvmctl reimage-golden vm1 --clean-install               # Reimage with default specs
  qlabvmctl reimage-golden -f vm1                            # Reimage without confirmation
  qlabvmctl reimage-golden --hosts vm1,vm2,vm3               # Reimage multiple VMs
  qlabvmctl reimage-golden -H vm1,vm2,vm3 --clean-install   # Reimage multiple with defaults
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
    confirm_reimage_operation "$qemu_kvm_hostname" "golden image"

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

    # Update /etc/hosts
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/update-etc-hosts.sh
    if ! update_etc_hosts "${qemu_kvm_hostname}" "${IPV4_ADDRESS}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/validate-golden-image-exists.sh
    if ! validate_golden_image_exists "$qemu_kvm_hostname" "${OS_DISTRO}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    golden_qcow2_disk_path="/kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2"

    # Shut down VM if running
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
    POWEROFF_VM_CONTEXT="Powering off before reimaging" poweroff_vm "$qemu_kvm_hostname"

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
        
        # Clone golden image disk
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/clone-golden-image-disk.sh
        if ! clone_golden_image_disk "$qemu_kvm_hostname" "${OS_DISTRO}"; then
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        # Install VM with default specs using default-vm-install function
        print_info "[INFO] Starting VM installation of \"$qemu_kvm_hostname\" with default specs via golden image disk..."
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/start-vm-installation.sh
        if ! start_vm_installation "$qemu_kvm_hostname" "golden image disk with default specs"; then
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    else
        # Default path: preserve disk size
        print_info "[INFO] Reimaging VM \"$qemu_kvm_hostname\" by replacing its qcow2 disk with the golden image disk..."
        
        vm_qcow2_disk_path="/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2"
        
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/get-current-disk-size.sh
        get_current_disk_size "$qemu_kvm_hostname"
        current_disk_gib="${CURRENT_DISK_SIZE:-20}"
        
        golden_disk_gib=$(sudo qemu-img info "${golden_qcow2_disk_path}" 2>/dev/null | grep "virtual size" | grep -o '[0-9]\+ GiB' | cut -d' ' -f1)
        golden_disk_gib="${golden_disk_gib:-20}"
        
        # Delete existing qcow2 disk and recreate with appropriate size
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/delete-vm-disk.sh
        delete_vm_disk "$qemu_kvm_hostname"
        
        if ! sudo qemu-img convert -O qcow2 "${golden_qcow2_disk_path}" "${vm_qcow2_disk_path}" >/dev/null 2>&1; then
            print_error "[ERROR] Failed to convert golden image disk for \"$qemu_kvm_hostname\"."
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/resize-disk-if-larger.sh
        resize_disk_if_larger "$qemu_kvm_hostname" "$current_disk_gib" "$golden_disk_gib"
        
        # Start reimaging process
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/start-vm-for-reimage.sh
        if ! start_vm_for_reimage "$qemu_kvm_hostname" "reimaging via golden image disk"; then
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    fi

    SUCCESSFUL_VMS+=("$qemu_kvm_hostname")

    # Show completion message for single VM
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-vm-completion-message.sh
    show_vm_completion_message "${qemu_kvm_hostname}" "${ATTACH_CONSOLE}" "${TOTAL_VMS}" "reimaging via golden image disk" "Reimaging via golden image disk takes ~1 minute."
done

# Summary for multiple VMs
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/show-vm-operation-summary.sh
if ! show_vm_operation_summary "${TOTAL_VMS}" "SUCCESSFUL_VMS" "FAILED_VMS" "reimaging via golden image disk" "Reimaging via golden image disk takes ~1 minute per VM."; then
    exit 1
fi




