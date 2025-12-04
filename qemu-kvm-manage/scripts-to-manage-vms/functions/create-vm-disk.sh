#!/bin/bash
#
# create-vm-disk.sh
# 
# Creates a new VM qcow2 disk with specified size
#
# Usage:
#   source /path/to/create-vm-disk.sh
#   create_vm_disk "vm-hostname" size_gib
#
# Returns:
#   0 - Disk created successfully
#   1 - Failed to create disk

create_vm_disk() {
    local vm_hostname="$1"
    local disk_size_gib="$2"
    
    if [[ -z "$vm_hostname" || -z "$disk_size_gib" ]]; then
        print_error "[ERROR] create_vm_disk: Missing required parameters."
        return 1
    fi
    
    local vm_disk_path="/kvm-hub/vms/${vm_hostname}/${vm_hostname}.qcow2"
    
    print_info "[INFO] Creating new disk ${vm_disk_path} with ${disk_size_gib} GiB..." nskip
    
    if error_msg=$(sudo qemu-img create -f qcow2 "${vm_disk_path}" "${disk_size_gib}G" 2>&1); then
        print_success "[ SUCCESS ]"
        return 0
    else
        print_error "[ FAILED ]"
        print_error "$error_msg"
        return 1
    fi
}
