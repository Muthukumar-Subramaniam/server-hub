#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/qemu-kvm-manage/scripts-to-manage-vms/functions/defaults.sh

scripts_location_to_manage_vms="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"
temp_dir_to_create_wrapper_scripts="/tmp/scripts-to-manage-vms"
SSH_OPTS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo -n "[STEP] Authorize SSH public key of infra server VM . . . "
get_user_host_ssh_pub_key=$(ssh ${SSH_OPTS} ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "cat .ssh/id_rsa.pub" | cut -d " " -f3)
if ! grep -q "${get_user_host_ssh_pub_key}" ~/.ssh/authorized_keys; then
	ssh ${SSH_OPTS} ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "cat .ssh/id_rsa.pub" >> ~/.ssh/authorized_keys
fi
echo "[ok]"

echo -n "[STEP] Generating wrapper scripts to manage KVM VMs . . . "
mkdir -p "${temp_dir_to_create_wrapper_scripts}"


for FILENAME in $(find ${scripts_location_to_manage_vms}/*.sh -exec basename {} \; | sed "s/.sh//g"); do
cat > "${temp_dir_to_create_wrapper_scripts}/${FILENAME}" << EOF
#!/bin/bash
# Who am I?
SSH_OPTIONS="${SSH_OPTS}"
INFRA_SERVER_NAME="\$(hostname -f)"
for EACH_ARG in "\$@"; do
    if [[ "\${EACH_ARG}" == "\${INFRA_SERVER_NAME}" ]]; then
	echo -e "\n❌ This operation is not allowed to avoid self-referential KVM actions that could destabilize the infra server."
    	echo -e "⚠️ Note:"
	echo -e "  🔹 You are running a KVM management related action for the lab infra server from the infra server itself."
	echo -e "  🔹 If you still need to perform this operation, you need to do this from the Linux workstation running the QEMU/KVM setup.\n"
	exit 1
    fi
done
ssh \${SSH_OPTIONS} -t ${lab_infra_admin_username}@${lab_infra_server_ipv4_gateway} "export KVM_TOOL_EXECUTED_FROM='\${INFRA_SERVER_NAME}';${FILENAME} \$@"
exit
EOF
done

echo "[ok]"

echo -n "[STEP] Syncing wrapper scripts to infra server VM . . . "
rsync -az -e "ssh $SSH_OPTS" "$temp_dir_to_create_wrapper_scripts" ${lab_infra_admin_username}@${lab_infra_server_ipv4_address}:
ssh ${SSH_OPTS} ${lab_infra_admin_username}@${lab_infra_server_ipv4_address} "chmod +x -R scripts-to-manage-vms;sudo rsync -az scripts-to-manage-vms/* /bin/ && rm -rf scripts-to-manage-vms"
rm -rf "$temp_dir_to_create_wrapper_scripts"
echo "[ok]"

echo -e "\nNow you can manage QEMU/KVM environment from your infra server VM itself ! \n"
echo "CLI Tools to manage KVM VMs : "
echo "-----------------------------"
find ${scripts_location_to_manage_vms}/*.sh -exec basename {} \; | sed "s/.sh//g"
echo "-----------------------------"
