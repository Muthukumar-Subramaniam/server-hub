#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
DIR_PATH_SCRIPTS_TO_MANAGE_VMS='/server-hub/qemu-kvm-manage/scripts-to-manage-vms'

ATTACH_CONSOLE="no"
FORCE_DEFAULT="no"
HOSTNAMES=()
LOG_FILE=""

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl reimage-golden [OPTIONS] [hostname]

Options:
  -c, --console        Attach console during reimage (single VM only)
  -f, --force-default  Destroy VM and reinstall with default specs (2 vCPUs, 2 GiB RAM, 20 GiB disk)
  -H, --hosts          Specify multiple hostnames (comma-separated)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to reimage via golden image disk (optional, will prompt if not given)

Examples:
  qlabvmctl reimage-golden vm1                                # Reimage single VM
  qlabvmctl reimage-golden vm1 --console                      # Reimage and attach console
  qlabvmctl reimage-golden vm1 --force-default                # Reimage with default specs
  qlabvmctl reimage-golden --hosts vm1,vm2,vm3                # Reimage multiple VMs
  qlabvmctl reimage-golden -H vm1,vm2,vm3 --force-default     # Reimage multiple with defaults
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
        -f|--force-default)
            if [[ "$FORCE_DEFAULT" == "yes" ]]; then
                print_error "[ERROR] Duplicate --force-default option."
                fn_show_help
                exit 1
            fi
            FORCE_DEFAULT="yes"
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

# Main reimage loop
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

    LOG_FILE="/tmp/reimage-vm-logs-${qemu_kvm_hostname}"
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
    if [[ -z "${MAC_ADDRESS}" ]] || [[ -z "${IPV4_ADDRESS}" ]]; then
        print_error "[ERROR] Failed to extract information from ksmanager output for \"$qemu_kvm_hostname\"."
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

    # If --force-default is specified, destroy and reinstall VM with default specs
    if [[ "$FORCE_DEFAULT" == "yes" ]]; then
        print_info "[INFO] Using --force-default: VM will be destroyed and reinstalled with default specs (2 vCPUs, 2 GiB RAM, 20 GiB disk)."
        
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

    # Console attachment logic
    if [[ "$ATTACH_CONSOLE" == "yes" ]]; then
        print_info "[INFO] Attaching to VM console. Press Ctrl+] to exit console."
        sudo virsh console "${qemu_kvm_hostname}"
    elif [[ $TOTAL_VMS -eq 1 ]]; then
        print_info "[INFO] Reimaging via golden image disk takes ~1 minute."
        print_info "[INFO] To monitor reimaging progress, use: qlabvmctl console $qemu_kvm_hostname"
        print_info "[INFO] To check VM status, use: qlabvmctl list"
        print_success "[SUCCESS] VM \"$qemu_kvm_hostname\" reimaging initiated successfully via golden image disk."
    fi

    # Clean up log file for this VM
    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE"
    fi
done

# Summary for multiple VMs
if [[ $TOTAL_VMS -gt 1 ]]; then
    echo ""
    print_info "[INFO] Reimage Summary:"
    if [[ ${#SUCCESSFUL_VMS[@]} -gt 0 ]]; then
        print_success "[SUCCESS] Successfully initiated reimaging via golden image disk: ${#SUCCESSFUL_VMS[@]} VM(s)"
        for vm in "${SUCCESSFUL_VMS[@]}"; do
            print_success "  ✓ $vm"
        done
    fi
    
    if [[ ${#FAILED_VMS[@]} -gt 0 ]]; then
        print_error "[FAILED] Failed to initiate reimaging: ${#FAILED_VMS[@]} VM(s)"
        for vm in "${FAILED_VMS[@]}"; do
            print_error "  ✗ $vm"
        done
        exit 1
    fi
    
    print_info "[INFO] Reimaging via golden image disk takes ~1 minute per VM."
    print_info "[INFO] To monitor reimaging progress, use: qlabvmctl console <hostname>"
    print_info "[INFO] To check VM status, use: qlabvmctl list"
fi




