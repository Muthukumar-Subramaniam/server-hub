# Use first argument or prompt for hostname
if [ -n "$1" ]; then
    qemu_kvm_hostname="$1"
else
    read -rp "Please enter the hostname of the VM: " qemu_kvm_hostname
    if [[ -n "${KVM_TOOL_EXECUTED_FROM:-}" && "${KVM_TOOL_EXECUTED_FROM}" == "${qemu_kvm_hostname}" ]]; then
        print_error "[ERROR] This operation is not allowed to avoid self-referential KVM actions."
        print_info "[INFO] You are running a KVM management action for the lab infra server from the infra server itself."
        print_info "[INFO] To perform this operation, run it from the Linux workstation hosting the QEMU/KVM setup."
        exit 1
    fi
fi

# Validate and normalize hostname to FQDN
if [[ "${qemu_kvm_hostname}" == *.${lab_infra_domain_name} ]]; then
    stripped_hostname="${qemu_kvm_hostname%.${lab_infra_domain_name}}"
    # Verify the stripped part doesn't contain dots (ensure it's just hostname.domain, not host.something.domain)
    if [[ "${stripped_hostname}" == *.* ]]; then
        print_error "[ERROR] Invalid hostname format. Expected format: hostname.${lab_infra_domain_name}"
        exit 1
    fi
    # Validate the hostname part
    if [[ ! "${stripped_hostname}" =~ ^[a-z0-9-]+$ || "${stripped_hostname}" =~ ^- || "${stripped_hostname}" =~ -$ ]]; then
        print_error "[ERROR] Invalid hostname. Use only lowercase letters, numbers, and hyphens."
        print_info "[INFO] Hostname must not start or end with a hyphen."
        exit 1
    fi
    # Keep as FQDN
elif [[ "${qemu_kvm_hostname}" == *.* ]]; then
    print_error "[ERROR] Invalid domain. Expected domain: ${lab_infra_domain_name}"
    exit 1
else
    # Bare hostname provided - validate and convert to FQDN
    if [[ ! "${qemu_kvm_hostname}" =~ ^[a-z0-9-]+$ || "${qemu_kvm_hostname}" =~ ^- || "${qemu_kvm_hostname}" =~ -$ ]]; then
        print_error "[ERROR] Invalid hostname. Use only lowercase letters, numbers, and hyphens."
        print_info "[INFO] Hostname must not start or end with a hyphen."
        exit 1
    fi
    qemu_kvm_hostname="${qemu_kvm_hostname}.${lab_infra_domain_name}"
fi
