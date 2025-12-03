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
LOG_FILE=""

# Function to show help
fn_show_help() {
    print_notify "Usage: kvm-install-golden [OPTIONS] [hostname]

Options:
  -c, --console        Attach console during installation (single VM only)
  -H, --hosts          Specify multiple hostnames (comma-separated)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to install via golden image disk (optional, will prompt if not given)

Examples:
  kvm-install-golden vm1                           # Install single VM
  kvm-install-golden vm1 --console                 # Install and attach console
  kvm-install-golden --hosts vm1,vm2,vm3           # Install multiple VMs
  kvm-install-golden -H vm1,vm2,vm3                # Same as above
"
}

# Cleanup function
cleanup() {
    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE"
    fi
}

trap cleanup EXIT

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            fn_show_help
            exit 0
            ;;
        -c|--console)
            if [[ "$ATTACH_CONSOLE" == "yes" ]]; then
                print_error "[ERROR] Duplicate --console/-c option."
                fn_show_help
                exit 1
            fi
            ATTACH_CONSOLE="yes"
            shift
            ;;
        -H|--hosts)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "[ERROR] --hosts/-H requires a comma-separated list of hostnames."
                fn_show_help
                exit 1
            fi
            IFS=',' read -ra HOSTNAMES <<< "$2"
            shift 2
            ;;
        -*)
            print_error "[ERROR] No such option: $1"
            fn_show_help
            exit 1
            ;;
        *)
            if [[ ${#HOSTNAMES[@]} -eq 0 ]]; then
                HOSTNAMES+=("$1")
            else
                print_error "[ERROR] Cannot mix positional hostname with --hosts/-H option."
                fn_show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate console + multiple VMs conflict
if [[ "$ATTACH_CONSOLE" == "yes" && ${#HOSTNAMES[@]} -gt 1 ]]; then
    print_error "[ERROR] --console/-c option cannot be used with multiple VMs."
    fn_show_help
    exit 1
fi

# Remove duplicates from HOSTNAMES
if [[ ${#HOSTNAMES[@]} -gt 1 ]]; then
    UNIQUE_HOSTNAMES=($(printf '%s\n' "${HOSTNAMES[@]}" | sort -u))
    if [[ ${#UNIQUE_HOSTNAMES[@]} -ne ${#HOSTNAMES[@]} ]]; then
        print_warning "[WARNING] Removed duplicate hostnames from the list."
        HOSTNAMES=("${UNIQUE_HOSTNAMES[@]}")
    fi
fi

# If no hostnames provided, prompt for one
if [[ ${#HOSTNAMES[@]} -eq 0 ]]; then
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh ""
    HOSTNAMES=("$qemu_kvm_hostname")
fi

# Validate all hostnames using input-hostname.sh
if [[ ${#HOSTNAMES[@]} -gt 0 ]]; then
    validated_hosts=()
    for vm_name in "${HOSTNAMES[@]}"; do
        vm_name=$(echo "$vm_name" | xargs) # Trim whitespace
        [[ -z "$vm_name" ]] && continue  # Skip empty entries
        # Use input-hostname.sh to validate and normalize
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_name"
        validated_hosts+=("$qemu_kvm_hostname")
    done
    HOSTNAMES=("${validated_hosts[@]}")
fi

# Check if any valid hosts remain after validation
if [[ ${#HOSTNAMES[@]} -eq 0 ]]; then
    print_error "[ERROR] No valid hostnames provided."
    exit 1
fi

# Main installation loop
TOTAL_VMS=${#HOSTNAMES[@]}
CURRENT_VM=0
FAILED_VMS=()
SUCCESSFUL_VMS=()

for qemu_kvm_hostname in "${HOSTNAMES[@]}"; do
    ((CURRENT_VM++))
    
    if [[ $TOTAL_VMS -gt 1 ]]; then
        print_info "[INFO] Processing VM ${CURRENT_VM}/${TOTAL_VMS}: ${qemu_kvm_hostname}"
    fi

    # Check if VM exists in 'virsh list --all'
    if sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
        print_error "[ERROR] VM \"$qemu_kvm_hostname\" exists already."
        if [[ $TOTAL_VMS -eq 1 ]]; then
            print_warning "[WARNING] Either do one of the following:"
            print_info "[INFO] Remove the VM using 'kvm-remove', then try again."
            print_info "[INFO] Re-image the VM using 'kvm-reimage-golden' or 'kvm-reimage-pxe'."
            exit 1
        else
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    fi

    print_info "[INFO] Creating first boot environment for '${qemu_kvm_hostname}' using ksmanager..."

    LOG_FILE="/tmp/install-vm-logs-${qemu_kvm_hostname}"
    >"$LOG_FILE"

    if $lab_infra_server_mode_is_host; then
        if ! sudo ksmanager "${qemu_kvm_hostname}" --qemu-kvm --golden-image | tee -a "$LOG_FILE"; then
            print_error "[FAILED] ksmanager execution failed for \"$qemu_kvm_hostname\"."
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    else
        if ! ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${lab_infra_admin_username}@${lab_infra_server_ipv4_address}" "sudo ksmanager ${qemu_kvm_hostname} --qemu-kvm --golden-image" | tee -a "$LOG_FILE"; then
            print_error "[FAILED] ksmanager execution failed for \"$qemu_kvm_hostname\"."
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    fi

    MAC_ADDRESS=$( grep "MAC Address  :" "$LOG_FILE" | awk -F': ' '{print $2}' | tr -d '[:space:]' )
    IPV4_ADDRESS=$( grep "IPv4 Address :" "$LOG_FILE" | awk -F': ' '{print $2}' | tr -d '[:space:]' )
    OS_DISTRO=$( grep "Requested OS :" "$LOG_FILE" | awk -F': ' '{print $2}' | tr -d '[:space:]' )

    # Validate extracted values
    if [[ -z "${MAC_ADDRESS}" ]]; then
        print_error "[ERROR] Failed to extract MAC address from ksmanager output for \"$qemu_kvm_hostname\"."
        print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    if [[ -z "${IPV4_ADDRESS}" ]]; then
        print_error "[ERROR] Failed to extract IPv4 address from ksmanager output for \"$qemu_kvm_hostname\"."
        print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    if [[ -z "${OS_DISTRO}" ]]; then
        print_error "[ERROR] Failed to extract OS distro from ksmanager output for \"$qemu_kvm_hostname\"."
        print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Normalize OS distro names
    if echo "$OS_DISTRO" | grep -qi "almalinux"; then
        OS_DISTRO="almalinux"
    elif echo "$OS_DISTRO" | grep -qi "centos"; then
        OS_DISTRO="centos-stream"
    elif echo "$OS_DISTRO" | grep -qi "rocky"; then
        OS_DISTRO="rocky"
    elif echo "$OS_DISTRO" | grep -qi "oracle"; then
        OS_DISTRO="oraclelinux"
    elif echo "$OS_DISTRO" | grep -qi "redhat"; then
        OS_DISTRO="rhel"
    elif echo "$OS_DISTRO" | grep -qi "fedora"; then
        OS_DISTRO="fedora"
    elif echo "$OS_DISTRO" | grep -qi "ubuntu"; then
        OS_DISTRO="ubuntu-lts"
    elif echo "$OS_DISTRO" | grep -qi "suse"; then
        OS_DISTRO="opensuse-leap"
    else
        print_error "[ERROR] Unrecognized OS distro: $OS_DISTRO for \"$qemu_kvm_hostname\"."
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    # Create VM directory
    if ! mkdir -p /kvm-hub/vms/"${qemu_kvm_hostname}"; then
        print_error "[ERROR] Failed to create VM directory: /kvm-hub/vms/${qemu_kvm_hostname}"
        FAILED_VMS+=("$qemu_kvm_hostname")
        continue
    fi

    print_info "[INFO] Updating /etc/hosts file for ${qemu_kvm_hostname}..." nskip

    if grep -q "${qemu_kvm_hostname}" /etc/hosts; then
        HOST_FILE_IPV4=$( grep "${qemu_kvm_hostname}" /etc/hosts | awk '{print $1}' )
        if [ "${HOST_FILE_IPV4}" != "${IPV4_ADDRESS}" ]; then
            if error_msg=$(sudo sed -i.bak "/${qemu_kvm_hostname}/s/.*/${IPV4_ADDRESS} ${qemu_kvm_hostname}/" /etc/hosts 2>&1); then
                print_success "[ SUCCESS ]"
            else
                print_error "[ FAILED ]"
                print_error "$error_msg"
                FAILED_VMS+=("$qemu_kvm_hostname")
                continue
            fi
        else
            print_success "[ SUCCESS ]"
        fi
    else
        if error_msg=$(echo "${IPV4_ADDRESS} ${qemu_kvm_hostname}" | sudo tee -a /etc/hosts >/dev/null 2>&1); then
            print_success "[ SUCCESS ]"
        else
            print_error "[ FAILED ]"
            print_error "$error_msg"
            FAILED_VMS+=("$qemu_kvm_hostname")
            continue
        fi
    fi

    if [ ! -f /kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2 ]; then
        print_error "[ERROR] Golden image disk not found for \"$qemu_kvm_hostname\"!"
        print_info "[INFO] Expected at: /kvm-hub/golden-images-disk-store/${OS_DISTRO}-golden-image.${lab_infra_domain_name}.qcow2"
        print_info "[INFO] To build the golden image disk, run: kvm-build-golden-image"
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

    if [[ "$ATTACH_CONSOLE" == "yes" ]]; then
        print_info "[INFO] Attaching to VM console. Press Ctrl+] to exit console."
        sudo virsh console "${qemu_kvm_hostname}"
    elif [[ $TOTAL_VMS -eq 1 ]]; then
        print_info "[INFO] The VM will reboot once or twice during the installation process (~1 minute)."
        print_info "[INFO] To monitor installation progress, use: kvm-console $qemu_kvm_hostname"
        print_info "[INFO] To check VM status, use: kvm-list"
        print_success "[SUCCESS] VM \"$qemu_kvm_hostname\" installation initiated successfully via golden image disk."
    fi

    # Clean up log file for this VM
    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE"
    fi
done

# Summary for multiple VMs
if [[ $TOTAL_VMS -gt 1 ]]; then
    echo ""
    print_info "[INFO] Installation Summary:"
    print_success "[SUCCESS] Successfully initiated installation via golden image disk: ${#SUCCESSFUL_VMS[@]} VM(s)"
    if [[ ${#SUCCESSFUL_VMS[@]} -gt 0 ]]; then
        for vm in "${SUCCESSFUL_VMS[@]}"; do
            print_success "  ✓ $vm"
        done
    fi
    
    if [[ ${#FAILED_VMS[@]} -gt 0 ]]; then
        print_error "[FAILED] Failed to initiate installation: ${#FAILED_VMS[@]} VM(s)"
        for vm in "${FAILED_VMS[@]}"; do
            print_error "  ✗ $vm"
        done
        exit 1
    fi
    
    print_info "[INFO] All VMs will reboot once or twice during installation (~1 minute each)."
    print_info "[INFO] To monitor installation progress, use: kvm-console <hostname>"
    print_info "[INFO] To check VM status, use: kvm-list"
fi
