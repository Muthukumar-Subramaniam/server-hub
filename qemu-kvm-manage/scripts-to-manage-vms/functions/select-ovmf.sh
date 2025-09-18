if [ -f /usr/share/edk2/ovmf/OVMF_CODE.fd ]; then
    OVMF_CODE_PATH='/usr/share/edk2/ovmf/OVMF_CODE.fd'
    OVMF_VARS_PATH='/usr/share/edk2/ovmf/OVMF_VARS.fd'
elif [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ]; then
    OVMF_CODE_PATH='/usr/share/OVMF/OVMF_CODE_4M.fd'
    OVMF_VARS_PATH='/usr/share/OVMF/OVMF_VARS_4M.fd'
else
    OVMF_CODE_PATH='/server-hub/qemu-kvm-manage/ovmf-uefi-firmware/OVMF_CODE.fd'
    OVMF_VARS_PATH='/server-hub/qemu-kvm-manage/ovmf-uefi-firmware/OVMF_VARS.fd'
fi
