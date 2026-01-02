#!/bin/bash
#----------------------------------------------------------------------------------------#
# Script Name: qlabdnsbinder                                                             #
# Description: Manage DNS records for the KVM lab infrastructure                         #
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

if [[ -n "${KVM_TOOL_EXECUTED_FROM:-}" ]]; then
    print_error "Detected execution from the lab infra server."
    print_info "Please run the 'dnsbinder' utility directly with sudo to manage lab infra DNS."
    exit 1
fi

print_task "Enabling DNS of lab infra with resolvectl"

if grep -q "${lab_infra_server_ipv4_address}" <<< "$(resolvectl)"; then
    print_task_done
else
    if ip link show labbr0 &>/dev/null; then
       if error_msg=$(sudo resolvectl dns labbr0 "${lab_infra_server_ipv4_address}" "${lab_infra_server_ipv6_address}" 2>&1) && \
          error_msg=$(sudo resolvectl domain labbr0 "~${lab_infra_domain_name}" 2>&1); then
           print_task_done
       else
           print_task_fail
           print_error "$error_msg"
           exit 1
       fi
    else
       print_task_fail
       print_error "labbr0 interface is not yet available!"
       exit 1
    fi
fi

print_info "Invoking dnsbinder utility from lab infra server..."

if $lab_infra_server_mode_is_host; then
    sudo dnsbinder "$@"
    exit_code=$?
else
    ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${lab_infra_admin_username}@${lab_infra_server_hostname}" "sudo dnsbinder $(printf '%q ' "$@")"
    exit_code=$?
fi

exit $exit_code
