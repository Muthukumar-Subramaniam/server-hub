#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl start [OPTIONS] [hostname]

Options:
  -H, --hosts <list>   Comma-separated list of VM hostnames to start
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to Power-ON (optional, will prompt if not given)

Examples:
  qlabvmctl start vm1                    # Start single VM
  qlabvmctl start --hosts vm1,vm2,vm3    # Start multiple VMs
"
}

# Parse arguments
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/parse-vm-control-args.sh
parse_vm_control_args "$@"

hosts_list="$HOSTS_LIST"
vm_hostname_arg="$VM_HOSTNAME_ARG"

# Function to start a single VM
start_vm() {
    local vm_name="$1"
    
    # Check if VM exists
    print_task "Checking VM \"$vm_name\" exists..."
    if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$vm_name"; then
        print_task_fail
        print_error "[ERROR] VM does not exist"
        return 1
    fi
    print_task_done
    
    # Check if VM is already running
    print_task "Checking VM state..."
    if sudo virsh list | awk '{print $2}' | grep -Fxq "$vm_name"; then
        print_task_done
        print_skip "VM \"$vm_name\" is already running"
        return 0
    fi
    print_task_done
    
    # Start the VM
    print_task "Starting VM \"$vm_name\"..."
    if error_msg=$(sudo virsh start "$vm_name" 2>&1); then
        print_task_done
        return 0
    else
        print_task_fail
        print_error "[ERROR] $error_msg"
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
    
    # Start each VM
    failed_vms=()
    success_vms=()
    skipped_vms=()
    total_vms=${#validated_hosts[@]}
    current=0
    
    for vm_name in "${validated_hosts[@]}"; do
        ((current++))
        echo ""
        print_info "[INFO] Processing VM $current/$total_vms: $vm_name"
        
        # Check if already running before starting
        if sudo virsh list | awk '{print $2}' | grep -Fxq "$vm_name"; then
            print_skip "VM \"$vm_name\" is already running"
            skipped_vms+=("$vm_name")
        elif start_vm "$vm_name"; then
            success_vms+=("$vm_name")
        else
            failed_vms+=("$vm_name")
        fi
    done
    
    # Print summary
    echo ""
    print_summary "Start Operation Results"
    if [[ ${#success_vms[@]} -gt 0 ]]; then
        print_success "  DONE: ${#success_vms[@]}/$total_vms (${success_vms[*]})"
    fi
    if [[ ${#skipped_vms[@]} -gt 0 ]]; then
        print_warning "  SKIP: ${#skipped_vms[@]}/$total_vms (${skipped_vms[*]})"
    fi
    if [[ ${#failed_vms[@]} -gt 0 ]]; then
        print_error "  FAIL: ${#failed_vms[@]}/$total_vms (${failed_vms[*]})"
        exit 1
    fi
    
    exit 0
fi

# Handle single host
# Use argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_hostname_arg"

# Start the VM
if start_vm "$qemu_kvm_hostname"; then
    exit 0
else
    exit 1
fi
