# Set default values if not provided
DISK_PATH="${DISK_PATH:-/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2}"
NVRAM_PATH="${NVRAM_PATH:-/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}_VARS.fd}"
CONSOLE_MODE="${CONSOLE_MODE:---noautoconsole}"

# Only redirect output if running in non-console mode
if [[ "${CONSOLE_MODE}" == "--noautoconsole" ]]; then
    virt_install_error=$(sudo virt-install \
      --name ${qemu_kvm_hostname} \
      --features acpi=on,apic=on \
      --memory 2048 \
      --vcpus 2 \
      --disk path=${DISK_PATH},size=20,bus=virtio,boot.order=1 \
      --os-variant almalinux9 \
      --network network=default,model=virtio,mac=${MAC_ADDRESS},boot.order=2 \
      --graphics none \
      ${CONSOLE_MODE} \
      --machine q35 \
      --watchdog none \
      --cpu host-model \
      --boot loader=${OVMF_CODE_PATH},\
nvram.template=${OVMF_VARS_PATH},\
nvram=${NVRAM_PATH},menu=on \
      2>&1 >/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo "$virt_install_error" >&2
        return 1
    fi
else
    # Run with console attached (no output redirection)
    sudo virt-install \
      --name ${qemu_kvm_hostname} \
      --features acpi=on,apic=on \
      --memory 2048 \
      --vcpus 2 \
      --disk path=${DISK_PATH},size=20,bus=virtio,boot.order=1 \
      --os-variant almalinux9 \
      --network network=default,model=virtio,mac=${MAC_ADDRESS},boot.order=2 \
      --graphics none \
      ${CONSOLE_MODE} \
      --machine q35 \
      --watchdog none \
      --cpu host-model \
      --boot loader=${OVMF_CODE_PATH},\
nvram.template=${OVMF_VARS_PATH},\
nvram=${NVRAM_PATH},menu=on
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
fi