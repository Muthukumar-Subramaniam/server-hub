#!/bin/bash

if [[ "${UID}" -ne 0 ]]
then
    echo -e "${v_RED}\nRun with sudo or run from root account ! ${v_RESET}\n"
    exit 1
fi


ipv4_domain="${dnsbinder_domain}"
ipv4_network_cidr="${dnsbinder_network_cidr}"
ipv4_netmask="${dnsbinder_netmask}"
ipv4_prefix="${dnsbinder_cidr_prefix}"
ipv4_gateway="${dnsbinder_gateway}"
ipv4_nameserver="${dnsbinder_server_ipv4_address}"
ipv4_nfsserver="${dnsbinder_server_ipv4_address}"
tftp_server_name="${dnsbinder_server_short_name}"
ntp_pool_name="${dnsbinder_server_short_name}"
web_server_name="${dnsbinder_server_short_name}"
##rhel_activation_key=$(cat /server-hub/rhel-activation-key.base64 | base64 -d)
time_of_last_update=$(date | sed  "s/ /-/g")
shadow_password_super_mgmt_user=$(grep "${mgmt_super_user}" /etc/shadow | cut -d ":" -f 2)
dnsbinder_script='/server-hub/named-manage/dnsbinder.sh'
ksmanager_main_dir='/server-hub/ks-manage'
ksmanager_hub_dir="/var/www/${web_server_name}.${ipv4_domain}/ksmanager-hub"


mkdir -p "${ksmanager_hub_dir}"

while :
do
	# shellcheck disable=SC2162
	if [ -z "${1}" ]
	then
		echo -e "Create Kickstart Host Profiles for PXE-boot in \"${ipv4_domain}\" domain,\n"
		echo "Points to Keep in Mind While Entering the Hostname:"
		echo " * Please use only letters, numbers, and hyphens."
		echo " * Please do not start with a number."
		echo -e " * Please do not append the domain name \"${ipv4_domain}\" \n"
		read -r -p "Please Enter the Hostname for which Kickstarts are required : " kickstart_hostname
	else
		kickstart_hostname="${1}"
	fi

	if [[ ${kickstart_hostname} =~ ^[[:alpha:]]([-[:alnum:]]*)$ ]]
	then
    		break
  	else
    		echo  "Invalid Hostname! "
		echo "FYI:"
		echo "	1. Please use only letters, numbers, and hyphens."
		echo "	2. Please do not start with a number."
		echo -e "	3. Please do not append the domain name ${ipv4_domain} \n"
		exit 1
  	fi
done

if ! host "${kickstart_hostname}" &>/dev/null
then
	echo -e "\nNo DNS record found for \"${kickstart_hostname}\"\n"	
	while :
	do
		read -r -p "Enter (y) to create DNS record for ${kickstart_hostname} or (n) to exit the script : " v_confirmation

		if [[ "${v_confirmation}" == "y" ]]
		then
			echo -e "\nExecuting the script ${dnsbinder_script} . . .\n"
			"${dnsbinder_script}" -c "${kickstart_hostname}"

			if host "${kickstart_hostname}" &>/dev/null
			then
				echo -e "\nDNS Record for ${kickstart_hostname} created successfully! "
				echo "FYI: $(host ${kickstart_hostname})"
				echo -e "\nProceeding further . . .\n"
				break
			else
				echo -e "\nSomething went wrong while creating ${kickstart_hostname} !\n"
				exit
			fi

		elif [[ "${v_confirmation}" == "n" ]]
		then
			echo -e "\nCancelled without any changes !\n"
			exit

		else
			echo -e "\nSelect only either (y/n) !\n"
			continue

		fi
	done
else
	echo -e "\nDNS Record found for ${kickstart_hostname}!\n"
	echo "FYI: $(host ${kickstart_hostname})"

fi

# Function to validate MAC address
fn_validate_mac() {
    local mac_address_of_host="${1}"
    
    # Regex for MAC address (allowing both colon and hyphen-separated)
    if [[ "${mac_address_of_host}" =~ ^([a-fA-F0-9]{2}([-:]?)){5}[a-fA-F0-9]{2}$ ]]
    then
        return 0  # Valid MAC address
    else
        return 1  # Invalid MAC address
    fi
}

fn_convert_mac_for_grub_cfg() {
	# Convert MAC address to required format to append with grub.cfg file
	grub_cfg_mac_address=$(echo "${mac_address_of_host}" | tr ':' '-' | tr 'A-F' 'a-f')
}

fn_cache_the_mac() {
	echo -e "\nUpdating MAC address to mac-address-cache for future use . . .\n"
	sed -i "/${kickstart_hostname}/d" "${ksmanager_hub_dir}"/mac-address-cache
	echo "${kickstart_hostname} ${mac_address_of_host}" >> "${ksmanager_hub_dir}"/mac-address-cache
}

# Loop until a valid MAC address is provided

fn_get_mac_address() {
	while :
	do
    		printf "\nEnter MAC address of the VM ${kickstart_hostname} : "
		read mac_address_of_host
    		# Call the function to validate the MAC address
    		if fn_validate_mac "${mac_address_of_host}"
    		then
        		break
    		else
        		echo -e "\nInvalid MAC address provided. Please try again.\n"
    		fi
	done
}

echo -e "\nLooking up MAC Address for the host ${kickstart_hostname} from mac-address-cache . . ."

if [ ! -f "${ksmanager_hub_dir}"/mac-address-cache ]; then
	touch  "${ksmanager_hub_dir}"/mac-address-cache
fi

if grep ^"${kickstart_hostname} " "${ksmanager_hub_dir}"/mac-address-cache &>>/dev/null
then
	mac_address_of_host=$(grep ^"${kickstart_hostname} " "${ksmanager_hub_dir}"/mac-address-cache | cut -d " " -f 2 )
	echo -e "\nMAC Address ${mac_address_of_host} found for ${kickstart_hostname} in mac-address-cache! \n" 
	while :
	do
		if [[ "$2" == "--qemu-kvm" ]]; then
			fn_convert_mac_for_grub_cfg
			break
		fi
		
		read -p "Has the MAC Address ${mac_address_of_host} been changed for ${kickstart_hostname} (y/N) ? : " confirmation 

		if [[ "${confirmation}" =~ ^[Nn]$ ]] 
		then
			fn_convert_mac_for_grub_cfg
			break

		elif [[ -z "${confirmation}" ]]
		then
			fn_convert_mac_for_grub_cfg
			break

		elif [[ "${confirmation}" =~ ^[Yy]$ ]]
		then
			fn_get_mac_address
			fn_convert_mac_for_grub_cfg
			fn_cache_the_mac
			break
		else
			echo -e "\nInvalid Input! \n"
		fi
	done
else
	echo -e "\nMAC Address for ${kickstart_hostname} not found in mac-address-cache! " 
	# Check if second argument is --qemu-kvm
	if [[ "$2" == "--qemu-kvm" ]]; then
		echo -e "\nGenerating MAC Address for the QEMU/KVM VM ${kickstart_hostname} . . . \n"
		mac_address_of_host=$(printf '52:54:00:%02x:%02x:%02x\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
		fn_convert_mac_for_grub_cfg
		fn_cache_the_mac
	else
		fn_get_mac_address
		fn_convert_mac_for_grub_cfg
		fn_cache_the_mac
	fi
fi

fn_select_os_distro() {
cat << EOF

Please select OS distribution to install :

	1 ) AlmaLinux Latest
	2 ) Ubuntu-Server-LTS Latest
	3 ) OpenSUSE-Leap Latest

EOF
	read -p "Enter Option Number ( default - AlmaLinux ) : " os_distribution

	case ${os_distribution} in
		1|"") os_distribution="almalinux"
	   	   ;;
		2) os_distribution="ubuntu"
	   	   ;;
		3) os_distribution="opensuse"
	   	   ;;
		*) echo "Invalid Option!"
	   	   fn_select_os_distro
	   	   ;;
	esac
}

# shellcheck disable=SC2021
ipv4_address=$(host "${kickstart_hostname}.${ipv4_domain}" | cut -d " " -f 4 | tr -d '[[:space:]]')

disk_type_for_the_vm=$(dmidecode -t1 | awk -F: '/Manufacturer/ {
    manufacturer=tolower($2);
    gsub(/^ +| +$/, "", manufacturer);
    if (manufacturer ~ /vmware/) print "nvme0n1";
    else if (manufacturer ~ /qemu/) print "vda";
}')


host_kickstart_dir="${ksmanager_hub_dir}/kickstarts/${kickstart_hostname}.${ipv4_domain}"

mkdir -p "${host_kickstart_dir}"

rm -rf "${host_kickstart_dir}"/*



fn_select_os_distro

if [[ "${os_distribution}" == "almalinux" ]]; then
	if [ ! -f /var/lib/tftpboot/almalinux-latest/vmlinuz ]; then
		echo -e "\nSeems like AlmaLinux is not yet configured for PXE-boot environment! \n"
		exit 1
	fi
	os_name_and_version=$(grep AlmaLinux /var/www/${web_server_name}.${ipv4_domain}/almalinux-latest/.discinfo)
	rsync -avPh "${ksmanager_main_dir}"/ks-templates/almalinux-latest-ks.cfg "${host_kickstart_dir}"/ 
elif [[ "${os_distribution}" == "ubuntu" ]]; then
	if [ ! -f /var/lib/tftpboot/ubuntu-lts-latest/vmlinuz ]; then
		echo -e "\nSeems like Ubuntu-LTS is not yet configured for PXE-boot environment! \n"
		exit 1
	fi
	os_name_and_version=$(awk -F'LTS' '{print $1 "LTS"}' /var/www/${web_server_name}.${ipv4_domain}/ubuntu-lts-latest/.disk/info)
	rsync -avPh --delete "${ksmanager_main_dir}"/ks-templates/ubuntu-lts-latest-ks "${host_kickstart_dir}"/
elif [[ "${os_distribution}" == "opensuse" ]]; then
	if [ ! -f /var/lib/tftpboot/opensuse-leap-latest/linux ]; then
		echo -e "\nSeems like OpenSUSE-Leap is not yet configured for PXE-boot environment! \n"
		exit 1
	fi
	rsync -avPh "${ksmanager_main_dir}"/ks-templates/opensuse-leap-latest-autoinst.xml "${host_kickstart_dir}"/ 
fi

rsync -avPh --delete "${ksmanager_main_dir}"/addons-for-kickstarts/ "${ksmanager_hub_dir}"/addons-for-kickstarts/

rsync -avPh /etc/pki/tls/certs/"${web_server_name}.${ipv4_domain}-apache-selfsigned.crt" "${ksmanager_hub_dir}"/addons-for-kickstarts/

rsync -avPh "/home/${mgmt_super_user}/.ssh/authorized_keys" "${ksmanager_hub_dir}"/addons-for-kickstarts/

chmod +r "${ksmanager_hub_dir}"/addons-for-kickstarts/authorized_keys

echo -e "\nGenerating kickstart for ${kickstart_hostname}.${ipv4_domain} under ${host_kickstart_dir} . . .\n"

# shellcheck disable=SC2044
escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\/&$.*[\]^(){}|?+\\]/\\&/g'
}

fn_set_environment() {
	local input_dir_or_file="${1}"
	local working_file=

	fn_update_dynamic_parameters() {

		local working_file="${1}"

		sed -i "s|get_ipv4_network_cidr|${ipv4_network_cidr}|g" "${working_file}"
		sed -i "s/get_ipv4_address/${ipv4_address}/g" "${working_file}"
		sed -i "s/get_ipv4_netmask/${ipv4_netmask}/g" "${working_file}"
		sed -i "s/get_ipv4_prefix/${ipv4_prefix}/g" "${working_file}"
    		sed -i "s/get_ipv4_gateway/${ipv4_gateway}/g" "${working_file}"
		sed -i "s/get_ipv4_nameserver/${ipv4_nameserver}/g" "${working_file}"
		sed -i "s/get_ipv4_nfsserver/${ipv4_nfsserver}/g" "${working_file}"
		sed -i "s/get_ipv4_domain/${ipv4_domain}/g" "${working_file}"
    		sed -i "s/get_hostname/${kickstart_hostname}/g" "${working_file}"
		sed -i "s/get_ntp_pool_name/${ntp_pool_name}/g" "${working_file}"
		sed -i "s/get_web_server_name/${web_server_name}/g" "${working_file}" 
		sed -i "s/get_win_hostname/${win_hostname}/g" "${working_file}"
		sed -i "s/get_tftp_server_name/${tftp_server_name}.ms.local/g" "${working_file}"
		sed -i "s/get_rhel_activation_key/${rhel_activation_key}/g" "${working_file}"
		sed -i "s/get_time_of_last_update/${time_of_last_update}/g" "${working_file}"
		sed -i "s/get_mgmt_super_user/${mgmt_super_user}/g" "${working_file}"
		sed -i "s/get_os_name_and_version/${os_name_and_version}/g" "${working_file}"
		sed -i "s/get_disk_type_for_the_vm/${disk_type_for_the_vm}/g" "${working_file}"

		awk -v val="$shadow_password_super_mgmt_user" '
		{
    			gsub(/get_shadow_password_super_mgmt_user/, val)
		}
		1
		' "${working_file}" > "${working_file}"_tmp_ksmanager && mv "${working_file}"_tmp_ksmanager "${working_file}"
	}

	if [ -d "${input_dir_or_file}" ]
	then
		for working_file in $(find "${input_dir_or_file}" -type f )
		do
			fn_update_dynamic_parameters "${working_file}"
		done

	elif [ -f "${input_dir_or_file}" ]
	then
		working_file="${input_dir_or_file}"
		fn_update_dynamic_parameters "${working_file}"
	fi
}


fn_set_environment "${host_kickstart_dir}"

echo -e "\nCreating or Updating /var/lib/tftpboot/grub.cfg-01-${grub_cfg_mac_address} . . .\n"

if [[ "${os_distribution}" == "almalinux" ]]; then
	rsync -avPh "${ksmanager_main_dir}"/grub-template-almalinux-auto.cfg  /var/lib/tftpboot/grub.cfg-01-"${grub_cfg_mac_address}"
	rsync -avPh "${ksmanager_main_dir}"/grub-template-almalinux-manual.cfg /var/lib/tftpboot/grub.cfg
elif [[ "${os_distribution}" == "ubuntu" ]]; then
	rsync -avPh "${ksmanager_main_dir}"/grub-template-ubuntu-lts-auto.cfg  /var/lib/tftpboot/grub.cfg-01-"${grub_cfg_mac_address}"
	rsync -avPh "${ksmanager_main_dir}"/grub-template-ubuntu-lts-manual.cfg /var/lib/tftpboot/grub.cfg
elif [[ "${os_distribution}" == "opensuse" ]]; then
	rsync -avPh "${ksmanager_main_dir}"/grub-template-opensuse-leap-auto.cfg  /var/lib/tftpboot/grub.cfg-01-"${grub_cfg_mac_address}"
	rsync -avPh "${ksmanager_main_dir}"/grub-template-opensuse-leap-manual.cfg /var/lib/tftpboot/grub.cfg
fi

fn_set_environment "/var/lib/tftpboot/grub.cfg-01-${grub_cfg_mac_address}"

echo -e "\nCreating or Updating /var/lib/tftpboot/grub.cfg . . .\n"

fn_set_environment "/var/lib/tftpboot/grub.cfg"

chown -R ${mgmt_super_user}:${mgmt_super_user}  "${ksmanager_hub_dir}"

echo -e "\nFYI:"
echo "	Hostname     : ${kickstart_hostname}.${ipv4_domain}"
echo "	MAC Address  : ${mac_address_of_host}" 
echo "	IPv4 Address : ${ipv4_address}"
echo "	IPv4 Netmask : ${ipv4_netmask}"
echo "	IPv4 Gateway : ${ipv4_gateway}"
echo "	IPv4 Network : ${ipv4_network_cidr}"
echo "	IPv4 DNS     : ${ipv4_nameserver}"
echo "	Domain Name  : ${ipv4_domain}"
echo "	TFTP Server  : ${tftp_server_name}.${ipv4_domain}"
echo "	NTP Pool     : ${ntp_pool_name}.${ipv4_domain}"
echo "	Web Server   : ${web_server_name}.${ipv4_domain}"
echo "	KS Local     : ${host_kickstart_dir}"
echo "	KS Web       : https://${host_kickstart_dir#/var/www/}"
echo "	Requested OS : ${os_name_and_version}"

echo -e "\nAll done, You can proceed to pxeboot the host ${kickstart_hostname}\n"

exit
