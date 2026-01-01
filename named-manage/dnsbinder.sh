#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh

# Source environment variables for IPv6 dual-stack support
if [ -f /etc/environment ]; then
    source /etc/environment
fi

if [[ "${UID}" -ne 0 ]]
then
    print_error "Run with sudo or run from root account ! "
    exit 1
fi


v_tmp_file_dnsbinder="/tmp/tmp_file_dnsbinder"

v_domain_name=$(if [ -f /etc/named.conf ];then grep 'zones-are-managed-by-dnsbinder' /etc/named.conf | awk '{print $2}';fi)
dnsbinder_network=$(if [ -f /etc/named.conf ];then grep 'dnsbinder-network' /etc/named.conf | awk '{print $3}';fi)
var_zone_dir='/var/named/dnsbinder-managed-zone-files'
v_fw_zone="${var_zone_dir}/${v_domain_name}-forward.db"

fn_check_existence_of_domain() {
	if [ -z "${v_domain_name}" ]
	then
		print_error "> Seems like bind dns service is not being handled by dnsbinder! "
		print_info "> Please check and setup the same using dnsbinder utility itself! "
		exit 1
	fi
}

fn_calculate_network_cidr() {
    local ipv4_address="${1}"
    local subnet_mask="${2}"

    IFS=. read -r ipv4_octet1 ipv4_octet2 ipv4_octet3 ipv4_octet4 <<< "${ipv4_address}"
    IFS=. read -r mask_octet1 mask_octet2 mask_octet3 mask_octet4 <<< "${subnet_mask}"

    # Perform bitwise AND operation using arithmetic expansion
    local network_octet1=$((ipv4_octet1 & mask_octet1))
    local network_octet2=$((ipv4_octet2 & mask_octet2))
    local network_octet3=$((ipv4_octet3 & mask_octet3))
    local network_octet4=$((ipv4_octet4 & mask_octet4))

    local network_cidr=0
    for octet in ${mask_octet1} ${mask_octet2} ${mask_octet3} ${mask_octet4}; do
	for bit in {7..0}; do
            if (( (octet >> bit) & 1 )); then
                ((network_cidr++))
            fi
        done
    done
    local ipv4_address="${1}"
    local subnet_mask="${2}"

    IFS=. read -r ipv4_octet1 ipv4_octet2 ipv4_octet3 ipv4_octet4 <<< "${ipv4_address}"
    IFS=. read -r mask_octet1 mask_octet2 mask_octet3 mask_octet4 <<< "${subnet_mask}"

    # Perform bitwise AND operation using arithmetic expansion
    local network_octet1=$((ipv4_octet1 & mask_octet1))
    local network_octet2=$((ipv4_octet2 & mask_octet2))
    local network_octet3=$((ipv4_octet3 & mask_octet3))
    local network_octet4=$((ipv4_octet4 & mask_octet4))

    echo "${network_octet1}.${network_octet2}.${network_octet3}.${network_octet4}/${network_cidr}"
}

fn_cidr_prefix_to_netmask() {
    local cidr_prefix=$1
    
    local binary_mask=$(printf '%*s' "$cidr_prefix" '' | tr ' ' '1')
    binary_mask=$(printf '%-32s' "$binary_mask" | tr ' ' '0')

    dnsbinder_netmask=""
    for i in {0..3}; do
        local octet_decimal=$((2#${binary_mask:$((i * 8)):8}))
        dnsbinder_netmask+=$octet_decimal
        [[ $i -lt 3 ]] && dnsbinder_netmask+=.
    done
}

fn_split_network_into_cidr24subnets() {

	v_network_and_cidr="${1}"

	# Function to convert an IP address to a number
	fn_ip_to_int() {
    		local ipv4_address=${1}
    		local ipv4_octet1 ipv4_octet2 ipv4_octet3 ipv4_octet4
    		IFS=. read -r ipv4_octet1 ipv4_octet2 ipv4_octet3 ipv4_octet4 <<< "${ipv4_address}"
    		echo "$((ipv4_octet1 * 256 ** 3 + ipv4_octet2 * 256 ** 2 + ipv4_octet3 * 256 + ipv4_octet4))"
	}
	
	# Function to convert a number back to an IP address
	fn_int_to_ip() {
    		local int=${1}
    		echo "$((int >> 24 & 255)).$((int >> 16 & 255)).$((int >> 8 & 255)).$((int & 255))"
	}
	
	# Function to generate /24 subnets within a given network
	fn_generate_subnets() {
    		local v_network=${1}
    		local v_cidr=${2}
	
    		# Convert network address to an integer
    		local v_network_int
    		v_network_int=$(fn_ip_to_int "${v_network}")
	
    		# Calculate the number of subnets to generate
    		local v_subnet_count
    		v_subnet_count=$(( 2 ** (32 - v_cidr) / 256 ))
	
    		# Generate subnets
    		for ((i = 0; i < v_subnet_count; i++)); do
        		local v_subnet_int=$(( v_network_int + i * 256 ))
        		local v_subnet
        		v_subnet=$(fn_int_to_ip "${v_subnet_int}")
        		echo "${v_subnet}/24"
    		done
	}

	if [[ -z "${v_network_and_cidr}" ]];
	then
		v_network_and_cidr=$(ip r | grep -v default | grep "${v_primary_interface}" | head -n 1 | awk '{ print $1 }')
	fi

	# Extract network and CIDR from input
	v_network=$(echo "${v_network_and_cidr}" | cut -d "/" -f 1)
	v_cidr=$(echo "${v_network_and_cidr}" | cut -d "/" -f 2)

	fn_cidr_prefix_to_netmask "${v_cidr}"
	
	# Check if CIDR is valid
	if ! [[ "${v_cidr}" =~ ^[0-9]+$ ]] || [ "${v_cidr}" -lt 16 ] || [ "${v_cidr}" -gt 24 ]; then
    		print_error "Invalid CIDR. Only Networks with CIDR between 16 and 24 is allowed ! "
    		exit 1
	fi
	
	# Generate and display the subnets
	v_splited_subnets=$(fn_generate_subnets "${v_network}" "${v_cidr}" |  sed "s/\.0\/24//")
}

if [[ ! -z "${dnsbinder_network}" ]]; then
	v_splited_subnets=$(ls "${var_zone_dir}"/*-reverse.db | awk -F'/' '{print $NF}' | awk -F'.' '{print $1"."$2"."$3}' | sort -n)
	v_total_ptr_zones=$(ls "${var_zone_dir}"/*-reverse.db | wc -l)

	v_zone_number=1
	for v_subnet_part in ${v_splited_subnets}
	do
    		eval "v_ptr_zone${v_zone_number}=\"${var_zone_dir}/${v_subnet_part}.${v_domain_name}-reverse.db\""
    		eval "v_subnet${v_zone_number}=\"${v_subnet_part}\""
    		let v_zone_number++
	done
fi

fn_instruct_on_valid_domain_name() {
print_warning "FYI :
  > Only allowed TLD is 'local' .
  > Maximum 2 subdomains are only allowed.
  > Only letters, numbers, and hyphens are allowed with subdomains.
  > Hyphens cannot appear at the start or end of the subdomains.
  > The total length must be between 1 and 63 characters.
  > Follows the format defined in RFC 1035.
  > Examples for Valid Domain Names :
      test.local, test.example.local, 123-example.local, test-lab1.local
      123.example.local, test1.lab1.local, test-1.example-1.local"
}

fn_configure_named_dns_server() {

	KVM_HOST_MODE_SET=false
	if ip link show labbr0 &>/dev/null; then
        	KVM_HOST_MODE_SET=true
	fi

	if [ ! -z "${v_domain_name}" ]
	then
		print_error "> Seems like bind dns server and domain is already setup and managed by dnsbinder! "
		print_success "> Domain '${v_domain_name}' is already being managed by dnsbinder! "
		print_warning "> Nothing to do!  "
		exit
	fi

	if [[ ! -z "${1}" ]]; then
		v_given_domain="${1}"
	else
		fn_instruct_on_valid_domain_name
	fi

	while :
	do
		if [[ -z "${v_given_domain}" ]]; then
			read -p "Provide the preferred local domain : " v_given_domain 
		fi
			
		if [[ "${#v_given_domain}" -le 63 ]] && [[ "${v_given_domain}" =~ ^[[:alnum:]]+([-.][[:alnum:]]+)*(\.[[:alnum:]]+){0,2}\.local$ ]]
		then
			break
		else
			v_given_domain=""
			fn_instruct_on_valid_domain_name
			continue
		fi
	done

	print_task "Fetching network information from the system..."

	if $KVM_HOST_MODE_SET; then
		source /kvm-hub/lab_environment_vars
		v_dns_host_short_name="${lab_infra_server_hostname%%.*}"
		v_primary_interface='labbr0'
		v_primary_ip=$lab_infra_server_ipv4_address
		v_network_gateway=$lab_infra_server_ipv4_gateway
		# Extract IPv6 information for dual-stack support
		v_ipv6_address=$lab_infra_server_ipv6_address
		v_ipv6_gateway=$lab_infra_server_ipv6_gateway
		v_ipv6_prefix=$lab_infra_server_ipv6_prefix
		if [[ -z "${v_ipv6_ula_subnet}" ]]; then
			v_ipv6_ula_subnet=$lab_infra_server_ipv6_ula_subnet
		fi
	else
		v_dns_host_short_name=$(hostname -s)
		v_primary_interface=$(ip r | grep default | awk '{ print $5 }')
		v_primary_ip=$(ip r | grep -v default | grep "${v_primary_interface}" | head -n 1 | awk '{ print $9 }')
		v_network_gateway=$(ip r | grep default | awk '{ print $3 }')
		
		# Auto-detect IPv6 from system (lab infra server VM must have IPv6 configured)
		# Try to get IPv6 from primary interface (exclude link-local fe80 and loopback ::1)
		v_ipv6_address=$(ip -6 addr show "${v_primary_interface}" | grep -oP 'inet6\s+\Kfd[0-9a-f:]+' | grep -v 'fe80' | grep -v '::1' | head -1)
		if [[ ! -z "${v_ipv6_address}" ]]; then
			# Extract prefix length
			v_ipv6_prefix=$(ip -6 addr show "${v_primary_interface}" | grep -oP 'fd[0-9a-f:]+/\K[0-9]+' | head -1)
			# Build ULA subnet
			if [[ ! -z "${v_ipv6_address}" && ! -z "${v_ipv6_prefix}" ]]; then
				v_ipv6_base=$(echo "${v_ipv6_address}" | sed 's/::[^:]*$//')
				v_ipv6_ula_subnet="${v_ipv6_base}::/${v_ipv6_prefix}"
				# Gateway is always ::1 in the subnet (no default route needed for detection)
				v_ipv6_gateway="${v_ipv6_base}::1"
			fi
		fi
		
		# Verify dual-stack configuration is present on the system
		if [[ -z "${v_ipv6_ula_subnet}" ]]; then
			print_error "IPv6 configuration not found. Dual-stack (IPv4+IPv6) is required."
			print_error "Please configure IPv6 on ${v_primary_interface} before running this script."
			exit 1
		fi
	fi

	fn_split_network_into_cidr24subnets

	print_task_done

	print_task "Checking whether required bind dns packages are installed..."

	if rpm -q bind bind-utils &>/dev/null 
	then
		print_task_done
	else
		print_warning "Not yet installed"

		print_task "Installing the required bind dns packages..."

		if dnf install bind bind-utils -y &>/dev/null
		then
			print_task_done
		else
			print_task_fail
			print_error "Try installing the packages bind and bind-utils manually then try the script again!"
			exit 1
		fi
	fi

	print_task "Taking backup of named.conf..."

	cp -p /etc/named.conf /etc/named.conf_bkp_by_dnsbinder
	
	print_task_done

	print_task "Configuring named.conf..."

	if $KVM_HOST_MODE_SET; then
		sed -i "s/listen-on port 53 {\s*127.0.0.1;\s*};/listen-on port 53 { ${v_primary_ip}; };/" /etc/named.conf
		# Enable IPv6 listening for dual-stack support
		if [[ ! -z "${v_ipv6_address}" ]]; then
			sed -i "s/listen-on-v6 port 53 {\s*::1;\s*};/listen-on-v6 port 53 { ${v_ipv6_address}; };/" /etc/named.conf
		else
			sed -i '/^[[:space:]]*[^#].*listen-on-v6/s/^/#/' /etc/named.conf
		fi
	else
		sed -i "s/listen-on port 53 {\s*127.0.0.1;\s*};/listen-on port 53 { 127.0.0.1; ${v_primary_ip}; };/" /etc/named.conf
		# Enable IPv6 listening for dual-stack support
		if [[ ! -z "${v_ipv6_address}" ]]; then
			sed -i "s/listen-on-v6 port 53 {\s*::1;\s*};/listen-on-v6 port 53 { ::1; ${v_ipv6_address}; };/" /etc/named.conf
		else
			sed -i '/^[[:space:]]*[^#].*listen-on-v6/s/^/#/' /etc/named.conf
		fi
	fi

	# Configure allow-query for IPv4 and optionally IPv6
	if [[ ! -z "${v_ipv6_address}" ]]; then
		sed -i "s/allow-query\s*{\s*localhost;\s*};/allow-query     { localhost; ${v_network}\/${v_cidr}; ${v_ipv6_subnet}\/${v_ipv6_prefix}; };/" /etc/named.conf
	else
		sed -i "s/allow-query\s*{\s*localhost;\s*};/allow-query     { localhost; ${v_network}\/${v_cidr}; };/" /etc/named.conf
	fi

	sed -i '/dnssec-validation yes;/d' /etc/named.conf

	sed -i '/recursion yes;/a # BEGIN public-dns-servers-as-forwarders\n\n        forwarders {\n                8.8.8.8;\n                8.8.4.4;\n        };\n\n        dnssec-validation no;\n# END public-dns-servers-as-forwarders' /etc/named.conf


	tee -a /etc/named.conf > /dev/null << EOF
# BEGIN zones-of-${v_given_domain}-domain
# dnsbinder-network ${v_network}/${v_cidr} 
# ${v_given_domain} zones-are-managed-by-dnsbinder
//Forward Zone for ${v_given_domain}
zone "${v_given_domain}" IN {
           type master;
           file "dnsbinder-managed-zone-files/${v_given_domain}-forward.db";
           allow-update { none; };
};
//Reverse Zones ms.local
EOF
	
	for v_subnet_part in ${v_splited_subnets}
	do
		if [[ -z "${v_first_subnet_part}" ]]; then
			v_first_subnet_part="${v_subnet_part}"
		fi

		v_reverse_subnet_part=$(echo "${v_subnet_part}" | awk -F. '{print $3"."$2"."$1}')
		tee -a /etc/named.conf > /dev/null << EOF
zone "${v_reverse_subnet_part}.in-addr.arpa" IN {
             type master;
             file "dnsbinder-managed-zone-files/${v_subnet_part}.${v_given_domain}-reverse.db";
             allow-update { none; };
};
EOF
		v_last_subnet_part="${v_subnet_part}"
	done

	# Add IPv6 reverse zone if IPv6 is configured
	if [[ ! -z "${v_ipv6_ula_subnet}" ]]; then
		# Extract IPv6 prefix for reverse zone (e.g., fd00:1234:1234:1234::/64)
		# Convert to reverse DNS format
		v_ipv6_base=$(echo "${v_ipv6_ula_subnet}" | cut -d'/' -f1 | sed 's/::$//')
		# For fd00:1234:1234:1234::, reverse is 4.3.2.1.4.3.2.1.4.3.2.1.0.0.d.f.ip6.arpa
		v_ipv6_reverse_zone=$(echo "${v_ipv6_base}" | awk -F':' '{
			for(i=NF; i>=1; i--) {
				if($i != "") {
					len=length($i)
					for(j=len; j>=1; j--) {
						printf "%s.", substr($i,j,1)
					}
				}
			}
		}' | sed 's/\.$//')
		
		tee -a /etc/named.conf > /dev/null << EOF
//IPv6 Reverse Zone
zone "${v_ipv6_reverse_zone}.ip6.arpa" IN {
             type master;
             file "dnsbinder-managed-zone-files/${v_given_domain}-ipv6-reverse.db";
             allow-update { none; };
};
EOF
	fi

	echo -e "# END zones-of-${v_given_domain}-domain" | tee -a /etc/named.conf > /dev/null

	print_task_done

	print_task "Creating and configuring zone files..."

	mkdir -p "${var_zone_dir}"

	fn_update_dns_server_data_to_zone_file() {
		v_file_name="${1}"
		tee -a "${v_file_name}" > /dev/null << EOF
\$TTL 86400
@   IN  SOA  ${v_dns_host_short_name}.${v_given_domain}. root.${v_given_domain}. (
        1	;Serial
        3600	;Refresh
        1800	;Retry
        604800	;Expire
        86400	;Minimum TTL
)

;Name Server Information
@ IN NS ${v_dns_host_short_name}.${v_given_domain}.
EOF
	}

	v_zone_file_name="${var_zone_dir}/${v_given_domain}-forward.db"

	fn_update_dns_server_data_to_zone_file "${v_zone_file_name}"
	echo -e "\n;A-Records" | tee -a "${v_zone_file_name}" > /dev/null

	v_network_adjusted_space=$(printf "%-*s" 63 "network")

	echo -e "${v_network_adjusted_space} IN A ${v_first_subnet_part}.0" | tee -a  "${v_zone_file_name}" > /dev/null

	v_gateway_adjusted_space=$(printf "%-*s" 63 "gateway")

	echo -e "${v_gateway_adjusted_space} IN A ${v_first_subnet_part}.1" | tee -a  "${v_zone_file_name}" > /dev/null

	v_dns_host_short_name_adjusted_space=$(printf "%-*s" 63 "${v_dns_host_short_name}")
	
	echo -e "${v_dns_host_short_name_adjusted_space} IN A ${v_primary_ip}" | tee -a "${v_zone_file_name}" > /dev/null

	v_broadcast_adjusted_space=$(printf "%-*s" 63 "broadcast")

	echo -e "${v_broadcast_adjusted_space} IN A ${v_last_subnet_part}.255" | tee -a  "${v_zone_file_name}" > /dev/null

	# Add AAAA records for IPv6 (dual-stack)
	if [[ ! -z "${v_ipv6_address}" ]]; then
		echo -e "\n;AAAA-Records (IPv6)" | tee -a "${v_zone_file_name}" > /dev/null
		
		v_ipv6_gateway_adjusted_space=$(printf "%-*s" 63 "gateway")
		echo -e "${v_ipv6_gateway_adjusted_space} IN AAAA ${v_ipv6_gateway}" | tee -a "${v_zone_file_name}" > /dev/null
		
		v_dns_host_short_name_adjusted_space=$(printf "%-*s" 63 "${v_dns_host_short_name}")
		echo -e "${v_dns_host_short_name_adjusted_space} IN AAAA ${v_ipv6_address}" | tee -a "${v_zone_file_name}" > /dev/null
	fi

	echo -e "\n;CNAME-Records" | tee -a "${v_zone_file_name}" > /dev/null

	for v_subnet_part in ${v_splited_subnets}
	do
		v_zone_file_name="${var_zone_dir}/${v_subnet_part}.${v_given_domain}-reverse.db"
		fn_update_dns_server_data_to_zone_file "${v_zone_file_name}"
		echo -e "\n;PTR-Records" | tee -a "${v_zone_file_name}" > /dev/null
		if [[ "${v_subnet_part}" == "${v_first_subnet_part}" ]]
		then
			echo -e "0   IN PTR network.${v_given_domain}." | tee -a "${v_zone_file_name}" > /dev/null
			echo -e "1   IN PTR gateway.${v_given_domain}." | tee -a "${v_zone_file_name}" > /dev/null
			v_get_ip_part_primary_ip=$(echo "${v_primary_ip}" | awk -F. '{print $4}')
			v_ip_part_primary_ip_adjusted_space=$(printf "%-*s" 3 "${v_get_ip_part_primary_ip}")
			echo -e "${v_ip_part_primary_ip_adjusted_space} IN PTR ${v_dns_host_short_name}.${v_given_domain}." | tee -a "${v_zone_file_name}" > /dev/null
		elif [[ "${v_subnet_part}" == "${v_last_subnet_part}" ]]
		then
			echo -e "255 IN PTR broadcast.${v_given_domain}." | tee -a "${v_zone_file_name}" > /dev/null
		fi
	done

	# Create IPv6 reverse zone file if IPv6 is configured
	if [[ ! -z "${v_ipv6_address}" && ! -z "${v_ipv6_ula_subnet}" ]]; then
		v_ipv6_zone_file="${var_zone_dir}/${v_given_domain}-ipv6-reverse.db"
		fn_update_dns_server_data_to_zone_file "${v_ipv6_zone_file}"
		echo -e "\n;IPv6 PTR-Records" | tee -a "${v_ipv6_zone_file}" > /dev/null
		
		# Add PTR record for gateway (::1)
		echo -e "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0 IN PTR gateway.${v_given_domain}." | tee -a "${v_ipv6_zone_file}" > /dev/null
		
		# Add PTR record for DNS server's IPv6 address
		# Extract the IPv6 base prefix
		v_ipv6_base=$(echo "${v_ipv6_ula_subnet}" | cut -d'/' -f1 | sed 's/::$//')
		# Extract the host portion from the full IPv6 address
		v_ipv6_host_portion=$(echo "${v_ipv6_address}" | sed "s|${v_ipv6_base}:||" | sed 's/:://')
		# Convert to reverse notation (each nibble separated by dots)
		v_ipv6_ptr=$(echo "${v_ipv6_host_portion}" | awk -F':' '{
			result = ""
			for(i=1; i<=NF; i++) {
				if($i != "") {
					# Pad to 4 characters
					padded = sprintf("%04s", $i)
					gsub(/ /, "0", padded)
					# Reverse the string
					len=length(padded)
					for(j=len; j>=1; j--) {
						if(result != "") result = result "."
						result = result substr(padded,j,1)
					}
				}
			}
			print result
		}')
		
		if [[ ! -z "${v_ipv6_ptr}" ]]; then
			echo -e "${v_ipv6_ptr} IN PTR ${v_dns_host_short_name}.${v_given_domain}." | tee -a "${v_ipv6_zone_file}" > /dev/null
		fi
	fi

	print_task_done

	print_task "Enabling and starting named DNS Service..."

	systemctl enable --now named &>/dev/null	
	
	print_task_done

	print_task "Doing a final restart of named DNS Service..."

	systemctl restart named &>/dev/null	

	print_task_done

	print_task "Updating dnsbinder related global variables to /etc/environment..."
	declare -A dnsbinder_environment_map=(
		["dnsbinder_domain"]="$v_given_domain"
		["dnsbinder_network_cidr"]="$v_network_and_cidr"
		["dnsbinder_cidr_prefix"]="$v_cidr"
		["dnsbinder_first24_subnet"]="$v_first_subnet_part"
		["dnsbinder_last24_subnet"]="$v_last_subnet_part"
		["dnsbinder_netmask"]="$dnsbinder_netmask"
		["dnsbinder_gateway"]="$v_network_gateway"
		["dnsbinder_broadcast"]="${v_last_subnet_part}.255"
		["dnsbinder_server_ipv4_address"]="$v_primary_ip"
		["dnsbinder_server_short_name"]="$v_dns_host_short_name"
		["dnsbinder_server_fqdn"]="${v_dns_host_short_name}.${v_given_domain}"
	)

	# Add IPv6 variables if configured
	if [[ ! -z "${v_ipv6_address}" ]]; then
		dnsbinder_environment_map["dnsbinder_server_ipv6_address"]="$v_ipv6_address"
		dnsbinder_environment_map["dnsbinder_ipv6_gateway"]="$v_ipv6_gateway"
		dnsbinder_environment_map["dnsbinder_ipv6_prefix"]="$v_ipv6_prefix"
		dnsbinder_environment_map["dnsbinder_ipv6_ula_subnet"]="$v_ipv6_ula_subnet"
	fi

	target_environment_file="/etc/environment"

	# Ensure the environment file exists
	touch "$target_environment_file"

	# Iterate through all key-value pairs and update or append as necessary
	for environment_key in "${!dnsbinder_environment_map[@]}"; do
		environment_value="${dnsbinder_environment_map[$environment_key]}"
		if grep -q "^${environment_key}=" "$target_environment_file"; then
			# Update existing variable line
			sed -i "s|^${environment_key}=.*|${environment_key}=\"${environment_value}\"|" "$target_environment_file"
		else
			# Append new variable if not already present
			echo "${environment_key}=\"${environment_value}\"" | tee -a "$target_environment_file" > /dev/null
		fi
	done

	source /etc/environment

	print_task_done

	if ! $KVM_HOST_MODE_SET; then
		print_task "Updating Network Manager to point the local dns server and domain..."
		v_active_connection_name=$(nmcli connection show --active | grep "${v_primary_interface}" | head -n 1 | awk '{ print $1 }')
		nmcli connection modify "${v_active_connection_name}" ipv4.dns-search "${v_given_domain}" &>/dev/null
		nmcli connection modify "${v_active_connection_name}" ipv4.dns "127.0.0.1,8.8.8.8,8.8.4.4"  &>/dev/null
		nmcli connection reload "${v_active_connection_name}" &>/dev/null
		nmcli connection up "${v_active_connection_name}" &>/dev/null
		print_task_done
	else
		print_task "Updating systemd-resolvd to point the local dns server and domain..."
		if command -v resolvectl &>/dev/null; then
  				resolvectl dns labbr0 "$v_primary_ip"
  				resolvectl domain labbr0 "$v_given_domain"
		fi
		print_task_done
	fi

	print_task "Make named service as a dependency for network-online.target..."

	if ! $KVM_HOST_MODE_SET; then
		if [ ! -f /etc/systemd/system/network-online.target.wants/named.service ]; then
			ln -s /usr/lib/systemd/system/named.service /etc/systemd/system/network-online.target.wants/named.service 
		fi
	fi

	print_task_done

	print_task "Creating the command dnsbinder..."

	ln -s /server-hub/named-manage/dnsbinder.sh /usr/sbin/dnsbinder

	print_task_done

	# Display success message with dual-stack info if configured
	if [[ ! -z "${v_ipv6_address}" ]]; then
		print_success "All done! Your domain \"${v_given_domain}\" with dual-stack DNS server IPv4: ${v_primary_ip}, IPv6: ${v_ipv6_address} [ ${v_dns_host_short_name}.${v_given_domain} ] has been configured."
	else
		print_success "All done! Your domain \"${v_given_domain}\" with DNS server ${v_primary_ip} [ ${v_dns_host_short_name}.${v_given_domain} ] has been configured."
	fi
	print_info "Now you could manage the domain \"${v_given_domain}\" with dnsbinder utility from command line."

	exit
}

fn_instruct_on_valid_host_record() {
	print_error "> Only letters, numbers, and hyphens are allowed.
	> Hyphens cannot appear at the start or end.
	> The total length must be between 1 and 63 characters.
	> The domain name '${v_domain_name}' will be appended if not present.
	> Follows the format defined in RFC 1035."
	exit 1
}

fn_get_host_record() {
	v_input_host="${1}"
	v_action_requested="${2}"
	v_rename_record="${3}"

	fn_get_host_record_from_user() {

		while :
		do
			echo

			if [[ "${v_action_requested}" != "rename" ]]
			then
				read -p "Please Enter the name of host record to ${v_action_requested} : " v_input_host_record
			else
				if [ -z "${v_host_record}" ]
				then
					read -p "Please Enter the name of host record to ${v_action_requested} : " v_input_host_record
				else
					read -p "Please Enter the name of host record to ${v_action_requested} ${v_host_record}.${v_domain_name} : " v_input_host_record
				fi
			fi
				
			v_input_host_record="${v_input_host_record%.${v_domain_name}.}"  
			v_input_host_record="${v_input_host_record%.${v_domain_name}}"

			if [[ "${#v_input_host_record}" -le 63 ]] && [[ "${v_input_host_record}" =~ ^[[:alnum:]]([-[:alnum:]]*[[:alnum:]])$ ]]
	       		then
				if [[ "${v_action_requested}" != "rename" ]]
				then
					v_host_record="${v_input_host_record}"
				else
					if [ -z "${v_host_record}" ]
					then
						v_host_record="${v_input_host_record}"
					else
						v_rename_record="${v_input_host_record}"
					fi
				fi

    				break
  			else
				fn_instruct_on_valid_host_record
  			fi
		done
	}

	if [[ ! -z ${v_input_host} ]]
	then
                v_host_record=${1}
		v_host_record="${v_host_record%.${v_domain_name}.}"  
		v_host_record="${v_host_record%.${v_domain_name}}"

		if [[ ! ${v_host_record} =~ ^[[:alnum:]]([-[:alnum:]]*[[:alnum:]])$ ]] || [[ ! "${#v_host_record}" -le 63 ]]
		then
                        if ${v_if_autorun_false}
			then
				fn_instruct_on_valid_host_record
			else
				return 9
			fi
		fi

	else
		fn_get_host_record_from_user
	fi

	if grep "^${v_host_record} "  "${v_fw_zone}" &>/dev/null
	then 
		if [[ "${v_action_requested}" == "create" ]]
		then
			${v_if_autorun_false} && print_error "Host record for ${v_host_record}.${v_domain_name} already exists ! "
			${v_if_autorun_false} && print_error "Nothing to do ! Exiting !  "
			return 8

		elif [[ "${v_action_requested}" == "rename" ]]
		then
			if [[ ! -z ${v_rename_record} ]]
			then
				v_rename_record="${v_rename_record%.${v_domain_name}.}"  
				v_rename_record="${v_rename_record%.${v_domain_name}}"

				if [[ ! ${v_rename_record} =~ ^[[:alnum:]]([-[:alnum:]]*[[:alnum:]])$ ]] || [[ ! "${#v_rename_record}" -le 63 ]]
				then
					fn_instruct_on_valid_host_record
				fi
			else
				fn_get_host_record_from_user
			fi

			if grep "^${v_rename_record} "  "${v_fw_zone}" &>/dev/null
			then 
				print_error "Conflict ! Existing host record found for ${v_rename_record}.${v_domain_name} ! "
				print_error "Nothing to do ! Exiting !  "
				exit
			fi
		fi

	elif [[ "${v_action_requested}" != "create" ]]
	then
		if ${v_if_autorun_false}
		then
			print_error "Host record for ${v_host_record}.${v_domain_name} doesn't exist ! "
			print_error "Nothing to do ! Exiting ! "
			exit
		else
			return 8
		fi
		
	fi
}


fn_update_serial_number_of_zones() {

	${v_if_autorun_false} && print_task "Updating serial numbers of zone files..."

	v_current_serial_fw_zone=$(grep ';Serial' "${v_fw_zone}" | cut -d ";" -f 1 | tr -d '[:space:]')
	v_set_new_serial_fw_zone=$(( v_current_serial_fw_zone + 1 ))
	sed -i "/;Serial/s/${v_current_serial_fw_zone}/${v_set_new_serial_fw_zone}/g" "${v_fw_zone}"

	if [[ "${1}" != "forward-zone-only" ]]
	then
		v_current_serial_ptr_zone=$(grep ';Serial' "${v_ptr_zone}" | cut -d ";" -f 1 | tr -d '[:space:]')
		v_set_new_serial_ptr_zone=$(( v_current_serial_ptr_zone + 1 ))
		sed -i "/;Serial/s/${v_current_serial_ptr_zone}/${v_set_new_serial_ptr_zone}/g" "${v_ptr_zone}"
	fi

	${v_if_autorun_false} && print_task_done
}


fn_reload_named_dns_service() {

	cname_record_true="${1}"

	if [[ "${cname_record_true}" != "true" ]]; then
		cname_record_true="false"
	fi

	print_task "Reloading the DNS service (named)..."

	systemctl reload named &>/dev/null

	if systemctl is-active named &>/dev/null;
	then 
		print_task_done
	else
		print_task_fail
	fi
        
	if [[  "${v_action_requested}" == "create" ]]
	then
		if "${cname_record_true}"
		then
			print_success "Successfully created cname record ${v_input_cname}.${v_domain_name}"
		else
			print_success "Successfully created host record ${v_host_record}.${v_domain_name}"
		fi
	 
	elif [[ "${v_action_requested}" == "delete" ]]
	then
		if "${cname_record_true}"
		then
			print_success "Successfully deleted cname record ${v_input_cname}.${v_domain_name}"
		else
			print_success "Successfully deleted host record ${v_host_record}.${v_domain_name}"
		fi

	elif [[ "${v_action_requested}" == "rename" ]]
	then
        	print_success "Successfully renamed host ${v_host_record}.${v_domain_name} to ${v_rename_record}.${v_domain_name}"
	fi

	if "${cname_record_true}" && [[ "${v_action_requested}" == "create" ]]
	then
		print_task "Validating CNAME record..."
		if host ${v_input_cname}.${v_domain_name} &>/dev/null
		then
			print_task_done
		else
			print_task_fail
		fi

		print_info "FYI :\n$(host ${v_input_cname}.${v_domain_name})"

		return
	fi

	if [[ "${v_action_requested}" != "delete" ]]
	then

		print_task "Validating forward look up..."

		if  [[ "${v_action_requested}" == "rename" ]]
		then
			if host ${v_rename_record}.${v_domain_name} &>/dev/null
			then
				print_task_done
			else
				print_task_fail
			fi
		else
			if host ${v_host_record}.${v_domain_name} &>/dev/null
			then
				print_task_done
			else
				print_task_fail
			fi
		fi

		print_task "Validating reverse look up..."

		if host ${v_current_ip_of_host_record} &>/dev/null
		then
                	print_task_done
                else
                	print_task_fail
                fi

		if  [[ "${v_action_requested}" == "rename" ]]
                then
			print_info "FYI : $(host ${v_rename_record}.${v_domain_name})"
		else
			print_info "FYI : $(host ${v_host_record}.${v_domain_name})"
		fi
	fi
}

fn_set_ptr_zone() {

	arr_subnets=()
	arr_ptr_zones=()

	for ((v_zone_number=1; v_zone_number<=v_total_ptr_zones; v_zone_number++))
	do
    		arr_subnet_var="v_subnet${v_zone_number}"
    		arr_ptr_zone_var="v_ptr_zone${v_zone_number}"
    		arr_subnets+=( "$(eval echo \${${arr_subnet_var}})" )
    		arr_ptr_zones+=( "$(eval echo \${${arr_ptr_zone_var}})" )
	done

	for i in "${!arr_subnets[@]}"
	do
    		if [[ "${v_current_ip_of_host_record}" =~ ${arr_subnets[i]} ]]
		then
        		${v_if_autorun_false} && print_info "Match found with IP ${v_current_ip_of_host_record} for host record ${v_host_record}.${v_domain_name}"
        		v_ptr_zone="${arr_ptr_zones[i]}"
        		break
    		fi
	done
}

fn_get_ipv4_address() {

	ipv4_provided="${1}"

	fn_validate_ipv4_address() {
    		local ipv4_provided="$1"
    		local octet

    		# Use a regex pattern for IPv4 validation
    		if [[ "$ipv4_provided" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        		# Check if each octet is in the range 0-255
        		for octet in ${BASH_REMATCH[@]:1}; do
            			if (( octet < 0 || octet > 255 )); then
                			print_error "Invalid input provided for IPv4 Address ! "
					fn_get_ipv4_address
            			fi
        		done
    		else
    			print_error "Invalid input provided for IPv4 Address ! "
			fn_get_ipv4_address
    		fi
	}

	if [[ -z "${ipv4_provided}" ]]; then
		read -p "Provide the required IPv4 Address ( within ${dnsbinder_network} ) : " ipv4_provided
	fi

	fn_validate_ipv4_address "${ipv4_provided}"

	# Convert IP to decimal
	fn_convert_ip_to_decimal() {
    		IFS=. read -r ipv4_octet1 ipv4_octet2 ipv4_octet3 ipv4_octet4 <<< "${1}"
    		echo $(( (ipv4_octet1 << 24) + (ipv4_octet2 << 16) + (ipv4_octet3 << 8) + ipv4_octet4 ))
	}

	# Function to check if an IP is within a CIDR range
	fn_check_whether_ip_in_range() {
    		local ipv4_provided="${1}"
    		local dnsbinder_network="${2}"

    		# Split network into base IP and prefix length
    		IFS='/'
    		read -r network_base network_mask <<< "${dnsbinder_network}"

    		# Convert IPs to decimal
    		decimal_value_of_ipv4=$(fn_convert_ip_to_decimal "${ipv4_provided}")
    		decimal_value_of_network=$(fn_convert_ip_to_decimal "${network_base}")

    		# Calculate network range
    		range_size=$(( 32 - network_mask ))
    		net_start=$(( decimal_value_of_network & (0xFFFFFFFF << range_size) ))
    		net_end=$(( net_start | ((1 << range_size) - 1) ))

    		# Check if IP falls within range
    		if (( decimal_value_of_ipv4 >= net_start && decimal_value_of_ipv4 <= net_end )); then
        		return 0  # IP is in range
    		else
        		return 1  # IP is NOT in range
    		fi
	}

	while :
	do
		if fn_check_whether_ip_in_range "${ipv4_provided}" "${dnsbinder_network}"; then
			break
		else
			print_error "Provided IPv4 address doesn't reside within the network ${dnsbinder_network} ! "
			fn_get_ipv4_address
		fi
	done
}

fn_create_host_record() {

	if [[ "${2}" != "Automated-Execution" ]]
	then
		v_if_autorun_false=true	
	else
		v_if_autorun_false=false	
	fi

	fn_get_host_record "${1}" "create"

	v_exit_status_fn_get_host_record=${?}

	if [[ ${v_exit_status_fn_get_host_record} -ne 0 ]]
	then
		return ${v_exit_status_fn_get_host_record}
	fi

	if [ ! -z "${specific_ipv4_requested}" ] ; then
		fn_get_ipv4_address "${2}"
	fi

	fn_check_free_ip() {

		local v_file_ptr_zone="${1}"
		local v_start_ip="${2}"
		local v_max_ip="${3}"
		local v_subnet="${4}"
		local v_capture_list_of_ips=$(sed -n 's/^\([0-9]\+\).*/\1/p' "${v_file_ptr_zone}")
		declare -A v_existing_ips

		if [ -z "${v_capture_list_of_ips}" ]
		then
			v_host_part_of_current_ip="${v_start_ip}"
			v_current_ip_of_host_record="${v_subnet}.${v_host_part_of_current_ip}"
			v_previous_ip=';PTR-Records'
			v_ptr_zone="${v_file_ptr_zone}"
			return 0
		fi


		while IFS= read -r ip
		do
        		v_existing_ips["$ip"]=1
		done <<< "${v_capture_list_of_ips}"

		if [[ "${#v_existing_ips[@]}" -eq 1 ]]
		then
			if grep -q "broadcast.${v_domain_name}." "${v_file_ptr_zone}" 
			then
				v_host_part_of_current_ip="${v_start_ip}"
				v_current_ip_of_host_record="${v_subnet}.${v_host_part_of_current_ip}"
				v_previous_ip=';PTR-Records'
				v_ptr_zone="${v_file_ptr_zone}"
				return 0
			fi
		fi

		for ((v_num_ptr = ${v_start_ip}; v_num_ptr <= ${v_max_ip}; v_num_ptr++))
		do
			if [[ -z "${v_existing_ips[$v_num_ptr]+isset}" ]]
			then
				v_host_part_of_current_ip="${v_num_ptr}"
				v_current_ip_of_host_record="${v_subnet}.${v_host_part_of_current_ip}"
				v_ptr_zone="${v_file_ptr_zone}"
				
				if [[ ${v_num_ptr} -eq 0 ]]
				then
					v_previous_ip=';PTR-Records'
				else
					v_host_part_of_previous_ip=$((v_num_ptr - 1))
					v_previous_ip="${v_subnet}.${v_host_part_of_previous_ip}"
				fi
				return 0
			fi
		done
		
		# No free IP found in this zone
		return 1
	}	
	
	
	count_houseful_ptr_zones=0
	for ((v_zone_number=1; v_zone_number<=v_total_ptr_zones; v_zone_number++))
	do
		v_current_ptr_zone_file="v_ptr_zone${v_zone_number}"

		v_current_ptr_zone_file="${!v_current_ptr_zone_file}"

		v_total_ips_in_current_zone=$(sed -n 's/^\([0-9]\+\).*/\1/p' "${v_current_ptr_zone_file}" | wc -l)

		v_current_subnet="v_subnet${v_zone_number}"

		v_current_subnet="${!v_current_subnet}"

		if [[ ! -z "${ipv4_provided}" ]]
		then
			IFS='.' read -r ipv4_octet1 ipv4_octet2 ipv4_octet3 ipv4_octet4 <<< "${ipv4_provided}"
			subnet_part_of_ipv4_provided="${ipv4_octet1}.${ipv4_octet2}.${ipv4_octet3}"
			host_part_of_ipv4_provided="${ipv4_octet4}"
			
			if [[ "${v_current_subnet}" == "${subnet_part_of_ipv4_provided}" ]]
			then	
				if grep "^${host_part_of_ipv4_provided} " "${v_current_ptr_zone_file}" &>/dev/null  	
				then
					print_error "Record already exists for provided IPv4 address ${ipv4_provided} !"
					host  ${ipv4_provided}
					print_warning "Please try again with another IPv4 address ! "
					exit 1
				else
					mapfile -t v_list_of_ips_in_zone < <(sed -n 's/^\([0-9]\+\).*/\1/p' "${v_current_ptr_zone_file}" | sort -n)
					v_host_part_of_current_ip="${host_part_of_ipv4_provided}"
					v_current_ip_of_host_record="${subnet_part_of_ipv4_provided}.${v_host_part_of_current_ip}"
					v_ptr_zone="${v_current_ptr_zone_file}"
					if [[ ! -z "${v_list_of_ips_in_zone[@]}" ]]
					then
						v_count_less=0
						for ptr_ip in "${v_list_of_ips_in_zone[@]}"
						do
							if [[ "${ptr_ip}" -lt "${v_host_part_of_current_ip}" ]]
							then
								v_host_part_of_previous_ip="${ptr_ip}"
								((v_count_less++))
								continue
							else
								break
							fi
						done

						if [[ "${v_count_less}" -eq 0 ]]
						then
							v_previous_ip=';PTR-Records'
						else	
							v_previous_ip="${subnet_part_of_ipv4_provided}.${v_host_part_of_previous_ip}"
						fi
					else
						v_previous_ip=';PTR-Records'
					fi
				fi
			else
				continue
			fi

		else

			if [[ ${v_total_ips_in_current_zone} -ne 256 ]]
			then
				if fn_check_free_ip "${v_current_ptr_zone_file}" "0" "255" "${v_current_subnet}"
				then
					# Found a free IP in this zone
					break
				else
					# This zone is exhausted even though it has < 256 records (sparse allocation)
					((count_houseful_ptr_zones++))
					if [[ "${count_houseful_ptr_zones}" -eq "${v_total_ptr_zones}" ]]
					then
						${v_if_autorun_false} && print_error "No more IP addresses are available in the ${dnsbinder_network} network of ${v_domain_name} domain ! "
						return 255
					else
						continue
					fi
				fi
			else
				((count_houseful_ptr_zones++))
				if [[ "${count_houseful_ptr_zones}" -eq "${v_total_ptr_zones}" ]]
				then
					${v_if_autorun_false} && print_error "No more IP addresses are available in the ${dnsbinder_network} network of ${v_domain_name} domain ! "
					return 255
				else
					continue
				fi
			fi
		fi
	done


	${v_if_autorun_false} && print_task "Creating host record ${v_host_record}.${v_domain_name}..."

	############### A Record Creation Section ############################

	v_host_record_adjusted_space=$(printf "%-*s" 63 "${v_host_record}")

	v_add_host_record=$(echo "${v_host_record_adjusted_space} IN A ${v_current_ip_of_host_record}")

	if [[ "${v_previous_ip}" == ';PTR-Records' ]]
	then
		sed -i "/^broadcast /i \\${v_add_host_record}" "${v_fw_zone}"
	else
		sed -i "/${v_previous_ip}$/a \\${v_add_host_record}" "${v_fw_zone}"
	fi

	##################  End of  A Record Create Section ############################

	############### AAAA Record Creation Section (IPv6 dual-stack) ############################

	# Add AAAA record if IPv6 is configured
	if [[ ! -z "${dnsbinder_ipv6_ula_subnet}" && ! -z "${dnsbinder_ipv6_gateway}" ]]; then
		# Convert IPv4 to IPv6 using the mapping scheme
		IFS=. read -r oct1 oct2 oct3 oct4 <<< "$v_current_ip_of_host_record"
		
		# Extract IPv6 prefix base from gateway
		ipv6_prefix_base=$(echo "$dnsbinder_ipv6_gateway" | sed 's/::[^:]*$//')
		
		# Build IPv6 address: prefix:subnet_encoding:ipv4_full
		group5=$(printf "%02x%02x" $oct1 $oct2)
		group6=$(printf "00%02x" $oct3)
		group7=$(printf "%02x%02x" $oct1 $oct2)
		group8=$(printf "%02x%02x" $oct3 $oct4)
		
		v_ipv6_address_for_host="${ipv6_prefix_base}:${group5}:${group6}:${group7}:${group8}"
		
		v_add_ipv6_host_record=$(echo "${v_host_record_adjusted_space} IN AAAA ${v_ipv6_address_for_host}")
		
		# Find the position after the A record we just added
		sed -i "/${v_host_record_adjusted_space} IN A ${v_current_ip_of_host_record}/a \\${v_add_ipv6_host_record}" "${v_fw_zone}"
	fi

	##################  End of  AAAA Record Create Section ############################



	################## PTR Record Create  Section ###################################

	v_space_adjusted_host_part_of_current_ip=$(printf "%-*s" 3 "${v_host_part_of_current_ip}")

	v_add_ptr_record=$(echo "${v_space_adjusted_host_part_of_current_ip} IN PTR ${v_host_record}.${v_domain_name}.")

	if [[ "${v_previous_ip}" == ';PTR-Records' ]]
	then
		sed -i "/^;PTR-Records/a\\${v_add_ptr_record}" "${v_ptr_zone}"
	else
		sed -i "/^${v_host_part_of_previous_ip} /a\\${v_add_ptr_record}" "${v_ptr_zone}"
	fi

	############# End of PTR Record Create Section #######################


	${v_if_autorun_false} && print_task_done

	fn_update_serial_number_of_zones

	if ${v_if_autorun_false}
	then
		fn_reload_named_dns_service
	fi
}


fn_delete_host_record() {

	if [[ "${3}" != "Automated-Execution" ]]
	then
		v_if_autorun_false=true	
	else
		v_if_autorun_false=false	
	fi

	fn_get_host_record "${1}" "delete"

	v_exit_status_fn_get_host_record=${?}

	if [[ ${v_exit_status_fn_get_host_record} -ne 0 ]]
	then
		return ${v_exit_status_fn_get_host_record}
	fi

	v_capture_host_record=$(grep "^${v_host_record} " "${v_fw_zone}" ) 
	v_current_ip_of_host_record=$(grep "^${v_host_record} " ${v_fw_zone} | awk '{print $NF}' | tr -d '[:space:]')
	v_capture_ptr_prefix=$(awk -F. '{ print $4 }' <<< ${v_current_ip_of_host_record} )

	fn_set_ptr_zone
	v_input_delete_confirmation="${2}"

	while :
	do
		if [[ ! ${v_input_delete_confirmation} == "-y" ]]
		then
			read -p "Please confirm deletion of records (y/n) : " v_confirmation
		else
			v_confirmation='y'
		fi

		if [[ ${v_confirmation} == "y" ]]
		then
			${v_if_autorun_false} && print_task "Deleting host record ${v_host_record}.${v_domain_name}..."

			sed -i "/^${v_capture_ptr_prefix} /d" "${v_ptr_zone}"
			sed -i "/^${v_capture_host_record}/d" "${v_fw_zone}"
			
			# Also delete AAAA record if it exists (IPv6 dual-stack)
			sed -i "/^${v_host_record} .*IN AAAA/d" "${v_fw_zone}"

			${v_if_autorun_false} && print_task_done

			fn_update_serial_number_of_zones

			if ${v_if_autorun_false}
			then
				fn_reload_named_dns_service
			fi

			break

		elif [[ ${v_confirmation} == "n" ]]
		then
			print_warning "Cancelled without any changes ! "
			break

		else
			print_error "Select only either (y/n) ! "
			continue

		fi
	done
}

fn_rename_host_record() {

	if [[ "${3}" != "Automated-Execution" ]]
	then
		v_if_autorun_false=true	
	else
		v_if_autorun_false=false	
	fi

	fn_get_host_record "${1}" "rename" "${2}"

	v_exit_status_fn_get_host_record=${?}

	if [[ ${v_exit_status_fn_get_host_record} -ne 0 ]]
	then
		return ${v_exit_status_fn_get_host_record}
	fi

	v_host_record_exist=$(grep "^$v_host_record " $v_fw_zone)
	v_current_ip_of_host_record=$(grep "^$v_host_record " $v_fw_zone | cut -d "A" -f 2 | tr -d '[[:space:]]')

	fn_set_ptr_zone

	v_host_record_rename=$(printf "%-*s" 63 "${v_rename_record}")
	v_host_record_rename=$(echo "$v_host_record_rename IN A ${v_current_ip_of_host_record}")

	v_input_rename_confirmation="${3}"
	
	while :
	do
		if [[ ! ${v_input_rename_confirmation} == "-y" ]]
		then
			read -p "Please confirm to rename the record ${v_host_record}.${v_domain_name} to ${v_rename_record}.${v_domain_name} (y/n) : " v_confirmation
		else
			v_confirmation='y'
		fi

		if [[ $v_confirmation == "y" ]]
		then
			print_task "Renaming host record ${v_host_record}.${v_domain_name} to ${v_rename_record}.${v_domain_name}..."

			sed -i "s/${v_host_record_exist}/${v_host_record_rename}/g" ${v_fw_zone}
			sed -i "s/${v_host_record}.${v_domain_name}./${v_rename_record}.${v_domain_name}./g" ${v_ptr_zone}
			
			# Also rename AAAA record if it exists (IPv6 dual-stack)
			sed -i "s/^${v_host_record} \(.*\)IN AAAA/${v_rename_record} \1IN AAAA/g" ${v_fw_zone}

			print_task_done
			
			fn_update_serial_number_of_zones

			if ${v_if_autorun_false}
			then
				fn_reload_named_dns_service
			fi

			break

		elif [[ $v_confirmation == "n" ]]
		then
			print_warning "Cancelled without any changes ! "
			break

		else
			print_error "Select only either (y/n) ! "
			continue

		fi
	done
}

fn_handle_multiple_host_record() {		

	touch /tmp/dnsbinder_fn_handle_multiple_host_record.lock

	v_host_list_file="${1}"
	v_action_required="${2}"

	clear

	fn_progress_title() {
	
		if [[ ${v_action_required} == "create" ]]
		then
			print_cyan "#############################(DNS-Bulk-Records-Maker)##############################"

		elif [[ ${v_action_required} == "delete" ]]
		then
			print_cyan "###########################(DNS-Bulk-Records-Destroyer)############################"
		fi
	}

	fn_progress_title
	
	if [ -z "${v_host_list_file}" ]
	then
		echo
		print_notify "Name of the file containing the list of host records to ${v_action_required} : " 
		read -e v_host_list_file
	fi
	
	if [[ ! -f ${v_host_list_file} ]];then print_error "File \"${v_host_list_file}\" doesn't exist!\n";exit;fi 
	
	if [[ ! -s ${v_host_list_file} ]];then print_error "File \"${v_host_list_file}\" is emty!\n";exit;fi
	
	sed -i '/^[[:space:]]*$/d' ${v_host_list_file}
	
	sed -i 's/.${v_domain_name}.//g' ${v_host_list_file}
	
	sed -i 's/.${v_domain_name}//g' ${v_host_list_file}
	
	
	while :
	do
		print_info "Records to be ${v_action_required^}d : "
	
		cat ${v_host_list_file}
	
		echo
		print_notify "Provide your confirmation to ${v_action_required} the above host records (y/n) : " "nskip"
		
		read v_confirmation
	
		if [[ ${v_confirmation} == "y" ]]
		then
			break
	
		elif [[ ${v_confirmation} == "n" ]]
		then
			print_error "Cancelled without any changes !!"
			exit
		else
			print_error "Select either (y/n) only !"
			continue
		fi
	done
	
	> "${v_tmp_file_dnsbinder}"
	
	v_count_successfull=0
	v_count_failed=0
	v_count_invalid_host=0
	v_count_already_exists=0
	v_count_doesnt_exist=0
	v_count_ip_exhausted=0
	v_count_other_failures=0
	
	v_pre_execution_serial_fw_zone=$(grep ';Serial' ${v_fw_zone} | cut -d ";" -f 1 | tr -d '[:space:]')
	
	v_total_host_records=$(wc -l < "${v_host_list_file}")
	
	v_host_count=0
	
	# Show initial header once
	clear
	fn_progress_title
	
	while read -r v_host_record
	do
		# Update progress header in place (move cursor to top)
		tput cup 1 0
		print_cyan "####################################( Running )####################################"
		print_white "Status     : [ ${v_host_count}/${v_total_host_records} ] host records have been processed"
		print_green "Successful : ${v_count_successfull}"
		print_red "Failed     : ${v_count_failed}"
		
		let v_host_count++
		
		print_task "Attempting to ${v_action_required} the host record ${v_host_record}.${v_domain_name} . . . " "nskip"
	
		v_serial_fw_zone_pre_execution=$(grep ';Serial' ${v_fw_zone} | cut -d ";" -f 1 | tr -d '[:space:]')
	
		if [[ ${v_action_required} == "create" ]]
                then
			fn_create_host_record "${v_host_record}" "Automated-Execution"
			var_exit_status=${?}

		elif [[ ${v_action_required} == "delete" ]]
		then
			fn_delete_host_record "${v_host_record}" -y "Automated-Execution"
			var_exit_status=${?}
		fi
	
		v_serial_fw_zone_post_execution=$(grep ';Serial' ${v_fw_zone} | cut -d ";" -f 1 | tr -d '[:space:]')
	
	        v_fqdn="${v_host_record}.${v_domain_name}"
	
	        
		if [[ ${v_action_required} == "create" ]]
		then
			v_ip_address=$(grep -w "^${v_host_record} " "${v_fw_zone}" | grep "IN A " | awk '{print $NF}' | tr -d '[:space:]')
			v_ipv6_address=$(grep -w "^${v_host_record} " "${v_fw_zone}" | grep "IN AAAA " | awk '{print $NF}' | tr -d '[:space:]')
	
			if [[ -z "${v_ip_address}" ]]; then
	        		v_ip_address="N/A"
	    		fi
	    		
	    		# Build address display (dual-stack)
	    		if [[ ! -z "${v_ipv6_address}" ]]; then
	    			v_address_display="IPv4: ${v_ip_address}, IPv6: ${v_ipv6_address}"
	    		else
	    			v_address_display="${v_ip_address}"
	    		fi
		fi
	
		if [[ ${v_action_required} == "create" ]]
		then
			v_details_of_host_record="${v_fqdn} ( ${v_address_display} )"

		elif [[ ${v_action_required} == "delete" ]]
		then
			v_details_of_host_record="${v_fqdn}"
		fi
			
	if [[ ${var_exit_status} -eq 9 ]]
	then
        	print_red "Invalid-Host     ${v_details_of_host_record}" >> "${v_tmp_file_dnsbinder}"
		print_task_fail
		let v_count_failed++
		let v_count_invalid_host++ 

	elif [[ ${var_exit_status} -eq 8 ]]
	then
		if [[ ${v_action_required} == "create" ]]
                then
			v_existence_state="Already-Exists  "

		elif [[ ${v_action_required} == "delete" ]]
		then
			v_existence_state="Doesn't-Exist   "
		fi

        	print_yellow "${v_existence_state} ${v_details_of_host_record}" >> "${v_tmp_file_dnsbinder}"
		print_task_fail
		let v_count_failed++
		if [[ ${v_action_required} == "create" ]]; then
			let v_count_already_exists++
		else
			let v_count_doesnt_exist++
		fi

	elif [[ ${var_exit_status} -eq 255 ]]
	then
        	print_red "IP-Exhausted     ${v_details_of_host_record}" >> "${v_tmp_file_dnsbinder}"
		print_task_fail
		let v_count_failed++
		let v_count_ip_exhausted++
	else
		v_serial_fw_zone_post_execution=$(grep ';Serial' ${v_fw_zone} | cut -d ";" -f 1 | tr -d '[:space:]')

		if [[ "${v_serial_fw_zone_pre_execution}" -ne "${v_serial_fw_zone_post_execution}" ]]
		then
			print_green "${v_action_required^}d          ${v_details_of_host_record}" >> "${v_tmp_file_dnsbinder}"
			print_task_done
			let v_count_successfull++
		else
        		print_red "Failed-to-${v_action_required^} ${v_details_of_host_record}" >> "${v_tmp_file_dnsbinder}"
			print_task_fail
			let v_count_failed++
			let v_count_other_failures++
		fi
	fi

	# Clear from cursor to end of screen for next iteration
	tput ed
	
	done < "${v_host_list_file}"

	# Clear the progress display before showing final summary
	clear

	v_post_execution_serial_fw_zone=$(grep ';Serial' ${v_fw_zone} | cut -d ";" -f 1 | tr -d '[:space:]')
	
	if [[ "${v_pre_execution_serial_fw_zone}" -ne "${v_post_execution_serial_fw_zone}" ]]
	then
		print_task "Reloading the DNS service (named) for the changes to take effect..."
	
		systemctl reload named &>/dev/null
	
		if systemctl is-active named &>/dev/null;
		then 
			print_task_done
		else
			print_task_fail
		fi
	else
		print_yellow "No changes done! Nothing to do!"
	fi
		
	print_white "Please find the below details of the records:"

	if [[ ${v_action_required} == "create" ]]
	then
		if [[ ! -z "${dnsbinder_ipv6_ula_subnet}" ]]; then
			print_white "Action-Taken     FQDN ( IPv4-Address, IPv6-Address )"
		else
			print_white "Action-Taken     FQDN ( IPv4-Address )"
		fi

	elif [[ ${v_action_required} == "delete" ]]
	then
		print_white "Action-Taken     FQDN"
	fi
	
	cat "${v_tmp_file_dnsbinder}"
	
	# Final completion summary with title and breakdown
	fn_progress_title
	print_cyan "###################################( Completed )###################################"
	print_white "Total      : ${v_total_host_records} host records processed"
	print_green "Successful : ${v_count_successfull}"
	print_red "Failed     : ${v_count_failed}"
	
	# Show failure breakdown if there were failures
	if [[ ${v_count_failed} -gt 0 ]]; then
		print_white "Failure Breakdown:"
		if [[ ${v_count_invalid_host} -gt 0 ]]; then
			print_red "  Invalid Host    : ${v_count_invalid_host}"
		fi
		if [[ ${v_count_already_exists} -gt 0 ]]; then
			print_yellow "  Already Exists  : ${v_count_already_exists}"
		fi
		if [[ ${v_count_doesnt_exist} -gt 0 ]]; then
			print_yellow "  Doesn't Exist   : ${v_count_doesnt_exist}"
		fi
		if [[ ${v_count_ip_exhausted} -gt 0 ]]; then
			print_red "  IP Exhausted    : ${v_count_ip_exhausted}"
		fi
		if [[ ${v_count_other_failures} -gt 0 ]]; then
			print_red "  Other Failures  : ${v_count_other_failures}"
		fi
	fi
	
	rm -f "${v_tmp_file_dnsbinder}"

	rm -f /tmp/dnsbinder_fn_handle_multiple_host_record.lock
}

fn_get_cname_record() {

	v_action_requested="${1}"

	fn_get_cname_record_from_user() {
		while :
		do
			if [ -z "${v_input_cname}" ]
			then
				if [[ "${v_action_requested}" == "create" ]]
				then
					read -p "Please Enter the name of CNAME record to ${v_action_requested} : " v_input_cname
				elif  [[ "${v_action_requested}" == "delete" ]]
				then
					read -p "Please Enter the name of CNAME record to ${v_action_requested} : " v_input_cname
				fi
			fi
				
			v_input_cname="${v_input_cname%.${v_domain_name}.}"  
			v_input_cname="${v_input_cname%.${v_domain_name}}"

			if [[ ! "${#v_input_cname}" -le 63 ]] || [[ ! "${v_input_cname}" =~ ^[[:alnum:]]([-[:alnum:]]*[[:alnum:]])$ ]]
	       		then
				fn_instruct_on_valid_host_record
  			fi

			break
		done
	}

	fn_get_hostname_record_from_user() {
		while :
		do
			if [ -z "${v_input_hostname}" ]
			then
				read -p "Please Enter the host record to which CNAME \"${v_input_cname}\" is required : " v_input_hostname
			fi
				
			v_input_hostname="${v_input_hostname%.${v_domain_name}.}"  
			v_input_hostname="${v_input_hostname%.${v_domain_name}}"

			if [[ ! "${#v_input_hostname}" -le 63 ]] || [[ ! "${v_input_hostname}" =~ ^[[:alnum:]]([-[:alnum:]]*[[:alnum:]])$ ]]
	       		then
				fn_instruct_on_valid_host_record
  			fi

			break
		done
	}

	fn_get_cname_record_from_user

	if [[ "${v_action_requested}" == "create" ]]
	then
		if grep -q "^${v_input_cname} " <<< $(sed -n '/;CNAME-Records/,$p' "${v_fw_zone}")
		then 
			print_error "CNAME record for \"${v_input_cname}.${v_domain_name}\" already exists! "
			exit 1

		elif grep -q "^${v_input_cname} "  <<< $(sed -n '/;A-Records/,/;CNAME-Records/{//!p;}' "${v_fw_zone}")
		then
			print_error "Conflict! Already a host record exists with the same name of CNAME \"${v_input_cname}.${v_domain_name}\" ! "
			exit 1
		fi

		fn_get_hostname_record_from_user

		if ! grep -q "^${v_input_hostname} "  <<< $(sed -n '/;A-Records/,/;CNAME-Records/{//!p;}' "${v_fw_zone}")
		then
			print_error "Provided host record \"${v_input_hostname}.${v_domain_name}\" doesn't exist to create CNAME \"${v_input_cname}.${v_domain_name}\" ! "
			exit 1
		fi
	fi

	if [[ "${v_action_requested}" == "delete" ]]
	then
		if ! grep -q "^${v_input_cname} " <<< $(sed -n '/;CNAME-Records/,$p' "${v_fw_zone}")
		then 
			print_error "CNAME record for ${v_input_cname}.${v_domain_name} doesn't exist! "
			exit 1
		fi
	fi
}

fn_create_cname_record() {
	v_input_cname="${1}"
	v_input_hostname="${2}"
	
	fn_get_cname_record "create"

	print_task "Creating CNAME record \"${v_input_cname}.${v_domain_name}\" for the host record \"${v_input_hostname}.${v_domain_name}\"..."

	v_cname_adjusted_space=$(printf "%-*s" 63 "${v_input_cname}")

	v_cname_record=$(echo "${v_cname_adjusted_space} IN CNAME ${v_input_hostname}.${v_domain_name}.")

	sed -i "/^;CNAME-Records/a \\${v_cname_record}" "${v_fw_zone}"

	print_task_done

	fn_update_serial_number_of_zones "forward-zone-only"

	fn_reload_named_dns_service "true"
}

fn_delete_cname_record() {
	v_input_cname="${1}"
	v_input_delete_confirmation="${2}"

	fn_get_cname_record "delete"

	while :
	do
		print_warning "CNAME Record to be deleted : $(grep 'alias' <<< $(host ${v_input_cname}.${v_domain_name})) "
		if [[ ! ${v_input_delete_confirmation} == "-y" ]]
		then
			read -p "Please confirm deletion of cname record \"${v_input_cname}.${v_domain_name}\" (y/n) : " v_confirmation
		else
			v_confirmation='y'
		fi

		case "${v_confirmation}" in
			y|Y|"yes")
				break
				;;
			n|N|"no")
				print_warning "Aborted ! No changes done! "
				exit
				;;
			"")
				print_error "No Input Provided! "
				continue
				;;
			*)
				print_error "Invalid Input! "
				continue
				;;
		esac
	done

	print_task "Deleting CNAME record \"${v_input_cname}.${v_domain_name}\"..."

	sed -i "/^${v_input_cname} / {/IN CNAME/d}" "${v_fw_zone}" 

	print_task_done

	fn_update_serial_number_of_zones "forward-zone-only"

	fn_reload_named_dns_service "true"
}

v_domain_if_present=$(if [ ! -z "${v_domain_name}" ];then echo -n "${v_domain_name}";else echo '[dnsbinder-not-yet-configured]';fi)
v_domain_if_present=$(printf "%-*s" 53 "${v_domain_if_present}")
v_network_if_present=$(if [ ! -z "${dnsbinder_network}" ];then echo -n "${dnsbinder_network}";else echo '[dnsbinder-not-yet-configured]';fi)
v_network_if_present=$(printf "%-*s" 53 "${v_network_if_present}")
v_ipv6_if_present=$(if [ ! -z "${dnsbinder_ipv6_ula_subnet}" ];then echo -n "${dnsbinder_ipv6_ula_subnet}";else echo '[ipv6-not-configured]';fi)
v_ipv6_if_present=$(printf "%-*s" 53 "${v_ipv6_if_present}")

fn_main_menu() {

print_notify "##################################################################
#-------------------------[ DNS-BINDER ]-------------------------#
# Domain  : ${v_domain_if_present}#
# IPv4 Net: ${v_network_if_present}#
# IPv6 Net: ${v_ipv6_if_present}#
#----------------------------------------------------------------#
# 1) Create a DNS host record (dual-stack A + AAAA)              #
# 2) Delete a DNS host record (removes A + AAAA)                 #
# 3) Rename an existing DNS host record (updates A + AAAA)       #
# 4) Create multiple DNS host records provided in a file         #
# 5) Delete multiple DNS host records provided in a file         #
# 6) Create DNS host with specific IPv4 (auto-generates IPv6)    #
# 7) Create a CNAME/Alias record for existing host record        #
# 8) Delete a CNAME/Alias record for existing host record        #
#----------------------------------------------------------------#
# 0) Configure local dns server and domain (dual-stack)          #
#----------------------------------------------------------------#
# q) Quit without any changes                                    #
#----------------------------------------------------------------#"

read -p "# Please select one of the options above : " var_function

case ${var_function} in
	0) 	
		fn_configure_named_dns_server
		exit
		;;
	1)
		fn_check_existence_of_domain
		fn_create_host_record
		exit
		;;
	2)
		fn_check_existence_of_domain
		fn_delete_host_record
		exit
		;;
	3)
		fn_check_existence_of_domain
		fn_rename_host_record
		exit
		;;
	4)
		fn_check_existence_of_domain
		fn_handle_multiple_host_record "${2}" "create"
		exit
		;;
	5)
		fn_check_existence_of_domain
		fn_handle_multiple_host_record "${2}" "delete"
		exit
		;;
	6)
		fn_check_existence_of_domain
		specific_ipv4_requested="yes"
		fn_create_host_record 
		exit
		;;
	7)
		fn_check_existence_of_domain
		fn_create_cname_record
		exit
		;;
	8)
		fn_check_existence_of_domain
		fn_delete_cname_record
		exit
		;;
	q)
		exit
		;;
	*)
		print_error "Invalid Option! Try Again! "
		fn_main_menu
		exit 1
		;;
esac
}


fn_usage_message() {
print_notify "Domain   : ${v_domain_if_present}
IPv4 Net : ${v_network_if_present}
IPv6 Net : ${v_ipv6_if_present}

Usage: dnsbinder [ option ] [ arguments ]
Use one of the following Options :
	-c      To create a host record (dual-stack: A + AAAA records)
	-d      To delete a host record (removes both A and AAAA records)
	-dy     caution ! To do the above without any confirmation
	-r      To rename an existing host record (updates A and AAAA records)
	-ry     caution ! To do the above without any confirmation
	-cf     To create multiple host records provided in a file (dual-stack)
	-df     To delete multiple host records provided in a file (dual-stack)
	-ci     To create a host record with specific IPv4 Address (auto-generates IPv6)
	-cc     To create a CNAME/Alias record for an existing host record
	-dc     To delete a CNAME/Alias record for an existing host record
	-dcy    caution ! To do the above without any confirmation
	--setup	To configure local dns server and domain (dual-stack IPv4/IPv6)
	        Both IPv4 and IPv6 networks are auto-detected from system
	        Usage: dnsbinder --setup <domain>
	        Example: dnsbinder --setup lab.local
	-h (or) --help To print this usage info	

Note: All host record operations automatically create/manage both IPv4 (A) and IPv6 (AAAA) records

[ Or ]
Run dnsbinder utility without any arguements to get menu driven actions."
}

if [ ! -z "${1}" ]
then

	case "${1}" in
		-c)
			fn_check_existence_of_domain
			if [[ ! -z "${3}" ]];then
				print_error "Invalid Option! '-c' option takes only 1 arguement as hostname ! "
				fn_usage_message
				exit 1
			fi
			fn_create_host_record "${2}"
			exit
			;;
		-d|-dy)
			fn_check_existence_of_domain
			if [[ ! -z "${3}" ]];then
				print_error " Invalid Option! ${1} option takes only 1 arguement as hostname ! "
				fn_usage_message
				exit 1
			fi
			if [[ "${1}" == "-d" ]];then
				fn_delete_host_record "${2}"
			elif [[ "${1}" == "-dy" ]];then
				fn_delete_host_record "${2}" "-y"
			fi
			exit
			;;
		-r|-ry)
			fn_check_existence_of_domain
			if [[ ! -z "${4}" ]];then
				print_error "Invalid Option! ${1} option takes only 2 arguements [ existing host record and new host record ] ! "
				fn_usage_message
				exit 1
			fi
			if [[ "${1}" == "-r" ]];then
				fn_rename_host_record "${2}" "${3}"
			elif [[ "${1}" == "-ry" ]];then
				fn_rename_host_record "${2}" "${3}" "-y"
			fi
			exit
			;;
		-cf)
			fn_check_existence_of_domain
			if [[ ! -z "${3}" ]];then
				print_error "Invalid Option! '-cf' option takes only 1 arguement as file containing list of hostnames ! "
				fn_usage_message
				exit 1
			fi
			fn_handle_multiple_host_record "${2}" "create"
			exit
			;;
		-df)
			fn_check_existence_of_domain
			if [[ ! -z "${3}" ]];then
				print_error "Invalid Option! '-df' option takes only 1 arguement as file containing list of hostnames ! "
				fn_usage_message
				exit 1
			fi
			fn_handle_multiple_host_record "${2}" "delete"
			exit
			;;
		-ci)	
			fn_check_existence_of_domain 
			if [[ ! -z "${4}" ]];then
				print_error "Invalid Option! '-ci' option takes only 2 arguements [ hostname and required ipv4 address ] ! "
				fn_usage_message
				exit 1
			fi
			specific_ipv4_requested="yes"
			fn_create_host_record "${2}" "${3}"
			exit
			;;
		-cc)	
			fn_check_existence_of_domain 
			if [[ ! -z "${4}" ]];then
				print_error "Invalid Option! '-cc' option takes only 2 arguements [ cname and hostname ] ! "
				fn_usage_message
				exit 1
			fi
			fn_create_cname_record "${2}" "${3}"
			exit
			;;
		-dc|-dcy)	
			fn_check_existence_of_domain 
			if [[ ! -z "${3}" ]];then
				print_error "Invalid Option! ${1} option takes only 1 arguement as cname ! "
				fn_usage_message
				exit 1
			fi
			if [[ "${1}" == "-dc" ]];then
				fn_delete_cname_record "${2}"
			elif [[ "${1}" == "-dcy" ]];then
				fn_delete_cname_record "${2}" "-y"
			fi
			exit
			;;
		--setup)
			fn_configure_named_dns_server "${2}"
			exit
			;;
		*)
			if [[ ! "${1}" =~ ^-h|--help$ ]]
			then
				print_error "Invalid Option \"${1}\"! "
			fi
			fn_usage_message
			exit 1
			;;
	esac
else
	fn_main_menu
fi
