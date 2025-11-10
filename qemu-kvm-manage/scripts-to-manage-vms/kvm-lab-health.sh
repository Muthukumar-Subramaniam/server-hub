#!/usr/bin/env bash
#
# Purpose : Health check script for KVM lab infrastructure with colored output and summary
# Author  : Cooper & TARS
# File    : kvm-lab-health.sh
#

set -euo pipefail

# -----------------------------------------------------------------------------
# Source environment defaults
# -----------------------------------------------------------------------------
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

# -----------------------------------------------------------------------------
# Lab Infra Server Details (from existing vars in defaults.sh)
# -----------------------------------------------------------------------------
LAB_INFRA_SERVER_IP="${lab_infra_server_ipv4_address:?Variable lab_infra_server_ipv4_address is not set in defaults.sh}"
LAB_INFRA_SERVER_FQDN="${lab_infra_server_shortname}.${lab_infra_domain_name}"

# -----------------------------------------------------------------------------
# Ports for critical lab infrastructure services
# -----------------------------------------------------------------------------
DNS_SERVER_PORT=53
DHCP_SERVER_PORT=67
NTP_SERVER_PORT=123
TFTP_SERVER_PORT=69
NFS_SERVER_PORT=2049
WEB_SERVER_PORT=80

# -----------------------------------------------------------------------------
# ASCII Colors
# -----------------------------------------------------------------------------
COLOR_GREEN="\033[0;32m"
COLOR_RED="\033[0;31m"
COLOR_RESET="\033[0m"

# -----------------------------------------------------------------------------
# Function: Check service port and print colored status
# Arguments:
#   $1 -> Service Name
#   $2 -> Port Number
# Returns:
#   Sets a global variable SERVICE_STATUS to "active" or "inactive"
# -----------------------------------------------------------------------------
check_service_port_status() {
    local service_name="$1"
    local service_port="$2"

    if nc -z -w 3 "$LAB_INFRA_SERVER_IP" "$service_port" &>/dev/null; then
        SERVICE_STATUS="active"
        echo -e "[${COLOR_GREEN}OK${COLOR_RESET}]   $service_name ($LAB_INFRA_SERVER_IP:$service_port) is $SERVICE_STATUS"
    else
        SERVICE_STATUS="inactive"
        echo -e "[${COLOR_RED}FAIL${COLOR_RESET}] $service_name ($LAB_INFRA_SERVER_IP:$service_port) is $SERVICE_STATUS"
    fi
}

# -----------------------------------------------------------------------------
# Main Health Check
# -----------------------------------------------------------------------------
echo "-------------------------------------------------------------"
echo "Starting KVM Lab Infrastructure Health Check"
echo "Target Lab Infra Server : ${LAB_INFRA_SERVER_FQDN} (${LAB_INFRA_SERVER_IP})"
echo "-------------------------------------------------------------"

# Ordered by base service dependency
LAB_INFRA_SERVICES_TO_CHECK=(
    "DNS Server:$DNS_SERVER_PORT"
    "DHCP Server:$DHCP_SERVER_PORT"
    "NTP Server:$NTP_SERVER_PORT"
    "TFTP Server:$TFTP_SERVER_PORT"
    "NFS Server:$NFS_SERVER_PORT"
    "Web Server:$WEB_SERVER_PORT"
)

# Summary counters
TOTAL_SERVICES=0
ACTIVE_SERVICES=0
INACTIVE_SERVICES=0

# Loop over services and check each one
for service_entry in "${LAB_INFRA_SERVICES_TO_CHECK[@]}"; do
    SERVICE_NAME="${service_entry%%:*}"
    SERVICE_PORT="${service_entry##*:}"

    ((TOTAL_SERVICES++))
    check_service_port_status "$SERVICE_NAME" "$SERVICE_PORT"

    if [[ "$SERVICE_STATUS" == "active" ]]; then
        ((ACTIVE_SERVICES++))
    else
        ((INACTIVE_SERVICES++))
    fi
done

# -----------------------------------------------------------------------------
# Print summary
# -----------------------------------------------------------------------------
echo "-------------------------------------------------------------"
echo "Health Check Summary of KVM Lab Infrastructure:"
echo -e "Total Services Checked : $TOTAL_SERVICES"
echo -e "Active Services        : ${COLOR_GREEN}$ACTIVE_SERVICES${COLOR_RESET}"
echo -e "Inactive Services      : ${COLOR_RED}$INACTIVE_SERVICES${COLOR_RESET}"
echo "-------------------------------------------------------------"
