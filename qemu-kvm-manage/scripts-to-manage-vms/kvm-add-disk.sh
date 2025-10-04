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
    echo -e "\n⚠️ Note:"
    echo -e "  🔹 This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo -e "  🔹 You’re currently inside a QEMU guest VM, which makes absolutely no sense.\n"
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

# Function to show help
fn_show_help() {
    cat <<EOF
Usage: kvm-add-disk [hostname]

Arguments:
  hostname  Name of the VM to add disks to (optional, will prompt if not given)
EOF
}

# Handle help and argument validation
if [[ $# -gt 1 ]]; then
    echo -e "❌ Too many arguments.\n"
    fn_show_help
    exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    fn_show_help
    exit 0
fi

if [[ "$1" == -* ]]; then
    echo -e "❌ No such option: $1\n"
    fn_show_help
    exit 1
fi

# Use first argument or prompt for hostname
if [ -n "$1" ]; then
    qemu_kvm_hostname="$1"
else
    read -rp "⌨️ Please enter the Hostname of the VM to add disks : " qemu_kvm_hostname
    if [[ -n "${KVM_TOOL_EXECUTED_FROM:-}" && "${KVM_TOOL_EXECUTED_FROM}" == "${qemu_kvm_hostname}" ]]; then
	echo -e "\n❌ This operation is not allowed to avoid self-referential KVM actions that could destabilize the infra server."
    	echo -e "⚠️ Note:"
	echo -e "  🔹 You are running a KVM management related action for the lab infra server from the infra server itself."
	echo -e "  🔹 If you still need to perform this operation, you need to do this from the Linux workstation running the QEMU/KVM setup.\n"
	exit 1
    fi
fi

if [[ ! "${qemu_kvm_hostname}" =~ ^[a-z0-9-]+$ || "${qemu_kvm_hostname}" =~ ^- || "${qemu_kvm_hostname}" =~ -$ ]]; then
    echo -e "\n❌ VM hostname '$qemu_kvm_hostname' is invalid.\n"
    exit 1
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
	    infra_mgmt_super_username=$(cat /kvm-hub/infra-mgmt-super-username)
            local_infra_domain_name=$(cat /kvm-hub/local_infra_domain_name)
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
            echo "❌ Invalid option ! "
            ;;
    esac
}

if ! sudo virsh list  | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo -e "✅ VM '$qemu_kvm_hostname' is not Running, Proceeding further. \n"
else
    fn_shutdown_or_poweroff
fi

while true; do
    read -p "Enter number of disks to add (max 10) : " DISK_COUNT
    if [[ "$DISK_COUNT" =~ ^[1-9][0-9]*$ ]] && (( DISK_COUNT <= 10 )); then
        break
    else
        echo "❌ Invalid input. Enter a number between 1 and 10."
    fi
done

while true; do
    echo -e "\n📌 Allowed disk size: Steps of 5 GiB — e.g., 5, 10, 15 ... up to 50 GiB\n"
    read -p "Enter disk size in GB (default 5) : " DISK_SIZE_GB
    DISK_SIZE_GB=${DISK_SIZE_GB:-5}
    if [[ "$DISK_SIZE_GB" =~ ^[0-9]+$ ]] && (( DISK_SIZE_GB % 5 == 0 && DISK_SIZE_GB <= 50 )); then
        break
    else
        echo "❌ Invalid size. Enter a multiple of 5 between 5 and 50."
    fi
done

VM_DIR="/kvm-hub/vms/${qemu_kvm_hostname}"

# Determine existing disks
EXISTING_FILES=($(ls "$VM_DIR"/*.qcow2 2>/dev/null))

NEXT_DISK_LETTER="b"

for ((i=1; i<=DISK_COUNT; i++)); do
    # Find the next available letter
    while true; do
        FOUND=0
        for f in "${EXISTING_FILES[@]}"; do
            BASENAME=$(basename "$f")
            if [[ "$BASENAME" == "${qemu_kvm_hostname}_vd${NEXT_DISK_LETTER}.qcow2" ]]; then
                FOUND=1
                break
            fi
        done
        if [[ $FOUND -eq 0 ]]; then
            break
        fi
        NEXT_DISK_LETTER=$(echo "$NEXT_DISK_LETTER" | tr "0-9a-z" "1-9a-z_")
    done

    DISK_NAME="${qemu_kvm_hostname}_vd${NEXT_DISK_LETTER}.qcow2"
    DISK_PATH="$VM_DIR/$DISK_NAME"

    # Create disk
    echo -ne "\n⚙️ Creating disk vd${NEXT_DISK_LETTER} (${DISK_SIZE_GB}GB) . . . "
    if ! qemu-img create -f qcow2 "$DISK_PATH" "${DISK_SIZE_GB}G" &>/dev/null; then
        echo -e "[ ❌ ]\n"
        exit 1
    fi
    echo -e "[ ✅ ]\n"

    # Attach disk
    echo -ne "\n⚙️ Attaching vd${NEXT_DISK_LETTER} (${DISK_SIZE_GB}GB) to VM '$qemu_kvm_hostname' . . . "
    if ! sudo virsh attach-disk "$qemu_kvm_hostname" "$DISK_PATH" "vd$NEXT_DISK_LETTER" --persistent &>/dev/null; then
        echo -e "[ ❌ ]\n"
        exit 1
    fi
    echo -e "[ ✅ ]\n"

    # Update EXISTING_FILES and increment letter
    EXISTING_FILES+=("$DISK_PATH")
    NEXT_DISK_LETTER=$(echo "$NEXT_DISK_LETTER" | tr "0-9a-z" "1-9a-z_")
done

echo -e "\n✅ Added $DISK_COUNT ${DISK_SIZE_GB}GB disk(s) to VM '$qemu_kvm_hostname', Proceeding to power on the VM."

sudo virsh start "${qemu_kvm_hostname}" 2>/dev/null
echo -e "✅ VM '$qemu_kvm_hostname' is started successfully after adding disk(s)."
