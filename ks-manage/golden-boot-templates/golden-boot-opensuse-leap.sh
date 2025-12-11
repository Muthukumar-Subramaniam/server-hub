#!/bin/bash

# Setup logging to both file and console
LOGFILE="/var/log/golden-boot-opensuse-leap.log"
exec > >(tee -a "$LOGFILE") 2>&1

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
	log "FATAL ERROR: $1"
	log "Golden boot configuration failed - check $LOGFILE for details"
	exit 1
}

if [ -f /root/golden-boot-opensuse-leap-completed ]; then
	log "Golden boot already completed, exiting"
	exit 0
fi

if [ ! -f /root/golden-image-setup-completed ]; then
	log "Golden image setup not completed, exiting"
	exit 0
fi

log "Starting golden boot configuration for openSUSE Leap system"

log "Checking network connectivity to lab infrastructure server..."
if ! ping -c 3 get_web_server_name.get_ipv4_domain; then
	error_exit "Cannot reach lab infrastructure server"
fi
log "Network connectivity to lab infrastructure server confirmed"

log "Creating systemd network configuration directory"
mkdir -p /etc/systemd/network

log "Creating .link files for predictable interface naming"
V_count=0
for v_interface in $(ls /sys/class/net | grep -v lo)
do
	mac_addr=$(ip link show "$v_interface" | grep link/ether | awk '{print $2}')
	log "Creating link file for interface $v_interface (MAC: $mac_addr) -> eth$V_count"
	echo -e "[Match]\nMACAddress=$mac_addr\n\n[Link]\nName=eth$V_count" > /etc/systemd/network/7$V_count-eth$V_count.link
	V_count=$((V_count+1))
done

log "Retrieving MAC address for eth0"
get_mac_address_path=$(grep '^MACAddress=' /etc/systemd/network/70-eth0.link | cut -d= -f2 | sed 's/:/-/g')
log "MAC address path: $get_mac_address_path"

log "Downloading network configuration from lab infrastructure server"
if ! curl -fsSL "http://get_web_server_name.get_ipv4_domain/ksmanager-hub/golden-boot-mac-configs/network-config-${get_mac_address_path}" -o "/root/network-config-$get_mac_address_path"; then
	error_exit "Failed to download network configuration for MAC: $get_mac_address_path"
fi

if [ ! -f "/root/network-config-$get_mac_address_path" ] || [ ! -s "/root/network-config-$get_mac_address_path" ]; then
	error_exit "Network configuration file is missing or empty"
fi

log "Loading network configuration"
source "/root/network-config-$get_mac_address_path"

# Validate required variables
if [ -z "$HOST_NAME" ] || [ -z "$IPv4_ADDRESS" ] || [ -z "$IPv4_CIDR" ] || [ -z "$IPv4_GATEWAY" ] || [ -z "$IPv4_DNS_SERVER" ] || [ -z "$IPv4_DNS_DOMAIN" ]; then
	error_exit "Required network configuration variables are missing"
fi

log "Setting hostname to: ${HOST_NAME}"
hostnamectl set-hostname "${HOST_NAME}"

log "Configuring kernel hostname"
cat << EOF > /etc/sysctl.d/hostname.conf
kernel.hostname=${HOST_NAME}
EOF

log "Applying sysctl settings"
sysctl --system > /dev/null 2>&1

log "Generating SSH host keys"
if ! ssh-keygen -A; then
	log "WARNING: SSH host key generation failed, continuing anyway"
fi

log "Bringing down all network interfaces"
for v_interface in $(ls /sys/class/net | grep -v lo)
do
	log "  Bringing down interface: $v_interface"
	ip link set $v_interface down
done

log "Reloading udev rules for interface renaming"
udevadm control --reload-rules
udevadm trigger --action=add --subsystem-match=net

log "Waiting for eth0 interface to be available..."
timeout=30
counter=0
while [ ! -e /sys/class/net/eth0 ] && [ $counter -lt $timeout ]; do
	sleep 0.5
	counter=$((counter + 1))
done

if [ ! -e /sys/class/net/eth0 ]; then
	error_exit "eth0 interface not found after rename (timeout after ${timeout}s)"
fi
log "eth0 interface is available"

log "Bringing up all network interfaces"
for v_interface in $(ls /sys/class/net | grep -v lo)
do
	log "  Bringing up interface: $v_interface"
	ip link set $v_interface up
done

log "Creating network configuration for eth0"
log "  IP: ${IPv4_ADDRESS}/${IPv4_CIDR}"
log "  Gateway: ${IPv4_GATEWAY}"
log "  DNS: ${IPv4_DNS_SERVER}"

cat << EOF > /etc/sysconfig/network/ifcfg-eth0
IPADDR='${IPv4_ADDRESS}/${IPv4_CIDR}'
BOOTPROTO='static'
STARTMODE='auto'
ZONE=public
EOF

cat << EOF > /etc/sysconfig/network/ifroute-eth0
default ${IPv4_GATEWAY} - eth0
EOF

log "Restarting network service to apply configuration"
if ! systemctl restart network; then
	error_exit "Failed to restart network service"
fi

log "Waiting for network to become ready..."
timeout=10
counter=0
while ! ip addr show eth0 | grep -q "inet ${IPv4_ADDRESS}" && [ $counter -lt $timeout ]; do
	sleep 0.5
	counter=$((counter + 1))
done

if ! ip addr show eth0 | grep -q "inet ${IPv4_ADDRESS}"; then
	error_exit "Network interface did not receive IP address"
fi
log "Network interface configured with IP ${IPv4_ADDRESS}/${IPv4_CIDR}"

log "Verifying network connectivity to lab infrastructure server..."
if ! ping -c 3 get_web_server_name.get_ipv4_domain; then
	error_exit "Cannot reach lab infrastructure server after reconfiguration"
fi
log "Network connectivity to lab infrastructure server confirmed with new IP configuration"

log "Running lab rootfs extender"
if ! curl -fsSL "http://get_web_server_name.get_ipv4_domain/server-hub/common-utils/lab-rootfs-extender" | bash -s -- localhost; then
	log "WARNING: Lab rootfs extender failed, continuing anyway"
fi

log "Restarting SSH service to ensure it picks up new host keys"
systemctl restart sshd || systemctl restart ssh

log "Marking golden boot as completed"
touch /root/golden-boot-opensuse-leap-completed

log "Disabling golden-boot-opensuse-leap.service to prevent future execution"
systemctl disable golden-boot-opensuse-leap.service 2>/dev/null || true

log "Golden boot configuration completed successfully"
