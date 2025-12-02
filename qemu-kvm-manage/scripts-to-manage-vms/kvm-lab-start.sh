#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# ====== GLOBAL CONFIGURATION ======
lab_bridge_interface_name="labbr0"

# ====== DNS CONFIGURATION FUNCTION ======
configure_dns_for_bridge() {
    print_info "[INFO] Configuring DNS for $lab_bridge_interface_name..."
    sudo resolvectl dns "$lab_bridge_interface_name" "$lab_infra_server_ipv4_address" || print_warning "[WARNING] Could not set DNS server"
    sudo resolvectl domain "$lab_bridge_interface_name" "$lab_infra_domain_name" || print_warning "[WARNING] Could not set DNS domain"
    print_success "[SUCCESS] DNS configured"
}

when_lab_infra_server_is_host() {
    # ====== CONFIGURATION ======
    local lab_bridge_dummy_interface_name="dummy-vnet"
    local lab_essential_services=("kea-dhcp4" "nfs-server" "nginx" "tftp.socket")
    
    # ====== CLEANUP ON EXIT ======
    trap 'print_error "[ERROR] Script interrupted!"' SIGINT

    # ====== STEP 1: Check and start libvirtd if needed ======
    if sudo systemctl is-active --quiet libvirtd; then
        print_success "[SUCCESS] libvirtd is already running"
    else
        print_info "[INFO] Starting libvirtd..."
        if ! sudo systemctl restart libvirtd; then
            print_error "[ERROR] Failed to start libvirtd"
            return 1
        fi
        print_success "[SUCCESS] libvirtd started successfully"
    fi
    
    # ====== STEP 2: Wait for labbr0 ======
    print_info "[INFO] Waiting for $lab_bridge_interface_name to be created..." nskip
    local bridge_creation_timeout_seconds=30
    local bridge_creation_elapsed_seconds=0
    until ip link show "$lab_bridge_interface_name" &>/dev/null; do
        if [ $bridge_creation_elapsed_seconds -ge $bridge_creation_timeout_seconds ]; then
            print_error "[ERROR] Timeout waiting for $lab_bridge_interface_name"
            return 1
        fi
        printf "."
        sleep 1
        bridge_creation_elapsed_seconds=$((bridge_creation_elapsed_seconds + 1))
    done
    echo
    print_success "[SUCCESS] $lab_bridge_interface_name detected!"
    
    # ====== STEP 3: Create dummy link if missing ======
    if ! ip link show "$lab_bridge_dummy_interface_name" &>/dev/null; then
        print_info "[INFO] Creating dummy interface $lab_bridge_dummy_interface_name to keep $lab_bridge_interface_name always up..."
        sudo ip link add name "$lab_bridge_dummy_interface_name" type dummy || { print_error "[ERROR] Failed to create dummy interface"; return 1; }
        sudo ip link set "$lab_bridge_dummy_interface_name" master "$lab_bridge_interface_name" || { print_error "[ERROR] Failed to attach dummy to bridge"; return 1; }
        sudo ip link set "$lab_bridge_dummy_interface_name" up || { print_error "[ERROR] Failed to bring up dummy interface"; return 1; }
        print_success "[SUCCESS] Dummy interface created and attached"
    else
        print_info "[INFO] Dummy interface $lab_bridge_dummy_interface_name already exists."
    fi
    
    # ====== STEP 4: Wait for labbr0 to come up ======
    print_info "[INFO] Waiting for $lab_bridge_interface_name to come UP..." nskip
    local bridge_up_timeout_seconds=30
    local bridge_up_elapsed_seconds=0
    while [[ "$(cat /sys/class/net/$lab_bridge_interface_name/operstate 2>/dev/null)" != "up" ]]; do
        if [ $bridge_up_elapsed_seconds -ge $bridge_up_timeout_seconds ]; then
            print_error "[ERROR] Timeout waiting for $lab_bridge_interface_name to come up"
            return 1
        fi
        printf "."
        sleep 1
        bridge_up_elapsed_seconds=$((bridge_up_elapsed_seconds + 1))
    done
    echo
    print_success "[SUCCESS] $lab_bridge_interface_name is UP and running!"
    
    # ====== STEP 5: Assign IP address ======
    print_info "[INFO] Configuring IP ${lab_infra_server_ipv4_address} netmask ${lab_infra_server_ipv4_netmask} on $lab_bridge_interface_name..."
    # Add the secondary IP address with netmask
    if sudo ip addr add "${lab_infra_server_ipv4_address}/${lab_infra_server_ipv4_netmask}" dev "$lab_bridge_interface_name" 2>/dev/null; then
        print_success "[SUCCESS] IP address assigned successfully"
    else
        print_info "[INFO] IP address may already be assigned"
    fi

    # ====== STEP 6: Restart named service ======
    print_info "[INFO] Restarting named service..."
    if ! sudo systemctl restart named; then
        print_error "[ERROR] Failed to restart named service"
        return 1
    fi
    print_success "[SUCCESS] Named service restarted"
    
    # ====== STEP 7: Restart dependent services ======
    print_info "[INFO] Restarting dependent lab services..."
    local failed_services_list=()
    for service_name in "${lab_essential_services[@]}"; do
        if sudo systemctl restart "$service_name" 2>/dev/null; then
            print_success "  [SUCCESS] $service_name restarted"
        else
            print_error "  [ERROR] $service_name failed to restart"
            failed_services_list+=("$service_name")
        fi
    done
    
    if [ ${#failed_services_list[@]} -eq 0 ]; then
        print_success "[SUCCESS] All lab services restarted successfully"
    else
        print_warning "[WARNING] Some services failed: ${failed_services_list[*]}"
    fi
    
    # ====== STEP 8: Verify critical services ======
    print_info "[INFO] Verifying critical services..."
    local all_services_active=true
    for service_name in libvirtd named "${lab_essential_services[@]}"; do
        if sudo systemctl is-active --quiet "$service_name"; then
            print_success "  [SUCCESS] $service_name is active"
        else
            print_error "  [ERROR] $service_name is not active"
            all_services_active=false
        fi
    done

    # ====== STEP 9: Configure DNS for labbr0 ======
    configure_dns_for_bridge || return 1

    if $all_services_active; then
        print_success "[SUCCESS] kvm lab infra is started, and all essential services are live."
    else
        print_warning "[WARNING] kvm lab infra is started, but some services need attention."
        print_info "[INFO] Run 'sudo systemctl status <service>' for details."
    fi
}

when_lab_infra_server_is_vm() {
    # ====== CLEANUP ON EXIT ======
    trap 'print_error "[ERROR] Script interrupted!"' SIGINT

    # ====== STEP 1: Check and start libvirtd if needed ======
    if sudo systemctl is-active --quiet libvirtd; then
        print_success "[SUCCESS] libvirtd is already running"
    else
        print_info "[INFO] Starting libvirtd..."
        if ! sudo systemctl restart libvirtd; then
            print_error "[ERROR] Failed to start libvirtd"
            return 1
        fi
        print_success "[SUCCESS] libvirtd started successfully"
    fi
    # ====== STEP 2: Wait for labbr0 ======
    print_info "[INFO] Waiting for $lab_bridge_interface_name to be created..." nskip
    local bridge_creation_timeout_seconds=30
    local bridge_creation_elapsed_seconds=0
    until ip link show "$lab_bridge_interface_name" &>/dev/null; do
        if [ $bridge_creation_elapsed_seconds -ge $bridge_creation_timeout_seconds ]; then
            print_error "[ERROR] Timeout waiting for $lab_bridge_interface_name"
            return 1
        fi
        printf "."
        sleep 1
        bridge_creation_elapsed_seconds=$((bridge_creation_elapsed_seconds + 1))
    done
    echo
    print_success "[SUCCESS] $lab_bridge_interface_name detected!"
    # ====== STEP 3: Check and start lab infra server VM ======
    print_info "[INFO] Checking lab infra server VM status..."
    if sudo virsh list --state-running | awk '{print $2}' | grep -Fxq "$lab_infra_server_hostname"; then
        print_success "[SUCCESS] Lab infra server VM ($lab_infra_server_hostname) is already running"
    else
        print_info "[INFO] Lab infra server VM ($lab_infra_server_hostname) is not running. Starting..."
        if sudo virsh start "$lab_infra_server_hostname" >/dev/null 2>&1; then
            print_success "[SUCCESS] Lab infra server VM started successfully"
        else
            print_error "[ERROR] Failed to start lab infra server VM"
            return 1
        fi
    fi

    # ====== STEP 4: Wait for lab infra server VM to be SSH accessible ======
    print_info "[INFO] Waiting for lab infra server VM to become SSH accessible..." nskip
    local ssh_check_timeout=120
    local ssh_check_elapsed=0
    local ssh_check_interval=5
    local vm_is_ssh_accessible=false
    
    local ssh_connection_options="-o StrictHostKeyChecking=no \
                                   -o UserKnownHostsFile=/dev/null \
                                   -o LogLevel=QUIET \
                                   -o ConnectTimeout=5 \
                                   -o ConnectionAttempts=1 \
                                   -o ServerAliveInterval=5 \
                                   -o PreferredAuthentications=publickey \
                                   -o ServerAliveCountMax=1"
    
    while [[ $ssh_check_elapsed -lt $ssh_check_timeout ]]; do
        if ssh $ssh_connection_options "${lab_infra_admin_username}@${lab_infra_server_hostname}" \
           'systemctl is-system-running' >/dev/null 2>&1 </dev/null; then
            vm_is_ssh_accessible=true
            break
        fi
        sleep "$ssh_check_interval"
        ssh_check_elapsed=$((ssh_check_elapsed + ssh_check_interval))
        echo -n "."
    done
    [ $ssh_check_elapsed -gt 0 ] && echo
    
    if [[ "$vm_is_ssh_accessible" != "true" ]]; then
        print_error "[ERROR] Lab infra server VM did not become SSH accessible within ${ssh_check_timeout} seconds"
        return 1
    fi
    print_success "[SUCCESS] Lab infra server VM is SSH accessible"
    # ====== STEP 5: Check essential services connectivity ======
    print_info "[INFO] Checking essential services connectivity..."
    
    # Define port numbers
    local port_dns=53
    local port_dhcp=67
    local port_ntp=123
    local port_tftp=69
    local port_nfs=2049
    local port_web=80
    
    # Define lab infra services (service_name:port:protocol)
    local services_to_check=(
        "DNS Server:$port_dns:tcp"
        "DHCP Server:$port_dhcp:udp"
        "NTP Server:$port_ntp:udp"
        "TFTP Server:$port_tftp:udp"
        "NFS Server:$port_nfs:tcp"
        "Web Server:$port_web:tcp"
    )
    
    # Calculate max length for alignment
    local max_len=0
    for entry in "${services_to_check[@]}"; do
        IFS=':' read -r service_name service_port service_proto <<< "$entry"
        (( ${#service_name} > max_len )) && max_len=${#service_name}
    done
    
    local active_services=0
    local inactive_services=0
    local all_services_active=true
    
    for entry in "${services_to_check[@]}"; do
        IFS=':' read -r service_name service_port service_proto <<< "$entry"
        
        if [[ "$service_proto" == "udp" ]]; then
            nc -z -u -w 3 "$lab_infra_server_ipv4_address" "$service_port" &>/dev/null
        else
            nc -z -w 3 "$lab_infra_server_ipv4_address" "$service_port" &>/dev/null
        fi
        
        if [[ $? -eq 0 ]]; then
            printf "\033[0;36m[ \033[0;32m✓\033[0;36m ] %-*s [ %s/%s ]\033[0m\n" "$max_len" "$service_name" "$service_port" "$service_proto"
            ((active_services++))
        else
            printf "\033[0;36m[ \033[0;31m✗\033[0;36m ] %-*s [ %s/%s ]\033[0m\n" "$max_len" "$service_name" "$service_port" "$service_proto"
            ((inactive_services++))
            all_services_active=false
        fi
    done

    # ====== STEP 6: Configure DNS for labbr0 ======
    configure_dns_for_bridge || return 1

    if $all_services_active; then
        print_success "[SUCCESS] kvm lab infra is started, and all essential services are live."
    else
        print_warning "[WARNING] kvm lab infra is started, but some services need attention."
        print_info "[INFO] Total: ${#services_to_check[@]}, Active: $active_services, Inactive: $inactive_services"
    fi
}
    
# ====== MAIN LOGIC ======

print_info "=============================================================="
print_info "KVM Lab Infrastructure Startup"
print_info "=============================================================="

if $lab_infra_server_mode_is_host; then
    print_notify "[NOTIFY] Lab Infra Server Mode: HOST"
    print_info "--------------------------------------------------------------"
    when_lab_infra_server_is_host
else
    print_notify "[NOTIFY] Lab Infra Server Mode: VM"
    print_info "--------------------------------------------------------------"
    when_lab_infra_server_is_vm
fi

exit_code=$?
print_info "=============================================================="
exit $exit_code
