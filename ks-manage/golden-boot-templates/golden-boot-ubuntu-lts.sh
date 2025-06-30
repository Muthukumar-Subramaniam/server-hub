#!/bin/bash
if [ -f /root/golden-boot-ubuntu-lts-completed ]; then
	exit
fi

if [ ! -f /root/golden-image-setup-completed ]; then
	exit
fi

if ! ping -c 5 get_web_server_name.get_ipv4_domain; then
	exit
fi

/bin/mkdir -p /etc/systemd/network

V_count=0
for v_interface in $(/bin/ls /sys/class/net | /bin/grep -v lo)
do
        /bin/echo -e "[Match]\nMACAddress=$(/sbin/ip link | /bin/grep $v_interface -A 1 | /bin/grep link/ether | /bin/cut -d " " -f 6)\n\n[Link]\nName=eth$V_count" >/etc/systemd/network/7$V_count-eth$V_count.link
	V_count=$((V_count+1))
done

get_mac_address_path=$(grep '^MACAddress=' /etc/systemd/network/70-eth0.link | cut -d= -f2 | sed 's/:/-/g')

curl -fsSL "http://get_web_server_name.get_ipv4_domain/ksmanager-hub/golden-boot-mac-configs/network-config-${get_mac_address_path}" -o "/root/network-config-$get_mac_address_path"

source "/root/network-config-$get_mac_address_path"

hostnamectl set-hostname "${HOST_NAME}"

/bin/mkdir -p /etc/netplan

cat << EOF > /etc/netplan/eth0.yaml
network:
    version: 2
    ethernets:
        eth0:
            dhcp4: false
            addresses: ["${IPv4_ADDRESS}"/"${IPv4_CIDR}"]
            routes:
              - to: default
                via: "${IPv4_GATEWAY}"
                on-link: true
            nameservers:
              addresses: ["${IPv4_DNS_SERVER}"]
              search: ["${IPv4_DNS_DOMAIN}"]
EOF

chmod 600 /etc/netplan/eth0.yaml

touch /root/golden-boot-ubuntu-lts-completed

systemctl disable golden-boot-ubuntu-lts.service 

reboot
