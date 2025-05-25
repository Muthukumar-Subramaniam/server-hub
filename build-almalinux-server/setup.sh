#!/bin/bash
vars_file="server_vars.yaml"
>"${vars_file}"
echo "mgmt_user: \"$USER\"" >> "${vars_file}"
echo "shadow_pass_mgmt_user: \"$(sudo grep $USER /etc/shadow | cut -d ":" -f2)\"" >> "${vars_file}"
sed -i "/remote_user/c\remote_user=$USER" ansible.cfg 
