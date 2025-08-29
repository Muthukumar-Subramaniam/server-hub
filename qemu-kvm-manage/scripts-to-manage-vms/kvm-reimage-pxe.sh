#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

DIR_PATH_SCRIPTS_TO_MANAGE_VMS='/server-hub/qemu-kvm-manage/scripts-to-manage-vms'
INFRA_SERVER_VM_NAME=$(< /virtual-machines/local_infra_server_name)

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

ATTACH_CONSOLE="no"
qemu_kvm_hostname=""

# Fail fast if more than 2 args given
if [[ $# -gt 2 ]]; then
  echo "❌ Too many arguments."
  echo "ℹ️  Usage: $0 [hostname] [--console|-c]"
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --console|-c)
      if [[ "$ATTACH_CONSOLE" == "yes" ]]; then
        echo "❌ Duplicate --console/-c option."
        exit 1
      fi
      ATTACH_CONSOLE="yes"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [hostname] [--console|-c]"
      echo
      echo "Arguments:"
      echo "  hostname      Name of the VM to be installed (optional, will prompt if not given)"
      echo "  --console,-c  Attach console during install (optional, can appear before or after hostname)"
      exit 0
      ;;
    *)
      if [[ -z "$qemu_kvm_hostname" ]]; then
        qemu_kvm_hostname="$1"
      else
        echo "❌ Unexpected argument: $1"
        echo "ℹ️  Usage: $0 [hostname] [--console|-c]"
        exit 1
      fi
      shift
      ;;
  esac
done

# If hostname still not set, prompt
if [ -z "$qemu_kvm_hostname" ]; then
    echo
    read -p "🖥️  Please enter the hostname of the VM to be installed : " qemu_kvm_hostname
    if [[ -n "${KVM_TOOL_EXECUTED_FROM:-}" && "${KVM_TOOL_EXECUTED_FROM}" == "${qemu_kvm_hostname}" ]]; then
	echo -e "\n❌ This operation is not allowed to avoid self-referential KVM actions that could destabilize the infra server."
    	echo -e "⚠️ Note:"
	echo -e "  🔹 You are running a KVM management related action for the lab infra server from the infra server itself."
	echo -e "  🔹 If you still need to perform this operation, you need to do this from the Linux workstation running the QEMU/KVM setup.\n"
	exit 1
    fi
fi

if [[ "$qemu_kvm_hostname" == "$INFRA_SERVER_VM_NAME" ]]; then
    echo "❌❌❌  FATAL: WRONG VM, BUDDY! ❌❌❌"
    echo "You are trying to re-image the lab infra server VM $INFRA_SERVER_VM_NAME."
    echo "This VM runs the very services that make re-imaging possible."
    echo "All essential services for your lab environment runs on this VM."
    exit 1
fi

# Check if VM exists in 'virsh list --all'
if ! sudo virsh list --all | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    echo "❌ Error: VM \"$qemu_kvm_hostname\" does not exist."
    exit 1
fi

"$DIR_PATH_SCRIPTS_TO_MANAGE_VMS/kvm-remove.sh" "$qemu_kvm_hostname" && "$DIR_PATH_SCRIPTS_TO_MANAGE_VMS/kvm-install-pxe.sh" "$@"
