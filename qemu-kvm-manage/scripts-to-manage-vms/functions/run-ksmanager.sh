run_ksmanager() {
    local hostname="$1"
    local ksmanager_options="$2"
    local log_file="/tmp/ksmanager-${hostname}-$$.log"

    if [[ -z "$hostname" ]]; then
        print_error "[ERROR] run_ksmanager requires hostname"
        return 1
    fi

    # Create log file
    >"$log_file"

    # Execute ksmanager
    if $lab_infra_server_mode_is_host; then
        if ! sudo ksmanager "${hostname}" ${ksmanager_options} | tee -a "$log_file"; then
            print_error "[FAILED] ksmanager execution failed for \"$hostname\"."
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

    # Extract values from log file
    MAC_ADDRESS=$(grep "MAC Address  :" "$log_file" | awk -F': ' '{print $2}' | tr -d '[:space:]')
    IPV4_ADDRESS=$(grep "IPv4 Address :" "$log_file" | awk -F': ' '{print $2}' | tr -d '[:space:]')
    OS_DISTRO=$(grep "Requested OS :" "$log_file" | awk -F': ' '{print $2}' | tr -d '[:space:]')

    # Clean up log file
    rm -f "$log_file"

    # Validate extracted values
    if [[ -z "${MAC_ADDRESS}" ]]; then
        print_error "[ERROR] Failed to extract MAC address from ksmanager output for \"$hostname\"."
        print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
        return 1
    fi

    if [[ -z "${IPV4_ADDRESS}" ]]; then
        print_error "[ERROR] Failed to extract IPv4 address from ksmanager output for \"$hostname\"."
        print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
        return 1
    fi

    # OS_DISTRO is optional - only validate if it was expected (golden-image mode)
    if [[ "$ksmanager_options" == *"--golden-image"* && -z "${OS_DISTRO}" ]]; then
        print_error "[ERROR] Failed to extract OS distro from ksmanager output for \"$hostname\"."
        print_info "[INFO] Please check the lab infrastructure server VM at ${lab_infra_server_ipv4_address} for details."
        return 1
    fi

    return 0
}
