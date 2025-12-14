#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh

if [[ "$EUID" -eq 0 ]]; then
    print_error "Running as root user is not allowed."
    print_info "This script should be run as a user with sudo privileges, not as root."
    exit 1
fi

# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    print_error "This script cannot be executed inside a QEMU guest VM."
    print_info "This script must be run on the host system managing QEMU/KVM virtual machines."
    print_info "Current environment is a QEMU guest, which is not supported."
    exit 1
fi

print_task "Enabling passwordless sudo for $USER"
cat <<EOF | sudo tee "/etc/sudoers.d/$USER" &>/dev/null
$USER ALL=(ALL) NOPASSWD: ALL
Defaults:$USER !authenticate
EOF
print_task_done

print_info "Installing required packages for QEMU/KVM..."

if command -v apt-get &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients python3-requests python3-libxml2 python3-libvirt libosinfo-bin python3-gi gir1.2-libosinfo-1.0 gir1.2-gobject-2.0 ovmf ed || {
        print_error "Failed to install required packages."
        exit 1
    }
elif command -v dnf &>/dev/null; then
    sudo dnf install -y qemu-kvm qemu-img libvirt libvirt-daemon libvirt-daemon-driver-qemu python3-requests python3-libxml2 python3-libvirt libosinfo python3-gobject gobject-introspection edk2-ovmf ed || {
        print_error "Failed to install required packages."
        exit 1
    }
else
    print_error "Unsupported package manager. Only apt-get and dnf are supported."
    exit 1
fi

print_info "Disabling libvirtd-tls and libvirtd-tcp sockets..."
sudo systemctl disable --now libvirtd-tls.socket libvirtd-tcp.socket
sudo systemctl mask libvirtd-tls.socket libvirtd-tcp.socket

print_info "Enabling and starting libvirtd..."
sudo systemctl enable --now libvirtd
sudo systemctl status libvirtd -l --no-pager

print_task "Creating /kvm-hub/vms to manage VMs"
sudo mkdir -p /kvm-hub/vms || {
    print_error "Failed to create /kvm-hub/vms directory."
    exit 1
}
sudo chown -R "$USER":"$(id -g)" /kvm-hub || {
    print_error "Failed to change ownership of /kvm-hub directory."
    exit 1
}
print_task_done

print_info "Cloning virt-manager git repo to /kvm-hub/virt-manager..."
if [[ ! -d /kvm-hub/virt-manager/.git ]]; then
    sudo mkdir -p /kvm-hub/virt-manager || {
        print_error "Failed to create /kvm-hub/virt-manager directory."
        exit 1
    }
    git clone https://github.com/virt-manager/virt-manager.git /kvm-hub/virt-manager || {
        print_error "Failed to clone virt-manager repository."
        exit 1
    }
else
    print_info "virt-manager already cloned, skipping."
fi

print_task "Creating a wrapper binary for virt-install from /kvm-hub/virt-manager"
cat <<EOF | sudo tee /bin/virt-install &>/dev/null
#!/bin/bash
PYTHONPATH=/kvm-hub/virt-manager exec python3 /kvm-hub/virt-manager/virt-install "\$@"
EOF
sudo chmod +x /bin/virt-install
print_task_done

virsh_network_name="default"
virsh_network_definition="/server-hub/qemu-kvm-manage/labbr0.xml"

if [[ ! -f "$virsh_network_definition" ]]; then
    print_error "Network definition file not found: $virsh_network_definition"
    exit 1
fi

ipv4_labbr0=$(grep -oP "<ip address='\K[^']+" "$virsh_network_definition")

if [[ -z "$ipv4_labbr0" ]]; then
    print_error "Failed to extract IP address from $virsh_network_definition"
    exit 1
fi

if ( ip link show labbr0 &>/dev/null && ip addr show labbr0 | grep -q "$ipv4_labbr0" ); then
    print_success "labbr0 already has IP $ipv4_labbr0 — skipping task."
else
    print_task "Setting up custom bridge network labbr0 for QEMU/KVM"
    run_virsh_cmd() {
        sudo virsh "$@" &>/dev/null
    }
    run_virsh_cmd net-destroy "$virsh_network_name"
    run_virsh_cmd net-undefine "$virsh_network_name"
    run_virsh_cmd net-define "$virsh_network_definition" || {
        print_error "Failed to define network from $virsh_network_definition"
        exit 1
    }
    run_virsh_cmd net-start "$virsh_network_name" || {
        print_error "Failed to start network $virsh_network_name"
        exit 1
    }
    run_virsh_cmd net-autostart "$virsh_network_name"
    print_task_done
fi

print_task "Creating custom tools to manage QEMU/KVM"
scripts_directory="/server-hub/qemu-kvm-manage/scripts-to-manage-vms"
sudo ln -sf "$scripts_directory/qlabvmctl.sh" /usr/local/bin/qlabvmctl
sudo ln -sf "$scripts_directory/qlabstart.sh" /usr/local/bin/qlabstart
sudo ln -sf "$scripts_directory/qlabhealth.sh" /usr/local/bin/qlabhealth
sudo ln -sf "$scripts_directory/qlabdnsbinder.sh" /usr/local/bin/qlabdnsbinder
print_task_done

print_task "Installing bash completion for qlabvmctl"
sudo ln -sf "$scripts_directory/qlabvmctl-completion.bash" /etc/bash_completion.d/qlabvmctl-completion.bash
print_task_done

print_success "QEMU/KVM setup completed successfully!"

exit 0
