#!/bin/bash
#
# shutdown-vm.sh
# 
# Shuts down a running VM gracefully
#
# Usage:
#   source /path/to/shutdown-vm.sh
#   shutdown_vm "vm-hostname"
#
# Returns:
#   0 - VM was shut down or wasn't running
#   (always returns 0, warnings only)

shutdown_vm() {
    local vm_hostname="$1"
    
    if [[ -z "$vm_hostname" ]]; then
        print_error "[ERROR] shutdown_vm: VM hostname not provided."
        return 1
    fi
    
    if sudo virsh list | awk '{print $2}' | grep -Fxq "$vm_hostname"; then
        print_info "[INFO] VM \"$vm_hostname\" is currently running. Shutting down before reimaging..."
        if error_msg=$(sudo virsh destroy "$vm_hostname" 2>&1); then
            print_success "[SUCCESS] VM \"$vm_hostname\" has been shut down successfully."
        else
            print_warning "[WARNING] Could not shut down VM \"$vm_hostname\"."
            print_warning "$error_msg"
        fi
    fi
    
    return 0
}
