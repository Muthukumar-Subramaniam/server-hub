#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

scripts_location_to_manage_vms="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"
temp_dir_to_create_wrapper_scripts="/tmp/scripts-to-manage-vms"
SSH_OPTS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

print_info "[INFO] Authorizing SSH public key of infra server VM..." nskip
get_user_host_ssh_pub_key=$(ssh ${SSH_OPTS} ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "cat .ssh/kvm_lab_global_id_rsa.pub" | cut -d " " -f3)
if ! grep -q "${get_user_host_ssh_pub_key}" ~/.ssh/authorized_keys; then
	ssh ${SSH_OPTS} ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "cat .ssh/kvm_lab_global_id_rsa.pub" >> ~/.ssh/authorized_keys
fi
print_success "[ SUCCESS ]"

print_info "[INFO] Generating wrapper scripts to manage KVM VMs..." nskip
mkdir -p "${temp_dir_to_create_wrapper_scripts}"


for FILENAME in $(find ${scripts_location_to_manage_vms}/*.sh -exec basename {} \; | sed "s/.sh//g"); do
cat > "${temp_dir_to_create_wrapper_scripts}/${FILENAME}" << 'EOF'
#!/bin/bash
source /server-hub/common-utils/color-functions.sh
# Who am I?
SSH_OPTIONS="${SSH_OPTS}"
INFRA_SERVER_NAME="\$(hostname -f)"
for EACH_ARG in "\$@"; do
    if [[ "\${EACH_ARG}" == "\${INFRA_SERVER_NAME}" ]]; then
	print_error "[ERROR] This operation is not allowed to avoid self-referential KVM actions."
	print_info "[INFO] You are running a KVM management action for the lab infra server from the infra server itself."
	print_info "[INFO] To perform this operation, run it from the Linux workstation hosting the QEMU/KVM setup."
	exit 1
    fi
done
ssh \${SSH_OPTIONS} -t ${lab_infra_admin_username}@${lab_infra_server_ipv4_gateway} "export KVM_TOOL_EXECUTED_FROM='\${INFRA_SERVER_NAME}';${FILENAME} \$@"
exit
EOF
done

print_success "[ SUCCESS ]"

print_info "[INFO] Syncing wrapper scripts to infra server VM..." nskip
rsync -az -e "ssh $SSH_OPTS" "$temp_dir_to_create_wrapper_scripts" ${lab_infra_admin_username}@${lab_infra_server_ipv4_address}:
ssh ${SSH_OPTS} ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "chmod +x -R scripts-to-manage-vms;sudo rsync -az scripts-to-manage-vms/* /bin/ && rm -rf scripts-to-manage-vms"
rm -rf "$temp_dir_to_create_wrapper_scripts"
print_success "[ SUCCESS ]"

print_success "[SUCCESS] Now you can manage QEMU/KVM environment from your infra server VM!"
print_info "[INFO] CLI Tools to manage KVM VMs:"
find ${scripts_location_to_manage_vms}/*.sh -exec basename {} \; | sed "s/.sh//g"
