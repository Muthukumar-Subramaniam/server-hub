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
  -c, --count <num>    vCPU count (power of 2, min 2, only for cpu type, default: prompt)
  -g, --gib <size>     Size in GiB (default: prompt)
                       - For memory: power of 2 (2, 4, 8, 16...), less than host memory
                       - For disk: multiple of 5 (5, 10, 15...), range 5-50 GiB (OS disk only)
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to resize (optional, will prompt if not given)

Examples:
  qlabvmctl resize vm1                        # Interactive mode
  qlabvmctl resize -f -t memory -g 8 vm1      # Automated memory resize to 8GiB
  qlabvmctl resize -f -t cpu -c 4 vm1         # Automated CPU resize to 4 vCPUs
  qlabvmctl resize -f -t disk -g 10 vm1       # Automated OS disk increase by 10GiB
"
}

# Parse arguments
force_poweroff=false
vm_hostname_arg=""
resize_type_arg=""
count_arg=""
gib_arg=""

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
                print_error "Option -t/--type requires a value (memory, cpu, or disk)."
                exit 1
            fi
            resize_type_arg="$2"
            shift 2
            ;;
        -c|--count)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "Option -c/--count requires a value."
                exit 1
            fi
            count_arg="$2"
            shift 2
            ;;
        -g|--gib)
            if [[ -z "$2" || "$2" == -* ]]; then
                print_error "Option -g/--gib requires a value."
                exit 1
            fi
            gib_arg="$2"
            shift 2
            ;;
        -*)
            print_error "Unknown option: $1"
            fn_show_help
            exit 1
            ;;
        *)
            if [[ -n "$vm_hostname_arg" ]]; then
                print_error "Multiple hostnames provided. Only one VM can be processed at a time."
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
print_task "Checking if VM exists..."
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    print_task_fail
    print_error "VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi
print_task_done

fn_shutdown_or_poweroff() {
    # If force flag is set, try graceful shutdown first, then force if needed
    if [[ "$force_poweroff" == true ]]; then
        print_task "Shutting down VM (graceful then force if needed)..."
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh
        SHUTDOWN_VM_CONTEXT="Attempting graceful shutdown" SHUTDOWN_VM_STRICT=false shutdown_vm "$qemu_kvm_hostname" &>/dev/null
        
        # Wait for VM to shut down with timeout
        TIMEOUT=30
        ELAPSED=0
        while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
            if (( ELAPSED >= TIMEOUT )); then
                source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
                if ! POWEROFF_VM_CONTEXT="Forcing power off after timeout" POWEROFF_VM_STRICT=true poweroff_vm "$qemu_kvm_hostname" &>/dev/null; then
                    print_task_fail
                    exit 1
                fi
                break
            fi
            sleep 2
            ((ELAPSED+=2))
        done
        
        if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
            print_task_done
        fi
        return 0
    fi
    
    print_warning "VM \"$qemu_kvm_hostname\" is still running!"
    print_info "Select an option to proceed:
  1) Try Graceful Shutdown
  2) Force Power Off
  q) Quit"

    read -rp "Enter your choice: " selected_choice

    case "$selected_choice" in
        1)
            print_task "Shutting down VM gracefully..."
            source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/shutdown-vm.sh
            if ! SHUTDOWN_VM_CONTEXT="Initiating graceful shutdown" shutdown_vm "$qemu_kvm_hostname" &>/dev/null; then
                print_task_fail
                exit 1
            fi
            
            # Wait for VM to shut down with timeout
            TIMEOUT=60
            ELAPSED=0
            while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
                if (( ELAPSED >= TIMEOUT )); then
                    print_task_fail
                    print_warning "VM did not shut down within ${TIMEOUT}s."
                    print_info "You may want to force power off instead."
                    exit 1
                fi
                sleep 2
                ((ELAPSED+=2))
            done
            print_task_done
            ;;
        2)
            print_task "Forcing power off VM..."
            source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/poweroff-vm.sh
            if ! POWEROFF_VM_CONTEXT="Forcing power off" POWEROFF_VM_STRICT=true poweroff_vm "$qemu_kvm_hostname" &>/dev/null; then
                print_task_fail
                exit 1
            fi
            print_task_done
            ;;
        q)
            print_info "Quitting without any action."
            exit 0
            ;;
        *)
            print_error "Invalid option!"
            exit 1
            ;;
    esac
}

validate_memory_args() {
    host_mem_kib=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    host_mem_gib=$(( host_mem_kib / 1024 / 1024 ))
    (( host_mem_gib % 2 != 0 )) && host_mem_gib=$(( host_mem_gib + 1 ))

    current_mem_kib=$(sudo virsh dominfo "$qemu_kvm_hostname" | awk '/^Max memory/ {print $3}')
    current_vm_mem_gib=$(( current_mem_kib / 1024 / 1024 ))

    if [[ -n "$gib_arg" ]]; then
        if ! [[ "$gib_arg" =~ ^[0-9]+$ ]]; then
            print_error "Invalid memory size: $gib_arg. Must be numeric."
            exit 1
        fi
        if (( gib_arg < 2 || (gib_arg & (gib_arg - 1)) != 0 )); then
            print_error "Memory size must be a power of 2 (2, 4, 8...)."
            exit 1
        fi
        if (( gib_arg >= host_mem_gib )); then
            print_error "Memory size must be less than host memory ${host_mem_gib} GiB."
            exit 1
        fi
        if (( gib_arg == current_vm_mem_gib )); then
            print_error "New memory size (${gib_arg} GiB) is same as current memory size."
            exit 1
        fi
    fi
}

validate_cpu_args() {
    current_vcpus_of_vm=$(sudo virsh dominfo "$qemu_kvm_hostname" | awk '/^CPU\(s\)/ {print $2}')
    host_cpu_count=$(nproc)

    if [[ -n "$count_arg" ]]; then
        if ! [[ "$count_arg" =~ ^[0-9]+$ ]]; then
            print_error "Invalid vCPU count: $count_arg. Must be numeric."
            exit 1
        fi
        if (( count_arg < 2 )); then
            print_error "vCPU count must be at least 2."
            exit 1
        fi
        if ! (( (count_arg & (count_arg - 1)) == 0 )); then
            print_error "vCPU count must be a power of 2 (2, 4, 8...)."
            exit 1
        fi
        if (( count_arg > host_cpu_count )); then
            print_error "Cannot exceed host CPU count ${host_cpu_count}."
            exit 1
        fi
        if (( count_arg == current_vcpus_of_vm )); then
            print_error "New vCPU count (${count_arg}) is same as current vCPU count."
            exit 1
        fi
    fi
}

validate_disk_args() {
    if [[ -n "$gib_arg" ]]; then
        if ! [[ "$gib_arg" =~ ^[0-9]+$ ]]; then
            print_error "Invalid disk increase size: $gib_arg. Must be numeric."
            exit 1
        fi
        if (( gib_arg % 5 != 0 )); then
            print_error "Disk increase size must be a multiple of 5 GiB."
            exit 1
        fi
        if (( gib_arg < 5 || gib_arg > 50 )); then
            print_error "Disk increase size must be between 5 and 50 GiB."
            exit 1
        fi
    fi
}

resize_vm_memory() {
    host_mem_kib=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    host_mem_gib=$(( host_mem_kib / 1024 / 1024 ))
    (( host_mem_gib % 2 != 0 )) && host_mem_gib=$(( host_mem_gib + 1 ))

    current_mem_kib=$(sudo virsh dominfo "$qemu_kvm_hostname" | awk '/^Max memory/ {print $3}')
    current_vm_mem_gib=$(( current_mem_kib / 1024 / 1024 ))

    # Get memory size from argument or prompt
    if [[ -n "$gib_arg" ]]; then
        vm_mem_gib="$gib_arg"
    else
        # Prompt for memory size
        print_info "Memory of Host Machine: ${host_mem_gib} GiB"
        print_info "Memory of VM '${qemu_kvm_hostname}': ${current_vm_mem_gib} GiB"
        print_info "Allowed sizes: Powers of 2 — e.g., 2, 4, 8... but less than ${host_mem_gib} GiB"

        while true; do
            read -rp "Enter new VM memory size (GiB): " vm_mem_gib

            if ! [[ "$vm_mem_gib" =~ ^[0-9]+$ ]]; then
                print_error "Invalid input for VM memory size. Must be numeric."
                continue
            fi

            if (( vm_mem_gib < 2 || (vm_mem_gib & (vm_mem_gib - 1)) != 0 )); then
                print_error "VM memory size must be a power of 2 (2, 4, 8...)"
                continue
            fi

            if (( vm_mem_gib >= host_mem_gib )); then
                print_error "VM memory size must be less than host memory ${host_mem_gib} GiB"
                continue
            fi

            if (( vm_mem_gib == current_vm_mem_gib )); then
                print_error "New memory size is same as current memory size (${current_vm_mem_gib} GiB)"
                continue
            fi
            break
        done
    fi

    vm_mem_kib=$(( vm_mem_gib * 1024 * 1024 ))
    print_task "Updating VM memory to ${vm_mem_gib} GiB..."
    if sudo virsh setmaxmem "$qemu_kvm_hostname" "$vm_mem_kib" --config &>/dev/null && \
       sudo virsh setmem "$qemu_kvm_hostname" "$vm_mem_kib" --config &>/dev/null; then
        print_task_done
        print_task "Starting VM..."
        if sudo virsh start "${qemu_kvm_hostname}" &>/dev/null; then
            print_task_done
            print_summary "VM '${qemu_kvm_hostname}' memory successfully resized to ${vm_mem_gib} GiB."
        else
            print_task_fail
            print_error "Failed to start VM after memory resize."
            exit 1
        fi
    else
        print_task_fail
        print_error "Failed to update VM memory."
        exit 1
    fi
}

resize_vm_cpu() {
    current_vcpus_of_vm=$(sudo virsh dominfo "$qemu_kvm_hostname" | awk '/^CPU\(s\)/ {print $2}')
    host_cpu_count=$(nproc)

    # Get CPU count from argument or prompt
    if [[ -n "$count_arg" ]]; then
        new_vcpus_of_vm="$count_arg"
    else
        # Prompt for CPU count
        print_info "Host logical CPUs: $host_cpu_count"
        print_info "Current vCPUs of VM '${qemu_kvm_hostname}': $current_vcpus_of_vm"
        print_info "Allowed values: Powers of 2 — e.g., 2, 4, 8... up to ${host_cpu_count}"

        while true; do
            read -rp "Enter new vCPU count: " new_vcpus_of_vm

            if ! [[ "$new_vcpus_of_vm" =~ ^[0-9]+$ ]]; then
                print_error "Invalid input for vCPU count. Must be numeric."
                continue
            fi

            if (( new_vcpus_of_vm < 2 )); then
                print_error "vCPU count must be at least 2."
                continue
            fi

            if ! (( (new_vcpus_of_vm & (new_vcpus_of_vm - 1)) == 0 )); then
                print_error "vCPU count must be a power of 2 (2, 4, 8...)"
                continue
            fi

            if (( new_vcpus_of_vm > host_cpu_count )); then
                print_error "Cannot exceed host CPU count ${host_cpu_count}"
                continue
            fi

            if (( new_vcpus_of_vm == current_vcpus_of_vm )); then
                print_error "New vCPU count is same as current vCPU count (${current_vcpus_of_vm})"
                continue
            fi
            break
        done
    fi

    print_task "Updating VM vCPUs to ${new_vcpus_of_vm}..."
    if sudo virsh setvcpus "$qemu_kvm_hostname" "$new_vcpus_of_vm" --maximum --config &>/dev/null && \
       sudo virsh setvcpus "$qemu_kvm_hostname" "$new_vcpus_of_vm" --config &>/dev/null; then
        print_task_done
        print_task "Starting VM..."
        if sudo virsh start "${qemu_kvm_hostname}" &>/dev/null; then
            print_task_done
            print_summary "VM '${qemu_kvm_hostname}' vCPUs successfully resized to ${new_vcpus_of_vm}."
        else
            print_task_fail
            print_error "Failed to start VM after vCPU resize."
            exit 1
        fi
    else
        print_task_fail
        print_error "Failed to update vCPU count."
        exit 1
    fi
}

resize_vm_disk() {
    vm_qcow2_disk_path="/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2"

    if [ ! -f "$vm_qcow2_disk_path" ]; then
        print_error "Disk image not found at $vm_qcow2_disk_path"
        exit 1
    fi

    current_disk_gib=$(sudo qemu-img info "${vm_qcow2_disk_path}" | grep "virtual size" | grep -o '[0-9]\+ GiB' | cut -d' ' -f1)

    # Get disk increase size from argument or prompt
    if [[ -n "$gib_arg" ]]; then
        grow_size_gib="$gib_arg"
    else
        # Prompt for disk increase size
        print_info "Current disk size of VM '${qemu_kvm_hostname}': ${current_disk_gib} GiB"
        print_info "Allowed sizes for increase: Steps of 5 GiB — e.g., 5, 10, 15... up to 50 GiB"

        while true; do
            read -rp "Enter increase size (GiB): " grow_size_gib

            if ! [[ "$grow_size_gib" =~ ^[0-9]+$ ]]; then
                print_error "Invalid input for increase size of disk. Must be numeric."
                continue
            fi

            if (( grow_size_gib % 5 != 0 )); then
                print_error "Increase in disk size must be a multiple of 5 GiB."
                continue
            fi

            if (( grow_size_gib < 5 || grow_size_gib > 50 )); then
                print_error "Increase in disk size must be between 5 and 50 GiB."
                continue
            fi
            break
        done
    fi

    print_task "Growing disk by ${grow_size_gib} GiB..."
    if sudo qemu-img resize "$vm_qcow2_disk_path" +${grow_size_gib}G &>/dev/null; then
        print_task_done
        total_vm_disk_size=$(( current_disk_gib + grow_size_gib ))
        
        print_task "Starting VM..."
        if sudo virsh start "${qemu_kvm_hostname}" &>/dev/null; then
            print_task_done
        else
            print_task_fail
            print_error "Failed to start VM after disk resize."
            exit 1
        fi

        print_task "Waiting for SSH access..."
        SSH_TARGET_HOST="${qemu_kvm_hostname}"
        MAX_SSH_WAIT_SECONDS=120
        SSH_RETRY_INTERVAL_SECONDS=5
        SSH_OPTS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        
        ssh_start_time=$(date +%s)
        while true; do
            sleep "$SSH_RETRY_INTERVAL_SECONDS"
            if ssh $SSH_OPTS ${lab_infra_admin_username}@${SSH_TARGET_HOST} "true" &>/dev/null; then
                print_task_done
                break
            fi
            ssh_current_time=$(date +%s)
            ssh_elapsed_time=$((ssh_current_time - ssh_start_time))
            if [ "$ssh_elapsed_time" -ge "$MAX_SSH_WAIT_SECONDS" ]; then
                print_task_fail
                print_warning "Timed out waiting for SSH after $MAX_SSH_WAIT_SECONDS seconds."
                print_info "Execute lab-rootfs-extender utility manually from $SSH_TARGET_HOST once booted."
                exit 1
            fi
        done
        
        if ! /server-hub/common-utils/lab-rootfs-extender $SSH_TARGET_HOST; then
            print_error "Failed to extend root filesystem."
            exit 1
        fi
        
        print_summary "VM '${qemu_kvm_hostname}' disk successfully resized to ${total_vm_disk_size} GiB."
    else
        print_task_fail
        print_error "Disk resize failed!"
        exit 1
    fi
}

# Check if VM is running and shutdown if needed
fn_check_vm_power_state() {
    if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
        print_info "VM is not running."
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
            print_error "Invalid resize type: $resize_type_arg. Must be 'memory', 'cpu', or 'disk'."
            exit 1
            ;;
    esac
    
    # Automated mode - check VM state and perform resize
    case "$resize_type" in
        memory)
            validate_memory_args
            ;;
        cpu)
            validate_cpu_args
            ;;
        disk)
            validate_disk_args
            ;;
    esac

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
    print_info "Resize resource of VM '$qemu_kvm_hostname':
  1) Resize Memory
  2) Resize CPU
  3) Resize Disk
  q) Quit"

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
            print_info "Quitting without any action."
            exit 0
            ;;
        *)
            print_error "Invalid option!"
            ;;
    esac
done
