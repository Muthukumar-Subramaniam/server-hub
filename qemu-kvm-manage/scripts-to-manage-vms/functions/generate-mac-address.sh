#!/bin/bash
#----------------------------------------------------------------------------------------#
# MAC Address Generation Functions for QEMU/KVM VMs                                     #
#----------------------------------------------------------------------------------------#

# Function to generate a random MAC address for QEMU/KVM VMs
generate_mac() {
    # Use 52:54:00 prefix (QEMU/KVM range) followed by 3 random octets
    local mac="52:54:00:$(openssl rand -hex 3 | sed 's/../&:/g; s/:$//')"
    echo "$mac"
}

# Function to check if MAC is unique across all VMs
is_mac_unique() {
    local mac="$1"
    for used_mac in "${USED_MACS[@]}"; do
        if [[ "$mac" == "$used_mac" ]]; then
            return 1
        fi
    done
    return 0
}

# Function to collect all MAC addresses currently in use across all VMs
collect_used_macs() {
    USED_MACS=()
    while IFS= read -r vm; do
        [[ -z "$vm" ]] && continue
        while IFS= read -r mac; do
            [[ -n "$mac" && "$mac" != "-" ]] && USED_MACS+=("$mac")
        done < <(sudo virsh domiflist "$vm" 2>/dev/null | awk 'NR>2 && NF>=5 {print $5}')
    done < <(sudo virsh list --all --name)
}

# Main function to generate a unique MAC address for a VM
generate_unique_mac() {
    local hostname="$1"
    local max_attempts=100
    local attempt=0
    local mac

    # Collect all currently used MACs
    collect_used_macs

    # Try to generate a unique MAC
    while (( attempt < max_attempts )); do
        mac=$(generate_mac)
        if is_mac_unique "$mac"; then
            echo "$mac"
            return 0
        fi
        ((attempt++))
    done

    print_error "Failed to generate unique MAC address for VM \"${hostname}\" after ${max_attempts} attempts."
    return 1
}
