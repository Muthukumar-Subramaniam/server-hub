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
OS_DISTRO=""
VERSION_TYPE="latest"
HOSTNAMES=()
SUPPORTS_CLEAN_INSTALL="yes"
SUPPORTS_FORCE="yes"
SUPPORTS_DISTRO="yes"
SUPPORTS_VERSION="yes"

# Function to show help
fn_show_help() {
    print_cyan "Usage: qlabvmctl reimage-golden [OPTIONS] [hostname]
Options:
  -c, --console        Attach console during reimage (single VM only)
  -C, --clean-install  Destroy VM and reinstall with default specs (2 vCPUs, 2 GiB RAM, 20 GiB disk)
  -d, --distro         Specify OS distribution
                       (almalinux, rocky, oraclelinux, centos-stream, rhel, ubuntu-lts, opensuse-leap)
  -v, --version        Specify OS version: latest (default) or previous
  -f, --force          Skip confirmation prompt
  -H, --hosts          Specify multiple hostnames (comma-separated)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to reimage via golden image disk (optional, will prompt if not given)

Examples:
  qlabvmctl reimage-golden vm1                                   # Reimage single VM
  qlabvmctl reimage-golden vm1 --console                         # Reimage and attach console
  qlabvmctl reimage-golden vm1 --clean-install                   # Reimage with default specs
  qlabvmctl reimage-golden vm1 --distro almalinux                # Reimage with AlmaLinux (latest)
  qlabvmctl reimage-golden vm1 -d ubuntu-lts -v previous         # Reimage with Ubuntu 22.04
  qlabvmctl reimage-golden -f vm1                                # Reimage without confirmation
  qlabvmctl reimage-golden --hosts vm1,vm2,vm3 -d ubuntu-lts     # Reimage multiple with Ubuntu LTS
  qlabvmctl reimage-golden -H vm1,vm2,vm3 --clean-install       # Reimage multiple with defaults
"
}

# Parse and validate arguments
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/parse-vm-command-args.sh
parse_vm_command_args "$@"

# Validate: if --version is specified without --distro, warn user
if [[ "$VERSION_TYPE" != "latest" && -z "$OS_DISTRO" ]]; then
    print_warning "The --version option is specified without --distro."
    print_info "The version will be applied if OS is auto-detected from hostname pattern."
    print_info "If auto-detection fails, you'll be prompted to select OS distribution interactively."
    echo ""
fi

# Save command-line distro and version if specified
CMDLINE_OS_DISTRO="$OS_DISTRO"
CMDLINE_VERSION_TYPE="$VERSION_TYPE"

# Main reimage loop
CURRENT_VM=0
FAILED_VMS=()
SUCCESSFUL_VMS=()

for qemu_kvm_hostname in "${HOSTNAMES[@]}"; do
    # Reset OS_DISTRO and VERSION_TYPE to command-line values for each VM
    OS_DISTRO="$CMDLINE_OS_DISTRO"
    VERSION_TYPE="$CMDLINE_VERSION_TYPE"
    
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

    print_info "Creating first boot environment for '${qemu_kvm_hostname}' using ksmanager..."

    # Check if golden image exists for specified distro
    if [[ -n "$OS_DISTRO" ]]; then
        # Normalize OS distro name first for golden image check
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/normalize-os-distro.sh
        if ! normalize_os_distro "${OS_DISTRO}"; then
            print_error "Invalid OS distribution: $OS_DISTRO"
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        NORMALIZED_DISTRO="$NORMALIZED_OS_DISTRO"
        
        # Golden images follow pattern: {distro}-golden-image.*-{version}.qcow2
        golden_image_pattern="${NORMALIZED_DISTRO}-golden-image.*-${VERSION_TYPE}.qcow2"
        if ! ls /kvm-hub/golden-images-disk-store/${golden_image_pattern} &>/dev/null; then
            print_error "Golden image not found for '${OS_DISTRO}' (${VERSION_TYPE})"
            print_info "Available golden images:"
            if ls /kvm-hub/golden-images-disk-store/*.qcow2 &>/dev/null; then
                ls -1 /kvm-hub/golden-images-disk-store/*.qcow2 | xargs -n1 basename | sed 's/-golden-image.*//' | sort -u | sed 's/^/  - /'
            else
                echo "  (none)"
            fi
            print_info "Use 'qlabvmctl build-golden-image --distro ${OS_DISTRO} --version ${VERSION_TYPE}' to create it"
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    fi

    # Run ksmanager and extract VM details
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/run-ksmanager.sh
    ksmanager_opts="--qemu-kvm --golden-image"
    [[ -n "$OS_DISTRO" ]] && ksmanager_opts="$ksmanager_opts --distro $OS_DISTRO"
    [[ -n "$VERSION_TYPE" ]] && ksmanager_opts="$ksmanager_opts --version $VERSION_TYPE"
    if ! run_ksmanager "${qemu_kvm_hostname}" "$ksmanager_opts"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Use the normalized distro from earlier validation, not the extracted OS name from ksmanager
    if [[ -n "$NORMALIZED_DISTRO" ]]; then
        OS_DISTRO="$NORMALIZED_DISTRO"
    else
        # If no --distro was specified, normalize the extracted OS name from ksmanager output
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/normalize-os-distro.sh
        if ! normalize_os_distro "${OS_DISTRO}"; then
            print_error "Failed to normalize OS distro for \"$qemu_kvm_hostname\"."
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        OS_DISTRO="$NORMALIZED_OS_DISTRO"
    fi

    # Update /etc/hosts
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/update-etc-hosts.sh
    if ! update_etc_hosts "${qemu_kvm_hostname}" "${IPV4_ADDRESS}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/validate-golden-image-exists.sh
    if ! validate_golden_image_exists "$qemu_kvm_hostname" "${OS_DISTRO}" "${VERSION_TYPE}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Construct golden image FQDN matching ksmanager's format
    golden_image_fqdn="${OS_DISTRO}-golden-image-${VERSION_TYPE}.${lab_infra_domain_name}"
    golden_qcow2_disk_path="/kvm-hub/golden-images-disk-store/${golden_image_fqdn}.qcow2"

    # Shut down VM if running
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
    POWEROFF_VM_CONTEXT="Powering off before reimaging" poweroff_vm "$qemu_kvm_hostname"

    # If --clean-install is specified, destroy and reinstall VM with default specs
    if [[ "$CLEAN_INSTALL" == "yes" ]]; then
        print_info "Using --clean-install: VM will be destroyed and reinstalled with default specs (2 vCPUs, 2 GiB RAM, 20 GiB disk)."
        
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
        print_info "Starting VM installation of \"$qemu_kvm_hostname\" with default specs via golden image disk..."
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/start-vm-installation.sh
        if ! start_vm_installation "$qemu_kvm_hostname" "golden image disk with default specs"; then
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    else
        # Default path: preserve disk size
        print_task "Reimaging VM '${qemu_kvm_hostname}' by replacing qcow2 disk..."
        
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
            print_task_fail
            print_error "Failed to convert golden image disk for \"$qemu_kvm_hostname\"."
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        print_task_done
        
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




