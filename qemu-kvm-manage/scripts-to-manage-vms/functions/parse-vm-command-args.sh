#!/bin/bash
#
# parse-vm-command-args.sh
# 
# Reusable argument parsing function for VM management commands
# Handles common flags: -c/--console, -H/--hosts, -h/--help, -C/--clean-install
#
# Usage:
#   source /path/to/parse-vm-command-args.sh
#   parse_vm_command_args "$@"
#
# This function sets the following global variables:
#   ATTACH_CONSOLE  - "yes" or "no"
#   CLEAN_INSTALL   - "yes" or "no" (if supported)
#   HOSTNAMES       - Array of validated hostnames
#   TOTAL_VMS       - Number of VMs to process
#
# The function expects a help function named 'fn_show_help' to be defined before calling

parse_vm_command_args() {
    local supports_clean_install="${SUPPORTS_CLEAN_INSTALL:-no}"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                fn_show_help
                exit 0
                ;;
            -c|--console)
                if [[ "$ATTACH_CONSOLE" == "yes" ]]; then
                    print_error "[ERROR] Duplicate --console/-c option."
                    fn_show_help
                    exit 1
                fi
                ATTACH_CONSOLE="yes"
                shift
                ;;
            -C|--clean-install)
                if [[ "$supports_clean_install" != "yes" ]]; then
                    print_error "[ERROR] No such option: $1"
                    fn_show_help
                    exit 1
                fi
                if [[ "$CLEAN_INSTALL" == "yes" ]]; then
                    print_error "[ERROR] Duplicate --clean-install option."
                    fn_show_help
                    exit 1
                fi
                CLEAN_INSTALL="yes"
                shift
                ;;
            -H|--hosts)
                if [[ -z "$2" || "$2" == -* ]]; then
                    print_error "[ERROR] --hosts/-H requires a comma-separated list of hostnames."
                    fn_show_help
                    exit 1
                fi
                IFS=',' read -ra HOSTNAMES <<< "$2"
                shift 2
                ;;
            -*)
                print_error "[ERROR] No such option: $1"
                fn_show_help
                exit 1
                ;;
            *)
                if [[ ${#HOSTNAMES[@]} -eq 0 ]]; then
                    HOSTNAMES+=("$1")
                else
                    print_error "[ERROR] Cannot mix positional hostname with --hosts/-H option."
                    fn_show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate console + multiple VMs conflict
    if [[ "$ATTACH_CONSOLE" == "yes" && ${#HOSTNAMES[@]} -gt 1 ]]; then
        print_error "[ERROR] --console/-c option cannot be used with multiple VMs."
        fn_show_help
        exit 1
    fi

    # Remove duplicates from HOSTNAMES
    if [[ ${#HOSTNAMES[@]} -gt 1 ]]; then
        UNIQUE_HOSTNAMES=($(printf '%s\n' "${HOSTNAMES[@]}" | sort -u))
        if [[ ${#UNIQUE_HOSTNAMES[@]} -ne ${#HOSTNAMES[@]} ]]; then
            print_warning "[WARNING] Removed duplicate hostnames from the list."
            HOSTNAMES=("${UNIQUE_HOSTNAMES[@]}")
        fi
    fi

    # If no hostnames provided, prompt for one
    if [[ ${#HOSTNAMES[@]} -eq 0 ]]; then
        source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh ""
        HOSTNAMES=("$qemu_kvm_hostname")
    fi

    # Validate all hostnames using input-hostname.sh
    if [[ ${#HOSTNAMES[@]} -gt 0 ]]; then
        validated_hosts=()
        for vm_name in "${HOSTNAMES[@]}"; do
            vm_name=$(echo "$vm_name" | xargs) # Trim whitespace
            [[ -z "$vm_name" ]] && continue  # Skip empty entries
            # Use input-hostname.sh to validate and normalize
            source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/input-hostname.sh "$vm_name"
            validated_hosts+=("$qemu_kvm_hostname")
        done
        HOSTNAMES=("${validated_hosts[@]}")
    fi

    # Check if any valid hosts remain after validation
    if [[ ${#HOSTNAMES[@]} -eq 0 ]]; then
        print_error "[ERROR] No valid hostnames provided."
        exit 1
    fi

    # Set TOTAL_VMS for convenience
    TOTAL_VMS=${#HOSTNAMES[@]}
}
