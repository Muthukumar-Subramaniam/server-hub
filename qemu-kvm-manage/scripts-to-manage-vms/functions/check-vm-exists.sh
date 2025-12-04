#!/bin/bash
#
# check-vm-exists.sh
# 
# Validates VM existence for install or reimage operations
#
# Usage:
#   source /path/to/check-vm-exists.sh
#   check_vm_exists "vm-hostname" "install"  # VM should NOT exist
#   check_vm_exists "vm-hostname" "reimage"  # VM MUST exist
#
# Returns:
#   0 - Validation passed
#   1 - Validation failed

check_vm_exists() {
    local vm_hostname="$1"
    local operation="$2"  # "install" or "reimage"
    local total_vms="${TOTAL_VMS:-1}"
    
    if [[ -z "$vm_hostname" || -z "$operation" ]]; then
        print_error "[ERROR] check_vm_exists: Missing required parameters."
        return 1
    fi
    
    local vm_exists=false
    if sudo virsh list --all | awk '{print $2}' | grep -Fxq "$vm_hostname"; then
        vm_exists=true
    fi
    
    if [[ "$operation" == "install" ]]; then
        # For install operations, VM should NOT exist
        if [[ "$vm_exists" == "true" ]]; then
            print_error "[ERROR] VM \"$vm_hostname\" exists already."
            if [[ $total_vms -eq 1 ]]; then
                print_warning "[WARNING] Either do one of the following:"
                print_info "[INFO] Remove the VM using 'qlabvmctl remove', then try again."
                print_info "[INFO] Re-image the VM using 'qlabvmctl reimage-golden' or 'qlabvmctl reimage-pxe'."
                exit 1
            fi
            return 1
        fi
    elif [[ "$operation" == "reimage" ]]; then
        # For reimage operations, VM MUST exist
        if [[ "$vm_exists" == "false" ]]; then
            print_error "[ERROR] VM \"$vm_hostname\" does not exist."
            if [[ $total_vms -eq 1 ]]; then
                exit 1
            fi
            return 1
        fi
    else
        print_error "[ERROR] check_vm_exists: Invalid operation '$operation'. Use 'install' or 'reimage'."
        return 1
    fi
    
    return 0
}
