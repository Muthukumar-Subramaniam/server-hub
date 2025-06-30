#!/bin/bash
# AlmaLinux Golden Image Preparation Script
if [ -f /root/golden-image-setup-completed ]; then
	exit
fi

LOG=/root/golden-image-setup.log
echo -e "\nGolden Image Cleanup Started: $(date)\n" | tee -a "$LOG"

# 1. Clear machine-id
echo "Clearing machine-id..." | tee -a "$LOG"
truncate -s 0 /etc/machine-id

# 2. Remove SSH host keys
echo "Removing SSH host keys..." | tee -a "$LOG"
rm -f /etc/ssh/ssh_host_* 2>>"$LOG"

# 3. Truncate all log files under /var/log
echo "Truncating all log files under /var/log..." | tee -a "$LOG"
find /var/log -type f -exec truncate -s 0 {} \; 2>>"$LOG"

# 4. Disable cloud-init if present
echo "Disabling cloud-init (if present)..." | tee -a "$LOG"
#touch /etc/cloud/cloud-init.disabled 2>>"$LOG"

# 5. Remove NetworkManager system connections
echo "Removing NetworkManager system connections..." | tee -a "$LOG"
if grep -qi "rhel" /etc/os-release; then
	rm -f /etc/NetworkManager/system-connections/* 2>>"$LOG"
elif grep -qi "debian" /etc/os-release; then
	rm -f /etc/netplan/* 2>>"$LOG"
fi

# 7. Remove systemd-networkd configs
echo "Removing systemd network configuration files..." | tee -a "$LOG"
rm -f /etc/systemd/network/*.link 2>>"$LOG"

# 8. Self-disable this service
echo "Disabling this service after successful run..." | tee -a "$LOG"
systemctl disable golden-image-setup.service 2>>"$LOG"

# 9. Bring down the interface so that other script won't get activated
echo "Bringing down eth0 interface..." | tee -a "$LOG"
ip link set dev eth0 down

# 10. Touch a file to mark completion of this script
touch /root/golden-image-setup-completed 

# 11. Final message and shutdown
echo -e "\nGolden image cleanup complete. Shutting down now: $(date)\n" | tee -a "$LOG"
shutdown -h now
