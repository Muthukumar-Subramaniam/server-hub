#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

ETC_HOSTS_FILE='/etc/hosts'

# Initialize variables
force_remove=false
hosts_list=""
vm_hostname_arg=""

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl remove [OPTIONS] [hostname]

Options:
  -f, --force          Skip confirmation prompt (except for lab infra server)
  -H, --hosts <list>   Comma-separated list of VM hostnames to remove
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to be deleted permanently (optional, will prompt if not given)

Examples:
  qlabvmctl remove vm1                    # Remove single VM with confirmation
  qlabvmctl remove -f vm1                 # Remove single VM without confirmation
  qlabvmctl remove --hosts vm1,vm2,vm3    # Remove multiple VMs with confirmation
  qlabvmctl remove -f --hosts vm1,vm2     # Remove multiple VMs without confirmation

Note: Lab infra server always requires special confirmation regardless of -f flag.
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
            force_remove=true
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

# Function to remove a single VM
remove_vm() {
    local vm_name="$1"
    local skip_confirmation="${2:-false}"
    
    # Check if VM exists in 'virsh list --all'
    if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$vm_name"; then
        print_error "[ERROR] VM \"$vm_name\" does not exist."
        return 1
    fi
    
    # Special confirmation for lab infra server (always required)
    if [[ "$vm_name" == "$lab_infra_server_hostname" ]]; then
        print_warning "[WARNING] You are about to delete your lab infra server VM: $lab_infra_server_hostname!"
        read -r -p "If you know what you are doing, confirm by typing 'delete-lab-infra-server': " confirmation
        if [[ "$confirmation" != "delete-lab-infra-server" ]]; then
            print_info "[INFO] Operation cancelled by user."
            return 1
        fi
    elif [[ "$skip_confirmation" == false ]]; then
        # Regular confirmation for other VMs
        print_warning "[WARNING] This will permanently delete VM \"$vm_name\" and all associated files!"
        read -rp "Are you sure you want to proceed? (yes/no): " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            print_info "[INFO] Operation cancelled by user."
            return 1
        fi
    fi
    
    # Stop VM if running
    if sudo virsh list | awk '{print $2}' | grep -Fxq "$vm_name"; then
        print_info "[INFO] Stopping VM \"$vm_name\" before removal..."
        if error_msg=$(sudo virsh destroy "$vm_name" 2>&1); then
            print_success "[SUCCESS] VM stopped successfully."
        else
            print_warning "[WARNING] Could not stop VM \"$vm_name\", continuing with removal..."
            print_warning "$error_msg"
        fi
    fi
    
    # Undefine VM
    if ! error_msg=$(sudo virsh undefine "$vm_name" --nvram 2>&1); then
        print_error "[FAILED] Could not undefine VM \"$vm_name\"."
        print_error "$error_msg"
        return 1
    fi
    
    # Remove VM directory
    if [ -n "$vm_name" ] && [ -d "/kvm-hub/vms/$vm_name" ]; then
        if ! sudo rm -rf "/kvm-hub/vms/$vm_name" 2>/dev/null; then
            print_warning "[WARNING] Could not remove VM directory /kvm-hub/vms/$vm_name"
        fi
    fi
    
    # Remove from /etc/hosts
    if grep -q "$vm_name" "$ETC_HOSTS_FILE" 2>/dev/null; then
        if sudo sed -i.bak "/$vm_name/d" "$ETC_HOSTS_FILE" 2>/dev/null; then
            print_info "[INFO] Removed $vm_name from $ETC_HOSTS_FILE"
        else
            print_warning "[WARNING] Could not remove $vm_name from $ETC_HOSTS_FILE"
        fi
    fi
    
    print_success "[SUCCESS] VM \"$vm_name\" removed successfully."
    return 0
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
    
    # Warning prompt unless force flag is used (but each VM will have its own confirmation)
    if [[ "$force_remove" == false ]]; then
        print_warning "[WARNING] This will permanently delete ${#validated_hosts[@]} VM(s): ${validated_hosts[*]}"
        print_notify "[NOTIFY] All VM data and associated files will be removed."
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        echo -ne "\033[1A\033[2K"  # Move up one line and clear it
        if [[ "$confirmation" != "yes" ]]; then
            print_info "[INFO] Operation cancelled by user."
            exit 0
        fi
    fi
    
    # Remove each VM
    failed_vms=()
    total_vms=${#validated_hosts[@]}
    current=0
    for vm_name in "${validated_hosts[@]}"; do
        ((current++))
        print_info "[INFO] Removing VM $current of $total_vms: $vm_name"
        # Pass true to skip individual confirmation if force flag is set
        if ! remove_vm "$vm_name" "$force_remove"; then
            failed_vms+=("$vm_name")
        fi
    done
    
    # Report results
    if [[ ${#failed_vms[@]} -eq 0 ]]; then
        print_success "[SUCCESS] Successfully removed all $total_vms VM(s)."
        exit 0
    else
        print_error "[FAILED] Some VMs failed to remove: ${failed_vms[*]}"
        exit 1
    fi
fi

# Handle single host
# Use argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_hostname_arg"

# Remove the VM
if remove_vm "$qemu_kvm_hostname" "$force_remove"; then
    exit 0
else
    exit 1
fi