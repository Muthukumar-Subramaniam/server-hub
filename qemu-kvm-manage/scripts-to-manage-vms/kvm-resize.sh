#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

if [[ "$EUID" -eq 0 ]]; then
    echo -e "\n⛔ Running as root user is not allowed."
    echo -e "\n🔐 This script should be run as a user who has sudo privileges, but *not* using sudo.\n"
    exit 1
fi

# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    echo "❌❌❌  FATAL: WRONG PLACE, BUDDY! ❌❌❌"
    echo -e "\n⚠️  Note:"
    echo -e "  🔹 This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo -e "  🔹 You’re currently inside a QEMU guest VM, which makes absolutely no sense.\n"
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

# Use first argument or prompt for hostname
if [ -n "$1" ]; then
    qemu_kvm_hostname="$1"
else
    read -rp "⌨️ Please enter the Hostname of the VM to be resized : " qemu_kvm_hostname
fi

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM '$qemu_kvm_hostname' does not exist."
    exit 1
fi

fn_shutdown_or_poweroff() {
    echo -e "\n⚠️  VM '$qemu_kvm_hostname' is still Running ! "
    echo -e "    Select any of the below options to proceed further.\n"
    echo "	1) Try Graceful Shutdown"
    echo "	2) Force Power Off"
    echo -e "	q) Quit\n"

    read -rp "Enter your choice : " selected_choice

    case "$selected_choice" in
        1)
            echo -e "\n🛑 Initiating graceful shutdown . . ."
	    infra_mgmt_super_username=$(cat /virtual-machines/infra-mgmt-super-username)
            local_infra_domain_name=$(cat /virtual-machines/local_infra_domain_name)
	    echo -e "\n🔍 Checking SSH connectivity to ${qemu_kvm_hostname}.${local_infra_domain_name} . . ."
            if nc -zw5 "${qemu_kvm_hostname}.${local_infra_domain_name}" 22; then
                echo -e "\n🔗 SSH connectivity seems to be fine. Initiating graceful shutdown . . .\n"
                ssh -o LogLevel=QUIET \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    "${infra_mgmt_super_username}@${qemu_kvm_hostname}.${local_infra_domain_name}" \
                    "sudo shutdown -h now"

                echo -e "\n⏳ Waiting for VM '${qemu_kvm_hostname}' to shut down . . ."
                while sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; do
                    sleep 1
                done
                echo -e "\n✅ VM has been shut down successfully, Proceeding further."
            else
                echo -e "\n❌ SSH connection issue with ${qemu_kvm_hostname}.${local_infra_domain_name}.\n❌ Cannot perform graceful shutdown.\n"
		exit 1
            fi
            ;;
        2)
            echo -e "\n⚡ Forcing power off . . ."
	    sudo virsh destroy "${qemu_kvm_hostname}" &>/dev/null
	    sleep 1
	    echo -e "✅ VM '$qemu_kvm_hostname' is stopped successfully. \n"
            ;;
        q)
            echo -e "\n👋 Quitting without any action.\n"
            exit
            ;;
        *)
            echo "❌ Invalid option. Please choose between 1 and 3."
            ;;
    esac
}

resize_vm_memory() {
    host_mem_kib=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    host_mem_gib=$(( host_mem_kib / 1024 / 1024 ))
    (( host_mem_gib % 2 != 0 )) && host_mem_gib=$(( host_mem_gib + 1 ))

    current_mem_kib=$(sudo virsh dominfo "$qemu_kvm_hostname" | awk '/^Max memory/ {print $3}')
    current_vm_mem_gib=$(( current_mem_kib / 1024 / 1024 ))

    echo -e "\n🖥️ Memory of Host Machine : ${host_mem_gib} GiB"
    echo "📦 Memory of VM '${qemu_kvm_hostname}' : ${current_vm_mem_gib} GiB"
    echo -e "📌 Allowed sizes: Powers of 2 — e.g., 2, 4, 8... but less than ${host_mem_gib} GiB\n"

    while true; do
        read -rp "Enter new VM memory size (GiB): " vm_mem_gib

        if ! [[ "$vm_mem_gib" =~ ^[0-9]+$ ]]; then
            echo -e "\n❌ Invalid input for VM memory size. Must be numeric.\n"
            continue
        fi

	if (( vm_mem_gib < 2 || (vm_mem_gib & (vm_mem_gib - 1)) != 0 )); then
    	    echo -e "\n❌ VM memory size must be a power of 2 (2, 4, 8...)\n"
            continue
	fi

        if (( vm_mem_gib >= host_mem_gib )); then
            echo -e "\n❌ VM memory size must be less than host memory ${host_mem_gib} GiB\n"
            continue
        fi

        vm_mem_kib=$(( vm_mem_gib * 1024 * 1024 ))
        echo -e "\n📐 Updating memory size of VM to ${vm_mem_gib} GiB . . .\n"
        sudo virsh setmaxmem "$qemu_kvm_hostname" "$vm_mem_kib" --config && \
        sudo virsh setmem "$qemu_kvm_hostname" "$vm_mem_kib" --config && \
        echo -e "✅ VM memory updated to ${vm_mem_gib} GiB, Proceeding to power on the VM.\n"
	sudo virsh start "${qemu_kvm_hostname}" 2>/dev/null
	echo -e "✅ VM '${qemu_kvm_hostname}' is started successfully after Memory resize. \n"
        break
    done
}

resize_vm_cpu() {
    current_vcpus_of_vm=$(sudo virsh dominfo "$qemu_kvm_hostname" | awk '/^CPU\(s\)/ {print $2}')
    host_cpu_count=$(nproc)

    echo -e "\n🧠 Host logical CPUs : $host_cpu_count"
    echo "🧾 Current vCPUs of VM '${qemu_kvm_hostname}' : $current_vcpus_of_vm"
    echo -e "📌 Allowed values: Powers of 2 — e.g., 2, 4, 8... up to ${host_cpu_count}\n"

    while true; do
        read -rp "Enter new vCPU count: " new_vcpus_of_vm

        if ! [[ "$new_vcpus_of_vm" =~ ^[0-9]+$ ]]; then
            echo -e "\n❌ Invalid input for vCPU count. Must be numeric.\n"
            continue
        fi

        if (( new_vcpus_of_vm < 2 )); then
            echo -e "\n❌ vCPU count must be at least 2.\n"
            continue
        fi

        if ! (( (new_vcpus_of_vm & (new_vcpus_of_vm - 1)) == 0 )); then
            echo -e "\n❌ vCPU count must be a power of 2 (2, 4, 8...)\n"
            continue
        fi

        if (( new_vcpus_of_vm > host_cpu_count )); then
            echo -e "\n❌ Cannot exceed host CPU count ${host_cpu_count}\n"
            continue
        fi

        echo -e "\n🔧 Updating vCPUs of VM '${qemu_kvm_hostname}' to ${new_vcpus_of_vm}  . . .\n"
        sudo virsh setvcpus "$qemu_kvm_hostname" "$new_vcpus_of_vm" --maximum --config && \
        sudo virsh setvcpus "$qemu_kvm_hostname" "$new_vcpus_of_vm" --config && \
        echo -e "✅ vCPU count updated to $new_vcpus_of_vm, Proceeding to power on the VM.\n"
	sudo virsh start "${qemu_kvm_hostname}" 2>/dev/null
	echo -e "✅ VM '$qemu_kvm_hostname' is started successfully after vCPU resize. \n"
        break
    done
}

resize_vm_disk() {

    vm_qcow2_disk_path="/virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2"

    if [ ! -f "$vm_qcow2_disk_path" ]; then
        echo -e "\n❌ Disk image not found at $vm_qcow2_disk_path\n"
        return
    fi

    current_disk_gib=$(sudo qemu-img info "${vm_qcow2_disk_path}" | grep "virtual size" | grep -o '[0-9]\+ GiB' | cut -d' ' -f1)

    echo -e "\n📏 Current disk size of VM '${qemu_kvm_hostname}' : ${current_disk_gib} GiB\n"
    echo -e "📌 Allowed sizes for increase: Steps of 5 GiB — e.g., 5, 10, 15... upto 50 GiB\n"

    while true; do
        read -rp "Enter increase size (GiB): " grow_size_gib

        if ! [[ "$grow_size_gib" =~ ^[0-9]+$ ]]; then
            echo -e "\n❌ Invalid input for increase size of disk. Must be numeric.\n"
            continue
        fi

        if (( grow_size_gib % 5 != 0 )); then
            echo -e "\n❌ Increase in disk size must be a multiple of 5 GiB.\n"
            continue
        fi

        if (( grow_size_gib < 5 || grow_size_gib > 50 )); then
            echo -e "\n❌ Increase in disk size must be between 5 and 50 GiB.\n"
            continue
        fi

        echo "📂 Growing disk by ${grow_size_gib} GiB . . ."
        if sudo qemu-img resize "$vm_qcow2_disk_path" +${grow_size_gib}G; then
	    total_vm_disk_size=$(( current_disk_gib + grow_size_gib ))
            echo -e "\n✅ Disk of VM '${qemu_kvm_hostname}' resized to ${total_vm_disk_size} GiB, Proceeding to power on the VM."
            echo -e "📌 Expand filesystem inside VM after boot.\n"
	    sudo virsh start "${qemu_kvm_hostname}" 2>/dev/null
	    echo -e "✅ VM '$qemu_kvm_hostname' is started successfully after disk resize. \n"
        else
            echo -e "\n❌ Disk resize of VM '${qemu_kvm_hostname}' failed ! \n"
	    exit 1
        fi
        break
    done
}

while true; do
    echo -e "\n🛠️  Resize Resource of VM '$qemu_kvm_hostname' "
    echo -e "    Select an option.\n"
    echo "	1) Resize Memory"
    echo "	2) Resize CPU"
    echo "	3) Resize Disk"
    echo -e "	q) Quit\n"

    read -rp "Enter your choice : " resize_choice

    # Check if VM is running in 'virsh list'
    fn_check_vm_power_state() {
    	if ! sudo virsh list  | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
        	echo -e "✅ VM '$qemu_kvm_hostname' is not Running, Proceeding further. \n"
    	else
        	fn_shutdown_or_poweroff
    	fi
    }

    case "$resize_choice" in
        1) fn_check_vm_power_state;resize_vm_memory;exit;;
        2) fn_check_vm_power_state;resize_vm_cpu;exit;;
        3) fn_check_vm_power_state;resize_vm_disk;exit;;
        q) echo -e "\n👋 Quitting without any action.\n";exit;;
        *) echo -e "\n❌ Invalid option ! \n" ;;
    esac
done

exit
