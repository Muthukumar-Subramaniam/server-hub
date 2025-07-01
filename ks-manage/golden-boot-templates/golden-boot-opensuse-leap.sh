#!bash
if [ -f /root/golden-boot-opensuse-leap-completed ]; then
	exit
fi

if [ ! -f /root/golden-image-setup-completed ]; then
	exit
fi

if ! ping -c 5 get_web_server_name.get_ipv4_domain; then
	exit
fi

mkdir -p /etc/systemd/network

V_count=0
for v_interface in $(ls /sys/class/net | grep -v lo)
do
        echo -e "[Match]\nMACAddress=$(ip link | grep $v_interface -A 1 | grep link/ether | cut -d " " -f 6)\n\n[Link]\nName=eth$V_count" >/etc/systemd/network/7$V_count-eth$V_count.link
	V_count=$((V_count+1))
done

get_mac_address_path=$(grep '^MACAddress=' /etc/systemd/network/70-eth0.link | cut -d= -f2 | sed 's/:/-/g')

curl -fsSL "http://get_web_server_name.get_ipv4_domain/ksmanager-hub/golden-boot-mac-configs/network-config-${get_mac_address_path}" -o "/root/network-config-$get_mac_address_path"

source "/root/network-config-$get_mac_address_path"

hostnamectl set-hostname "${HOST_NAME}"

cat << EOF > /etc/sysconfig/network/ifcfg-eth0
IPADDR='${IPv4_ADDRESS}/${IPv4_CIDR}'
BOOTPROTO='static'
STARTMODE='auto'
ZONE=public
EOF

cat << EOF > /etc/sysconfig/network/ifroute-eth0
default ${IPv4_GATEWAY} - eth0
EOF

cat << EOF > /etc/sysctl.d/hostname.conf
kernel.hostname=${HOST_NAME}
EOF

ssh-keygen -A

touch /root/golden-boot-opensuse-leap-completed

systemctl disable golden-boot-opensuse-leap.service 

reboot
