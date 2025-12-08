#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Function to show help
fn_show_help() {
    print_cyan "Usage: qlabvmctl nic-add [OPTIONS] [hostname]
Options:
  -f, --force          Force power-off without prompt if VM is running
  -c, --count <num>    Number of NICs to add (1-10, default: 1)
  -n, --network <name> Network/bridge to attach to (default: default)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to add NICs to (optional, will prompt if not given)

Examples:
  qlabvmctl nic-add vm1                         # Interactive mode - add 1 NIC
  qlabvmctl nic-add -f vm1                      # Force power-off if running
  qlabvmctl nic-add -c 2 vm1                    # Add 2 NICs
  qlabvmctl nic-add -n br0 vm1                  # Add NIC to specific bridge
  qlabvmctl nic-add -f -c 3 -n default vm2       # Fully automated
"
}

# Parse arguments
force_poweroff=false
vm_hostname_arg=""
nic_count=1
network_name="default"

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
        -c|--count)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "Option -c/--count requires a value."
                exit 1
            fi
            nic_count="$2"
            shift 2
            ;;
        -n|--network)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "Option -n/--network requires a value."
                exit 1
            fi
            network_name="$2"
            shift 2
            ;;
        -*)
            print_error "Unknown option: $1"
            fn_show_help
            exit 1
            ;;
        *)
            if [[ -n "$vm_hostname_arg" ]]; then
                print_error "Multiple hostnames provided. Only one VM can be processed at a time."
                fn_show_help
                exit 1
            fi
            vm_hostname_arg="$1"
            shift
            ;;
    esac
done

# Validate NIC count
if ! [[ "$nic_count" =~ ^[0-9]+$ ]] || (( nic_count < 1 || nic_count > 10 )); then
    print_error "NIC count must be a number between 1 and 10."
    exit 1
fi

# Use argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_hostname_arg"

# Check if VM exists
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    print_error "VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

# Check if network/bridge exists (check both libvirt networks and system bridges)
network_exists=false
if sudo virsh net-list --all | awk '{print $1}' | grep -Fxq "$network_name"; then
    network_exists=true
elif ip link show "$network_name" &>/dev/null; then
    # It's a system bridge
    network_exists=true
fi

if [[ "$network_exists" == false ]]; then
    print_error "Network/bridge \"$network_name\" does not exist."
    print_info "Available libvirt networks:"
    sudo virsh net-list --all | tail -n +3 | awk 'NF>0 {print "  - " $1}'
    print_info "Available bridge interfaces:"
    ip link show type bridge | grep -oP '^\d+: \K[^:]+' | awk '{print "  - " $1}'
    exit 1
fi

fn_shutdown_or_poweroff() {
    # If force flag is set, try graceful shutdown first, then force if needed
    if [[ "$force_poweroff" == true ]]; then
        print_info "Force flag detected. Attempting graceful shutdown first..."
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh
        SHUTDOWN_VM_CONTEXT="Attempting graceful shutdown" SHUTDOWN_VM_STRICT=false shutdown_vm "$qemu_kvm_hostname"
        
        # Wait for VM to shut down with timeout
        print_info "Waiting for VM \"${qemu_kvm_hostname}\" to shut down (timeout: 30s)..."
        TIMEOUT=30
        ELAPSED=0
        while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
            if (( ELAPSED >= TIMEOUT )); then
                print_warning "Graceful shutdown timed out. Forcing power off..."
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
            print_success "VM has been shut down successfully. Proceeding further."
        fi
        return 0
    fi
    
    print_warning "VM \"$qemu_kvm_hostname\" is still running!"
    print_notify "Select an option to proceed:
	1) Try Graceful Shutdown
	2) Force Power Off
	q) Quit"

    read -rp "Enter your choice: " selected_choice

    case "$selected_choice" in
        1)
            print_info "Initiating graceful shutdown..."
            source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh
            if ! SHUTDOWN_VM_CONTEXT="Initiating graceful shutdown" shutdown_vm "$qemu_kvm_hostname"; then
                exit 1
            fi
            
            # Wait for VM to shut down with timeout
            print_info "Waiting for VM \"${qemu_kvm_hostname}\" to shut down (timeout: 60s)..."
            TIMEOUT=60
            ELAPSED=0
            while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
                if (( ELAPSED >= TIMEOUT )); then
                    print_warning "VM did not shut down within ${TIMEOUT}s."
                    print_info "You may want to force power off instead."
                    exit 1
                fi
                sleep 2
                ((ELAPSED+=2))
            done
            print_success "VM has been shut down successfully. Proceeding further."
            ;;
        2)
            print_info "Forcing power off..."
            source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
            if ! POWEROFF_VM_CONTEXT="Forcing power off" POWEROFF_VM_STRICT=true poweroff_vm "$qemu_kvm_hostname"; then
                exit 1
            fi
            ;;
        q)
            print_info "Quitting without any action."
            exit 0
            ;;
        *)
            print_error "Invalid option!"
            exit 1
            ;;
    esac
}

if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    print_info "VM \"$qemu_kvm_hostname\" is not running. Proceeding further."
else
    fn_shutdown_or_poweroff
fi

# Get all MAC addresses used across all VMs to avoid conflicts
declare -a USED_MACS
print_info "Checking MAC addresses across all VMs..."
while IFS= read -r vm; do
    while IFS= read -r mac; do
        [[ -n "$mac" && "$mac" != "-" ]] && USED_MACS+=("$mac")
    done < <(sudo virsh domiflist "$vm" 2>/dev/null | awk 'NR>2 && NF>=5 {print $5}')
done < <(sudo virsh list --all --name | grep -v '^$')

# Function to generate a random MAC address for the lab network
generate_mac() {
    # Use 52:54:00 prefix (QEMU/KVM range) followed by 3 random octets
    local mac="52:54:00:$(openssl rand -hex 3 | sed 's/../&:/g; s/:$//')"
    echo "$mac"
}

# Function to check if MAC is unique
is_mac_unique() {
    local mac="$1"
    for used_mac in "${USED_MACS[@]}"; do
        if [[ "$mac" == "$used_mac" ]]; then
            return 1
        fi
    done
    return 0
}

# Confirm NIC addition
print_warning "About to add $nic_count NIC(s) to VM \"$qemu_kvm_hostname\" on network \"$network_name\""
read -rp "Type 'yes' to confirm: " confirm
if [[ "$confirm" != "yes" ]]; then
    print_info "Operation cancelled."
    exit 0
fi

# Add NICs
added_count=0
for ((i=1; i<=nic_count; i++)); do
    # Generate unique MAC address
    attempts=0
    while true; do
        mac=$(generate_mac)
        if is_mac_unique "$mac"; then
            break
        fi
        ((attempts++))
        if (( attempts > 100 )); then
            print_error "Failed to generate unique MAC address after 100 attempts."
            break 2
        fi
    done
    
    # Determine interface type (network or bridge)
    interface_type="network"
    if ! sudo virsh net-list --all | awk '{print $1}' | grep -Fxq "$network_name"; then
        # Not a libvirt network, must be a bridge
        interface_type="bridge"
    fi
    
    print_task "Adding NIC #$i with MAC $mac to $interface_type \"$network_name\"..." nskip
    if error_msg=$(sudo virsh attach-interface "$qemu_kvm_hostname" "$interface_type" "$network_name" \
        --mac "$mac" --model virtio --config 2>&1); then
        print_task_done
        USED_MACS+=("$mac")
        ((added_count++))
    else
        print_task_fail
        print_error "$error_msg"
    fi
done

if [[ $added_count -eq 0 ]]; then
    print_error "Failed to add any NICs."
    exit 1
fi

print_task "Starting VM \"$qemu_kvm_hostname\"..." nskip

if error_msg=$(sudo virsh start "$qemu_kvm_hostname" 2>&1); then
    print_task_done
    print_success "Added $added_count NIC(s) to VM \"$qemu_kvm_hostname\" and started successfully."
else
    print_task_fail
    print_error "Could not start VM \"$qemu_kvm_hostname\"."
    print_error "$error_msg"
    exit 1
fi
