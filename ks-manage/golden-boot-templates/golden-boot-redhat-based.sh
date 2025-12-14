#!/usr/bin/bash

# Setup logging to both file and console
LOGFILE="/var/log/golden-boot-redhat-based.log"
exec > >(tee -a "$LOGFILE") 2>&1

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
	log "FATAL ERROR: $1"
	log "Golden boot configuration failed - check $LOGFILE for details"
	exit 1
}

if [ -f /root/golden-boot-redhat-based-completed ]; then
	log "Golden boot already completed, exiting"
	exit 0
fi

if [ ! -f /root/golden-image-setup-completed ]; then
	log "Golden image setup not completed, exiting"
	exit 0
fi

log "Starting golden boot configuration for Red Hat-based system"

log "Checking network connectivity to lab infrastructure server..."
if ! ping -c 3 get_web_server_name.get_ipv4_domain; then
	error_exit "Cannot reach lab infrastructure server"
fi
log "Network connectivity to lab infrastructure server confirmed"

log "Creating systemd network configuration directory"
/bin/mkdir -p /etc/systemd/network

log "Creating .link files for predictable interface naming"
V_count=0
for v_interface in $(/bin/ls /sys/class/net | /bin/grep -v lo)
do
	mac_addr=$(/sbin/ip link | /bin/grep $v_interface -A 1 | /bin/grep link/ether | /bin/cut -d " " -f 6)
	log "Creating link file for interface $v_interface (MAC: $mac_addr) -> eth$V_count"
        /bin/echo -e "[Match]\nMACAddress=$mac_addr\n\n[Link]\nName=eth$V_count" >/etc/systemd/network/7$V_count-eth$V_count.link
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

log "Creating backup directory for existing network connections"
mkdir -p /root/system-connections-golden-image

log "Backing up existing NetworkManager connections"
if [ -n "$(ls -A /etc/NetworkManager/system-connections/ 2>/dev/null)" ]; then
	/bin/rsync -avPh /etc/NetworkManager/system-connections/* /root/system-connections-golden-image/ > /dev/null 2>&1
	log "Backup completed"
else
	log "No existing connections to backup"
fi

log "Deleting all existing NetworkManager connections"
nmcli -t -f UUID,TYPE connection show | while IFS=: read -r uuid type; do
	if [ "$type" = "loopback" ]; then
		log "  Skipping loopback connection UUID: $uuid"
		continue
	fi
	log "  Bringing down connection UUID: $uuid"
	nmcli connection down uuid "$uuid" 2>/dev/null || true
	log "  Deleting connection UUID: $uuid"
	nmcli connection delete uuid "$uuid" 2>/dev/null || true
done

log "Deleting any remaining connection files from disk"
if [ -d /etc/NetworkManager/system-connections ]; then
	rm -f /etc/NetworkManager/system-connections/*.nmconnection
	log "Deleted connection files from /etc/NetworkManager/system-connections/"
fi

if [ -d /etc/sysconfig/network-scripts ]; then
	rm -f /etc/sysconfig/network-scripts/ifcfg-*
	log "Deleted legacy ifcfg files from /etc/sysconfig/network-scripts/"
fi

log "Reloading NetworkManager connections"
nmcli connection reload

log "Bringing down all network interfaces"
for v_interface in $(/bin/ls /sys/class/net | /bin/grep -v lo)
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
for v_interface in $(/bin/ls /sys/class/net | /bin/grep -v lo)
do
	log "  Bringing up interface: $v_interface"
	ip link set $v_interface up
done

log "Creating new NetworkManager connection for eth0"
log "  IP: ${IPv4_ADDRESS}/${IPv4_CIDR}"
log "  Gateway: ${IPv4_GATEWAY}"
log "  DNS: ${IPv4_DNS_SERVER},8.8.8.8,8.8.4.4"
log "  Search domain: ${IPv4_DNS_DOMAIN}"

if ! nmcli connection add type ethernet ifname eth0 con-name eth0 \
  ipv4.addresses "${IPv4_ADDRESS}"/"${IPv4_CIDR}" \
  ipv4.gateway "${IPv4_GATEWAY}" \
  ipv4.dns "${IPv4_DNS_SERVER},8.8.8.8,8.8.4.4" \
  ipv4.dns-search "${IPv4_DNS_DOMAIN}" \
  ipv4.method manual \
  connection.autoconnect yes > /dev/null 2>&1; then
	error_exit "Failed to create NetworkManager connection for eth0"
fi

log "Reloading NetworkManager to pick up new connection"
nmcli connection reload

log "Activating eth0 connection"
if ! nmcli connection up eth0; then
	error_exit "Failed to activate eth0 connection"
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

log "Creating system installation timestamp in /etc/bigbang"
date '+%Y-%m-%d %H:%M:%S %Z' > /etc/bigbang
log "Installation timestamp: $(cat /etc/bigbang)"

log "Running lab rootfs extender"
if ! curl -fsSL "http://get_web_server_name.get_ipv4_domain/server-hub/common-utils/lab-rootfs-extender" | bash -s -- localhost; then
	log "WARNING: Lab rootfs extender failed, continuing anyway"
fi

log "Waiting for system to stabilize..."
sleep 3

log "Generating SSH host keys now that network is stable"
if ! ssh-keygen -A; then
	log "WARNING: SSH host key generation failed, continuing anyway"
else
	log "SSH host keys generated successfully"
fi

log "Restarting SSH service to pick up new host keys"
if systemctl list-unit-files | grep -q '^sshd.service'; then
	log "Found sshd.service, restarting..."
	systemctl restart sshd && log "SSH service restarted successfully" || log "WARNING: SSH service restart failed"
elif systemctl list-unit-files | grep -q '^ssh.service'; then
	log "Found ssh.service, restarting..."
	systemctl restart ssh && log "SSH service restarted successfully" || log "WARNING: SSH service restart failed"
else
	log "WARNING: No SSH service unit found (sshd.service or ssh.service)"
fi

log "Marking golden boot as completed"
touch /root/golden-boot-redhat-based-completed

log "Disabling golden-boot-redhat-based.service to prevent future execution"
systemctl disable golden-boot-redhat-based.service 2>/dev/null || true

log "Golden boot configuration completed successfully"
