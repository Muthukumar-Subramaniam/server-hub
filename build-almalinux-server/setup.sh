#!/bin/bash
if command -v ansible &>/dev/null; then
	echo "Ansible is already installed, Proceeding further . . ."
else
	echo -e "\nInstalling Ansible . . . \n"
	curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
	python3 get-pip.py --user
	pip3 install packaging
	pip3 install --user ansible
	pip3 install argcomplete
	activate-global-python-argcomplete
	rm get-pip.py
	echo "## Completed Ansible Installation ##"
fi

echo -e "\nSetting Up Variables for the build-server playbook . . . \n"
vars_file="server_vars.yaml"
>"${vars_file}"
echo "mgmt_user: \"$USER\"" >> "${vars_file}"
echo "shadow_pass_mgmt_user: \"$(sudo grep $USER /etc/shadow | cut -d ":" -f2)\"" >> "${vars_file}"
sed -i "/remote_user/c\remote_user=$USER" ansible.cfg 
