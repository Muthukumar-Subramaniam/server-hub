#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl stop [OPTIONS] [hostname]

Options:
  -f, --force          Skip confirmation prompt and force power-off
  -H, --hosts <list>   Comma-separated list of VM hostnames to stop
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to Power-OFF (optional, will prompt if not given)

Examples:
  qlabvmctl stop vm1                    # Stop single VM with confirmation
  qlabvmctl stop -f vm1                 # Stop single VM without confirmation
  qlabvmctl stop --hosts vm1,vm2,vm3    # Stop multiple VMs with confirmation
  qlabvmctl stop -f --hosts vm1,vm2     # Stop multiple VMs without confirmation
"
}

# Parse arguments
SUPPORTS_FORCE="yes"
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/parse-vm-control-args.sh
parse_vm_control_args "$@"

force_stop="$FORCE_FLAG"
hosts_list="$HOSTS_LIST"
vm_hostname_arg="$VM_HOSTNAME_ARG"

# Function to stop a single VM
stop_vm() {
    local vm_name="$1"
    
    # Check if VM exists in 'virsh list --all'
    if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$vm_name"; then
        print_error "[ERROR] VM \"$vm_name\" does not exist."
        return 1
    fi
    
    # Check if VM exists in 'virsh list'
    if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$vm_name"; then
        print_info "[INFO] VM \"$vm_name\" is not running (already stopped)."
        return 0
    fi
    
    # Proceed with Stop
    if error_msg=$(sudo virsh destroy "$vm_name" 2>&1); then
        print_success "[SUCCESS] VM \"$vm_name\" stopped successfully."
        return 0
    else
        print_error "[FAILED] Could not stop VM \"$vm_name\"."
        print_error "$error_msg"
        return 1
    fi
}

# Handle multiple hosts
if [[ -n "$hosts_list" ]]; then
    IFS=',' read -ra hosts_array <<< "$hosts_list"
    
    # Check if hosts list is empty
    if [[ ${#hosts_array[@]} -eq 0 ]]; then
        print_error "[ERROR] No hostnames provided in --hosts list."
        exit 1
    fi
    
    # Validate and normalize hostnames
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/validate-and-process-hostnames.sh
    if ! validate_and_process_hostnames hosts_array; then
        exit 1
    fi
    
    validated_hosts=("${VALIDATED_HOSTS[@]}")
    
    # Warning prompt unless force flag is used
    if [[ "$force_stop" == false ]]; then
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/confirm-vm-operation.sh
        if ! confirm_vm_operation "stop" "forcefully power off" "This is equivalent to pulling the power plug (may cause data loss)." "${#validated_hosts[@]}" "${validated_hosts[*]}"; then
            exit 0
        fi
    fi
    
    # Stop each VM
    failed_vms=()
    total_vms=${#validated_hosts[@]}
    current=0
    for vm_name in "${validated_hosts[@]}"; do
        ((current++))
        print_info "[INFO] Stopping VM $current of $total_vms: $vm_name"
        if ! stop_vm "$vm_name"; then
            failed_vms+=("$vm_name")
        fi
    done
    
    # Report results
    if [[ ${#failed_vms[@]} -eq 0 ]]; then
        print_success "[SUCCESS] All $total_vms VM(s) stopped successfully."
        exit 0
    else
        print_error "[FAILED] Some VMs failed to stop: ${failed_vms[*]}"
        exit 1
    fi
fi

# Handle single host
# Use argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_hostname_arg"

# Warning prompt unless force flag is used
if [[ "$force_stop" == false ]]; then
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/confirm-vm-operation.sh
    if ! confirm_vm_operation "stop" "forcefully power off" "This is equivalent to pulling the power plug (may cause data loss)." 1 "$qemu_kvm_hostname"; then
        exit 0
    fi
fi
# Stop the VM
if stop_vm "$qemu_kvm_hostname"; then
    exit 0
else
    exit 1
fi
