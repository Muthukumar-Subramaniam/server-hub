#!/bin/bash
#
# poweroff-vm.sh
# 
# Force powers off a running VM using virsh destroy (equivalent to pulling the power plug)
#
# Usage:
#   source /path/to/poweroff-vm.sh
#   
#   # Default behavior: warnings only, always returns 0
#   poweroff_vm "vm-hostname"
#   
#   # Strict mode: errors cause return 1
#   POWEROFF_VM_STRICT=true poweroff_vm "vm-hostname"
#   
#   # Custom message context
#   POWEROFF_VM_CONTEXT="before reimaging" poweroff_vm "vm-hostname"
#
# Environment Variables:
#   POWEROFF_VM_STRICT - If "true", return 1 on errors (default: warnings only)
#   POWEROFF_VM_CONTEXT - Custom context message (default: "Powering off")
#
# Returns:
#   0 - VM was powered off or wasn't running (or warnings-only mode)
#   1 - Failed to power off VM (only in strict mode)

poweroff_vm() {
    local vm_hostname="$1"
    local context="${POWEROFF_VM_CONTEXT:-Powering off}"
    local strict_mode="${POWEROFF_VM_STRICT:-false}"
    
    if [[ -z "$vm_hostname" ]]; then
        print_error "[ERROR] poweroff_vm: VM hostname not provided."
        return 1
    fi
    
    # Check if VM is running
    if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$vm_hostname"; then
        return 0  # Not running, nothing to do
    fi
    
    # VM is running, proceed with force power-off
    print_info "[INFO] VM \"$vm_hostname\" is currently running. ${context}..."
    
    if error_msg=$(sudo virsh destroy "$vm_hostname" 2>&1); then
        print_success "[SUCCESS] VM \"$vm_hostname\" has been powered off successfully."
        return 0
    else
        if [[ "$strict_mode" == "true" ]]; then
            print_error "[FAILED] Could not power off VM \"$vm_hostname\"."
            print_error "$error_msg"
            return 1
        else
            print_warning "[WARNING] Could not power off VM \"$vm_hostname\"."
            print_warning "$error_msg"
            return 0
        fi
    fi
}
