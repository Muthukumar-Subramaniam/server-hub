#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh

if [[ "$EUID" -eq 0 ]]; then
    print_error "[ERROR] Running as root user is not allowed."
    print_info "[INFO] This script should be run as a user with sudo privileges, not as root."
    exit 1
fi

# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    print_error "[ERROR] This script cannot be executed inside a QEMU guest VM."
    print_info "[INFO] This script must be run on the host system managing QEMU/KVM virtual machines."
    print_info "[INFO] Current environment is a QEMU guest, which is not supported."
    exit 1
fi

print_info "[INFO] Enabling passwordless sudo for $USER..." nskip
cat <<EOF | sudo tee "/etc/sudoers.d/$USER" &>/dev/null
$USER ALL=(ALL) NOPASSWD: ALL
Defaults:$USER !authenticate
EOF
print_success "[SUCCESS]"

print_info "[INFO] Installing required packages for QEMU/KVM..."

if command -v apt-get &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients python3-requests python3-libxml2 python3-libvirt libosinfo-bin python3-gi gir1.2-libosinfo-1.0 gir1.2-gobject-2.0 ovmf ed
elif command -v dnf &>/dev/null; then
    sudo dnf install -y qemu-kvm qemu-img libvirt libvirt-daemon libvirt-daemon-driver-qemu python3-requests python3-libxml2 python3-libvirt libosinfo python3-gobject gobject-introspection edk2-ovmf 
fi

print_info "[INFO] Disabling libvirtd-tls and libvirtd-tcp sockets..."
sudo systemctl disable --now libvirtd-tls.socket libvirtd-tcp.socket
sudo systemctl mask libvirtd-tls.socket libvirtd-tcp.socket

print_info "[INFO] Enabling and starting libvirtd..."
sudo systemctl enable --now libvirtd
sudo systemctl status libvirtd -l --no-pager

print_info "[INFO] Creating /kvm-hub/vms to manage VMs..." nskip
sudo mkdir -p /kvm-hub/vms
sudo chown -R $USER:$(id -g) /kvm-hub
print_success "[SUCCESS]"

print_info "[INFO] Cloning virt-manager git repo to /kvm-hub/virt-manager..."
mkdir -p /kvm-hub/virt-manager && \
git clone https://github.com/virt-manager/virt-manager.git /kvm-hub/virt-manager

print_info "[INFO] Creating a wrapper binary for virt-install from /kvm-hub/virt-manager..." nskip
cat <<EOF | sudo tee /bin/virt-install &>/dev/null
#!/bin/bash
PYTHONPATH=/kvm-hub/virt-manager exec python3 /kvm-hub/virt-manager/virt-install "\$@"
EOF
sudo chmod +x /bin/virt-install
print_success "[SUCCESS]"

virsh_network_name="default"
virsh_network_definition="labbr0.xml"
ipv4_labbr0=$(grep -oP "<ip address='\K[^']+" "$virsh_network_definition")

if ( ip link show labbr0 &>/dev/null && ip addr show labbr0 | grep -q "$ipv4_labbr0" ); then
    print_success "[SUCCESS] labbr0 already has IP $ipv4_labbr0 — skipping task."
else
    print_info "[INFO] Setting up custom bridge network labbr0 for QEMU/KVM..." nskip
    # your network setup logic here
    run_virsh_cmd() {
        sudo virsh "$@" &>/dev/null
    }
    run_virsh_cmd net-destroy "$virsh_network_name"
    run_virsh_cmd net-undefine "$virsh_network_name"
    run_virsh_cmd net-define "$virsh_network_definition"
    run_virsh_cmd net-start "$virsh_network_name"
    run_virsh_cmd net-autostart "$virsh_network_name"
    print_success "[SUCCESS]"
fi

print_info "[INFO] Creating custom tools to manage QEMU/KVM..." nskip
scripts_directory="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"
sudo ln -sf "$scripts_directory/qlabvmctl.sh" /usr/bin/qlabvmctl
sudo ln -sf "$scripts_directory/qlabstart.sh" /usr/bin/qlabstart
sudo ln -sf "$scripts_directory/qlabhealth.sh" /usr/bin/qlabhealth
sudo ln -sf "$scripts_directory/qlabdnsbinder.sh" /usr/bin/qlabdnsbinder
print_success "[SUCCESS]"

print_info "[INFO] Installing bash completion for qlabvmctl..." nskip
sudo ln -sf "$scripts_directory/qlabvmctl-completion.bash" /etc/bash_completion.d/qlabvmctl-completion.bash
print_success "[SUCCESS]"

print_success "[SUCCESS] QEMU/KVM setup completed successfully!"

exit
