#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

if [ "$#" -ne 0 ]; then
    echo -e "\n❌ $(basename $0) does not take any arguments.\n"
    exit 1
fi

mapfile -t vm_list < <(sudo virsh list --all | awk 'NR>2 && $2 != "" {print $2}')

ssh_options="-o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -o LogLevel=QUIET \
             -o ConnectTimeout=5 \
             -o ConnectionAttempts=1 \
             -o ServerAliveInterval=5 \
             -o PreferredAuthentications=publickey \
             -o ServerAliveCountMax=1"

COLOR_GREEN=$'\033[0;32m'
COLOR_YELLOW=$'\033[0;33m'
COLOR_RED=$'\033[0;31m'
COLOR_RESET=$'\033[0m'

# Collect results in an array
declare -a results=()

for vm_name in "${vm_list[@]}"; do
(
    current_vm_state="[ N/A ]"
    current_os_state="[ N/A ]"
    os_distro="[ N/A ]"

    current_vm_state=$(sudo virsh domstate "$vm_name" 2>/dev/null || echo "[ N/A ]")

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

    case "$current_os_state" in
        running) current_os_state="healthy"; color="$COLOR_GREEN" ;;
        "[ N/A ]") color="$COLOR_RED" ;;
        *) color="$COLOR_YELLOW" ;;
    esac

    echo -e "${color}${vm_name}|${current_vm_state}|${current_os_state}|${os_distro}${COLOR_RESET}"
) &
done | while IFS= read -r line; do results+=("$line"); done

wait

# Extract max column widths (strip color codes for length calc)
max_vm=8; max_vmstate=8; max_osstate=8; max_osdistro=9
for entry in "${results[@]}"; do
    clean=$(echo "$entry" | sed 's/\x1b\[[0-9;]*m//g')
    IFS='|' read -r vm state os distro <<< "$clean"
    (( ${#vm} > max_vm )) && max_vm=${#vm}
    (( ${#state} > max_vmstate )) && max_vmstate=${#state}
    (( ${#os} > max_osstate )) && max_osstate=${#os}
    (( ${#distro} > max_osdistro )) && max_osdistro=${#distro}
done

# Print header dynamically
printf "%-${max_vm}s %-${max_vmstate}s %-${max_osstate}s %-${max_osdistro}s\n" "VM-Name" "VM-State" "OS-State" "OS-Distro"
printf -- '-%.0s' $(seq 1 $((max_vm + max_vmstate + max_osstate + max_osdistro + 3)))
echo

# Print rows sorted: running first
{
    for entry in "${results[@]}"; do
        echo "$entry"
    done | sort -t'|' -k2
} | while IFS='|' read -r vm state os distro; do
    printf "%-${max_vm}s %-${max_vmstate}s %-${max_osstate}s %-${max_osdistro}s\n" "$vm" "$state" "$os" "$distro"
done
