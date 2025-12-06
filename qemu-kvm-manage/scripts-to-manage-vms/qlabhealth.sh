#!/bin/bash
#----------------------------------------------------------------------------------------#
# Script Name: qlabhealth                                                                #
# Description: KVM Lab Infrastructure Health Check Tool                                  #
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

# Source color functions and environment defaults
source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Define port numbers
PORT_DNS=53
PORT_DHCP=67
PORT_NTP=123
PORT_TFTP=69
PORT_NFS=2049
PORT_WEB=80

# Define lab infra services (service_name:port:protocol)
services_to_check=(
  "DNS Server:$PORT_DNS:tcp"
  "DHCP Server:$PORT_DHCP:udp"
  "NTP Server:$PORT_NTP:udp"
  "TFTP Server:$PORT_TFTP:udp"
  "NFS Server:$PORT_NFS:tcp"
  "Web Server:$PORT_WEB:tcp"
)

# -------------------------------------------------------------
# Calculate the max length of service names for proper alignment
# -------------------------------------------------------------
max_len=0
for entry in "${services_to_check[@]}"; do
    IFS=':' read -r service_name service_port service_proto <<< "$entry"
    (( ${#service_name} > max_len )) && max_len=${#service_name}
done

# -------------------------------------------------------------
# Header
# -------------------------------------------------------------
print_info "-------------------------------------------------------------
KVM Lab Infra Health Check
Lab Infra Server : ${lab_infra_server_hostname} ( ${lab_infra_server_ipv4_address} )
-------------------------------------------------------------"

active_services=0
inactive_services=0

# -------------------------------------------------------------
# Service checks
# -------------------------------------------------------------
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
    fi
done

# -------------------------------------------------------------
# Summary
# -------------------------------------------------------------
total_services=${#services_to_check[@]}
print_info "-------------------------------------------------------------
Health Check Summary of KVM Lab Infra:
Total Services    : $total_services
Active Services   : $active_services
Inactive Services : $inactive_services
-------------------------------------------------------------"
if [[ $active_services -eq 0 ]]; then
    print_error "[FAILED] KVM Lab Infra health is CRITICAL."
elif [[ $total_services -eq $active_services ]]; then
    print_success "[SUCCESS] KVM Lab Infra health is STABLE."
else
    print_warning "KVM Lab Infra health is DEGRADED."
fi
print_info "-------------------------------------------------------------"
