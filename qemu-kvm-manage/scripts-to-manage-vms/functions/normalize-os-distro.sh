################################################################################
# Function: normalize_os_distro
# Description: Normalize OS distro names to standard formats
# Parameters:
#   $1 - OS distro name (OS_DISTRO)
# Returns:
#   0 - Success (sets NORMALIZED_OS_DISTRO global)
#   1 - Unrecognized distro
################################################################################

normalize_os_distro() {
    local os_distro="$1"

    if [[ -z "$os_distro" ]]; then
        print_error "[ERROR] normalize_os_distro requires OS distro name"
        return 1
    fi

    # Normalize OS distro names
    if echo "$os_distro" | grep -qi "almalinux"; then
        NORMALIZED_OS_DISTRO="almalinux"
    elif echo "$os_distro" | grep -qi "centos"; then
        NORMALIZED_OS_DISTRO="centos-stream"
    elif echo "$os_distro" | grep -qi "rocky"; then
        NORMALIZED_OS_DISTRO="rocky"
    elif echo "$os_distro" | grep -qi "oracle"; then
        NORMALIZED_OS_DISTRO="oraclelinux"
    elif echo "$os_distro" | grep -qi "redhat"; then
        NORMALIZED_OS_DISTRO="rhel"
    elif echo "$os_distro" | grep -qi "fedora"; then
        NORMALIZED_OS_DISTRO="fedora"
    elif echo "$os_distro" | grep -qi "ubuntu"; then
        NORMALIZED_OS_DISTRO="ubuntu-lts"
    elif echo "$os_distro" | grep -qi "suse"; then
        NORMALIZED_OS_DISTRO="opensuse-leap"
    else
        print_error "[ERROR] Unrecognized OS distro: $os_distro"
        return 1
    fi

    return 0
}
