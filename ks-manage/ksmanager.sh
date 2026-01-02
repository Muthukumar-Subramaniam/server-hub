#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /etc/environment
source /server-hub/common-utils/color-functions.sh
source /server-hub/ks-manage/distro-versions.conf

if [[ -z "$mgmt_super_user" ]]; then
	print_error "Critical: mgmt_super_user is not defined in /etc/environment."
	print_error "Please ensure the environment is properly configured."
	exit 1
fi

if [[ "$USER" != "$mgmt_super_user" ]]; then
	print_error "Access denied. Only infra management super user '${mgmt_super_user}' is authorized to run this tool."
	print_error "Also if the user itself is ${mgmt_super_user}, Please do not elevate access again with sudo.\n"
    	exit 1
fi

ipv4_domain="${dnsbinder_domain}"
ipv4_network_cidr="${dnsbinder_network_cidr}"
ipv4_netmask="${dnsbinder_netmask}"
ipv4_prefix="${dnsbinder_cidr_prefix}"
ipv4_gateway="${dnsbinder_gateway}"
ipv4_nameserver="${dnsbinder_server_ipv4_address}"
ipv4_nfsserver="${dnsbinder_server_ipv4_address}"
lab_infra_server_hostname="${dnsbinder_server_fqdn}"

# IPv6 variables (if dual-stack configured)
ipv6_gateway="${dnsbinder_ipv6_gateway}"
ipv6_prefix="${dnsbinder_ipv6_prefix}"
ipv6_ula_subnet="${dnsbinder_ipv6_ula_subnet}"
ipv6_address=""  # Will be queried from DNS
##rhel_activation_key=$(cat /server-hub/rhel-activation-key.base64 | base64 -d)
time_of_last_update=$(date +"%Y-%m-%d_%H-%M-%S_%Z")
dnsbinder_script='/server-hub/named-manage/dnsbinder.sh'
ksmanager_main_dir='/server-hub/ks-manage'
ksmanager_hub_dir="/${lab_infra_server_hostname}/ksmanager-hub"
ipxe_web_dir="/${lab_infra_server_hostname}/ipxe"
shadow_password_super_mgmt_user=$(sudo grep "${mgmt_super_user}" /etc/shadow | cut -d ":" -f 2)
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
			print_info "Create kickstart host profiles for PXE boot."
			print_info "Points to keep in mind while entering the hostname:"
    		print_info "- Use only lowercase letters, numbers, and hyphens (-)."
    		print_info "- Must not start or end with a hyphen."
			read -r -p "Please enter the hostname for which kickstarts are required: " kickstart_hostname
		else
			kickstart_hostname="${1}"
		fi

		# Validate and normalize hostname to FQDN
		if [[ "${kickstart_hostname}" == *.${ipv4_domain} ]]; then
			local stripped_hostname="${kickstart_hostname%.${ipv4_domain}}"
			# Verify the stripped part doesn't contain dots (ensure it's just hostname.domain, not host.something.domain)
			if [[ "${stripped_hostname}" == *.* ]]; then
				print_error "Invalid hostname. Expected format: hostname.${ipv4_domain}"
				exit 1
			fi
			# Validate the hostname part
			if [[ ! "${stripped_hostname}" =~ ^[a-z0-9-]+$ || "${stripped_hostname}" =~ ^- || "${stripped_hostname}" =~ -$ ]]; then
				print_error "Invalid hostname. Use only lowercase letters, numbers, and hyphens."
				print_info "Hostname must not start or end with a hyphen."
				exit 1
			fi
			# Keep as FQDN
		elif [[ "${kickstart_hostname}" == *.* ]]; then
			print_error "Invalid domain. Expected domain: ${ipv4_domain}"
			exit 1
		else
			# Bare hostname provided - validate and convert to FQDN
			if [[ ! "${kickstart_hostname}" =~ ^[a-z0-9-]+$ || "${kickstart_hostname}" =~ ^- || "${kickstart_hostname}" =~ -$ ]]; then
				print_error "Invalid hostname. Use only lowercase letters, numbers, and hyphens."
				print_info "Hostname must not start or end with a hyphen."
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
		print_info "No DNS record found for \"${kickstart_hostname}\"."
		
		if $invoked_with_qemu_kvm; then
			sudo "${dnsbinder_script}" -c "${kickstart_hostname}"

			if ! host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" &>/dev/null; then
				print_error "Failed to create DNS record for \"${kickstart_hostname}\"."
				exit 1
			fi
		else
			while :
			do
				read -r -p "Enter (y) to create a DNS record for \"${kickstart_hostname}\" or (n) to exit: " v_confirmation

				if [[ "${v_confirmation}" == "y" ]]
				then
					sudo "${dnsbinder_script}" -c "${kickstart_hostname}"

					if ! host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" &>/dev/null; then
						print_error "Failed to create DNS record for \"${kickstart_hostname}\"."
						exit 1
					fi
					break

				elif [[ "${v_confirmation}" == "n" ]]
				then
					print_info "Operation cancelled by user."
					exit
				else
					print_warning "Invalid input. Please enter 'y' or 'n'."
					continue
				fi
			done
		fi
	else
		print_info "DNS record found for \"${kickstart_hostname}\"."
		print_info "$(host ${kickstart_hostname} ${dnsbinder_server_ipv4_address} | grep -E 'has address|has IPv6 address')"
	fi
}

golden_image_creation_not_requested=true

for input_arguement in "$@"; do
    if [[ "$input_arguement" == "--create-golden-image" ]]; then
	golden_image_creation_not_requested=false
        break
    fi
done

# Check for --remove-host flag
remove_host_requested=false
for input_arguement in "$@"; do
    if [[ "$input_arguement" == "--remove-host" ]]; then
        remove_host_requested=true
        break
    fi
done

# If --remove-host is requested, handle cleanup and exit
if $remove_host_requested; then
    if [ -z "${1}" ] || [[ "${1}" == "--remove-host" ]]; then
        print_error "Hostname is required with --remove-host flag."
        print_info "Usage: sudo ksmanager hostname --remove-host"
        exit 1
    fi
    
    # Extract hostname from arguments (skip --remove-host)
    for arg in "$@"; do
        if [[ "$arg" != "--remove-host" ]]; then
            cleanup_hostname="$arg"
            break
        fi
    done
    
    # Validate and normalize hostname to FQDN
    if [[ "${cleanup_hostname}" == *.${ipv4_domain} ]]; then
        stripped_hostname="${cleanup_hostname%.${ipv4_domain}}"
        if [[ "${stripped_hostname}" == *.* ]]; then
            print_error "Invalid hostname. Expected format: hostname.${ipv4_domain}"
            exit 1
        fi
        if [[ ! "${stripped_hostname}" =~ ^[a-z0-9-]+$ || "${stripped_hostname}" =~ ^- || "${stripped_hostname}" =~ -$ ]]; then
            print_error "Invalid hostname. Use only lowercase letters, numbers, and hyphens."
            exit 1
        fi
    elif [[ "${cleanup_hostname}" == *.* ]]; then
        print_error "Invalid domain. Expected domain: ${ipv4_domain}"
        exit 1
    else
        if [[ ! "${cleanup_hostname}" =~ ^[a-z0-9-]+$ || "${cleanup_hostname}" =~ ^- || "${cleanup_hostname}" =~ -$ ]]; then
            print_error "Invalid hostname. Use only lowercase letters, numbers, and hyphens."
            exit 1
        fi
        cleanup_hostname="${cleanup_hostname}.${ipv4_domain}"
    fi
    
    print_info "Removing host '${cleanup_hostname}' from all ksmanager databases..."
    
    # Get MAC address and IP before removal
    if [ -f "${ksmanager_hub_dir}/mac-address-cache" ]; then
        cached_mac=$(grep "^${cleanup_hostname} " "${ksmanager_hub_dir}/mac-address-cache" 2>/dev/null | cut -d " " -f 2)
        cached_ip=$(grep "^${cleanup_hostname} " "${ksmanager_hub_dir}/mac-address-cache" 2>/dev/null | cut -d " " -f 3)
        cached_ipv6=$(grep "^${cleanup_hostname} " "${ksmanager_hub_dir}/mac-address-cache" 2>/dev/null | cut -d " " -f 4)
        
        if [[ -n "$cached_mac" ]]; then
            ipxe_cfg_mac=$(echo "${cached_mac}" | tr ':' '-' | tr 'A-F' 'a-f')
        fi
    fi
    
    # 1. Remove from MAC address cache
    if [ -f "${ksmanager_hub_dir}/mac-address-cache" ] && grep -q "^${cleanup_hostname} " "${ksmanager_hub_dir}/mac-address-cache" 2>/dev/null; then
        sed -i "/^${cleanup_hostname} /d" "${ksmanager_hub_dir}/mac-address-cache"
        print_info "Removed from MAC address cache"
    else
        print_info "No MAC address cache entry found"
    fi
    
    # 2. Remove kickstart directory
    if [ -d "${ksmanager_hub_dir}/kickstarts/${cleanup_hostname}" ]; then
        rm -rf "${ksmanager_hub_dir}/kickstarts/${cleanup_hostname}"
        print_info "Removed kickstart files"
    else
        print_info "No kickstart files found"
    fi
    
    # 3. Remove iPXE config file
    if [[ -n "$ipxe_cfg_mac" ]]; then
        if [ -f "${ipxe_web_dir}/${ipxe_cfg_mac}.ipxe" ]; then
            rm -f "${ipxe_web_dir}/${ipxe_cfg_mac}.ipxe"
            print_info "Removed iPXE config file (${ipxe_cfg_mac}.ipxe)"
        else
            print_info "No iPXE config file found"
        fi
    else
        print_info "No iPXE config (no MAC address found)"
    fi
    
    # 4. Remove golden boot network config
    if [[ -n "$ipxe_cfg_mac" ]]; then
        if [ -f "${ksmanager_hub_dir}/golden-boot-mac-configs/network-config-${ipxe_cfg_mac}" ]; then
            rm -f "${ksmanager_hub_dir}/golden-boot-mac-configs/network-config-${ipxe_cfg_mac}"
            print_info "Removed golden boot network config"
        else
            print_info "No golden boot network config found"
        fi
    else
        print_info "No golden boot config (no MAC address found)"
    fi
    
    # 5. Remove KEA DHCP reservation
    if systemctl is-active --quiet kea-ctrl-agent && [[ -n "$cached_mac" ]]; then
        kea_api_url="http://127.0.0.1:8000/"
        kea_api_auth="kea-api:kea-api-password"
        
        # Delete DHCPv4 lease by MAC address
        curl -s -X POST -H "Content-Type: application/json" \
            -u "$kea_api_auth" \
            -d "{
                  \"command\": \"lease4-del\",
                  \"service\": [ \"dhcp4\" ],
                  \"arguments\": {
                    \"identifier-type\": \"hw-address\",
                    \"identifier\": \"${cached_mac}\",
                    \"subnet-id\": 1
                  }
                }" \
            "$kea_api_url" &>/dev/null
        
        # Delete DHCPv4 lease by IP address
        if [[ -n "$cached_ip" ]]; then
            curl -s -X POST -H "Content-Type: application/json" \
                -u "$kea_api_auth" \
                -d "{
                      \"command\": \"lease4-del\",
                      \"service\": [ \"dhcp4\" ],
                      \"arguments\": {
                        \"ip-address\": \"${cached_ip}\",
                        \"subnet-id\": 1
                      }
                    }" \
                "$kea_api_url" &>/dev/null
        fi
        
        # Delete DHCPv6 lease by MAC address
        curl -s -X POST -H "Content-Type: application/json" \
            -u "$kea_api_auth" \
            -d "{
                  \"command\": \"lease6-del\",
                  \"service\": [ \"dhcp6\" ],
                  \"arguments\": {
                    \"identifier-type\": \"hw-address\",
                    \"identifier\": \"${cached_mac}\",
                    \"subnet-id\": 1
                  }
                }" \
            "$kea_api_url" &>/dev/null
        
        # Delete DHCPv6 lease by IP address (if IPv6 exists in cache)
        if [[ -n "$cached_ipv6" ]]; then
            curl -s -X POST -H "Content-Type: application/json" \
                -u "$kea_api_auth" \
                -d "{
                      \"command\": \"lease6-del\",
                      \"service\": [ \"dhcp6\" ],
                      \"arguments\": {
                        \"ip-address\": \"${cached_ipv6}\",
                        \"subnet-id\": 1
                      }
                    }" \
                "$kea_api_url" &>/dev/null
        fi
        
        # Rebuild KEA DHCPv4 config without this host
        kea_cache_file="${ksmanager_hub_dir}/mac-address-cache"
        kea_dhcp4_config_file="/etc/kea/kea-dhcp4.conf"
        kea_dhcp6_config_file="/etc/kea/kea-dhcp6.conf"
        kea_temp_config_timestamp=$(date +"%Y%m%d_%H%M%S_%Z")
        kea_config_temp_dir="${ksmanager_hub_dir}/kea_dhcp_temp_configs_with_reservation"
        kea_dhcp4_tmp_config="${kea_config_temp_dir}/kea-dhcp4.conf_${kea_temp_config_timestamp}"
        kea_dhcp6_tmp_config="${kea_config_temp_dir}/kea-dhcp6.conf_${kea_temp_config_timestamp}"
        
        mkdir -p "$kea_config_temp_dir"
        
        # Rebuild DHCPv4 reservations
        kea_dhcp4_existing_config=$(sudo cat "$kea_dhcp4_config_file")
        
        kea_dhcp4_reservations_json=""
        while read -r kea_hostname kea_hw_address kea_ip_address; do
            kea_dhcp4_reservations_json+="{
              \"hostname\": \"$kea_hostname\",
              \"hw-address\": \"$kea_hw_address\",
              \"ip-address\": \"$kea_ip_address\"
            },"
        done < "$kea_cache_file"
        
        kea_dhcp4_reservations_json="[${kea_dhcp4_reservations_json%,}]"
        
        kea_dhcp4_new_config=$(echo "$kea_dhcp4_existing_config" | \
            jq --argjson reservations "$kea_dhcp4_reservations_json" \
              '.Dhcp4.subnet4[0].reservations = $reservations')
        
        cat > "$kea_dhcp4_tmp_config" <<EOF
{
  "command": "config-set",
  "service": [ "dhcp4" ],
  "arguments": $kea_dhcp4_new_config
}
EOF
        
        # Rebuild DHCPv6 reservations
        kea_dhcp6_existing_config=$(sudo cat "$kea_dhcp6_config_file")
        
        kea_dhcp6_reservations_json=""
        while read -r kea_hostname kea_hw_address kea_ip_address kea_ipv6_address; do
            if [[ -n "$kea_ipv6_address" ]]; then
                kea_dhcp6_reservations_json+="{
                  \"hostname\": \"$kea_hostname\",
                  \"hw-address\": \"$kea_hw_address\",
                  \"ip-addresses\": [ \"${kea_ipv6_address}\" ]
                },"
            fi
        done < "$kea_cache_file"
        
        kea_dhcp6_reservations_json="[${kea_dhcp6_reservations_json%,}]"
        
        kea_dhcp6_new_config=$(echo "$kea_dhcp6_existing_config" | \
            jq --argjson reservations "$kea_dhcp6_reservations_json" \
              '.Dhcp6.subnet6[0].reservations = $reservations')
        
        cat > "$kea_dhcp6_tmp_config" <<EOF
{
  "command": "config-set",
  "service": [ "dhcp6" ],
  "arguments": $kea_dhcp6_new_config
}
EOF
        
        # Push DHCPv4 config
        curl -s -X POST -H "Content-Type: application/json" \
            -u "$kea_api_auth" \
            -d @"$kea_dhcp4_tmp_config" \
            "$kea_api_url" &>/dev/null
        
        # Push DHCPv6 config
        curl -s -X POST -H "Content-Type: application/json" \
            -u "$kea_api_auth" \
            -d @"$kea_dhcp6_tmp_config" \
            "$kea_api_url" &>/dev/null
        
        print_info "Removed KEA DHCP reservations (IPv4 and IPv6)"
    fi
    
    # 6. Remove DNS record
    if host "${cleanup_hostname}" "${dnsbinder_server_ipv4_address}" &>/dev/null; then
        sudo "${dnsbinder_script}" -dy "${cleanup_hostname}"
        if ! host "${cleanup_hostname}" "${dnsbinder_server_ipv4_address}" &>/dev/null; then
            print_info "Removed DNS record"
        else
            print_warning "DNS record may not have been removed properly"
        fi
    else
        print_info "No DNS record found"
    fi
    
    print_success "Host '${cleanup_hostname}' has been removed from all ksmanager databases."
    exit 0
fi

if $golden_image_creation_not_requested; then
	fn_check_and_create_host_record "${1}"
	ipv4_address=$(host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" | grep 'has address' | cut -d " " -f 4 | tr -d '[[: space:]]')
	
	# Query DNS for IPv6 address (if dual-stack configured)
	if [[ ! -z "${ipv6_gateway}" ]]; then
		ipv6_address=$(host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" | grep 'has IPv6 address' | awk '{print $NF}' | tr -d '[:space:]')
	fi
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
	print_task "Caching MAC address..."
	if sed -i "/${kickstart_hostname}/d" "${ksmanager_hub_dir}"/mac-address-cache && \
	   echo "${kickstart_hostname} ${mac_address_of_host} ${ipv4_address} ${ipv6_address}" >> "${ksmanager_hub_dir}"/mac-address-cache; then
		print_task_done
	else
		print_task_fail
		print_error "Failed to cache MAC address."
		exit 1
	fi
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
			print_error "Invalid MAC address provided. Please try again."
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

# Parse --distro, --version, and --mac flags
distro_from_flag=""
version_from_flag=""
mac_from_flag=""
for arg in "$@"; do
    if [[ "$prev_arg" == "--distro" ]]; then
        distro_from_flag="$arg"
    fi
    if [[ "$prev_arg" == "--version" ]]; then
        version_from_flag="$arg"
    fi
    if [[ "$prev_arg" == "--mac" ]]; then
        mac_from_flag="$arg"
    fi
    prev_arg="$arg"
done

# Set default version type
version_type="${version_from_flag:-latest}"

fn_check_and_create_mac_if_required() {

# If MAC address was provided via --mac flag, use it directly
if [[ -n "${mac_from_flag}" ]]; then
	print_info "Using MAC address provided via --mac flag: ${mac_from_flag}"
	mac_address_of_host="${mac_from_flag}"
	# Validate the provided MAC address
	if ! fn_validate_mac "${mac_address_of_host}"; then
		print_error "Invalid MAC address provided via --mac flag: ${mac_address_of_host}"
		exit 1
	fi
	fn_convert_mac_for_ipxe_cfg
	fn_cache_the_mac
	return
fi

print_info "Looking up MAC address for host \"${kickstart_hostname}\" from cache..."

if [ ! -f "${ksmanager_hub_dir}"/mac-address-cache ]; then
	touch  "${ksmanager_hub_dir}"/mac-address-cache
fi

if grep ^"${kickstart_hostname} " "${ksmanager_hub_dir}"/mac-address-cache &>/dev/null
then
	mac_address_of_host=$(grep ^"${kickstart_hostname} " "${ksmanager_hub_dir}"/mac-address-cache | cut -d " " -f 2 )

	print_info "MAC Address ${mac_address_of_host} found for ${kickstart_hostname} in cache."
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
			print_warning "Invalid input."
		fi
	done
else
	print_info "MAC address for \"${kickstart_hostname}\" not found in cache."
	if $invoked_with_qemu_kvm; then
		print_error "MAC address not found in cache and --mac flag not provided for QEMU/KVM mode."
		print_error "QEMU/KVM scripts must provide MAC address via --mac flag."
		exit 1
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

fn_get_version_number() {
	local os_distribution="$1"
	local version="${2:-latest}"
	
	if [[ "$version" == "latest" ]]; then
		echo "${DISTRO_LATEST_VERSIONS[$os_distribution]}"
	else
		echo "${DISTRO_PREVIOUS_VERSIONS[$os_distribution]}"
	fi
}

fn_check_distro_availability() {
	local os_distribution="${1}"
	local version="${2:-latest}"
	local mount_dir="/${lab_infra_server_hostname}/${os_distribution}-${version}"
	
	if mountpoint -q "${mount_dir}"; then
		print_green '[Ready]'
	else
		print_yellow '[Not-Ready]'
	fi
}

# Status will be computed dynamically in menu based on selected version

fn_select_os_distro() {
    # Check if --distro flag was provided
    if [[ -n "${distro_from_flag}" ]]; then
        case "${distro_from_flag}" in
            alma|almalinux) 
                os_distribution="almalinux"
                print_info "OS distribution selected via --distro flag: ${os_distribution}"
                return
                ;;
            rocky) 
                os_distribution="rocky"
                print_info "OS distribution selected via --distro flag: ${os_distribution}"
                return
                ;;
            oracle|oraclelinux) 
                os_distribution="oraclelinux"
                print_info "OS distribution selected via --distro flag: ${os_distribution}"
                return
                ;;
            centos|centos-stream) 
                os_distribution="centos-stream"
                print_info "OS distribution selected via --distro flag: ${os_distribution}"
                return
                ;;
            rhel|redhat) 
                os_distribution="rhel"
                print_info "OS distribution selected via --distro flag: ${os_distribution}"
                return
                ;;
            ubuntu-lts|ubuntu) 
                os_distribution="ubuntu-lts"
                print_info "OS distribution selected via --distro flag: ${os_distribution}"
                return
                ;;
            opensuse-leap|opensuse|suse) 
                os_distribution="opensuse-leap"
                print_info "OS distribution selected via --distro flag: ${os_distribution}"
                return
                ;;
            *)
                print_error "Invalid distro specified with --distro flag: ${distro_from_flag}"
                print_info "Valid options: almalinux, rocky, oraclelinux, centos-stream, rhel, ubuntu-lts, opensuse-leap"
                exit 1
                ;;
        esac
    fi
    
    # Two-step menu: First select version, then select distribution
    # Step 1: Select version (only if not already set via --version flag)
    if [[ -z "${version_from_flag}" ]]; then
        print_notify "Please select the OS version to install:
  1)  Latest  (AlmaLinux 10, Rocky 10, Ubuntu 24.04, openSUSE 15.6, etc.)
  2)  Previous (AlmaLinux 9, Rocky 9, Ubuntu 22.04, openSUSE 15.5, etc.)
  q)  Quit"

        read -p "Enter option number (default: Latest): " version_choice

        case "${version_choice}" in
            1 | "" ) version_type="latest" ;;
            2 )      version_type="previous" ;;
            q | Q )  print_info "Operation cancelled by user."; exit 130 ;;
            * )      print_error "Invalid option. Please try again."; fn_select_os_distro; return ;;
        esac
        
        print_info "Version selected: ${version_type}"
    fi
    
    # Step 2: Select distribution
    local -a distro_keys=("almalinux" "rocky" "oraclelinux" "centos-stream" "rhel" "ubuntu-lts" "opensuse-leap")
    local -a distro_names=("AlmaLinux" "Rocky Linux" "OracleLinux" "CentOS Stream" "Red Hat Enterprise Linux" "Ubuntu Server LTS" "openSUSE Leap")
    
    # Build menu
    local menu="Please select the OS distribution to install:\n"
    for i in "${!distro_keys[@]}"; do
        local key="${distro_keys[$i]}"
        local name="${distro_names[$i]}"
        local ver=$(fn_get_version_number "$key" "$version_type")
        local status=$(fn_check_distro_availability "$key" "$version_type")
        printf -v line "  %d)  %-32s %s\n" $((i+1)) "${name} ${ver}" "${status}"
        menu+="${line}"
    done
    menu+="  q)  Quit"
    
    print_notify "$menu"

    read -p "Enter option number (default: AlmaLinux): " os_distribution

    case "${os_distribution}" in
        1 | "" ) os_distribution="almalinux" ;;
        2 )      os_distribution="rocky" ;;
        3 )      os_distribution="oraclelinux" ;;
        4 )      os_distribution="centos-stream" ;;
        5 )      os_distribution="rhel" ;;
        6 )      os_distribution="ubuntu-lts" ;;
        7 )      os_distribution="opensuse-leap" ;;
        q | Q )  print_info "Operation cancelled by user."; exit 130 ;;
	* ) print_error "Invalid option. Please try again."; fn_select_os_distro ;;
    esac
    
    print_info "OS distribution selected: ${os_distribution} (${version_type})"
}

fn_select_os_distro

# Initialize variables for QEMU/KVM
disk_type_for_the_vm="vda"

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

mount_dir="/${lab_infra_server_hostname}/${os_distribution}-${version_type}"

while ! mountpoint -q "${mount_dir}"; do
	print_warning "${os_distribution} is not yet prepared for PXE-boot environment."
	print_info "Please use 'prepare-distro-for-ksmanager' tool to prepare ${os_distribution} for PXE-boot."
	if $invoked_with_qemu_kvm; then
		print_error "Cannot proceed with unprepared OS distribution in automation mode."
		exit 1
	fi
	fn_select_os_distro
done

if [[ "${os_distribution}" == "ubuntu-lts" ]]; then
	os_name_and_version=$(awk -F'LTS' '{print $1 "LTS"}' "/${lab_infra_server_hostname}/${os_distribution}-${version_type}/.disk/info")
elif [[ "${os_distribution}" == "opensuse-leap" ]]; then
	os_name_and_version=$(awk -F ' = ' '/^\[release\]/{f=1; next} /^\[/{f=0} f && /^(name|version)/ {gsub(/^[ \t]+/, "", $2); printf "%s ", $2} END{print ""}' "/${lab_infra_server_hostname}/${os_distribution}-${version_type}/.treeinfo")
	# Extract just the version number (e.g., "15.6" from "openSUSE Leap 15.6")
	opensuse_version_number=$(echo "$os_name_and_version" | grep -oP '\d+\.\d+')
else
	redhat_based_distro_name="${os_distribution}"
	if [[ "${os_distribution}" == "centos-stream" ]]; then
		os_name_and_version=$(grep -i "centos" "/${lab_infra_server_hostname}/${os_distribution}-${version_type}/.discinfo")
	elif [[ "${os_distribution}" == "oraclelinux" ]]; then
		os_name_and_version=$(grep -i "oracle" "/${lab_infra_server_hostname}/${os_distribution}-${version_type}/.discinfo")
	elif [[ "${os_distribution}" == "rhel" ]]; then
		os_name_and_version=$(grep -i "Red Hat" "/${lab_infra_server_hostname}/${os_distribution}-${version_type}/.discinfo")
	else
		os_name_and_version=$(grep -i "${os_distribution}" "/${lab_infra_server_hostname}/${os_distribution}-${version_type}/.discinfo")
	fi
fi

if ! $golden_image_creation_not_requested; then
	fn_check_and_create_host_record "${os_distribution}-golden-image-${version_type}"
	ipv4_address=$(host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" | grep 'has address' | cut -d " " -f 4 | tr -d '[[:space:]]')
	
	# Query DNS for IPv6 address (if dual-stack configured)
	if [[ ! -z "${ipv6_gateway}" ]]; then
		ipv6_address=$(host "${kickstart_hostname}" "${dnsbinder_server_ipv4_address}" | grep 'has IPv6 address' | awk '{print $NF}' | tr -d '[:space:]')
	fi
	
	fn_check_and_create_mac_if_required
	fn_create_host_kickstart_dir
fi

if ! $invoked_with_golden_image; then
	if [[ "${os_distribution}" == "opensuse-leap" ]]; then
		rsync -a -q "${ksmanager_main_dir}/ks-templates/${os_distribution}-${version_type}-autoinst.xml" "${host_kickstart_dir}/${os_distribution}-${version_type}-autoinst.xml" 
	elif [[ "${os_distribution}" == "ubuntu-lts" ]]; then 
		rsync -a -q --delete "${ksmanager_main_dir}/ks-templates/${os_distribution}-${version_type}-ks" "${host_kickstart_dir}"/
	else
		rsync -a -q "${ksmanager_main_dir}/ks-templates/redhat-based-${version_type}-ks.cfg" "${host_kickstart_dir}"/ 
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

	print_task "Generating kickstart profile and iPXE configs..."
	if rsync -a -q --delete "${ksmanager_main_dir}"/addons-for-kickstarts/ "${ksmanager_hub_dir}"/addons-for-kickstarts/ && \
	   rsync -a -q /home/${mgmt_super_user}/.ssh/{authorized_keys,kvm_lab_global_id_rsa.pub,kvm_lab_global_id_rsa} "${ksmanager_hub_dir}"/addons-for-kickstarts/ && \
	   chmod +r "${ksmanager_hub_dir}"/addons-for-kickstarts/{authorized_keys,kvm_lab_global_id_rsa.pub,kvm_lab_global_id_rsa} && \
	   mkdir -p "${ksmanager_hub_dir}"/golden-boot-mac-configs; then
		print_task_done
	else
		print_task_fail
		print_error "Failed to generate kickstart profile."
		exit 1
	fi
fi

if $invoked_with_golden_image; then

	print_task "Generating golden boot network config..."
	if rsync -a -q "${ksmanager_main_dir}"/golden-boot-templates/network-config-for-mac-address "${ksmanager_hub_dir}"/golden-boot-mac-configs/network-config-"${ipxe_cfg_mac_address}"; then
		print_task_done
	else
		print_task_fail
		print_error "Failed to generate network config."
		exit 1
	fi
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
		
		# IPv6 replacements (if configured)
		if [[ ! -z "${ipv6_address}" ]]; then
			sed -i "s|get_ipv6_address|${ipv6_address}|g" "${working_file}"
			sed -i "s/get_ipv6_gateway/${ipv6_gateway}/g" "${working_file}"
			sed -i "s/get_ipv6_prefix/${ipv6_prefix}/g" "${working_file}"
		fi
    	sed -i "s/get_hostname/${kickstart_short_hostname}/g" "${working_file}"
		sed -i "s/get_lab_infra_server_hostname/${lab_infra_server_hostname}/g" "${working_file}"
		sed -i "s/get_win_hostname/${win_hostname}/g" "${working_file}"
		sed -i "s/get_rhel_activation_key/${rhel_activation_key}/g" "${working_file}"
		sed -i "s/get_time_of_last_update/${time_of_last_update}/g" "${working_file}"
		sed -i "s/get_mgmt_super_user/${mgmt_super_user}/g" "${working_file}"
		sed -i "s/get_os_name_and_version/${os_name_and_version}/g" "${working_file}"
		sed -i "s/get_disk_type_for_the_vm/${disk_type_for_the_vm}/g" "${working_file}"
	 	sed -i "s/get_golden_image_creation_not_requested/$golden_image_creation_not_requested/g" "${working_file}"
	 	sed -i "s/get_redhat_based_distro_name/$redhat_based_distro_name/g" "${working_file}"
	 	sed -i "s/get_version_type/$version_type/g" "${working_file}"
	 	sed -i "s/get_opensuse_version_number/$opensuse_version_number/g" "${working_file}"
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
            rsync -a -q "${ksmanager_main_dir}/ipxe-templates/ipxe-template-${os_distribution}-auto-${version_type}.ipxe"  "${mac_based_ipxe_cfg_file}"
	else
	    rsync -a -q "${ksmanager_main_dir}/ipxe-templates/ipxe-template-redhat-based-auto-${version_type}.ipxe"  "${mac_based_ipxe_cfg_file}"
	fi

	fn_set_environment "${mac_based_ipxe_cfg_file}"

fi

if $invoked_with_golden_image; then
	fn_set_environment "${ksmanager_hub_dir}"/golden-boot-mac-configs/network-config-"${ipxe_cfg_mac_address}"
fi

chown -R ${mgmt_super_user}:${mgmt_super_user}  "${ksmanager_hub_dir}"

fn_update_kea_dhcp_reservations() {
  print_task "Updating KEA DHCP reservations..."
  local kea_cache_file="${ksmanager_hub_dir}/mac-address-cache"
  local kea_dhcp4_config_file="/etc/kea/kea-dhcp4.conf"
  local kea_dhcp6_config_file="/etc/kea/kea-dhcp6.conf"
  local kea_api_url="http://127.0.0.1:8000/"
  local kea_api_auth="kea-api:kea-api-password"
  local kea_temp_config_timestamp=$(date +"%Y%m%d_%H%M%S_%Z")
  local kea_config_temp_dir="${ksmanager_hub_dir}/kea_dhcp_temp_configs_with_reservation"
  local kea_dhcp4_tmp_config="${kea_config_temp_dir}/kea-dhcp4.conf_${kea_temp_config_timestamp}"
  local kea_dhcp6_tmp_config="${kea_config_temp_dir}/kea-dhcp6.conf_${kea_temp_config_timestamp}"

  mkdir -p "$kea_config_temp_dir"

  current_ip_with_mac=$(grep ^"${kickstart_hostname} " "${kea_cache_file}" | cut -d " " -f 3 )
  if [[ "${current_ip_with_mac}" != "${ipv4_address}" ]]; then
    sed -i "/^${kickstart_hostname} / s/${current_ip_with_mac}/${ipv4_address}/" "${kea_cache_file}"
  fi

  # ===== DHCPv4 Reservations =====
  # Read existing Kea DHCPv4 config
  local kea_dhcp4_existing_config
  kea_dhcp4_existing_config=$(sudo cat "$kea_dhcp4_config_file")

  # Build JSON array of DHCPv4 reservations from cache file
  local kea_dhcp4_reservations_json=""
  while read -r kea_hostname kea_hw_address kea_ip_address; do
    kea_dhcp4_reservations_json+="{
      \"hostname\": \"$kea_hostname\",
      \"hw-address\": \"$kea_hw_address\",
      \"ip-address\": \"$kea_ip_address\"
    },"
  done < "$kea_cache_file"

  kea_dhcp4_reservations_json="[${kea_dhcp4_reservations_json%,}]"

  # Insert DHCPv4 reservations into config JSON
  local kea_dhcp4_new_config
  kea_dhcp4_new_config=$(echo "$kea_dhcp4_existing_config" | \
    jq --argjson reservations "$kea_dhcp4_reservations_json" \
      '.Dhcp4.subnet4[0].reservations = $reservations')

  # Wrap into config-set command for DHCPv4
  cat > "$kea_dhcp4_tmp_config" <<EOF
{
  "command": "config-set",
  "service": [ "dhcp4" ],
  "arguments": $kea_dhcp4_new_config
}
EOF

  # ===== DHCPv6 Reservations =====
  # Read existing Kea DHCPv6 config
  local kea_dhcp6_existing_config
  kea_dhcp6_existing_config=$(sudo cat "$kea_dhcp6_config_file")

  # Build JSON array of DHCPv6 reservations from cache file
  local kea_dhcp6_reservations_json=""
  while read -r kea_hostname kea_hw_address kea_ip_address; do
    kea_dhcp6_reservations_json+="{
      \"hostname\": \"$kea_hostname\",
      \"hw-address\": \"$kea_hw_address\",
      \"ip-addresses\": [ \"${ipv6_address}\" ]
    },"
  done < "$kea_cache_file"

  kea_dhcp6_reservations_json="[${kea_dhcp6_reservations_json%,}]"

  # Insert DHCPv6 reservations into config JSON
  local kea_dhcp6_new_config
  kea_dhcp6_new_config=$(echo "$kea_dhcp6_existing_config" | \
    jq --argjson reservations "$kea_dhcp6_reservations_json" \
      '.Dhcp6.subnet6[0].reservations = $reservations')

  # Wrap into config-set command for DHCPv6
  cat > "$kea_dhcp6_tmp_config" <<EOF
{
  "command": "config-set",
  "service": [ "dhcp6" ],
  "arguments": $kea_dhcp6_new_config
}
EOF

  # ===== Delete old DHCPv4 leases =====
  # Delete old DHCPv4 lease by MAC (safe if none exists)
  curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
    -d "{
          \"command\": \"lease4-del\",
          \"service\": [ \"dhcp4\" ],
          \"arguments\": {
            \"identifier-type\": \"hw-address\",
            \"identifier\": \"${mac_address_of_host}\",
            \"subnet-id\": 1
          }
        }" \
  "$kea_api_url" &>/dev/null

  # Delete DHCPv4 lease by IP (safe if none exists)
  curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
  # Delete DHCPv4 lease by IP (safe if none exists)
  curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
    -d "{
          \"command\": \"lease4-del\",
          \"service\": [ \"dhcp4\" ],
          \"arguments\": {
            \"ip-address\": \"${ipv4_address}\",
            \"subnet-id\": 1
          }
        }" \
   "$kea_api_url" &>/dev/null

  # ===== Delete old DHCPv6 leases =====
  # Delete old DHCPv6 lease by MAC (safe if none exists)
  curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
    -d "{
          \"command\": \"lease6-del\",
          \"service\": [ \"dhcp6\" ],
          \"arguments\": {
            \"identifier-type\": \"hw-address\",
            \"identifier\": \"${mac_address_of_host}\",
            \"subnet-id\": 1
          }
        }" \
  "$kea_api_url" &>/dev/null

  # Delete DHCPv6 lease by IP (safe if none exists)
  curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
    -d "{
          \"command\": \"lease6-del\",
          \"service\": [ \"dhcp6\" ],
          \"arguments\": {
            \"ip-address\": \"${ipv6_address}\",
            \"subnet-id\": 1
          }
        }" \
   "$kea_api_url" &>/dev/null

  # ===== Push new configs dynamically =====
  # Push DHCPv4 config
  if ! curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
    -d @"$kea_dhcp4_tmp_config" \
    "$kea_api_url" &>/dev/null; then
    print_task_fail
    print_error "Failed to update KEA DHCPv4 reservations."
    exit 1
  fi

  # Push DHCPv6 config
  if curl -s -X POST -H "Content-Type: application/json" \
    -u "$kea_api_auth" \
    -d @"$kea_dhcp6_tmp_config" \
    "$kea_api_url" &>/dev/null; then
    print_task_done
  else
    print_task_fail
    print_error "Failed to update KEA DHCPv6 reservations."
    exit 1
  fi
}

if systemctl is-active --quiet kea-ctrl-agent; then
	fn_update_kea_dhcp_reservations
fi

config_summary="Configuration Summary:
  ✓ Hostname         : ${kickstart_hostname}
  ✓ MAC Address      : ${mac_address_of_host}
  ✓ IPv4 Address     : ${ipv4_address}
  ✓ IPv4 Netmask     : ${ipv4_netmask}
  ✓ IPv4 Gateway     : ${ipv4_gateway}
  ✓ IPv4 Network     : ${ipv4_network_cidr}
  ✓ IPv4 DNS         : ${ipv4_nameserver}
  ✓ IPv6 Address     : ${ipv6_address}
  ✓ IPv6 Prefix      : ${ipv6_prefix}
  ✓ IPv6 Gateway     : ${ipv6_gateway}
  ✓ Domain           : ${ipv4_domain}
  ✓ Lab Infra Server : ${lab_infra_server_hostname}
  ✓ Requested OS     : ${os_name_and_version}"

print_info "$config_summary"

if ! $invoked_with_golden_image; then
	print_info "Kickstart configs ready for '${kickstart_hostname}'."
else
	print_info "Golden boot configs ready for '${kickstart_hostname}'."
fi

exit
