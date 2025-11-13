# Use first argument or prompt for hostname
if [ -n "$1" ]; then
    qemu_kvm_hostname="$1"
else
    read -rp "⌨️ Please enter the Hostname of the VM to add disks : " qemu_kvm_hostname
    if [[ -n "${KVM_TOOL_EXECUTED_FROM:-}" && "${KVM_TOOL_EXECUTED_FROM}" == "${qemu_kvm_hostname}" ]]; then
	echo -e "\n❌ This operation is not allowed to avoid self-referential KVM actions that could destabilize the infra server."
    	echo -e "⚠️ Note:"
	echo -e "  🔹 You are running a KVM management related action for the lab infra server from the infra server itself."
	echo -e "  🔹 If you still need to perform this operation, you need to do this from the Linux workstation running the QEMU/KVM setup.\n"
	exit 1
    fi
fi

# Validate and normalize hostname to FQDN
if [[ "${qemu_kvm_hostname}" == *.${lab_infra_domain_name} ]]; then
	stripped_hostname="${qemu_kvm_hostname%.${lab_infra_domain_name}}"
	# Verify the stripped part doesn't contain dots (ensure it's just hostname.domain, not host.something.domain)
	if [[ "${stripped_hostname}" == *.* ]]; then
		echo -e "\n❌ Invalid hostname!\n   🔹 If providing a domain, use format: hostname.${lab_infra_domain_name}\n"
		exit 1
	fi
	# Validate the hostname part
	if [[ ! "${stripped_hostname}" =~ ^[a-z0-9-]+$ || "${stripped_hostname}" =~ ^- || "${stripped_hostname}" =~ -$ ]]; then
		echo -e "\n❌ Invalid hostname!\n   🔹 Use only lowercase letters, numbers, and hyphens (-).\n   🔹 Must not start or end with a hyphen.\n"
		exit 1
	fi
	# Keep as FQDN
elif [[ "${qemu_kvm_hostname}" == *.* ]]; then
	echo -e "\n❌ Invalid hostname!\n   🔹 If providing a domain, it must match: ${lab_infra_domain_name}\n"
	exit 1
else
	# Bare hostname provided - validate and convert to FQDN
	if [[ ! "${qemu_kvm_hostname}" =~ ^[a-z0-9-]+$ || "${qemu_kvm_hostname}" =~ ^- || "${qemu_kvm_hostname}" =~ -$ ]]; then
		echo -e "\n❌ Invalid hostname!\n   🔹 Use only lowercase letters, numbers, and hyphens (-).\n   🔹 Must not start or end with a hyphen.\n"
		exit 1
	fi
	qemu_kvm_hostname="${qemu_kvm_hostname}.${lab_infra_domain_name}"
fi
