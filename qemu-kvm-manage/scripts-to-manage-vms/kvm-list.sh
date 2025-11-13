#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Check if any arguments are passed
if [ "$#" -ne 0 ]; then
    echo -e "\n❌ $(basename $0) does not take any arguments.\n"
    exit 1
fi

mapfile -t vm_list < <(sudo virsh list --all | awk 'NR>2 && $2 != "" {print $2}')

# SSH options
ssh_options="-o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -o LogLevel=QUIET \
             -o ConnectTimeout=5 \
             -o ConnectionAttempts=1 \
             -o ServerAliveInterval=5 \
	         -o PreferredAuthentications=publickey \
             -o ServerAliveCountMax=1"

# Color codes
COLOR_GREEN=$'\033[0;32m'
COLOR_YELLOW=$'\033[0;33m'
COLOR_RED=$'\033[0;31m'
COLOR_RESET=$'\033[0m'

# Temporary files to collect output
tmp_file_running_vms=$(mktemp)
tmp_file_off_vms=$(mktemp)

# Iterate over VMs in parallel
for vm_name in "${vm_list[@]}"; do
(
    current_vm_state="[ N/A ]"
    current_os_state="[ N/A ]"
    os_distro="[ N/A ]"

    # Get VM state from virsh
    current_vm_state=$(sudo virsh domstate "$vm_name" 2>/dev/null || echo "[ N/A ]")

    # If VM is running, check systemd + distro via single SSH
    if [[ "$current_vm_state" == "running" ]]; then
        ssh_output=$(ssh $ssh_options "${lab_infra_admin_username}@${vm_name}" \
            'systemctl is-system-running; \
             source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "[ N/A ]"' \
            2>/dev/null </dev/null || true)
        if [[ ! -z "$ssh_output" ]]; then
        	current_os_state=$(echo "$ssh_output" | sed -n '1p')
            os_distro=$(echo "$ssh_output" | sed -n '2p')	
	    else
            current_os_state="Not-Ready"
            os_distro="[ N/A ]"
	    fi
    fi

    # Determine line color based on OS state
    line_color="$COLOR_RESET"
    case "$current_os_state" in
        running) current_os_state="healthy"; line_color="$COLOR_GREEN" ;;
        "[ N/A ]") line_color="$COLOR_RED" ;;
	*) line_color="$COLOR_YELLOW" ;;
    esac

    formatted_line=$(printf "%s%-20s %-12s %-12s %-25s%s\n" \
        "$line_color" "$vm_name" "$current_vm_state" "$current_os_state" "$os_distro" "$COLOR_RESET")

    # Collect output: running VMs first, others at end
    if [[ "$current_vm_state" == "running" ]]; then
        echo "$formatted_line" >> "$tmp_file_running_vms"
    else
        echo "$formatted_line" >> "$tmp_file_off_vms"
    fi
) &
done

# Wait for all background jobs
wait

# Print table header
printf "%-20s %-12s %-12s %-25s\n" "VM-Name" "VM-State" "OS-State" "OS-Distro"
printf '%.0s-' {1..56}
echo

# Print running first, then non-running VMs
sort "$tmp_file_running_vms"
sort "$tmp_file_off_vms"

# Cleanup temporary files
rm -f "$tmp_file_running_vms" "$tmp_file_off_vms"
