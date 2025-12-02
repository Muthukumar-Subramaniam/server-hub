#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh

if [[ "$EUID" -ne 0 ]]; then
	if [[ "$USER" == "$mgmt_super_user" ]]; then
		print_error "[ERROR] Please run this tool using 'sudo' — direct execution is not allowed."
	    	exit 1
    	else
		print_error "[ERROR] Access denied. Only infra management super user '${mgmt_super_user}' is authorized to run this tool."
    		exit 1
    	fi
fi

if [[ "$(id -un)" == "root" && "$SUDO_USER" != "${mgmt_super_user}" ]]; then
	print_error "[ERROR] Access denied. Only infra management super user '${mgmt_super_user}' is authorized to run this tool with 'sudo'."
	exit 1
fi

script_name="$(basename "$0")"
if [[ "$SUDO_COMMAND" != *"$script_name"* ]]; then
	print_error "[ERROR] Direct root execution is not allowed. Only infra management super user '${mgmt_super_user}' can run this tool with sudo."
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
nfs_server_name="${dnsbinder_server_short_name}"
ntp_pool_name="${dnsbinder_server_short_name}"
web_server_name="${dnsbinder_server_short_name}"
##rhel_activation_key=$(cat /server-hub/rhel-activation-key.base64 | base64 -d)
time_of_last_update=$(date | sed  "s/ /-/g")
dnsbinder_script='/server-hub/named-manage/dnsbinder.sh'
ksmanager_main_dir='/server-hub/ks-manage'
ksmanager_hub_dir="/${web_server_name}.${ipv4_domain}/ksmanager-hub"
ipxe_web_dir="/${web_server_name}.${ipv4_domain}/ipxe"
shadow_password_super_mgmt_user=$(grep "${mgmt_super_user}" /etc/shadow | cut -d ":" -f 2)
if [ -d "/kvm-hub" ]; then
	if [ -f "/kvm-hub/lab_environment_vars" ]; then
		source /kvm-hub/lab_environment_vars
		shadow_password_super_mgmt_user=$lab_admin_shadow_password
	fi
fi
subnets_to_allow_ssh_pub_access=""
for i in $(seq ${dnsbinder_first24_subnet##*.} ${dnsbinder_last24_subnet##*.}); do
    subnets_to_allow_ssh_pub_access+=" ${dnsbinder_first24_subnet%.*}.$i.*"
done
subnets_to_allow_ssh_pub_access="${subnets_to_allow_ssh_pub_access# }"

mkdir -p "${ksmanager_hub_dir}"
mkdir -p "${ipxe_web_dir}"

fn_check_and_create_host_record() {
	while :
	do
		# shellcheck disable=SC2162
		if [ -z "${1}" ]
		then
			print_info "[INFO] Create kickstart host profiles for PXE boot."
			print_info "[INFO] Points to keep in mind while entering the hostname:"
    		print_info "[INFO] - Use only lowercase letters, numbers, and hyphens (-)."
    		print_info "[INFO] - Must not start or end with a hyphen."
			read -r -p "Please enter the hostname for which kickstarts are required: " kickstart_hostname
		else
			kickstart_hostname="${1}"
		fi

		# Validate and normalize hostname to FQDN
		if [[ "${kickstart_hostname}" == *.${ipv4_domain} ]]; then
			local stripped_hostname="${kickstart_hostname%.${ipv4_domain}}"
			# Verify the stripped part doesn't contain dots (ensure it's just hostname.domain, not host.something.domain)
			if [[ "${stripped_hostname}" == *.* ]]; then
				print_error "[ERROR] Invalid hostname. Expected format: hostname.${ipv4_domain}"
				exit 1
			fi
			# Validate the hostname part
			if [[ ! "${stripped_hostname}" =~ ^[a-z0-9-]+$ || "${stripped_hostname}" =~ ^- || "${stripped_hostname}" =~ -$ ]]; then
				print_error "[ERROR] Invalid hostname. Use only lowercase letters, numbers, and hyphens."
				print_info "[INFO] Hostname must not start or end with a hyphen."
				exit 1
			fi
			# Keep as FQDN
		elif [[ "${kickstart_hostname}" == *.* ]]; then
			print_error "[ERROR] Invalid domain. Expected domain: ${ipv4_domain}"
			exit 1
		else
			# Bare hostname provided - validate and convert to FQDN
			if [[ ! "${kickstart_hostname}" =~ ^[a-z0-9-]+$ || "${kickstart_hostname}" =~ ^- || "${kickstart_hostname}" =~ -$ ]]; then
				print_error "[ERROR] Invalid hostname. Use only lowercase letters, numbers, and hyphens."
				print_info "[INFO] Hostname must not start or end with a hyphen."
				exit 1
			fi
			kickstart_hostname="${kickstart_hostname}.${ipv4_domain}"
		fi

		break
	done

	# Extract short hostname for use with tools that need it
	kickstart_short_hostname="${kickstart_hostname%%.*}"

	if ! host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" &>/dev/null
	then
		print_error "[ERROR] No DNS record found for \"${kickstart_hostname}\"."
		while :
		do
			read -r -p "Enter (y) to create a DNS record for \"${kickstart_hostname}\" or (n) to exit: " v_confirmation

			if [[ "${v_confirmation}" == "y" ]]
			then
				print_info "[INFO] Creating DNS record for \"${kickstart_hostname}\" using dnsbinder..."
				"${dnsbinder_script}" -c "${kickstart_hostname}"

				if host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" &>/dev/null
				then
					print_info "[INFO] Proceeding with kickstart creation..."
					break
				else
					print_error "[ERROR] Failed to create DNS record for \"${kickstart_hostname}\"."
					exit 1
				fi

			elif [[ "${v_confirmation}" == "n" ]]
			then
				print_info "[INFO] Operation cancelled by user."
				exit
			else
				print_warning "[WARNING] Invalid input. Please enter 'y' or 'n'."
				continue
			fi
		done
	else
		print_success "[SUCCESS] DNS record found for \"${kickstart_hostname}\"."
		print_info "[INFO] $(host ${kickstart_hostname} ${dnsbinder_server_ipv4_address} | grep 'has address')"
	fi
}

golden_image_creation_not_requested=true

for input_arguement in "$@"; do
    if [[ "$input_arguement" == "--create-golden-image" ]]; then
	golden_image_creation_not_requested=false
        break
    fi
done

if $golden_image_creation_not_requested; then
	fn_check_and_create_host_record "${1}"
	ipv4_address=$(host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" | grep 'has address' | cut -d " " -f 4 | tr -d '[[:space:]]')
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

fn_convert_mac_for_ipxe_cfg() {
	# Convert MAC address to required format to append with ipxe.cfg file
	ipxe_cfg_mac_address=$(echo "${mac_address_of_host}" | tr ':' '-' | tr 'A-F' 'a-f')
}

fn_cache_the_mac() {
	print_info "[INFO] Updating MAC address to cache for future use..."
	sed -i "/${kickstart_hostname}/d" "${ksmanager_hub_dir}"/mac-address-cache
	echo "${kickstart_hostname} ${mac_address_of_host} ${ipv4_address}" >> "${ksmanager_hub_dir}"/mac-address-cache
}

# Loop until a valid MAC address is provided

fn_get_mac_address() {
	while :
	do
		echo -n "Enter the MAC address of the VM \"${kickstart_hostname}\": "
		read mac_address_of_host
    		# Call the function to validate the MAC address
    		if fn_validate_mac "${mac_address_of_host}"
    		then
        		break
    		else
			print_error "[ERROR] Invalid MAC address provided. Please try again."
    		fi
	done
}

invoked_with_qemu_kvm=false
for input_arguement in "$@"; do
    if [[ "$input_arguement" == "--qemu-kvm" ]]; then
        invoked_with_qemu_kvm=true
        break
    fi
done

invoked_with_golden_image=false
for input_arguement in "$@"; do
    if [[ "$input_arguement" == "--golden-image" ]]; then
        invoked_with_golden_image=true
        break
    fi
done

fn_check_and_create_mac_if_required() {

print_info "[INFO] Looking up MAC address for host \"${kickstart_hostname}\" from cache..."

if [ ! -f "${ksmanager_hub_dir}"/mac-address-cache ]; then
	touch  "${ksmanager_hub_dir}"/mac-address-cache
fi

if grep ^"${kickstart_hostname} " "${ksmanager_hub_dir}"/mac-address-cache &>/dev/null
then
	mac_address_of_host=$(grep ^"${kickstart_hostname} " "${ksmanager_hub_dir}"/mac-address-cache | cut -d " " -f 2 )

	print_success "[SUCCESS] MAC Address ${mac_address_of_host} found for ${kickstart_hostname} in cache."
	while :
	do
		if $invoked_with_qemu_kvm; then
			fn_convert_mac_for_ipxe_cfg
			break
		fi
		
		read -p "Has the MAC Address ${mac_address_of_host} been changed for ${kickstart_hostname} (y/N)? : " confirmation 

		if [[ "${confirmation}" =~ ^[Nn]$ ]] 
		then
			fn_convert_mac_for_ipxe_cfg
			break

		elif [[ -z "${confirmation}" ]]
		then
			fn_convert_mac_for_ipxe_cfg
			break

		elif [[ "${confirmation}" =~ ^[Yy]$ ]]
		then
			fn_get_mac_address
			fn_convert_mac_for_ipxe_cfg
			fn_cache_the_mac
			break
		else
			print_warning "[WARNING] Invalid input."
		fi
	done
else
	print_info "[INFO] MAC address for \"${kickstart_hostname}\" not found in cache."
	if $invoked_with_qemu_kvm; then
		print_info "[INFO] Generating MAC address for QEMU/KVM VM \"${kickstart_hostname}\"..."
		mac_address_of_host=$(printf '52:54:00:%02x:%02x:%02x\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
		fn_convert_mac_for_ipxe_cfg
		fn_cache_the_mac
	else
		fn_get_mac_address
		fn_convert_mac_for_ipxe_cfg
		fn_cache_the_mac
	fi
fi
}

if $golden_image_creation_not_requested; then
	fn_check_and_create_mac_if_required
fi

fn_check_distro_availability() {
	local os_distribution="${1}"
	if [[ "${os_distribution}" == "opensuse-leap" ]]; then
		kernel_file_name="linux"
	else
		kernel_file_name="vmlinuz"
	fi

	if [[ ! -f "${ipxe_web_dir}/images/${os_distribution}-latest/${kernel_file_name}" ]]; then
		echo '[Not-Ready]'
	else
		echo '[Ready]'
	fi
}

almalinux_os_availability=$(fn_check_distro_availability "almalinux")
rocky_os_availability=$(fn_check_distro_availability "rocky")
oraclelinux_os_availability=$(fn_check_distro_availability "oraclelinux")
centos_stream_os_availability=$(fn_check_distro_availability "centos-stream")
rhel_os_availability=$(fn_check_distro_availability "rhel")
fedora_os_availability=$(fn_check_distro_availability "fedora")
ubuntu_lts_os_availability=$(fn_check_distro_availability "ubuntu-lts")
opensuse_leap_os_availability=$(fn_check_distro_availability "opensuse-leap")

fn_select_os_distro() {
    print_info "[INFO] Please select the OS distribution to install:
  1)  AlmaLinux                ${almalinux_os_availability}
  2)  Rocky Linux              ${rocky_os_availability}
  3)  OracleLinux              ${oraclelinux_os_availability}
  4)  CentOS Stream            ${centos_stream_os_availability}
  5)  Red Hat Enterprise Linux ${rhel_os_availability}
  6)  Fedora Linux             ${fedora_os_availability}
  7)  Ubuntu Server LTS        ${ubuntu_lts_os_availability}
  8)  openSUSE Leap Latest     ${opensuse_leap_os_availability}"

    read -p "Enter option number (default: AlmaLinux): " os_distribution

    case "${os_distribution}" in
        1 | "" ) os_distribution="almalinux" ;;
        2 )      os_distribution="rocky" ;;
        3 )      os_distribution="oraclelinux" ;;
        4 )      os_distribution="centos-stream" ;;
        5 )      os_distribution="rhel" ;;
        6 )      os_distribution="fedora" ;;
        7 )      os_distribution="ubuntu-lts" ;;
        8 )      os_distribution="opensuse-leap" ;;
	* ) print_error "[ERROR] Invalid option. Please try again."; fn_select_os_distro ;;
    esac
}

fn_select_os_distro

# Detect VM platform
manufacturer=$(dmidecode -t1 | awk -F: '/Manufacturer/ {
    gsub(/^ +| +$/, "", $2);
    print tolower($2)
}')

# Initialize variables
disk_type_for_the_vm="vda"
whether_vga_console_is_required=""

# Set values based on platform
if [[ "$manufacturer" == *vmware* ]]; then
    disk_type_for_the_vm="nvme0n1"
    whether_vga_console_is_required="console=tty0"
elif [[ "$manufacturer" == *qemu* ]]; then
    disk_type_for_the_vm="vda"
    whether_vga_console_is_required=""
fi

fn_create_host_kickstart_dir() {
	host_kickstart_dir="${ksmanager_hub_dir}/kickstarts/${kickstart_hostname}"
	mkdir -p "${host_kickstart_dir}"
	rm -rf "${host_kickstart_dir}"/*
}

if $golden_image_creation_not_requested; then
	if ! $invoked_with_golden_image; then
		fn_create_host_kickstart_dir
	fi
fi

if [[ "${os_distribution}" == "opensuse-leap" ]]; then
	kernel_file_name="linux"
else
	kernel_file_name="vmlinuz"
fi

while [ ! -f "${ipxe_web_dir}/images/${os_distribution}-latest/${kernel_file_name}" ]; do
	print_warning "[WARNING] ${os_distribution} is not yet prepared for PXE-boot environment."
	print_info "[INFO] Please use 'prepare-distro-for-ksmanager' tool to prepare ${os_distribution} for PXE-boot."
	fn_select_os_distro
done

if [[ "${os_distribution}" == "ubuntu-lts" ]]; then
	os_name_and_version=$(awk -F'LTS' '{print $1 "LTS"}' "/${web_server_name}.${ipv4_domain}/${os_distribution}-latest/.disk/info")
elif [[ "${os_distribution}" == "opensuse-leap" ]]; then
	os_name_and_version=$(awk -F ' = ' '/^\[release\]/{f=1; next} /^\[/{f=0} f && /^(name|version)/ {gsub(/^[ \t]+/, "", $2); printf "%s ", $2} END{print ""}' "/${web_server_name}.${ipv4_domain}/${os_distribution}-latest/.treeinfo")
else
	redhat_based_distro_name="${os_distribution}"
	if [[ "${os_distribution}" == "centos-stream" ]]; then
		os_name_and_version=$(grep -i "centos" "/${web_server_name}.${ipv4_domain}/${os_distribution}-latest/.discinfo")
	elif [[ "${os_distribution}" == "oraclelinux" ]]; then
		os_name_and_version=$(grep -i "oracle" "/${web_server_name}.${ipv4_domain}/${os_distribution}-latest/.discinfo")
	elif [[ "${os_distribution}" == "rhel" ]]; then
		os_name_and_version=$(grep -i "Red Hat" "/${web_server_name}.${ipv4_domain}/${os_distribution}-latest/.discinfo")
	else
		os_name_and_version=$(grep -i "${os_distribution}" "/${web_server_name}.${ipv4_domain}/${os_distribution}-latest/.discinfo")
	fi
fi

if ! $golden_image_creation_not_requested; then
	fn_check_and_create_host_record "${os_distribution}-golden-image"
	ipv4_address=$(host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" | grep 'has address' | cut -d " " -f 4 | tr -d '[[:space:]]')
	fn_check_and_create_mac_if_required
	fn_create_host_kickstart_dir
fi

if ! $invoked_with_golden_image; then
	if [[ "${os_distribution}" == "opensuse-leap" ]]; then
		if [[ ! -z "${whether_vga_console_is_required}" ]]; then
			rsync -a -q "${ksmanager_main_dir}/ks-templates/${os_distribution}-latest-autoinst-vmware.xml" "${host_kickstart_dir}/${os_distribution}-latest-autoinst.xml" 
		else
			rsync -a -q "${ksmanager_main_dir}/ks-templates/${os_distribution}-latest-autoinst.xml" "${host_kickstart_dir}/${os_distribution}-latest-autoinst.xml" 
		fi
	elif [[ "${os_distribution}" == "ubuntu-lts" ]]; then 
		rsync -a -q --delete "${ksmanager_main_dir}/ks-templates/${os_distribution}-latest-ks" "${host_kickstart_dir}"/
	else
		if [[ "${os_distribution}" == "fedora" ]]; then
			rsync -a -q "${ksmanager_main_dir}/ks-templates/fedora-latest-ks.cfg" "${host_kickstart_dir}"/ 
		else
			rsync -a -q "${ksmanager_main_dir}/ks-templates/redhat-based-latest-ks.cfg" "${host_kickstart_dir}"/ 
		fi
	fi
	if ! $golden_image_creation_not_requested; then
		if [[ -z "${redhat_based_distro_name}" ]]; then
			rsync -a -q "${ksmanager_main_dir}/golden-boot-templates/golden-boot-${os_distribution}.service" "${host_kickstart_dir}"/ 
			rsync -a -q "${ksmanager_main_dir}/golden-boot-templates/golden-boot-${os_distribution}.sh" "${host_kickstart_dir}"/ 
		else
			rsync -a -q "${ksmanager_main_dir}/golden-boot-templates/golden-boot-redhat-based.service" "${host_kickstart_dir}"/ 
			rsync -a -q "${ksmanager_main_dir}/golden-boot-templates/golden-boot-redhat-based.sh" "${host_kickstart_dir}"/ 
		fi
	fi
fi

if ! $invoked_with_golden_image; then

	print_info "[INFO] Generating kickstart profile and iPXE configs for PXE boot of VM '${kickstart_hostname}'..."

	rsync -a -q --delete "${ksmanager_main_dir}"/addons-for-kickstarts/ "${ksmanager_hub_dir}"/addons-for-kickstarts/

	rsync -a -q /home/${mgmt_super_user}/.ssh/{authorized_keys,kvm_lab_global_id_rsa.pub,kvm_lab_global_id_rsa} "${ksmanager_hub_dir}"/addons-for-kickstarts/

	chmod +r "${ksmanager_hub_dir}"/addons-for-kickstarts/{authorized_keys,kvm_lab_global_id_rsa.pub,kvm_lab_global_id_rsa}

	mkdir -p "${ksmanager_hub_dir}"/golden-boot-mac-configs
fi

if $invoked_with_golden_image; then

	print_info "[INFO] Generating network configs for golden boot installation of VM '${kickstart_hostname}'..."

	rsync -a -q "${ksmanager_main_dir}"/golden-boot-templates/network-config-for-mac-address "${ksmanager_hub_dir}"/golden-boot-mac-configs/network-config-"${ipxe_cfg_mac_address}"

fi

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
    	sed -i "s/get_hostname/${kickstart_short_hostname}/g" "${working_file}"
		sed -i "s/get_ntp_pool_name/${ntp_pool_name}/g" "${working_file}"
		sed -i "s/get_web_server_name/${web_server_name}/g" "${working_file}" 
		sed -i "s/get_win_hostname/${win_hostname}/g" "${working_file}"
		sed -i "s/get_tftp_server_name/${tftp_server_name}.${ipv4_domain}/g" "${working_file}"
		sed -i "s/get_nfs_server_name/${nfs_server_name}.${ipv4_domain}/g" "${working_file}"
		sed -i "s/get_rhel_activation_key/${rhel_activation_key}/g" "${working_file}"
		sed -i "s/get_time_of_last_update/${time_of_last_update}/g" "${working_file}"
		sed -i "s/get_mgmt_super_user/${mgmt_super_user}/g" "${working_file}"
		sed -i "s/get_os_name_and_version/${os_name_and_version}/g" "${working_file}"
		sed -i "s/get_disk_type_for_the_vm/${disk_type_for_the_vm}/g" "${working_file}"
		sed -i "s/get_whether_vga_console_is_required/${whether_vga_console_is_required}/g" "${working_file}"
	 	sed -i "s/get_golden_image_creation_not_requested/$golden_image_creation_not_requested/g" "${working_file}"
	 	sed -i "s/get_redhat_based_distro_name/$redhat_based_distro_name/g" "${working_file}"
	 	sed -i "s/get_subnets_to_allow_ssh_pub_access/${subnets_to_allow_ssh_pub_access}/g" "${working_file}"

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

if ! $invoked_with_golden_image; then

	fn_set_environment "${host_kickstart_dir}"
	mac_based_ipxe_cfg_file="${ipxe_web_dir}/${ipxe_cfg_mac_address}.ipxe"

	if [[ -z "${redhat_based_distro_name}" ]]; then
            rsync -a -q "${ksmanager_main_dir}/ipxe-templates/ipxe-template-${os_distribution}-auto.ipxe"  "${mac_based_ipxe_cfg_file}"
	else
	    rsync -a -q "${ksmanager_main_dir}/ipxe-templates/ipxe-template-redhat-based-auto.ipxe"  "${mac_based_ipxe_cfg_file}"
	    if [[ "${os_distribution}" == "fedora" ]]; then
		    sed -i "s/redhat-based/fedora/g" "${mac_based_ipxe_cfg_file}"
	    fi
	fi

	fn_set_environment "${mac_based_ipxe_cfg_file}"

fi

if $invoked_with_golden_image; then
	fn_set_environment "${ksmanager_hub_dir}"/golden-boot-mac-configs/network-config-"${ipxe_cfg_mac_address}"
fi

chown -R ${mgmt_super_user}:${mgmt_super_user}  "${ksmanager_hub_dir}"

fn_update_kea_dhcp_reservations() {
  print_info "[INFO] Updating IPv4 reservations with kea-dhcp server..."
  local kea_cache_file="${ksmanager_hub_dir}/mac-address-cache"
  local kea_config_file="/etc/kea/kea-dhcp4.conf"
  local kea_api_url="http://127.0.0.1:8000/"
  local kea_api_auth="kea-api:kea-api-password"
  local kea_temp_config_timestamp=$(date +"%Y%m%d_%H%M%S_%Z")
  local kea_config_temp_dir="${ksmanager_hub_dir}/kea_dhcp_temp_configs_with_reservation"
  local kea_tmp_config="${kea_config_temp_dir}/kea-dhcp4.conf_${kea_temp_config_timestamp}"

  mkdir -p "$kea_config_temp_dir"

  current_ip_with_mac=$(grep ^"${kickstart_hostname} " "${kea_cache_file}" | cut -d " " -f 3 )
  if [[ "${current_ip_with_mac}" != "${ipv4_address}" ]]; then
    sed -i "/^${kickstart_hostname} / s/${current_ip_with_mac}/${ipv4_address}/" "${kea_cache_file}"
  fi

  # Read existing Kea config
  local kea_existing_config
  kea_existing_config=$(cat "$kea_config_file")

  # Build JSON array of reservations from cache file
  local kea_reservations_json=""
  while read -r kea_hostname kea_hw_address kea_ip_address; do
    kea_reservations_json+="{
      \"hostname\": \"$kea_hostname\",
      \"hw-address\": \"$kea_hw_address\",
      \"ip-address\": \"$kea_ip_address\"
    },"
  done < "$kea_cache_file"

  kea_reservations_json="[${kea_reservations_json%,}]"

  # Insert reservations into config JSON
  local kea_new_config
  kea_new_config=$(echo "$kea_existing_config" | \
    jq --argjson reservations "$kea_reservations_json" \
      '.Dhcp4.subnet4[0].reservations = $reservations')

  # Wrap into config-set command for Kea Control Agent
  cat > "$kea_tmp_config" <<EOF
{
  "command": "config-set",
  "service": [ "dhcp4" ],
  "arguments": $kea_new_config
}
EOF

  chown ${mgmt_super_user}:${mgmt_super_user}  "${kea_tmp_config}"

  # Delete old lease (safe if none exists)
  curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
    -d "{
          \"command\": \"lease4-del\",
          \"service\": [ \"dhcp4\" ],
          \"arguments\": {
            \"hw-address\": \"${mac_address_of_host}\"
          }
        }" \
  "$kea_api_url" &>/dev/null

  # Delete lease by IP (safe if none exists)
  curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
    -d "{
          \"command\": \"lease4-del\",
          \"service\": [ \"dhcp4\" ],
          \"arguments\": {
            \"ip-address\": \"${ipv4_address}\"
          }
        }" \
   "$kea_api_url" &>/dev/null

  # Push new config dynamically
  curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
    -d @"$kea_tmp_config" \
    "$kea_api_url" &>/dev/null
}

if systemctl is-active --quiet kea-ctrl-agent; then
	fn_update_kea_dhcp_reservations
fi

if ! $invoked_with_golden_image; then
	print_info "[INFO] Configuration Summary:
  ✓ Hostname     : ${kickstart_hostname}
  ✓ MAC Address  : ${mac_address_of_host}
  ✓ IPv4 Address : ${ipv4_address}
  ✓ IPv4 Netmask : ${ipv4_netmask}
  ✓ IPv4 Gateway : ${ipv4_gateway}
  ✓ IPv4 Network : ${ipv4_network_cidr}
  ✓ IPv4 DNS     : ${ipv4_nameserver}
  ✓ Domain Name  : ${ipv4_domain}
  ✓ NTP Pool     : ${ntp_pool_name}.${ipv4_domain}
  ✓ Web Server   : ${web_server_name}.${ipv4_domain}
  ✓ NFS Server   : ${nfs_server_name}.${ipv4_domain}
  ✓ DHCP Server  : ${tftp_server_name}.${ipv4_domain}
  ✓ TFTP Server  : ${tftp_server_name}.${ipv4_domain}
  ✓ KS Local     : ${host_kickstart_dir}
  ✓ KS Web       : https://${host_kickstart_dir#/}
  ✓ Requested OS : ${os_name_and_version}
"
	print_success "[SUCCESS] All done! You can proceed with installation of '${kickstart_hostname}' using PXE boot."
else
	print_info "[INFO] Configuration Summary:
  ✓ Hostname     : ${kickstart_hostname}
  ✓ MAC Address  : ${mac_address_of_host}
  ✓ IPv4 Address : ${ipv4_address}
  ✓ IPv4 Netmask : ${ipv4_netmask}
  ✓ IPv4 Gateway : ${ipv4_gateway}
  ✓ IPv4 Network : ${ipv4_network_cidr}
  ✓ IPv4 DNS     : ${ipv4_nameserver}
  ✓ Domain Name  : ${ipv4_domain}
  ✓ NTP Pool     : ${ntp_pool_name}.${ipv4_domain}
  ✓ Web Server   : ${web_server_name}.${ipv4_domain}
  ✓ NFS Server   : ${nfs_server_name}.${ipv4_domain}
  ✓ Requested OS : ${os_name_and_version}
"
	print_success "[SUCCESS] All done! You can proceed with installation of '${kickstart_hostname}' using golden image."
fi

exit
