#!/bin/bash
if [ -f /root/golden-boot-almalinux-completed ]; then
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

nmcli connection add type ethernet ifname eth0 con-name eth0 \
  ipv4.addresses "${IPv4_ADDRESS}"/"${IPv4_CIDR}" \
  ipv4.gateway "${IPv4_GATEWAY}" \
  ipv4.dns "${IPv4_DNS_SERVER}" \
  ipv4.dns-search "${IPv4_DNS_DOMAIN}" \
  ipv4.method manual \

mkdir -p /root/system-connections/orig-during-install

/bin/rsync -avPh /etc/NetworkManager/system-connections/* /root/system-connections/orig-during-install/

v_count=0
for v_interface_file in $(/bin/ls /etc/NetworkManager/system-connections/)
do
        /bin/mv /etc/NetworkManager/system-connections/$v_interface_file /etc/NetworkManager/system-connections/eth$v_count.nmconnection
        v_interface=$(/bin/echo $v_interface_file | /bin/cut -d "." -f 1)
        /bin/sed -i "s/$v_interface/eth$v_count/g" /etc/NetworkManager/system-connections/eth$v_count.nmconnection
        v_count=$((v_count+1))
done

/bin/mv /etc/NetworkManager/system-connections/eth* /root/system-connections

/bin/rm -rf /etc/NetworkManager/system-connections/*

/bin/rsync -avPh /root/system-connections/* /etc/NetworkManager/system-connections/.

/bin/rm -rf /etc/NetworkManager/system-connections/orig-during-install

touch /root/golden-boot-almalinux-completed

systemctl disable golden-boot-almalinux.service 

reboot
