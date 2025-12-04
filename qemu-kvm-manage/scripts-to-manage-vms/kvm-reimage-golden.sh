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
    print_info "Usage: qlabvmctl reimage-golden [OPTIONS] [hostname]

Options:
  -c, --console        Attach console during reimage (single VM only)
  -C, --clean-install  Destroy VM and reinstall with default specs (2 vCPUs, 2 GiB RAM, 20 GiB disk)
  -H, --hosts          Specify multiple hostnames (comma-separated)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to reimage via golden image disk (optional, will prompt if not given)

Examples:
  qlabvmctl reimage-golden vm1                               # Reimage single VM
  qlabvmctl reimage-golden vm1 --console                     # Reimage and attach console
  qlabvmctl reimage-golden vm1 --clean-install               # Reimage with default specs
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
    ((CURRENT_VM++))
    
    if [[ $TOTAL_VMS -gt 1 ]]; then
        print_info "[INFO] Processing VM ${CURRENT_VM}/${TOTAL_VMS}: ${qemu_kvm_hostname}"
    fi

    # Check if VM exists in 'virsh list --all'
    if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
        print_error "[ERROR] VM \"$qemu_kvm_hostname\" does not exist."
        if [[ $TOTAL_VMS -eq 1 ]]; then
            exit 1
        else
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    fi

    # Prevent re-imaging of lab infra server VM
    if [[ "$qemu_kvm_hostname" == "$lab_infra_server_hostname" ]]; then
        print_error "[ERROR] Cannot reimage Lab Infra Server!"
        print_warning "[WARNING] You are attempting to reimage the lab infrastructure server VM: $lab_infra_server_hostname"
        print_info "[INFO] This VM hosts critical services and must not be destroyed."
        if [[ $TOTAL_VMS -eq 1 ]]; then
            exit 1
        else
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    fi
    
    # Confirmation prompt for single VM (unless --hosts with multiple VMs)
    if [[ $TOTAL_VMS -eq 1 ]]; then
        print_warning "[WARNING] This will reimage VM \"$qemu_kvm_hostname\" using golden image!"
        print_warning "[WARNING] All existing data on this VM will be permanently lost."
        read -rp "Are you sure you want to proceed? (yes/no): " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            print_info "[INFO] Operation cancelled by user."
            exit 0
        fi
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

    # Update /etc/hosts
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/update-etc-hosts.sh
    if ! update_etc_hosts "${qemu_kvm_hostname}" "${IPV4_ADDRESS}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Validate golden image disk exists
    golden_qcow2_disk_path="/kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2"
    if [ ! -f "${golden_qcow2_disk_path}" ]; then
        print_error "[ERROR] Golden image disk not found for \"$qemu_kvm_hostname\"!"
        print_info "[INFO] Expected at: ${golden_qcow2_disk_path}"
        print_info "[INFO] To build the golden image disk, run: qlabvmctl build-golden-image"
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Shut down VM if running
    if sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
        print_info "[INFO] VM \"$qemu_kvm_hostname\" is currently running. Shutting down before reimaging..."
        if error_msg=$(sudo virsh destroy "$qemu_kvm_hostname" 2>&1); then
            print_success "[SUCCESS] VM \"$qemu_kvm_hostname\" has been shut down successfully."
        else
            print_warning "[WARNING] Could not shut down VM \"$qemu_kvm_hostname\"."
            print_warning "$error_msg"
        fi
    fi

    # If --clean-install is specified, destroy and reinstall VM with default specs
    if [[ "$CLEAN_INSTALL" == "yes" ]]; then
        print_info "[INFO] Using --clean-install: VM will be destroyed and reinstalled with default specs (2 vCPUs, 2 GiB RAM, 20 GiB disk)."
        
        # Undefine the VM
        print_info "[INFO] Undefining VM \"$qemu_kvm_hostname\"..."
        if error_msg=$(sudo virsh undefine "$qemu_kvm_hostname" --nvram 2>&1); then
            print_success "[SUCCESS] VM undefined successfully."
        else
            print_error "[FAILED] Could not undefine VM \"$qemu_kvm_hostname\"."
            print_error "$error_msg"
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        # Delete VM folder and contents
        print_info "[INFO] Deleting VM folder /kvm-hub/vms/${qemu_kvm_hostname}..."
        if sudo rm -rf "/kvm-hub/vms/${qemu_kvm_hostname}"; then
            print_success "[SUCCESS] VM folder deleted successfully."
        else
            print_error "[FAILED] Could not delete VM folder."
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        # Create fresh VM directory
        if ! mkdir -p /kvm-hub/vms/"${qemu_kvm_hostname}"; then
            print_error "[ERROR] Failed to create VM directory: /kvm-hub/vms/${qemu_kvm_hostname}"
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        # Clone golden image disk
        print_info "[INFO] Cloning golden image disk to /kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2..." nskip
        if error_msg=$(sudo qemu-img convert -O qcow2 "${golden_qcow2_disk_path}" /kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2 2>&1); then
            print_success "[ SUCCESS ]"
        else
            print_error "[ FAILED ]"
            print_error "$error_msg"
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        # Install VM with default specs using default-vm-install function
        print_info "[INFO] Starting VM installation of \"$qemu_kvm_hostname\" with default specs via golden image disk..."
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh
        if ! virt_install_output=$(source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/default-vm-install.sh 2>&1); then
            print_error "[ERROR] Failed to start VM installation for \"$qemu_kvm_hostname\"."
            if [[ -n "$virt_install_output" ]]; then
                print_error "$virt_install_output"
            fi
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    else
        # Default path: preserve disk size
        print_info "[INFO] Reimaging VM \"$qemu_kvm_hostname\" by replacing its qcow2 disk with the golden image disk..."
        
        vm_qcow2_disk_path="/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2"
        current_disk_gib=$(sudo qemu-img info "${vm_qcow2_disk_path}" 2>/dev/null | grep "virtual size" | grep -o '[0-9]\+ GiB' | cut -d' ' -f1)
        golden_disk_gib=$(sudo qemu-img info "${golden_qcow2_disk_path}" 2>/dev/null | grep "virtual size" | grep -o '[0-9]\+ GiB' | cut -d' ' -f1)
        
        # Use default if disk doesn't exist or size extraction failed
        default_qcow2_disk_gib=20
        if [[ -z "$current_disk_gib" ]]; then
            current_disk_gib="$default_qcow2_disk_gib"
        fi
        if [[ -z "$golden_disk_gib" ]]; then
            golden_disk_gib="$default_qcow2_disk_gib"
        fi
        
        # Delete existing qcow2 disk and recreate with appropriate size
        sudo rm -f "${vm_qcow2_disk_path}"
        if ! sudo qemu-img convert -O qcow2 "${golden_qcow2_disk_path}" "${vm_qcow2_disk_path}" >/dev/null 2>&1; then
            print_error "[ERROR] Failed to convert golden image disk for \"$qemu_kvm_hostname\"."
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        
        if [[ "$current_disk_gib" -gt "$golden_disk_gib" ]]; then
            if sudo qemu-img resize "${vm_qcow2_disk_path}" "${current_disk_gib}G" >/dev/null 2>&1; then
                print_success "[SUCCESS] Retained disk size of ${current_disk_gib} GiB for VM \"$qemu_kvm_hostname\"."
            fi
        fi
        
        # Start reimaging process
        print_info "[INFO] Starting reimaging of VM \"$qemu_kvm_hostname\" via golden image disk..."
        if error_msg=$(sudo virsh start "$qemu_kvm_hostname" 2>&1); then
            print_success "[SUCCESS] VM started successfully."
        else
            print_error "[FAILED] Could not start VM \"$qemu_kvm_hostname\"."
            print_error "$error_msg"
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




