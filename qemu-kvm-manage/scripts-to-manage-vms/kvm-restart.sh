#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Initialize variables
force_restart=false
hosts_list=""
vm_hostname_arg=""

# Function to show help
fn_show_help() {
    print_notify "Usage: kvm-restart [OPTIONS] [hostname]

Options:
  -f, --force          Skip confirmation prompt and force cold restart
  -H, --hosts <list>   Comma-separated list of VM hostnames to restart
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to do cold restart (optional, will prompt if not given)

Examples:
  kvm-restart vm1                    # Restart single VM with confirmation
  kvm-restart -f vm1                 # Restart single VM without confirmation
  kvm-restart --hosts vm1,vm2,vm3    # Restart multiple VMs with confirmation
  kvm-restart -f --hosts vm1,vm2     # Restart multiple VMs without confirmation
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
            force_restart=true
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

# Function to restart a single VM
restart_vm() {
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
    
    # Proceed with Restart
    if error_msg=$(sudo virsh reset "$vm_name" 2>&1); then
        print_success "[SUCCESS] VM \"$vm_name\" restarted successfully."
        return 0
    else
        print_error "[FAILED] Could not restart VM \"$vm_name\"."
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
    if [[ "$force_restart" == false ]]; then
        print_warning "[WARNING] This will perform cold restart on ${#validated_hosts[@]} VM(s): ${validated_hosts[*]}"
        print_notify "[NOTIFY] This is equivalent to pressing the reset button (may cause data loss)."
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            print_info "[INFO] Operation cancelled by user."
            exit 0
        fi
    fi
    
    # Restart each VM
    failed_vms=()
    total_vms=${#validated_hosts[@]}
    current=0
    for vm_name in "${validated_hosts[@]}"; do
        ((current++))
        print_info "[INFO] Restarting VM $current of $total_vms: $vm_name"
        if ! restart_vm "$vm_name"; then
            failed_vms+=("$vm_name")
        fi
    done
    
    # Report results
    if [[ ${#failed_vms[@]} -eq 0 ]]; then
        print_success "[SUCCESS] All VMs restarted successfully."
        exit 0
    else
        print_error "[FAILED] Some VMs failed to restart: ${failed_vms[*]}"
        exit 1
    fi
fi

# Handle single host
# Use argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_hostname_arg"

# Warning prompt unless force flag is used
if [[ "$force_restart" == false ]]; then
    print_warning "[WARNING] This will perform cold restart on VM \"$qemu_kvm_hostname\"."
    print_notify "[NOTIFY] This is equivalent to pressing the reset button (may cause data loss)."
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        print_info "[INFO] Operation cancelled by user."
        exit 0
    fi
fi

# Restart the VM
if restart_vm "$qemu_kvm_hostname"; then
    exit 0
else
    exit 1
fi