################################################################################
# Function: show_vm_operation_summary
# Description: Display summary of VM operations (install/reimage) for multiple VMs
# Parameters:
#   $1 - Total VMs count
#   $2 - Array name for successful VMs (pass as string, e.g., "SUCCESSFUL_VMS")
#   $3 - Array name for failed VMs (pass as string, e.g., "FAILED_VMS")
#   $4 - Operation description (e.g., "installation via golden image disk")
#   $5 - Additional info message (e.g., "Installation takes ~1 minute")
# Returns:
#   0 - All operations successful
#   1 - Some operations failed
################################################################################

show_vm_operation_summary() {
    local total_vms="$1"
    local successful_array_name="$2"
    local failed_array_name="$3"
    local operation_desc="$4"
    local additional_info="$5"

    # Only show summary for multiple VMs
    if [[ $total_vms -le 1 ]]; then
        return 0
    fi

    # Use nameref to access arrays by name
    local -n successful_vms="$successful_array_name"
    local -n failed_vms="$failed_array_name"

    echo ""
    print_info "Operation Summary:"
    
    if [[ ${#successful_vms[@]} -gt 0 ]]; then
        print_success "Successfully initiated ${operation_desc}: ${#successful_vms[@]} VM(s)"
        for vm in "${successful_vms[@]}"; do
            print_success "  ✓ $vm"
        done
    fi
    
    if [[ ${#failed_vms[@]} -gt 0 ]]; then
        print_error "Failed to initiate ${operation_desc}: ${#failed_vms[@]} VM(s)"
        for vm in "${failed_vms[@]}"; do
            print_error "  ✗ $vm"
        done
    fi
    
    if [[ -n "$additional_info" ]]; then
        print_info "${additional_info}"
    fi
    
    print_info "To monitor progress, use: qlabvmctl console <hostname>"
    print_info "To check VM status, use: qlabvmctl list"

    # Return failure if any VMs failed
    if [[ ${#failed_vms[@]} -gt 0 ]]; then
        return 1
    fi

    return 0
}
