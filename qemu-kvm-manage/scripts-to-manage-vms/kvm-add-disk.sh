#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl add-disk [OPTIONS] [hostname]

Options:
  -f, --force          Force power-off without prompt if VM is running
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to add disks to (optional, will prompt if not given)

Examples:
  qlabvmctl add-disk vm1                  # Add disks to VM with interactive prompts
  qlabvmctl add-disk -f vm1               # Force power-off if running without prompt
"
}

# Parse arguments
force_poweroff=false
vm_hostname_arg=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            fn_show_help
            exit 0
            ;;
        -f|--force)
            force_poweroff=true
            shift
            ;;
        -*)
            print_error "[ERROR] Unknown option: $1"
            fn_show_help
            exit 1
            ;;
        *)
            if [[ -n "$vm_hostname_arg" ]]; then
                print_error "[ERROR] Multiple hostnames provided. Only one VM can be processed at a time."
                fn_show_help
                exit 1
            fi
            vm_hostname_arg="$1"
            shift
            ;;
    esac
done

# Use argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_hostname_arg"

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    print_error "[ERROR] VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

fn_shutdown_or_poweroff() {
    # If force flag is set, try graceful shutdown first, then force if needed
    if [[ "$force_poweroff" == true ]]; then
        print_info "[INFO] Force flag detected. Attempting graceful shutdown first..."
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh
        SHUTDOWN_VM_CONTEXT="Attempting graceful shutdown" SHUTDOWN_VM_STRICT=false shutdown_vm "$qemu_kvm_hostname"
        
        # Wait for VM to shut down with timeout
        print_info "[INFO] Waiting for VM \"${qemu_kvm_hostname}\" to shut down (timeout: 30s)..."
        TIMEOUT=30
        ELAPSED=0
        while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
            if (( ELAPSED >= TIMEOUT )); then
                print_warning "[WARNING] Graceful shutdown timed out. Forcing power off..."
                source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
                if ! POWEROFF_VM_CONTEXT="Forcing power off after timeout" POWEROFF_VM_STRICT=true poweroff_vm "$qemu_kvm_hostname"; then
                    exit 1
                fi
                break
            fi
            sleep 2
            ((ELAPSED+=2))
        done
        
        if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
            print_success "[SUCCESS] VM has been shut down successfully. Proceeding further."
        fi
        return 0
    fi
    
    print_warning "[WARNING] VM \"$qemu_kvm_hostname\" is still running!"
    print_info "[INFO] Select an option to proceed:\n"
    echo "	1) Try Graceful Shutdown"
    echo "	2) Force Power Off"
    echo -e "	q) Quit\n"

    read -rp "Enter your choice: " selected_choice

    case "$selected_choice" in
        1)
            print_info "[INFO] Initiating graceful shutdown..."
            source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh
            if ! SHUTDOWN_VM_CONTEXT="Initiating graceful shutdown" shutdown_vm "$qemu_kvm_hostname"; then
                exit 1
            fi
            
            # Wait for VM to shut down with timeout
            print_info "[INFO] Waiting for VM \"${qemu_kvm_hostname}\" to shut down (timeout: 60s)..."
            TIMEOUT=60
            ELAPSED=0
            while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
                if (( ELAPSED >= TIMEOUT )); then
                    print_warning "[WARNING] VM did not shut down within ${TIMEOUT}s."
                    print_info "[INFO] You may want to force power off instead."
                    exit 1
                fi
                sleep 2
                ((ELAPSED+=2))
            done
            print_success "[SUCCESS] VM has been shut down successfully. Proceeding further."
            ;;
        2)
            print_info "[INFO] Forcing power off..."
            source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
            if ! POWEROFF_VM_CONTEXT="Forcing power off" POWEROFF_VM_STRICT=true poweroff_vm "$qemu_kvm_hostname"; then
                exit 1
            fi
            ;;
        q)
            print_info "[INFO] Quitting without any action."
            exit 0
            ;;
        *)
            print_error "[ERROR] Invalid option!"
            exit 1
            ;;
    esac
}

if ! sudo virsh list  | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    print_success "[SUCCESS] VM \"$qemu_kvm_hostname\" is not running. Proceeding further."
else
    fn_shutdown_or_poweroff
fi

print_info "[INFO] Select number of disks to add (1-10):"
while true; do
    read -rp "Enter disk count: " DISK_COUNT
    if [[ "$DISK_COUNT" =~ ^[1-9][0-9]*$ ]] && (( DISK_COUNT <= 10 )); then
        print_success "[SUCCESS] Selected $DISK_COUNT disk(s)."
        break
    else
        print_error "[ERROR] Invalid input! Enter a number between 1 and 10."
    fi
done

print_info "[INFO] Allowed disk size: Steps of 5GB (5, 10, 15 ... up to 50GB)"
while true; do
    read -rp "Enter disk size in GB (default 5): " DISK_SIZE_GB
    DISK_SIZE_GB=${DISK_SIZE_GB:-5}
    if [[ "$DISK_SIZE_GB" =~ ^[0-9]+$ ]] && (( DISK_SIZE_GB >= 5 && DISK_SIZE_GB % 5 == 0 && DISK_SIZE_GB <= 50 )); then
        print_success "[SUCCESS] Selected ${DISK_SIZE_GB}GB disk size."
        break
    else
        print_error "[ERROR] Invalid size! Enter a multiple of 5 between 5 and 50."
    fi
done

VM_DIR="/kvm-hub/vms/${qemu_kvm_hostname}"

# Verify VM directory exists
if [[ ! -d "$VM_DIR" ]]; then
    print_error "[ERROR] VM directory does not exist: $VM_DIR"
    exit 1
fi

# Determine existing disks using associative array for O(1) lookup
declare -A EXISTING_DISKS
for disk_file in "$VM_DIR"/*.qcow2; do
    [[ -e "$disk_file" ]] || continue
    BASENAME=$(basename "$disk_file")
    EXISTING_DISKS["$BASENAME"]=1
done

# Function to get next available disk letter
get_next_disk_letter() {
    local letter
    for letter in {b..z}; do
        if [[ -z "${EXISTING_DISKS[${qemu_kvm_hostname}_vd${letter}.qcow2]}" ]]; then
            echo "$letter"
            return 0
        fi
    done
    return 1
}

for ((i=1; i<=DISK_COUNT; i++)); do
    # Get next available letter
    if ! NEXT_DISK_LETTER=$(get_next_disk_letter); then
        print_error "[ERROR] Maximum disk letters reached (vdb-vdz)."
        exit 1
    fi

    DISK_NAME="${qemu_kvm_hostname}_vd${NEXT_DISK_LETTER}.qcow2"
    DISK_PATH="$VM_DIR/$DISK_NAME"

    # Create disk
    print_info "[INFO] Creating disk vd${NEXT_DISK_LETTER} (${DISK_SIZE_GB}GB)..." nskip
    if error_msg=$(qemu-img create -f qcow2 "$DISK_PATH" "${DISK_SIZE_GB}G" 2>&1); then
        print_success "[ SUCCESS ]"
    else
        print_error "[ FAILED ]"
        print_error "$error_msg"
        exit 1
    fi

    # Attach disk
    print_info "[INFO] Attaching vd${NEXT_DISK_LETTER} (${DISK_SIZE_GB}GB) to VM \"$qemu_kvm_hostname\"..." nskip
    if error_msg=$(sudo virsh attach-disk "$qemu_kvm_hostname" "$DISK_PATH" "vd$NEXT_DISK_LETTER" --subdriver qcow2 --persistent 2>&1); then
        print_success "[ SUCCESS ]"
    else
        print_error "[ FAILED ]"
        print_error "$error_msg"
        exit 1
    fi

    # Mark disk as used
    EXISTING_DISKS["$DISK_NAME"]=1
done

print_success "[SUCCESS] Added $DISK_COUNT ${DISK_SIZE_GB}GB disk(s) to VM \"$qemu_kvm_hostname\"."
print_info "[INFO] Starting VM \"$qemu_kvm_hostname\"..."

if error_msg=$(sudo virsh start "$qemu_kvm_hostname" 2>&1); then
    print_success "[SUCCESS] VM \"$qemu_kvm_hostname\" started successfully."
else
    print_error "[FAILED] Could not start VM \"$qemu_kvm_hostname\"."
    print_error "$error_msg"
    exit 1
fi
