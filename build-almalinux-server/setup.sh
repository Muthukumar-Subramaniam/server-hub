#!/bin/bash
source /etc/os-release
almalinux_major_version="${VERSION_ID%%.*}"

if command -v ansible &>/dev/null; then
	echo "Ansible is already installed, Proceeding further . . ."
else
	echo -e "\nInstalling Ansible . . . \n"
#	curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
#	python3 get-pip.py --user
	sudo dnf install python3-pip -y
	pip3 install packaging
	pip3 install --user ansible
	pip3 install argcomplete
	activate-global-python-argcomplete
	rm get-pip.py
	echo "## Completed Ansible Installation ##"
fi

echo "\nAdd password-less sudo access for $USER . . . \n"
mgmt_super_user=$USER

echo "${mgmt_super_user} ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/${mgmt_super_user}
echo "mgmt_super_user=\"${mgmt_super_user}\"" | sudo tee -a /etc/environment
echo "almalinux_major_version=\"${almalinux_major_version}\"" | sudo tee -a /etc/environment

echo -e "\nSetting Up ansible.cfg . . . \n"
sed -i "/remote_user/c\remote_user=$USER" ansible.cfg 

echo -e "\nSetting up local dns domain with dnsbinder . . .\n"

sudo bash /server-hub/named-manage/dnsbinder.sh

echo -e "\nPlease reboot the server if you did not face any issue with setup script ! \n"
