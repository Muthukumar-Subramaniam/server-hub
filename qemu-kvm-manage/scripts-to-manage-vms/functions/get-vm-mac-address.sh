#!/bin/bash
#----------------------------------------------------------------------------------------#
# Get MAC Address from Existing VM                                                      #
#----------------------------------------------------------------------------------------#

# Function to get the MAC address of the first network interface of an existing VM
get_vm_mac_address() {
    local vm_name="$1"
    local mac
    
    # Get the MAC address from the first network interface
    mac=$(sudo virsh domiflist "$vm_name" 2>/dev/null | awk 'NR>2 && NF>=5 {print $5; exit}')
    
    if [[ -z "$mac" || "$mac" == "-" ]]; then
        return 1
    fi
    
    echo "$mac"
    return 0
}
