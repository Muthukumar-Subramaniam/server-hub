#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

temp_dir_to_create_wrappers="/tmp/qlabtools-wrappers"
SSH_OPTS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

print_task "Authorizing SSH public key of infra server VM"
get_user_host_ssh_pub_key=$(ssh ${SSH_OPTS} ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "cat .ssh/kvm_lab_global_id_rsa.pub" | cut -d " " -f3)
if ! grep -q "${get_user_host_ssh_pub_key}" ~/.ssh/authorized_keys; then
	ssh ${SSH_OPTS} ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "cat .ssh/kvm_lab_global_id_rsa.pub" >> ~/.ssh/authorized_keys
fi
print_task_done

print_task "Generating wrapper scripts"
mkdir -p "${temp_dir_to_create_wrappers}"

# Create qlabvmctl wrapper
cat > "${temp_dir_to_create_wrappers}/qlabvmctl" << 'EOF'
#!/bin/bash
source /server-hub/common-utils/color-functions.sh

# Who am I?
SSH_OPTIONS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
INFRA_SERVER_NAME="$(hostname -f)"

# Check if any argument matches the infra server name
for EACH_ARG in "$@"; do
    if [[ "${EACH_ARG}" == "${INFRA_SERVER_NAME}" ]]; then
        print_error "This operation is not allowed to avoid self-referential KVM actions."
        print_info "You are running a KVM management action for the lab infra server from the infra server itself."
        print_info "To perform this operation, run it from the Linux workstation hosting the QEMU/KVM setup."
        exit 1
    fi
done

# Forward qlabvmctl command to workstation
ssh ${SSH_OPTIONS} -t __LAB_INFRA_USERNAME__@__LAB_INFRA_GATEWAY__ "export KVM_TOOL_EXECUTED_FROM='${INFRA_SERVER_NAME}'; qlabvmctl $@"
exit
EOF

# Create qlabhealth wrapper
cat > "${temp_dir_to_create_wrappers}/qlabhealth" << 'EOF'
#!/bin/bash
SSH_OPTIONS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# Forward qlabhealth command to workstation
ssh ${SSH_OPTIONS} -t __LAB_INFRA_USERNAME__@__LAB_INFRA_GATEWAY__ "qlabhealth $@"
exit
EOF

# Create qlabdnsbinder wrapper
cat > "${temp_dir_to_create_wrappers}/qlabdnsbinder" << 'EOF'
#!/bin/bash
SSH_OPTIONS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# Forward qlabdnsbinder command to workstation
ssh ${SSH_OPTIONS} -t __LAB_INFRA_USERNAME__@__LAB_INFRA_GATEWAY__ "qlabdnsbinder $@"
exit
EOF

# Replace placeholders with actual values
sed -i "s|__LAB_INFRA_USERNAME__|${lab_infra_admin_username}|g" "${temp_dir_to_create_wrappers}/"*
sed -i "s|__LAB_INFRA_GATEWAY__|${lab_infra_server_ipv4_gateway}|g" "${temp_dir_to_create_wrappers}/"*

print_task_done

print_task "Syncing wrapper scripts to infra server VM"
rsync -az -e "ssh $SSH_OPTS" "${temp_dir_to_create_wrappers}/"* ${lab_infra_admin_username}@${lab_infra_server_ipv4_address}:
ssh ${SSH_OPTS} ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "chmod +x qlabvmctl qlabhealth qlabdnsbinder && sudo mv qlabvmctl qlabhealth qlabdnsbinder /usr/bin/"
rm -rf "$temp_dir_to_create_wrappers"
print_task_done

print_success "Now you can manage QEMU/KVM environment from your infra server VM!"
print_info "Available commands:"
print_info "  - qlabvmctl <subcommand> [options]  # VM management"
print_info "  - qlabhealth [options]              # Check lab health"
print_info "  - qlabdnsbinder [options]           # Manage DNS records"
