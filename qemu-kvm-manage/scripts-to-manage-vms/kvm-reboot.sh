#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl reboot [OPTIONS] [hostname]

Options:
  -f, --force          Skip confirmation prompt and force graceful reboot
  -H, --hosts <list>   Comma-separated list of VM hostnames to reboot
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to do graceful reboot (optional, will prompt if not given)

Examples:
  qlabvmctl reboot vm1                    # Reboot single VM with confirmation
  qlabvmctl reboot -f vm1                 # Reboot single VM without confirmation
  qlabvmctl reboot --hosts vm1,vm2,vm3    # Reboot multiple VMs with confirmation
  qlabvmctl reboot -f --hosts vm1,vm2     # Reboot multiple VMs without confirmation
"
}

# Parse arguments
SUPPORTS_FORCE="yes"
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/parse-vm-control-args.sh
parse_vm_control_args "$@"

force_reboot="$FORCE_FLAG"
hosts_list="$HOSTS_LIST"
vm_hostname_arg="$VM_HOSTNAME_ARG"

# Function to reboot a single VM
reboot_vm() {
    local vm_name="$1"
    
    # Check if VM exists in 'virsh list --all'
    if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$vm_name"; then
        print_error "[ERROR] VM \"$vm_name\" does not exist."
        return 1
    fi
    
    # Check if VM exists in 'virsh list'
    if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$vm_name"; then
        print_error "[ERROR] VM \"$vm_name\" is not running."
        return 1
    fi
    
    # Proceed with Reboot
    if error_msg=$(sudo virsh reboot "$vm_name" 2>&1); then
        print_success "[SUCCESS] VM \"$vm_name\" reboot signal sent successfully."
        return 0
    else
        print_error "[FAILED] Could not reboot VM \"$vm_name\"."
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
    if [[ "$force_reboot" == false ]]; then
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/confirm-vm-operation.sh
        if ! confirm_vm_operation "reboot" "send graceful reboot signal to" "Guest OS will attempt to reboot cleanly (requires guest tools)." "${#validated_hosts[@]}" "${validated_hosts[*]}"; then
            exit 0
        fi
    fi
    
    # Reboot each VM
    failed_vms=()
    total_vms=${#validated_hosts[@]}
    current=0
    for vm_name in "${validated_hosts[@]}"; do
        ((current++))
        print_info "[INFO] Rebooting VM $current of $total_vms: $vm_name"
        if ! reboot_vm "$vm_name"; then
            failed_vms+=("$vm_name")
        fi
    done
    
    # Report results
    if [[ ${#failed_vms[@]} -eq 0 ]]; then
        print_success "[SUCCESS] All VMs reboot signals sent successfully."
        exit 0
    else
        print_error "[FAILED] Some VMs failed to reboot: ${failed_vms[*]}"
        exit 1
    fi
fi

# Handle single host
# Use argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_hostname_arg"

# Warning prompt unless force flag is used
if [[ "$force_reboot" == false ]]; then
    source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/confirm-vm-operation.sh
    if ! confirm_vm_operation "reboot" "send graceful reboot signal to" "Guest OS will attempt to reboot cleanly (requires guest tools)." 1 "$qemu_kvm_hostname"; then
        exit 0
    fi
fi
# Reboot the VM
if reboot_vm "$qemu_kvm_hostname"; then
    exit 0
else
    exit 1
fi