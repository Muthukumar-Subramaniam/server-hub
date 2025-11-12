#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

if [[ $UID -eq 0 ]]; then
	echo -e "\nPlease do not run as root or with sudo, directly run the script from user who has sudo access! \n"
	exit 1
fi

if command -v ansible &>/dev/null; then
	echo -e "\nAnsible is already installed, Proceeding further . . .\n"
else
	echo -e "\nInstalling Ansible . . . \n"
	sudo dnf install python3-pip python3-cryptography -y
	pip3 install packaging
	pip3 install --user ansible
	pip3 install argcomplete
	activate-global-python-argcomplete
	echo "## Completed Ansible Installation ##"
fi

echo -e "\nAdd password-less sudo access for $USER . . . \n"
mgmt_super_user=$USER
echo "${mgmt_super_user} ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/${mgmt_super_user} &>/dev/null

echo -e "\nSetting up some custom global vars . . .\n"

if ! grep -q mgmt_super_user /etc/environment;then
	echo "mgmt_super_user=\"${mgmt_super_user}\"" | sudo tee -a /etc/environment &>/dev/null
fi

# Set mgmt_interface_name in environment
if ! grep -q mgmt_interface_name /etc/environment; then
  echo "mgmt_interface_name=\"eth0\"" | sudo tee -a /etc/environment &>/dev/null
fi

# Set default_linux_distro_iso_path in environment
if ! grep -q default_linux_distro_iso_path /etc/environment; then
  echo "default_linux_distro_iso_path=\"/dev/sr0\"" | sudo tee -a /etc/environment &>/dev/null
fi

# Backup environment file
sudo cp -p /etc/environment /root/environment_bkp_$(date +%F)

echo -e "\nSetting Up ansible.cfg . . . \n"

sed -i "/remote_user/c\remote_user=$USER" ansible.cfg 

echo -e "\nSetting up local dns domain with dnsbinder . . .\n"

input_domain_to_dnsbinder=$(sudo bash -c '[[ -f /root/infra_server_on_qemu_kvm_dnsbinder_domain_provided ]] && cat /root/infra_server_on_qemu_kvm_dnsbinder_domain_provided')

sudo bash /server-hub/named-manage/dnsbinder.sh --setup "${input_domain_to_dnsbinder}"

source /etc/environment

echo -e "\nSetting motd . . .\n"

cat << EOF | sudo tee /etc/motd &>/dev/null
+-------------------------------------------------------------+
|               Welcome to your Lab Infra Server              |
+-------------------------------------------------------------+
| This host provisions and manages all lab hosts.             |
| All essential services for your lab environment run here.   |
| It is critical to the lab — please handle with care.        |
| Automation toolkits are available to manage the lab.        |
+-------------------------------------------------------------+
| Have a bug report, suggestion, or query? Drop it here:      |
| https://github.com/Muthukumar-Subramaniam/server-hub/issues |
+-------------------------------------------------------------+
EOF

echo -e "\nReserve Records for DHCP lease DNS . . .\n"

for IP in $(seq 201 254)
do 
	sudo bash /server-hub/named-manage/dnsbinder.sh -ci dhcp-lease${IP} ${dnsbinder_last24_subnet}.${IP}
done

echo -e "\nUpdate Network Interface to conventional naming . . .\n"

if ! ip link | grep -q eth0; then

	sudo mkdir -p /etc/systemd/network
	V_count=0
	for v_interface in $(ls /sys/class/net | grep -v lo)
	do
        	echo -e "[Match]\nMACAddress=$(ip link | grep $v_interface -A 1 | grep link/ether | cut -d " " -f 6)\n\n[Link]\nName=eth$V_count" | sudo tee /etc/systemd/network/7$V_count-eth$V_count.link
	V_count=$((V_count+1))
	done

	sudo mkdir -p /root/system-connections/orig-during-install

	sudo cp -a /etc/NetworkManager/system-connections/* /root/system-connections/orig-during-install/

	v_count=0
	for v_interface_file in $(ls /etc/NetworkManager/system-connections/)
	do
        	sudo mv /etc/NetworkManager/system-connections/$v_interface_file /etc/NetworkManager/system-connections/eth$v_count.nmconnection
        	v_interface=$(echo $v_interface_file | /bin/cut -d "." -f 1)
        	sudo sed -i "s/$v_interface/eth$v_count/g" /etc/NetworkManager/system-connections/eth$v_count.nmconnection
        	v_count=$((v_count+1))
	done

	sudo mv /etc/NetworkManager/system-connections/eth* /root/system-connections

	sudo rm -rf /etc/NetworkManager/system-connections/*

	sudo cp -a /root/system-connections/. /etc/NetworkManager/system-connections/.

	sudo rm -rf /etc/NetworkManager/system-connections/orig-during-install
fi

echo -e "\nDisabling SELinux . . .\n"

sudo grubby --update-kernel ALL --args selinux=0

echo -e "\nRemove crashkernel memory reserve if present . . .\n"

sudo grubby --update-kernel ALL --remove-args=crashkernel

if [[ "$1" != "--invoked-by-automation" ]]; then
    echo -e "\nPlease reboot the server if you did not face any issue with setup script ! \n"
    echo -e "\nAfter Reboot you can ansible playbook build-server.yaml to setup the system ! \n" 
fi
