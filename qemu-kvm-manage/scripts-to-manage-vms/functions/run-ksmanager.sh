run_ksmanager() {
    local hostname="$1"
    local ksmanager_options="$2"
    local log_file

    # For --create-golden-image mode, hostname is not provided upfront
    if [[ "$ksmanager_options" == *"--create-golden-image"* ]]; then
        log_file="/tmp/ksmanager-golden-image-$$.log"
    else
        if [[ -z "$hostname" ]]; then
            print_error "[ERROR] run_ksmanager requires hostname"
            return 1
        fi
        log_file="/tmp/ksmanager-${hostname}-$$.log"
    fi

    # Create log file
    >"$log_file"

    # Execute ksmanager
    if $lab_infra_server_mode_is_host; then
        if [[ -z "$hostname" ]]; then
            # For golden image creation without hostname
            if ! sudo ksmanager ${ksmanager_options} | tee -a "$log_file"; then
                print_error "[FAILED] ksmanager execution failed."
                rm -f "$log_file"
                return 1
            fi
        else
            if ! sudo ksmanager "${hostname}" ${ksmanager_options} | tee -a "$log_file"; then
                print_error "[FAILED] ksmanager execution failed for \"$hostname\"."
                rm -f "$log_file"
                return 1
            fi
        fi
    else
        if [[ -z "$hostname" ]]; then
            # For golden image creation without hostname
            if ! ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${lab_infra_admin_username}@${lab_infra_server_ipv4_address}" "sudo ksmanager ${ksmanager_options}" | tee -a "$log_file"; then
                print_error "[FAILED] ksmanager execution failed."
                rm -f "$log_file"
                return 1
            fi
        else
            if ! ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${lab_infra_admin_username}@${lab_infra_server_ipv4_address}" "sudo ksmanager ${hostname} ${ksmanager_options}" | tee -a "$log_file"; then
                print_error "[FAILED] ksmanager execution failed for \"$hostname\"."
                rm -f "$log_file"
                return 1
            fi
        fi
    fi

    # Extract values from log file
    MAC_ADDRESS=$(grep "MAC Address  :" "$log_file" | awk -F': ' '{print $2}' | tr -d '[:space:]')
    IPV4_ADDRESS=$(grep "IPv4 Address :" "$log_file" | awk -F': ' '{print $2}' | tr -d '[:space:]')
    OS_DISTRO=$(grep "Requested OS :" "$log_file" | awk -F': ' '{print $2}' | tr -d '[:space:]')
    EXTRACTED_HOSTNAME=$(grep "Hostname     :" "$log_file" | awk -F': ' '{print $2}' | tr -d '[:space:]')

    # Clean up log file
    rm -f "$log_file"

    # Validate extracted values
    if [[ -z "${MAC_ADDRESS}" ]]; then
        print_error "[ERROR] Failed to extract MAC address from ksmanager output."
        print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
        return 1
    fi

    # For golden image creation, we need hostname instead of IP
    if [[ "$ksmanager_options" == *"--create-golden-image"* ]]; then
        if [[ -z "${EXTRACTED_HOSTNAME}" ]]; then
            print_error "[ERROR] Failed to extract hostname from ksmanager output."
            print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
            return 1
        fi
    else
        # For regular VM operations, we need IP address
        if [[ -z "${IPV4_ADDRESS}" ]]; then
            print_error "[ERROR] Failed to extract IPv4 address from ksmanager output."
            print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
            return 1
        fi
    fi

    # OS_DISTRO is optional - only validate if it was expected (golden-image mode)
    if [[ "$ksmanager_options" == *"--golden-image"* && -z "${OS_DISTRO}" ]]; then
        print_error "[ERROR] Failed to extract OS distro from ksmanager output."
        print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
        return 1
    fi

    return 0
}
