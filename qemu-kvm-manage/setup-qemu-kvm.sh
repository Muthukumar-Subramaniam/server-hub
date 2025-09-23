#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

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

echo -n -e "\n🔓 Enabling passwordless sudo for $USER . . . "
cat <<EOF | sudo tee "/etc/sudoers.d/$USER" &>/dev/null
$USER ALL=(ALL) NOPASSWD: ALL
Defaults:$USER !authenticate
EOF
echo -e "✅"

echo -e "\n📦 Installing required packages for QEMU/KVM . . . \n"

if command -v apt-get &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients python3-requests python3-libxml2 python3-libvirt libosinfo-bin python3-gi gir1.2-libosinfo-1.0 gir1.2-gobject-2.0 ovmf ed
elif command -v dnf &>/dev/null; then
    sudo dnf install -y qemu-kvm qemu-img libvirt libvirt-daemon libvirt-daemon-driver-qemu python3-requests python3-libxml2 python3-libvirt libosinfo python3-gobject gobject-introspection edk2-ovmf 
fi

echo -e "\n📦 Disabling libvirtd-tls and libvirtd-tcp sockets . . . \n"
sudo systemctl disable --now libvirtd-tls.socket libvirtd-tcp.socket
sudo systemctl mask libvirtd-tls.socket libvirtd-tcp.socket

echo -e "\n🔌 Enabling and starting libvirtd . . . \n"
sudo systemctl enable --now libvirtd
sudo systemctl status libvirtd -l --no-pager

echo -n -e "\n📁 Creating /kvm-hub/vms to manage VMs . . . "
sudo mkdir -p /kvm-hub/vms
sudo chown -R $USER:$(id -g) /kvm-hub
echo -e "✅"

echo -e "\n📥 Cloning virt-manager git repo to /kvm-hub/virt-manager . . . "
mkdir -p /kvm-hub/virt-manager && \
git clone https://github.com/virt-manager/virt-manager.git /kvm-hub/virt-manager

echo -n -e "\n🛠️ Creating a wrapper binary for virt-install from /kvm-hub/virt-manager . . . "
cat <<EOF | sudo tee /bin/virt-install &>/dev/null
#!/bin/bash
PYTHONPATH=/kvm-hub/virt-manager exec python3 /kvm-hub/virt-manager/virt-install "\$@"
EOF
sudo chmod +x /bin/virt-install
echo -e "✅"

virsh_network_name="default"
virsh_network_definition="virbr0.xml"
ipv4_virbr0=$(grep -oP "<ip address='\K[^']+" "$virsh_network_definition")

if ( ip link show virbr0 &>/dev/null && ip addr show virbr0 | grep -q "$ipv4_virbr0" ); then
    echo "✅ virbr0 already has IP $ipv4_virbr0 — skipping task."
else
    echo -n -e "\n🛜 Setting up custom bridge network virbr0 for QEMU/KVM . . . "
    # your network setup logic here
    run_virsh_cmd() {
        sudo virsh "$@" &>/dev/null
    }
    run_virsh_cmd net-destroy "$virsh_network_name"
    run_virsh_cmd net-undefine "$virsh_network_name"
    run_virsh_cmd net-define "$virsh_network_definition"
    run_virsh_cmd net-start "$virsh_network_name"
    run_virsh_cmd net-autostart "$virsh_network_name"
    echo -e "✅"
fi

echo -n -e "\n⚙️  Creating custom tools to manage QEMU/KVM . . . "
scripts_directory="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"
system_bin_directory="/bin"
vm_tool_names=(
  kvm-build-golden-qcow2-disk
  kvm-install-pxe
  kvm-install-golden
  kvm-remove
  kvm-reimage-pxe
  kvm-reimage-golden
  kvm-start
  kvm-stop
  kvm-restart
  kvm-resize
  kvm-console
  kvm-list
  kvm-dnsbinder
)
for vm_tool in "${vm_tool_names[@]}"; do
    source_script="${scripts_directory}/${vm_tool}.sh"
    target_symlink="${system_bin_directory}/${vm_tool}"

    [[ -f "$source_script" && ! -e "$target_symlink" ]] && sudo ln -s "$source_script" "$target_symlink"
done
echo -e "✅"

echo -e "\n🎉 QEMU/KVM setup completed successfully ! \n"

exit
