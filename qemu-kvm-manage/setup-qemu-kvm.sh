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

echo -e "\n📦 Removing a package that might conflict with QEMU/KVM installation . . .\n"

sudo dnf remove -y cuda

echo -e "\n📦 Installing required packages for QEMU/KVM . . . \n"

sudo dnf install -y qemu-kvm qemu-img libvirt libvirt-daemon libvirt-daemon-driver-qemu python3-libxml2 python3-libvirt libosinfo python3-gobject gobject-introspection edk2-ovmf 

echo -e "\n🔌 Enabling and starting libvirtd . . . \n"
sudo systemctl enable --now libvirtd
sudo systemctl status libvirtd -l --no-pager
sudo usermod -aG libvirt $USER

echo -n -e "\n📁 Creating /virtual-machines to manage VMs . . . "
sudo mkdir -p /virtual-machines
sudo chown -R $USER:qemu /virtual-machines
chmod -R g+s /virtual-machines
echo -e "✅"

echo -e "\n📥 Cloning virt-manager git repo to /virtual-machines/virt-manager . . . "
mkdir -p /virtual-machines/virt-manager && \
git clone https://github.com/virt-manager/virt-manager.git /virtual-machines/virt-manager

echo -n -e "\n🛠️ Creating a wrapper binary for virt-install from /virtual-machines/virt-manager . . . "
cat <<EOF | sudo tee /bin/virt-install &>/dev/null
#!/bin/bash
PYTHONPATH=/virtual-machines/virt-manager exec python3 /virtual-machines/virt-manager/virt-install "\$@"
EOF
sudo chmod +x /bin/virt-install
echo -e "✅"

echo -n -e "\n🛜 Setting up custom bridge network virbr0 for QEMU/KVM . . . "
virsh_network_name="default"
virsh_network_definition="virbr0.xml"
run_virsh_cmd() {
    sudo virsh "$@" &>/dev/null
}
run_virsh_cmd net-destroy "$virsh_network_name"
run_virsh_cmd net-undefine "$virsh_network_name"
run_virsh_cmd net-define "$virsh_network_definition"
run_virsh_cmd net-start "$virsh_network_name"
run_virsh_cmd net-autostart "$virsh_network_name"
echo -e "✅"

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
  kvm-console
  kvm-list
)
for vm_tool in "${vm_tool_names[@]}"; do
    source_script="${scripts_directory}/${vm_tool}.sh"
    target_symlink="${system_bin_directory}/${vm_tool}"

    [[ -f "$source_script" && ! -e "$target_symlink" ]] && sudo ln -s "$source_script" "$target_symlink"
done
echo -e "✅"

echo -e "\n🎉 QEMU/KVM setup completed successfully ! \n"

exit
