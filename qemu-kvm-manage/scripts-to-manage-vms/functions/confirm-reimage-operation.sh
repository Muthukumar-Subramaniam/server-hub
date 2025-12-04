#!/bin/bash
#
# confirm-reimage-operation.sh
# 
# Prompts user for confirmation before reimaging a VM
#
# Usage:
#   source /path/to/confirm-reimage-operation.sh
#   confirm_reimage_operation "vm-hostname" "golden image" # or "PXE boot"
#
# Returns:
#   0 - User confirmed
#   (exits if user declined)

confirm_reimage_operation() {
    local vm_hostname="$1"
    local reimage_method="$2"  # "golden image" or "PXE boot"
    local total_vms="${TOTAL_VMS:-1}"
    
    if [[ -z "$vm_hostname" || -z "$reimage_method" ]]; then
        print_error "[ERROR] confirm_reimage_operation: Missing required parameters."
        exit 1
    fi
    
    # Only prompt for single VM operations
    if [[ $total_vms -eq 1 ]]; then
        print_warning "[WARNING] This will reimage VM \"$vm_hostname\" using $reimage_method!"
        print_warning "[WARNING] All existing data on this VM will be permanently lost."
        read -rp "Are you sure you want to proceed? (yes/no): " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            print_info "[INFO] Operation cancelled by user."
            exit 0
        fi
    fi
    
    return 0
}
