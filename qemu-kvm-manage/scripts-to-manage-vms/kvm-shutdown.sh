#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Initialize variables
force_shutdown=false
hosts_list=""
vm_hostname_arg=""

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

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            fn_show_help
            exit 0
            ;;
        -f|--force)
            force_shutdown=true
            shift
            ;;
        -H|--hosts)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "[ERROR] --hosts requires a comma-separated list of hostnames."
                fn_show_help
                exit 1
            fi
            hosts_list="$2"
            shift 2
            ;;
        -*)
            print_error "[ERROR] No such option: $1"
            fn_show_help
            exit 1
            ;;
        *)
            # This is the hostname argument
            if [[ -n "$hosts_list" ]]; then
                print_error "[ERROR] Cannot use both hostname argument and --hosts option."
                fn_show_help
                exit 1
            fi
            vm_hostname_arg="$1"
            shift
            ;;
    esac
done

# Function to shutdown a single VM
shutdown_vm() {
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
    
    # Proceed with Shutdown
    if error_msg=$(sudo virsh shutdown "$vm_name" 2>&1); then
        print_success "[SUCCESS] VM \"$vm_name\" shutdown signal sent successfully."
        return 0
    else
        print_error "[FAILED] Could not shutdown VM \"$vm_name\"."
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
    
    # Validate and normalize all hostnames using input-hostname.sh
    validated_hosts=()
    for vm_name in "${hosts_array[@]}"; do
        vm_name=$(echo "$vm_name" | xargs) # Trim whitespace
        [[ -z "$vm_name" ]] && continue  # Skip empty entries
        # Use input-hostname.sh to validate and normalize
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_name"
        validated_hosts+=("$qemu_kvm_hostname")
    done
    
    # Check if any valid hosts remain after validation
    if [[ ${#validated_hosts[@]} -eq 0 ]]; then
        print_error "[ERROR] No valid hostnames provided in --hosts list."
        exit 1
    fi
    
    # Remove duplicates while preserving order
    declare -A seen_hosts
    unique_hosts=()
    for vm_name in "${validated_hosts[@]}"; do
        if [[ -z "${seen_hosts[$vm_name]}" ]]; then
            seen_hosts[$vm_name]=1
            unique_hosts+=("$vm_name")
        fi
    done
    
    # Check if duplicates were found
    if [[ ${#unique_hosts[@]} -lt ${#validated_hosts[@]} ]]; then
        duplicate_count=$((${#validated_hosts[@]} - ${#unique_hosts[@]}))
        print_warning "[WARNING] Removed $duplicate_count duplicate hostname(s) from the list."
    fi
    
    validated_hosts=("${unique_hosts[@]}")
    
    # Warning prompt unless force flag is used
    if [[ "$force_shutdown" == false ]]; then
        print_warning "[WARNING] This will send graceful shutdown signal to ${#validated_hosts[@]} VM(s): ${validated_hosts[*]}"
        print_notify "[NOTIFY] Guest OS will attempt to shutdown cleanly (requires guest tools)."
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        echo -ne "\033[1A\033[2K"  # Move up one line and clear it
        if [[ "$confirmation" != "yes" ]]; then
            print_info "[INFO] Operation cancelled by user."
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
    print_warning "[WARNING] This will send graceful shutdown signal to VM \"$qemu_kvm_hostname\"."
    print_notify "[NOTIFY] Guest OS will attempt to shutdown cleanly (requires guest tools)."
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    echo -ne "\033[1A\033[2K"  # Move up one line and clear it
    if [[ "$confirmation" != "yes" ]]; then
        print_info "[INFO] Operation cancelled by user."
        exit 0
    fi
fi
# Shutdown the VM
if shutdown_vm "$qemu_kvm_hostname"; then
    exit 0
else
    exit 1
fi