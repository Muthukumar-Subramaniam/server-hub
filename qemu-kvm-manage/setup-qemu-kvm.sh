#!/bin/bash

echo "\nEnabling passwordless sudo for $USER . . .\n"
cat <<EOF | sudo tee "/etc/sudoers.d/$USER"
$USER ALL=(ALL) NOPASSWD: ALL
Defaults:$USER !authenticate
EOF

echo -e "\nInstall required packages for qemu-kvm . . . \n"

sudo dnf install -y qemu-kvm qemu-img libvirt libvirt-daemon libvirt-daemon-driver-qemu bridge-utils python3-libxml2 python3-libvirt libosinfo python3-gobject gobject-introspection edk2-ovmf 

echo -e "\nEnable and start libvirtd . . . \n"
systemctl enable --now libvirtd
systemctl status libvirtd
sudo usermod -aG libvirt $USER
sudo newgrp libvirt

echo -e "\nCreating /virtual-machines to manage VMs . . . \n"
sudo mkdir -p /virtual-machines
sudo chown -R $USER:qemu /virtual-machines
chmod -R g+s /virtual-machines

echo -e "Clone https://github.com/virt-manager/virt-manager.git repo to /virtual-machines/virt-manager .  . . \n"
mkdir -p /virtual-machines/virt-manager && \
git clone https://github.com/virt-manager/virt-manager.git /virtual-machines/virt-manager

echo -e "\nCreate a wrapper binary for /bin/virt-install from /virtual-machines/virt-manager . . .\n"
cat <<EOF | sudo tee /bin/virt-install
#!/bin/bash
PYTHONPATH=/virtual-machines/virt-manager exec python3 /virtual-machines/virt-manager/virt-install "\$@"
EOF
sudo chmod +x /bin/virt-install

echo -e "\nSetup Custom Bridge Network virbr0 defined in virbr0.xml . . .\n" 
sudo virsh net-destroy default &>/dev/null
sudo virsh net-undefine default &>/dev/null
sudo virsh net-define virbr0.xml
sudo virsh net-start default
sudo virsh net-autostart default
sudo virsh net-dumpxml default

echo -e "\nCreate custom tools to manage VMs . . .\n"
sudo ln -s /server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-install.sh /bin/kvm-install
sudo ln -s /server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-remove.sh /bin/kvm-remove
sudo ln -s /server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-reimage.sh /bin/kvm-reimage
