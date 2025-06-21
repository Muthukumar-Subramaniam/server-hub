#!/bin/bash
# Run the script without sudo but the user shoudl have sudo access
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

echo "\nEnabling passwordless sudo for $USER . . .\n"
cat <<EOF | sudo tee "/etc/sudoers.d/$USER"
$USER ALL=(ALL) NOPASSWD: ALL
Defaults:$USER !authenticate
EOF

echo -e "\nInstalling required packages for QEMU/KVM . . . \n"

sudo dnf install -y qemu-kvm qemu-img libvirt libvirt-daemon libvirt-daemon-driver-qemu bridge-utils python3-libxml2 python3-libvirt libosinfo python3-gobject gobject-introspection edk2-ovmf 

echo -e "\nEnabling and starting libvirtd . . . \n"
sudo systemctl enable --now libvirtd
sudo systemctl status libvirtd -l --no-pager
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
sudo ln -s /server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-start.sh /bin/kvm-start
sudo ln -s /server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-stop.sh /bin/kvm-stop
sudo ln -s /server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-restart.sh /bin/kvm-restart
sudo ln -s /server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-console.sh /bin/kvm-console
sudo ln -s /server-hub/qemu-kvm-manage/scripts-to-manage-vms/kvm-list.sh /bin/kvm-list
