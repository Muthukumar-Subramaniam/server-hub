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

declare -a results=()

# ────────────────────────────────────────────────────────────────
# Collect data
# ────────────────────────────────────────────────────────────────
for vm_name in "${vm_list[@]}"; do
    current_vm_state="[ N/A ]"
    current_os_state="[ N/A ]"
    os_distro="[ N/A ]"

    current_vm_state=$(sudo virsh domstate "$vm_name" 2>/dev/null || echo "[ N/A ]")

    if [[ "$current_vm_state" == "running" ]]; then
        ssh_output=$(ssh $ssh_options "${lab_infra_admin_username}@${vm_name}" \
            'systemctl is-system-running; \
             source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "[ N/A ]"' \
            2>/dev/null </dev/null || true)

        if [[ -n "$ssh_output" ]]; then
            current_os_state=$(echo "$ssh_output" | sed -n '1p')
            os_distro=$(echo "$ssh_output" | sed -n '2p')
        else
            current_os_state="Not-Ready"
            os_distro="[ N/A ]"
        fi
    fi

    # Color by health
    case "$current_os_state" in
        running) current_os_state="healthy"; color="$COLOR_GREEN" ;;
        "[ N/A ]") color="$COLOR_RED" ;;
        *) color="$COLOR_YELLOW" ;;
    esac

    results+=("${color}${vm_name}|${current_vm_state}|${current_os_state}|${os_distro}${COLOR_RESET}")
done

# ────────────────────────────────────────────────────────────────
# Determine max column widths (strip colors for length)
# ────────────────────────────────────────────────────────────────
max_vm=8; max_vmstate=8; max_osstate=8; max_osdistro=9
declare -a clean_results=()

for entry in "${results[@]}"; do
    clean=$(echo "$entry" | sed 's/\x1b\[[0-9;]*m//g')
    clean_results+=("$clean")
    IFS='|' read -r vm state os distro <<< "$clean"
    (( ${#vm} > max_vm )) && max_vm=${#vm}
    (( ${#state} > max_vmstate )) && max_vmstate=${#state}
    (( ${#os} > max_osstate )) && max_osstate=${#os}
    (( ${#distro} > max_osdistro )) && max_osdistro=${#distro}
done

# ────────────────────────────────────────────────────────────────
# Print header
# ────────────────────────────────────────────────────────────────
printf "%-${max_vm}s %-${max_vmstate}s %-${max_osstate}s %-${max_osdistro}s\n" \
    "VM-Name" "VM-State" "OS-State" "OS-Distro"
printf -- '-%.0s' $(seq 1 $((max_vm + max_vmstate + max_osstate + max_osdistro + 3)))
echo

# ────────────────────────────────────────────────────────────────
# Sort and print with colors
# ────────────────────────────────────────────────────────────────
# Sorting by VM-State (running first), using clean_results as key reference
sorted_indices=($(for i in "${!clean_results[@]}"; do
    IFS='|' read -r vm state _ <<< "${clean_results[$i]}"
    printf "%s %s\n" "$i" "$state"
done | sort -k2,2r | awk '{print $1}'))

for idx in "${sorted_indices[@]}"; do
    raw="${results[$idx]}"
    clean="${clean_results[$idx]}"
    IFS='|' read -r vm state os distro <<< "$clean"
    color_line=$(echo "$raw" | grep -oP '^\x1b\[[0-9;]*m')
    reset_line=$COLOR_RESET
    printf "%s%-${max_vm}s %- ${max_vmstate}s %- ${max_osstate}s %- ${max_osdistro}s%s\n" \
        "$color_line" "$vm" "$state" "$os" "$distro" "$reset_line"
done
