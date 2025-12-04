update_etc_hosts() {
    local hostname="$1"
    local ipv4_address="$2"
    local hosts_file="/etc/hosts"
    local error_msg=""

    if [[ -z "$hostname" || -z "$ipv4_address" ]]; then
        print_error "[ERROR] update_etc_hosts requires hostname and IPv4 address"
        return 1
    fi

    print_info "[INFO] Updating ${hosts_file} file for ${hostname}..." nskip

    if grep -q "${hostname}" "$hosts_file"; then
        local host_file_ipv4
        host_file_ipv4=$(grep "${hostname}" "$hosts_file" | awk '{print $1}')
        if [[ "${host_file_ipv4}" != "${ipv4_address}" ]]; then
            if error_msg=$(sudo sed -i.bak "/${hostname}/s/.*/${ipv4_address} ${hostname}/" "$hosts_file" 2>&1); then
                print_success "[ SUCCESS ]"
                return 0
            else
                print_error "[ FAILED ]"
                print_error "$error_msg"
                return 1
            fi
        else
            print_success "[ SUCCESS ]"
            return 0
        fi
    else
        if error_msg=$(echo "${ipv4_address} ${hostname}" | sudo tee -a "$hosts_file" >/dev/null 2>&1); then
            print_success "[ SUCCESS ]"
            return 0
        else
            print_error "[ FAILED ]"
            print_error "$error_msg"
            return 1
        fi
    fi
}
