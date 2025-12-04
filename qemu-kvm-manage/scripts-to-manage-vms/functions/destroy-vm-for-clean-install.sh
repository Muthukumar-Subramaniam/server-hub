# destroy-vm-for-clean-install.sh
# 
# Destroys VM completely for clean reinstall (undefine + delete directory)
#
# Usage:
#   source /path/to/destroy-vm-for-clean-install.sh
#   destroy_vm_for_clean_install "vm-hostname"
#
# Returns:
#   0 - VM destroyed successfully
#   1 - Failed to destroy VM

destroy_vm_for_clean_install() {
    local vm_hostname="$1"
    
    if [[ -z "$vm_hostname" ]]; then
        print_error "[ERROR] destroy_vm_for_clean_install: VM hostname not provided."
        return 1
    fi
    
    # Undefine the VM
    print_info "[INFO] Undefining VM \"$vm_hostname\"..."
    if error_msg=$(sudo virsh undefine "$vm_hostname" --nvram 2>&1); then
        print_success "[SUCCESS] VM undefined successfully."
    else
        print_error "[FAILED] Could not undefine VM \"$vm_hostname\"."
        print_error "$error_msg"
        return 1
    fi
    
    # Delete VM folder and contents
    print_info "[INFO] Deleting VM folder /kvm-hub/vms/${vm_hostname}..."
    if sudo rm -rf "/kvm-hub/vms/${vm_hostname}"; then
        print_success "[SUCCESS] VM folder deleted successfully."
    else
        print_error "[FAILED] Could not delete VM folder."
        return 1
    fi
    
    return 0
}
