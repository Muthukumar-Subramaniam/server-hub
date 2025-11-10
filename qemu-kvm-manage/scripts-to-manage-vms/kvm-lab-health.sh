#!/bin/bash
# KVM Lab Infrastructure Health Check Tool

# Source environment defaults
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# Combine hostname and domain name for display
target_lab_infra_fqdn="${lab_infra_server_shortname}.${lab_infra_domain_name}"

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
echo "-------------------------------------------------------------"
echo "KVM Lab Infra Health Check"
echo "Lab Infra Server : ${target_lab_infra_fqdn} ( ${lab_infra_server_ipv4_address} )"
echo "-------------------------------------------------------------"

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
        printf "[ ✅ ] %-*s [ %s/%s ]\n" "$max_len" "$service_name" "$service_port" "$service_proto"
        ((active_services++))
    else
        printf "[ ❌ ] %-*s [ %s/%s ]\n" "$max_len" "$service_name" "$service_port" "$service_proto"
        ((inactive_services++))
    fi
done

# -------------------------------------------------------------
# Summary
# -------------------------------------------------------------
total_services=${#services_to_check[@]}
echo "-------------------------------------------------------------"
echo "Health Check Summary of KVM Lab Infra:"
echo "Total Services    : $total_services"
echo "Active Services   : $active_services"
echo "Inactive Services : $inactive_services"
echo "-------------------------------------------------------------"
if [[ $active_services -eq 0 ]]; then
    echo -e "❌ KVM Lab Infra health is CRITICAL."
elif [[ $total_services -eq $active_services ]]; then
    echo -e "✅ KVM Lab Infra health is STABLE."
else
    echo -e "⚠️  KVM Lab Infra health is DEGRADED."
fi
echo "-------------------------------------------------------------"
