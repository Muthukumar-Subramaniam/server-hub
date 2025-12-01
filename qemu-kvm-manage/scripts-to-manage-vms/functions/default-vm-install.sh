sudo virt-install \
  --name ${qemu_kvm_hostname} \
  --features acpi=on,apic=on \
  --memory 2048 \
  --vcpus 2 \
  --disk path=/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2,size=20,bus=virtio,boot.order=1 \
  --os-variant almalinux9 \
  --network network=default,model=virtio,mac=${MAC_ADDRESS},boot.order=2 \
  --graphics none \
  --noautoconsole \
  --machine q35 \
  --watchdog none \
  --cpu host-model \
  --boot loader=${OVMF_CODE_PATH},\
nvram.template=${OVMF_VARS_PATH},\
nvram=/kvm-hub/vms/${qemu_kvm_hostname}/${qemu_kvm_hostname}_VARS.fd,menu=on