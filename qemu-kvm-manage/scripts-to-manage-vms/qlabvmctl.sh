#!/usr/bin/env bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#
# Script Name : qlabvmctl
# Description : Unified command-line interface for managing KVM lab VMs
# Usage       : qlabvmctl <subcommand> [options] [args]

set -euo pipefail

# Source color functions
source /server-hub/common-utils/color-functions.sh

# Script directory - same directory as this script
SCRIPT_DIR="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"

# Version
VERSION="1.0.0"

# Display usage information
show_usage() {
    print_cyan "qlabvmctl - QEMU/KVM Lab VM Control Interface

USAGE:
    qlabvmctl <subcommand> [options] [arguments]

VM DEPLOYMENT:
    build-golden-image      Build a golden image for an OS
    install-golden          Deploy VM(s) from golden image
    install-pxe             Deploy VM(s) using PXE boot
    reimage-golden          Reinstall VM(s) from golden image
    reimage-pxe             Reinstall VM(s) using PXE boot

VM OPERATIONS:
    list                    List all VMs and their status
    console                 Connect to VM serial console
    start                   Start VM(s)
    stop                    Force stop (power off) VM(s)
    shutdown                Gracefully shutdown VM(s)
    restart                 Hard restart (reset) VM(s)
    reboot                  Gracefully reboot VM(s)
    remove                  Delete VM(s) and its data

VM CONFIGURATION:
    resize                  Resize VM resources (CPU, memory, disk)
    add-disk                Add additional disk to VM
    detach-disk             Detach and save disk(s) from VM

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show version information

NOTES:
    - Use 'qlabvmctl <subcommand> --help' to see help for a specific subcommand
    - Use 'qlabstart' to start the lab infrastructure
    - Use 'qlabhealth' to check lab infrastructure health
    - Use 'qlabdnsbinder' to manage DNS records for lab infrastructure"
}

# Show version
show_version() {
    print_cyan "qlabvmctl version $VERSION"
    print_cyan "QEMU/KVM Lab VM Management Tool"
}

# Main logic
main() {
    # No arguments or help flag
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    local subcommand="$1"
    shift
    
    # Handle version flag
    if [[ "$subcommand" == "version" ]] || [[ "$subcommand" == "-v" ]] || [[ "$subcommand" == "--version" ]]; then
        show_version
        exit 0
    fi
    
    # Map subcommand to script
    local script_name=""
    case "$subcommand" in
        start|stop|shutdown|restart|reboot|remove|list|console|resize)
            script_name="kvm-${subcommand}.sh"
            ;;
        install-pxe|install-golden|reimage-pxe|reimage-golden)
            script_name="kvm-${subcommand}.sh"
            ;;
        build-golden-image)
            script_name="kvm-build-golden-image.sh"
            ;;
        add-disk|detach-disk)
            script_name="kvm-${subcommand}.sh"
            ;;
        *)
            print_error "Unknown subcommand: $subcommand"
            echo
            echo "Run 'qlabvmctl --help' to see available subcommands"
            exit 1
            ;;
    esac
    
    # Check if script exists
    local script_path="$SCRIPT_DIR/$script_name"
    if [[ ! -f "$script_path" ]]; then
        print_error "Script not found: $script_name"
        exit 1
    fi
    
    # Execute the underlying script with all remaining arguments
    exec "$script_path" "$@"
}

main "$@"
