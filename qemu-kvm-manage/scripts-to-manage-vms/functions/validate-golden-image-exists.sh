# validate-golden-image-exists.sh
# 
# Validates that golden image disk exists for given OS distro
#
# Usage:
#   source /path/to/validate-golden-image-exists.sh
#   validate_golden_image_exists "vm-hostname" "os-distro"
#
# Returns:
#   0 - Golden image exists
#   1 - Golden image not found

validate_golden_image_exists() {
    local vm_hostname="$1"
    local os_distro="$2"
    
    if [[ -z "$vm_hostname" || -z "$os_distro" ]]; then
        print_error "[ERROR] validate_golden_image_exists: Missing required parameters."
        return 1
    fi
    
    local golden_image_path="/kvm-hub/golden-images-disk-store/${os_distro}-golden-image.${lab_infra_domain_name}.qcow2"
    
    if [ ! -f "${golden_image_path}" ]; then
        print_error "[ERROR] Golden image disk not found for \"$vm_hostname\"!"
        print_info "[INFO] Expected at: ${golden_image_path}"
        print_info "[INFO] To build the golden image disk, run: qlabvmctl build-golden-image"
        return 1
    fi
    
    return 0
}
