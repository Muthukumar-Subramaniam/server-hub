#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/select-ovmf.sh

ATTACH_CONSOLE="no"
OS_DISTRO=""
HOSTNAMES=()
SUPPORTS_DISTRO="yes"

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl install-golden [OPTIONS] [hostname]

Options:
  -c, --console        Attach console during installation (single VM only)
  -d, --distro         Specify OS distribution
                       (almalinux, rocky, oraclelinux, centos-stream, rhel, fedora, ubuntu-lts, opensuse-leap)
  -H, --hosts          Specify multiple hostnames (comma-separated)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to install via golden image disk (optional, will prompt if not given)

Examples:
  qlabvmctl install-golden vm1                              # Install single VM
  qlabvmctl install-golden vm1 --console                    # Install and attach console
  qlabvmctl install-golden vm1 --distro almalinux           # Install with AlmaLinux
  qlabvmctl install-golden --hosts vm1,vm2,vm3              # Install multiple VMs
  qlabvmctl install-golden -H vm1,vm2,vm3 -d ubuntu-lts     # Install multiple with Ubuntu LTS
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

    print_info "[INFO] Creating first boot environment for '${qemu_kvm_hostname}' using ksmanager..."

    # Check if golden image exists for specified distro
    if [[ -n "$OS_DISTRO" ]]; then
        # Normalize OS distro name first for golden image check
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/normalize-os-distro.sh
        if ! normalize_os_distro "${OS_DISTRO}"; then
            print_error "[ERROR] Invalid OS distribution: $OS_DISTRO"
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
        NORMALIZED_DISTRO="$NORMALIZED_OS_DISTRO"
        
        # Golden images follow pattern: {distro}-golden-image.lab.local.qcow2
        golden_image_pattern="${NORMALIZED_DISTRO}-golden-image.*.qcow2"
        if ! ls /kvm-hub/golden-images-disk-store/${golden_image_pattern} &>/dev/null; then
            print_error "[ERROR] Golden image not found for '${OS_DISTRO}'"
            print_info "[INFO] Available golden images:"
            if ls /kvm-hub/golden-images-disk-store/*.qcow2 &>/dev/null; then
                ls -1 /kvm-hub/golden-images-disk-store/*.qcow2 | xargs -n1 basename | sed 's/-golden-image.*//' | sort -u | sed 's/^/  - /'
            else
                echo "  (none)"
            fi
            print_info "[INFO] Use 'qlabvmctl build-golden-image --distro ${OS_DISTRO}' to create it"
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    fi

    # Run ksmanager and extract VM details
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/run-ksmanager.sh
    ksmanager_opts="--qemu-kvm --golden-image"
    [[ -n "$OS_DISTRO" ]] && ksmanager_opts="$ksmanager_opts --distro $OS_DISTRO"
    if ! run_ksmanager "${qemu_kvm_hostname}" "$ksmanager_opts"; then
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

    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/validate-golden-image-exists.sh
    if ! validate_golden_image_exists "$qemu_kvm_hostname" "${OS_DISTRO}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/clone-golden-image-disk.sh
    if ! clone_golden_image_disk "$qemu_kvm_hostname" "${OS_DISTRO}"; then
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Start installation process via golden image disk
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/start-vm-installation.sh
    if ! start_vm_installation "$qemu_kvm_hostname" "golden image disk"; then
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
