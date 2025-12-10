################################################################################
# Function: normalize_os_distro
# Description: Normalize OS distro names to standard formats, handling version suffixes
# Parameters:
#   $1 - OS distro name (OS_DISTRO) - may include -latest or -previous suffix
# Returns:
#   0 - Success (sets NORMALIZED_OS_DISTRO and VERSION_TYPE globals)
#   1 - Unrecognized distro
################################################################################

normalize_os_distro() {
    local os_distro="$1"

    if [[ -z "$os_distro" ]]; then
        print_error "normalize_os_distro requires OS distro name"
        return 1
    fi

    # Extract version suffix if present (-latest or -previous)
    VERSION_TYPE="latest"  # Default to latest
    local base_distro="${os_distro}"
    
    if [[ "$os_distro" =~ -latest$ ]]; then
        VERSION_TYPE="latest"
        base_distro="${os_distro%-latest}"
    elif [[ "$os_distro" =~ -previous$ ]]; then
        VERSION_TYPE="previous"
        base_distro="${os_distro%-previous}"
    fi

    # Normalize OS distro names (case-insensitive exact match or known aliases)
    case "${base_distro,,}" in
        almalinux|alma)
            NORMALIZED_OS_DISTRO="almalinux"
            ;;
        centos-stream|centos)
            NORMALIZED_OS_DISTRO="centos-stream"
            ;;
        rocky)
            NORMALIZED_OS_DISTRO="rocky"
            ;;
        oraclelinux|oracle)
            NORMALIZED_OS_DISTRO="oraclelinux"
            ;;
        rhel|redhat)
            NORMALIZED_OS_DISTRO="rhel"
            ;;
        ubuntu-lts|ubuntu)
            NORMALIZED_OS_DISTRO="ubuntu-lts"
            ;;
        opensuse-leap|opensuse|suse)
            NORMALIZED_OS_DISTRO="opensuse-leap"
            ;;
        *)
            print_error "Unrecognized OS distro: $base_distro"
            print_info "Supported distros: almalinux, rocky, oraclelinux, centos-stream, rhel, ubuntu-lts, opensuse-leap"
            print_info "Optional suffixes: -latest (default), -previous"
            return 1
            ;;
    esac

    return 0
}
