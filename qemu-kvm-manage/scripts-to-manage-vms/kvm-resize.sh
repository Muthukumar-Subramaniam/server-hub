#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh
source /server-hub/common-utils/color-functions.sh

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl resize [OPTIONS] [hostname]

Options:
  -f, --force          Force power-off without prompt if VM is running
  -t, --type <type>    Resource type to resize: memory, cpu, disk (default: prompt)
  -m, --memory <size>  Memory size in GiB (power of 2, default: prompt)
  -c, --cpu <count>    vCPU count (power of 2, default: prompt)
  -d, --disk <size>    Disk increase size in GiB (multiple of 5, 5-50, default: prompt)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to resize (optional, will prompt if not given)

Examples:
  qlabvmctl resize vm1                        # Interactive mode
  qlabvmctl resize -f -t memory -m 8 vm1      # Automated memory resize to 8GiB
  qlabvmctl resize -f -t cpu -c 4 vm1         # Automated CPU resize to 4 vCPUs
  qlabvmctl resize -f -t disk -d 10 vm1       # Automated disk increase by 10GiB
"
}

# Parse arguments
force_poweroff=false
vm_hostname_arg=""
resize_type_arg=""
memory_size_arg=""
cpu_count_arg=""
disk_increase_arg=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            fn_show_help
            exit 0
            ;;
        -f|--force)
            force_poweroff=true
            shift
            ;;
        -t|--type)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "[ERROR] Option -t/--type requires a value (memory, cpu, or disk)."
                exit 1
            fi
            resize_type_arg="$2"
            shift 2
            ;;
        -m|--memory)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "[ERROR] Option -m/--memory requires a value."
                exit 1
            fi
            memory_size_arg="$2"
            shift 2
            ;;
        -c|--cpu)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "[ERROR] Option -c/--cpu requires a value."
                exit 1
            fi
            cpu_count_arg="$2"
            shift 2
            ;;
        -d|--disk)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "[ERROR] Option -d/--disk requires a value."
                exit 1
            fi
            disk_increase_arg="$2"
            shift 2
            ;;
        -*)
            print_error "[ERROR] Unknown option: $1"
            fn_show_help
            exit 1
            ;;
        *)
            if [[ -n "$vm_hostname_arg" ]]; then
                print_error "[ERROR] Multiple hostnames provided. Only one VM can be processed at a time."
                fn_show_help
                exit 1
            fi
            vm_hostname_arg="$1"
            shift
            ;;
    esac
done

# Use argument or prompt for hostname
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_hostname_arg"

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    print_error "[ERROR] VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

fn_shutdown_or_poweroff() {
    # If force flag is set, try graceful shutdown first, then force if needed
    if [[ "$force_poweroff" == true ]]; then
        print_info "[INFO] Force flag detected. Attempting graceful shutdown first..."
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh
        SHUTDOWN_VM_CONTEXT="Attempting graceful shutdown" SHUTDOWN_VM_STRICT=false shutdown_vm "$qemu_kvm_hostname"
        
        # Wait for VM to shut down with timeout
        print_info "[INFO] Waiting for VM \"${qemu_kvm_hostname}\" to shut down (timeout: 30s)..."
        TIMEOUT=30
        ELAPSED=0
        while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
            if (( ELAPSED >= TIMEOUT )); then
                print_warning "[WARNING] Graceful shutdown timed out. Forcing power off..."
                source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
                if ! POWEROFF_VM_CONTEXT="Forcing power off after timeout" POWEROFF_VM_STRICT=true poweroff_vm "$qemu_kvm_hostname"; then
                    exit 1
                fi
                break
            fi
            sleep 2
            ((ELAPSED+=2))
        done
        
        if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
            print_success "[SUCCESS] VM has been shut down successfully. Proceeding further."
        fi
        return 0
    fi
    
    print_warning "[WARNING] VM \"$qemu_kvm_hostname\" is still running!"
    print_info "[INFO] Select an option to proceed:\n"
    echo "\t1) Try Graceful Shutdown"
    echo "\t2) Force Power Off"
    echo -e "\tq) Quit\n"

    read -rp "Enter your choice: " selected_choice

    case "$selected_choice" in
        1)
            print_info "[INFO] Initiating graceful shutdown..."
            source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh
            if ! SHUTDOWN_VM_CONTEXT="Initiating graceful shutdown" shutdown_vm "$qemu_kvm_hostname"; then
                exit 1
            fi
            
            # Wait for VM to shut down with timeout
            print_info "[INFO] Waiting for VM \"${qemu_kvm_hostname}\" to shut down (timeout: 60s)..."
            TIMEOUT=60
            ELAPSED=0
            while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
                if (( ELAPSED >= TIMEOUT )); then
                    print_warning "[WARNING] VM did not shut down within ${TIMEOUT}s."
                    print_info "[INFO] You may want to force power off instead."
                    exit 1
                fi
                sleep 2
                ((ELAPSED+=2))
            done
            print_success "[SUCCESS] VM has been shut down successfully. Proceeding further."
            ;;
        2)
            print_info "[INFO] Forcing power off..."
            source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
            if ! POWEROFF_VM_CONTEXT="Forcing power off" POWEROFF_VM_STRICT=true poweroff_vm "$qemu_kvm_hostname"; then
                exit 1
            fi
            ;;
        q)
            print_info "[INFO] Quitting without any action."
            exit 0
            ;;
        *)
            print_error "[ERROR] Invalid option!"
            exit 1
            ;;
    esac
}

resize_vm_memory() {
    host_mem_kib=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    host_mem_gib=$(( host_mem_kib / 1024 / 1024 ))
    (( host_mem_gib % 2 != 0 )) && host_mem_gib=$(( host_mem_gib + 1 ))

    current_mem_kib=$(sudo virsh dominfo "$qemu_kvm_hostname" | awk '/^Max memory/ {print $3}')
    current_vm_mem_gib=$(( current_mem_kib / 1024 / 1024 ))

    # Get memory size from argument or prompt
    if [[ -n "$memory_size_arg" ]]; then
        # Validate provided memory size
        if ! [[ "$memory_size_arg" =~ ^[0-9]+$ ]]; then
            print_error "[ERROR] Invalid memory size: $memory_size_arg. Must be numeric."
            exit 1
        fi
        if (( memory_size_arg < 2 || (memory_size_arg & (memory_size_arg - 1)) != 0 )); then
            print_error "[ERROR] Memory size must be a power of 2 (2, 4, 8...)."
            exit 1
        fi
        if (( memory_size_arg >= host_mem_gib )); then
            print_error "[ERROR] Memory size must be less than host memory ${host_mem_gib} GiB."
            exit 1
        fi
        vm_mem_gib="$memory_size_arg"
        print_success "[SUCCESS] Using memory size: ${vm_mem_gib} GiB"
    else
        # Prompt for memory size
        print_info "[INFO] Memory of Host Machine: ${host_mem_gib} GiB"
        print_info "[INFO] Memory of VM '${qemu_kvm_hostname}': ${current_vm_mem_gib} GiB"
        print_info "[INFO] Allowed sizes: Powers of 2 — e.g., 2, 4, 8... but less than ${host_mem_gib} GiB\n"

        while true; do
            read -rp "Enter new VM memory size (GiB): " vm_mem_gib

            if ! [[ "$vm_mem_gib" =~ ^[0-9]+$ ]]; then
                print_error "[ERROR] Invalid input for VM memory size. Must be numeric.\n"
                continue
            fi

            if (( vm_mem_gib < 2 || (vm_mem_gib & (vm_mem_gib - 1)) != 0 )); then
                print_error "[ERROR] VM memory size must be a power of 2 (2, 4, 8...)\n"
                continue
            fi

            if (( vm_mem_gib >= host_mem_gib )); then
                print_error "[ERROR] VM memory size must be less than host memory ${host_mem_gib} GiB\n"
                continue
            fi
            break
        done
    fi

    vm_mem_kib=$(( vm_mem_gib * 1024 * 1024 ))
    print_info "[INFO] Updating memory size of VM to ${vm_mem_gib} GiB..."
    if sudo virsh setmaxmem "$qemu_kvm_hostname" "$vm_mem_kib" --config && \
       sudo virsh setmem "$qemu_kvm_hostname" "$vm_mem_kib" --config; then
        print_success "[SUCCESS] VM memory updated to ${vm_mem_gib} GiB. Proceeding to power on the VM."
        sudo virsh start "${qemu_kvm_hostname}" 2>/dev/null
        print_success "[SUCCESS] VM '${qemu_kvm_hostname}' started successfully after memory resize."
    else
        print_error "[ERROR] Failed to update VM memory."
        exit 1
    fi
}

resize_vm_cpu() {
    current_vcpus_of_vm=$(sudo virsh dominfo "$qemu_kvm_hostname" | awk '/^CPU\(s\)/ {print $2}')
    host_cpu_count=$(nproc)

    # Get CPU count from argument or prompt
    if [[ -n "$cpu_count_arg" ]]; then
        # Validate provided CPU count
        if ! [[ "$cpu_count_arg" =~ ^[0-9]+$ ]]; then
            print_error "[ERROR] Invalid vCPU count: $cpu_count_arg. Must be numeric."
            exit 1
        fi
        if (( cpu_count_arg < 2 )); then
            print_error "[ERROR] vCPU count must be at least 2."
            exit 1
        fi
        if ! (( (cpu_count_arg & (cpu_count_arg - 1)) == 0 )); then
            print_error "[ERROR] vCPU count must be a power of 2 (2, 4, 8...)."
            exit 1
        fi
        if (( cpu_count_arg > host_cpu_count )); then
            print_error "[ERROR] Cannot exceed host CPU count ${host_cpu_count}."
            exit 1
        fi
        new_vcpus_of_vm="$cpu_count_arg"
        print_success "[SUCCESS] Using vCPU count: ${new_vcpus_of_vm}"
    else
        # Prompt for CPU count
        print_info "[INFO] Host logical CPUs: $host_cpu_count"
        print_info "[INFO] Current vCPUs of VM '${qemu_kvm_hostname}': $current_vcpus_of_vm"
        print_info "[INFO] Allowed values: Powers of 2 — e.g., 2, 4, 8... up to ${host_cpu_count}\n"

        while true; do
            read -rp "Enter new vCPU count: " new_vcpus_of_vm

            if ! [[ "$new_vcpus_of_vm" =~ ^[0-9]+$ ]]; then
                print_error "[ERROR] Invalid input for vCPU count. Must be numeric.\n"
                continue
            fi

            if (( new_vcpus_of_vm < 2 )); then
                print_error "[ERROR] vCPU count must be at least 2.\n"
                continue
            fi

            if ! (( (new_vcpus_of_vm & (new_vcpus_of_vm - 1)) == 0 )); then
                print_error "[ERROR] vCPU count must be a power of 2 (2, 4, 8...)\n"
                continue
            fi

            if (( new_vcpus_of_vm > host_cpu_count )); then
                print_error "[ERROR] Cannot exceed host CPU count ${host_cpu_count}\n"
                continue
            fi
            break
        done
    fi

    print_info "[INFO] Updating vCPUs of VM '${qemu_kvm_hostname}' to ${new_vcpus_of_vm}..."
    if sudo virsh setvcpus "$qemu_kvm_hostname" "$new_vcpus_of_vm" --maximum --config && \
       sudo virsh setvcpus "$qemu_kvm_hostname" "$new_vcpus_of_vm" --config; then
        print_success "[SUCCESS] vCPU count updated to $new_vcpus_of_vm. Proceeding to power on the VM."
        sudo virsh start "${qemu_kvm_hostname}" 2>/dev/null
        print_success "[SUCCESS] VM '$qemu_kvm_hostname' started successfully after vCPU resize."
    else
        print_error "[ERROR] Failed to update vCPU count."
        exit 1
    fi
}

resize_vm_disk() {
    vm_qcow2_disk_path="/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2"

    if [ ! -f "$vm_qcow2_disk_path" ]; then
        print_error "[ERROR] Disk image not found at $vm_qcow2_disk_path"
        exit 1
    fi

    current_disk_gib=$(sudo qemu-img info "${vm_qcow2_disk_path}" | grep "virtual size" | grep -o '[0-9]\+ GiB' | cut -d' ' -f1)

    # Get disk increase size from argument or prompt
    if [[ -n "$disk_increase_arg" ]]; then
        # Validate provided disk increase size
        if ! [[ "$disk_increase_arg" =~ ^[0-9]+$ ]]; then
            print_error "[ERROR] Invalid disk increase size: $disk_increase_arg. Must be numeric."
            exit 1
        fi
        if (( disk_increase_arg % 5 != 0 )); then
            print_error "[ERROR] Disk increase size must be a multiple of 5 GiB."
            exit 1
        fi
        if (( disk_increase_arg < 5 || disk_increase_arg > 50 )); then
            print_error "[ERROR] Disk increase size must be between 5 and 50 GiB."
            exit 1
        fi
        grow_size_gib="$disk_increase_arg"
        print_success "[SUCCESS] Using disk increase size: ${grow_size_gib} GiB"
    else
        # Prompt for disk increase size
        print_info "[INFO] Current disk size of VM '${qemu_kvm_hostname}': ${current_disk_gib} GiB"
        print_info "[INFO] Allowed sizes for increase: Steps of 5 GiB — e.g., 5, 10, 15... up to 50 GiB\n"

        while true; do
            read -rp "Enter increase size (GiB): " grow_size_gib

            if ! [[ "$grow_size_gib" =~ ^[0-9]+$ ]]; then
                print_error "[ERROR] Invalid input for increase size of disk. Must be numeric.\n"
                continue
            fi

            if (( grow_size_gib % 5 != 0 )); then
                print_error "[ERROR] Increase in disk size must be a multiple of 5 GiB.\n"
                continue
            fi

            if (( grow_size_gib < 5 || grow_size_gib > 50 )); then
                print_error "[ERROR] Increase in disk size must be between 5 and 50 GiB.\n"
                continue
            fi
            break
        done
    fi

    print_info "[INFO] Growing disk by ${grow_size_gib} GiB..."
    if sudo qemu-img resize "$vm_qcow2_disk_path" +${grow_size_gib}G; then
        total_vm_disk_size=$(( current_disk_gib + grow_size_gib ))
        print_success "[SUCCESS] Disk of VM '${qemu_kvm_hostname}' resized to ${total_vm_disk_size} GiB. Proceeding to power on the VM."

        sudo virsh start "${qemu_kvm_hostname}" 2>/dev/null
        print_success "[SUCCESS] VM '$qemu_kvm_hostname' started successfully after disk resize."

        print_info "[INFO] Attempting to resize root file system of VM '$qemu_kvm_hostname'..."
        SSH_TARGET_HOST="${qemu_kvm_hostname}"
        MAX_SSH_WAIT_SECONDS=120
        SSH_RETRY_INTERVAL_SECONDS=5
        SSH_OPTS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        print_info "[INFO] Waiting up to $MAX_SSH_WAIT_SECONDS seconds for SSH connection on $SSH_TARGET_HOST..." nskip
        ssh_start_time=$(date +%s)
        while true; do
            sleep "$SSH_RETRY_INTERVAL_SECONDS"
            if ssh $SSH_OPTS ${lab_infra_admin_username}@${SSH_TARGET_HOST} "true" &>/dev/null; then
                echo " [SSH-Active]"
                break
            fi
            ssh_current_time=$(date +%s)
            ssh_elapsed_time=$((ssh_current_time - ssh_start_time))
            if [ "$ssh_elapsed_time" -ge "$MAX_SSH_WAIT_SECONDS" ]; then
                print_warning "[WARNING] Timed out waiting for SSH after $MAX_SSH_WAIT_SECONDS seconds."
                print_info "[INFO] Execute lab-rootfs-extender utility manually from $SSH_TARGET_HOST once booted."
                exit 1
            fi
        done
        /server-hub/common-utils/lab-rootfs-extender $SSH_TARGET_HOST
        print_success "[SUCCESS] Successfully extended the size of OS disk and root filesystem of ${SSH_TARGET_HOST} to ${total_vm_disk_size} GiB."
    else
        print_error "[ERROR] Disk resize of VM '${qemu_kvm_hostname}' failed!"
        exit 1
    fi
}

# Check if VM is running and shutdown if needed
fn_check_vm_power_state() {
    if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
        print_success "[SUCCESS] VM '$qemu_kvm_hostname' is not running. Proceeding further."
    else
        fn_shutdown_or_poweroff
    fi
}

# Determine resize type (from argument or prompt)
if [[ -n "$resize_type_arg" ]]; then
    # Validate resize type
    case "$resize_type_arg" in
        memory|cpu|disk)
            resize_type="$resize_type_arg"
            ;;
        *)
            print_error "[ERROR] Invalid resize type: $resize_type_arg. Must be 'memory', 'cpu', or 'disk'."
            exit 1
            ;;
    esac
    
    # Automated mode - check VM state and perform resize
    fn_check_vm_power_state
    
    case "$resize_type" in
        memory)
            resize_vm_memory
            ;;
        cpu)
            resize_vm_cpu
            ;;
        disk)
            resize_vm_disk
            ;;
    esac
    exit 0
fi

# Interactive mode - show menu
while true; do
    print_info "[INFO] Resize Resource of VM '$qemu_kvm_hostname'"
    print_info "[INFO] Select an option:\n"
    echo "\t1) Resize Memory"
    echo "\t2) Resize CPU"
    echo "\t3) Resize Disk"
    echo -e "\tq) Quit\n"

    read -rp "Enter your choice: " resize_choice

    case "$resize_choice" in
        1)
            fn_check_vm_power_state
            resize_vm_memory
            exit 0
            ;;
        2)
            fn_check_vm_power_state
            resize_vm_cpu
            exit 0
            ;;
        3)
            fn_check_vm_power_state
            resize_vm_disk
            exit 0
            ;;
        q)
            print_info "[INFO] Quitting without any action."
            exit 0
            ;;
        *)
            print_error "[ERROR] Invalid option!\n"
            ;;
    esac
done
