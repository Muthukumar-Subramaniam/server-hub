#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Initialize variables
vm_hostname_arg=""

# Function to show help
fn_show_help() {
    print_info "Usage: qlabvmctl console [OPTIONS] [hostname]

Options:
  -h, --help           Show this help message

Arguments:
  hostname             Name of the VM to access console (optional, will prompt if not given)

Examples:
  qlabvmctl console vm1                   # Access console of VM
  
Note: Press Ctrl+] to exit the console.
"
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            fn_show_help
            exit 0
            ;;
        -*)
            print_error "[ERROR] No such option: $1"
            fn_show_help
            exit 1
            ;;
        *)
            # This is the hostname argument
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

# Check if VM is running
if ! sudo virsh list | awk '{print $2}' | grep -Fxq "$qemu_kvm_hostname"; then
    print_error "[ERROR] VM \"$qemu_kvm_hostname\" is not running."
    exit 1
fi

# Proceed to access console
print_info "[INFO] Connecting to console of VM \"$qemu_kvm_hostname\"..."
print_notify "[NOTIFY] Press Ctrl+] to exit the console."
sudo virsh console "$qemu_kvm_hostname"