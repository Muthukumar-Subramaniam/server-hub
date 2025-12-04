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
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to add disks to (optional, will prompt if not given)

Examples:
  qlabvmctl add-disk vm1                  # Add disks to VM with interactive prompts
"
}

# Handle help and argument validation
if [[ $# -gt 1 ]]; then
    print_error "[ERROR] Too many arguments."
    fn_show_help
    exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    fn_show_help
    exit 0
fi

if [[ "$1" == -* ]]; then
    print_error "[ERROR] No such option: $1"
    fn_show_help
    exit 1
fi

# Use first argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$1"

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    print_error "[ERROR] VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

fn_shutdown_or_poweroff() {
    print_warning "[WARNING] VM \"$qemu_kvm_hostname\" is still running!"
    print_info "[INFO] Select an option to proceed:\n"
    echo "	1) Try Graceful Shutdown"
    echo "	2) Force Power Off"
    echo -e "	q) Quit\n"

    read -rp "Enter your choice: " selected_choice

    case "$selected_choice" in
        1)
            print_info "[INFO] Initiating graceful shutdown..."
            print_info "[INFO] Checking SSH connectivity to ${qemu_kvm_hostname}..."
            if nc -zw5 "${qemu_kvm_hostname}" 22; then
                print_success "[SUCCESS] SSH connectivity confirmed. Initiating graceful shutdown..."
                ssh -o LogLevel=QUIET \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    "${lab_infra_admin_username}@${qemu_kvm_hostname}" \
                    "sudo shutdown -h now"

                print_info "[INFO] Waiting for VM \"${qemu_kvm_hostname}\" to shut down..."
                while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
                    sleep 1
                done
                print_success "[SUCCESS] VM has been shut down successfully. Proceeding further."
            else
                print_error "[ERROR] SSH connection issue with ${qemu_kvm_hostname}."
                print_error "[ERROR] Cannot perform graceful shutdown."
                exit 1
            fi
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

# Determine existing disks
EXISTING_FILES=($(ls "$VM_DIR"/*.qcow2 2>/dev/null))

NEXT_DISK_LETTER="b"

for ((i=1; i<=DISK_COUNT; i++)); do
    # Find the next available letter
    while true; do
        FOUND=0
        for f in "${EXISTING_FILES[@]}"; do
            BASENAME=$(basename "$f")
            if [[ "$BASENAME" == "${qemu_kvm_hostname}_vd${NEXT_DISK_LETTER}.qcow2" ]]; then
                FOUND=1
                break
            fi
        done
        if [[ $FOUND -eq 0 ]]; then
            break
        fi
        # Increment letter properly (b->c->d...->z)
        NEXT_DISK_LETTER=$(echo "$NEXT_DISK_LETTER" | tr 'b-y' 'c-z')
        if [[ "$NEXT_DISK_LETTER" == "z" ]]; then
            print_error "[ERROR] Maximum disk letters reached (vdb-vdz)."
            exit 1
        fi
    done

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

    # Update EXISTING_FILES
    EXISTING_FILES+=("$DISK_PATH")
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
