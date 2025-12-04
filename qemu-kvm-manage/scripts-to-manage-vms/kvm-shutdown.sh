#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl shutdown [OPTIONS] [hostname]

Options:
  -f, --force          Skip confirmation prompt and force graceful shutdown
  -H, --hosts <list>   Comma-separated list of VM hostnames to shutdown
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to gracefully shutdown (optional, will prompt if not given)

Examples:
  qlabvmctl shutdown vm1                    # Shutdown single VM with confirmation
  qlabvmctl shutdown -f vm1                 # Shutdown single VM without confirmation
  qlabvmctl shutdown --hosts vm1,vm2,vm3    # Shutdown multiple VMs with confirmation
  qlabvmctl shutdown -f --hosts vm1,vm2     # Shutdown multiple VMs without confirmation
"
}

# Parse arguments
SUPPORTS_FORCE="yes"
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/parse-vm-control-args.sh
parse_vm_control_args "$@"

force_shutdown="$FORCE_FLAG"
hosts_list="$HOSTS_LIST"
vm_hostname_arg="$VM_HOSTNAME_ARG"

# Source the shutdown function
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh

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
    if [[ "$force_shutdown" == false ]]; then
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/confirm-vm-operation.sh
        if ! confirm_vm_operation "shutdown" "send graceful shutdown signal to" "Guest OS will attempt to shutdown cleanly (requires guest tools)." "${#validated_hosts[@]}" "${validated_hosts[*]}"; then
            exit 0
        fi
    fi
    
    # Shutdown each VM
    failed_vms=()
    total_vms=${#validated_hosts[@]}
    current=0
    for vm_name in "${validated_hosts[@]}"; do
        ((current++))
        print_info "[INFO] Shutting down VM $current of $total_vms: $vm_name"
        if ! shutdown_vm "$vm_name"; then
            failed_vms+=("$vm_name")
        fi
    done
    
    # Report results
    if [[ ${#failed_vms[@]} -eq 0 ]]; then
        print_success "[SUCCESS] All VMs shutdown signals sent successfully."
        exit 0
    else
        print_error "[FAILED] Some VMs failed to shutdown: ${failed_vms[*]}"
        exit 1
    fi
fi

# Handle single host
# Use argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_hostname_arg"

# Warning prompt unless force flag is used
if [[ "$force_shutdown" == false ]]; then
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/confirm-vm-operation.sh
    if ! confirm_vm_operation "shutdown" "send graceful shutdown signal to" "Guest OS will attempt to shutdown cleanly (requires guest tools)." 1 "$qemu_kvm_hostname"; then
        exit 0
    fi
fi
# Shutdown the VM
if shutdown_vm "$qemu_kvm_hostname"; then
    exit 0
else
    exit 1
fi