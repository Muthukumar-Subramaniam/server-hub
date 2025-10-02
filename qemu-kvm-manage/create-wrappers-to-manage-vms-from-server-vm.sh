#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

if [[ "$EUID" -eq 0 ]]; then
    echo -e "\n⛔ Running as root user is not allowed."
    echo -e "\n🔐 This script should be run as a user who has sudo privileges, but *not* using sudo.\n"
    exit 1
fi

# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    echo "❌❌❌  FATAL: WRONG PLACE, BUDDY! ❌❌❌"
    echo -e "\n⚠️  Note:"
    echo -e "  🔹 This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo -e "  🔹 You’re currently inside a QEMU guest VM, which makes absolutely no sense.\n"
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

infra_server_ipv4_address=$(cat /kvm-hub/ipv4-address-address-of-infra-server-vm)
infra_mgmt_super_username=$(cat /kvm-hub/infra-mgmt-super-username)
local_infra_domain_name=$(cat /kvm-hub/local_infra_domain_name)
kvm_host_admin_user="$USER"
scripts_location_to_manage_vms="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"
temp_dir_to_create_wrapper_scripts="/tmp/scripts-to-manage-vms"
virsh_network_definition="/server-hub/qemu-kvm-manage/virbr0.xml"
kvm_host_ipv4_address=$(grep -oP "<ip address='\K[^']+" "$virsh_network_definition")
SSH_OPTS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo -n "[STEP] Authorize SSH public key of infra server VM . . . "
get_user_host_ssh_pub_key=$(ssh ${SSH_OPTS} ${infra_mgmt_super_username}@${infra_server_ipv4_address} "cat .ssh/id_rsa.pub" | cut -d " " -f3)
if ! grep -q "${get_user_host_ssh_pub_key}" ~/.ssh/authorized_keys; then
	ssh ${SSH_OPTS} ${infra_mgmt_super_username}@${infra_server_ipv4_address} "cat .ssh/id_rsa.pub" >> ~/.ssh/authorized_keys
fi
echo "[ok]"

echo -n "[STEP] Generating wrapper scripts to manage KVM VMs . . . "
mkdir -p "${temp_dir_to_create_wrapper_scripts}"


for FILENAME in $(find "${scripts_location_to_manage_vms}/*.sh" -exec basename {} \; | sed "s/.sh//g"); do
cat > "${temp_dir_to_create_wrapper_scripts}/${FILENAME}" << EOF
#!/bin/bash
# Who am I?
SSH_OPTIONS="${SSH_OPTS}"
INFRA_SERVER_NAME="\$(hostname -s)"
for EACH_ARG in "\$@"; do
    if [[ "\${EACH_ARG}" == "\${INFRA_SERVER_NAME}" ]]; then
	echo -e "\n❌ This operation is not allowed to avoid self-referential KVM actions that could destabilize the infra server."
    	echo -e "⚠️ Note:"
	echo -e "  🔹 You are running a KVM management related action for the lab infra server from the infra server itself."
	echo -e "  🔹 If you still need to perform this operation, you need to do this from the Linux workstation running the QEMU/KVM setup.\n"
	exit 1
    fi
done
ssh \${SSH_OPTIONS} -t ${kvm_host_admin_user}@${kvm_host_ipv4_address} "export KVM_TOOL_EXECUTED_FROM='\${INFRA_SERVER_NAME}';${FILENAME} \$@"
exit
EOF
done

echo "[ok]"

echo -n "[STEP] Syncing wrapper scripts to infra server VM . . . "
rsync -az -e "ssh $SSH_OPTS" "$temp_dir_to_create_wrapper_scripts" ${infra_mgmt_super_username}@${infra_server_ipv4_address}:
ssh ${SSH_OPTS} ${infra_mgmt_super_username}@${infra_server_ipv4_address} "chmod +x -R scripts-to-manage-vms;sudo rsync -az scripts-to-manage-vms/* /bin/ && rm -rf scripts-to-manage-vms"
rm -rf "$temp_dir_to_create_wrapper_scripts"
echo "[ok]"

echo -e "\nNow you can manage QEMU/KVM environment from your infra server VM itself ! \n"
echo "CLI Tools to manage KVM VMs : "
echo "-----------------------------"
find "${scripts_location_to_manage_vms}/*.sh" -exec basename {} \; | sed "s/.sh//g"
echo "-----------------------------"
