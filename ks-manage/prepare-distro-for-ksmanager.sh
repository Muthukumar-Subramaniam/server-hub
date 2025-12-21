#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh
source /server-hub/ks-manage/distro-versions.conf

if [[ "$USER" != "$mgmt_super_user" ]]; then
	print_error "Access denied. Only infra management super user '${mgmt_super_user}' is authorized to run this tool."
	print_error "Also if the user itself is ${mgmt_super_user}, Please do not elevate access again with sudo.\n"
    	exit 1
fi

set -euo pipefail

: "${dnsbinder_server_fqdn:?Must set dnsbinder_server_fqdn}"
: "${mgmt_super_user:?Must set mgmt_super_user}"

# Validate required commands are installed
REQUIRED_COMMANDS=("wget" "curl" "mountpoint" "sed" "awk" "grep")
MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    MISSING_COMMANDS+=("$cmd")
  fi
done

if [[ ${#MISSING_COMMANDS[@]} -gt 0 ]]; then
  print_error "Missing required commands: ${MISSING_COMMANDS[*]}"
  print_info "Please install the missing tools before running this script."
  exit 1
fi

ISO_DIR="/iso-files"
FSTAB="/etc/fstab"

print_usage() {
  print_info "Usage:
    $(basename $0) --setup <distro> [--version latest|previous]
    $(basename $0) --cleanup <distro> [--version latest|previous]

Supported distros:
    almalinux, rocky, oraclelinux, centos-stream, rhel, ubuntu-lts, opensuse-leap

Version (optional, defaults to 'latest'):
    latest   - Setup/cleanup the latest major version
    previous - Setup/cleanup the previous major version"
}

fn_get_version_number() {
  local os_distribution="$1"
  local version="${2:-latest}"
  
  if [[ "$version" == "latest" ]]; then
    echo "${DISTRO_LATEST_VERSIONS[$os_distribution]}"
  else
    echo "${DISTRO_PREVIOUS_VERSIONS[$os_distribution]}"
  fi
}

fn_is_distro_ready() {
  local os_distribution="$1"
  local version="${2:-latest}"  # Default to 'latest' if not specified
  local mount_dir="/${dnsbinder_server_fqdn}/${os_distribution}-${version}"
  
  if mountpoint -q "$mount_dir"; then
    return 0  # Ready
  else
    return 1  # Not Ready
  fi
}

fn_get_distro_status_display() {
  local os_distribution="$1"
  local version="${2:-latest}"  # Default to 'latest' if not specified
  
  if fn_is_distro_ready "$os_distribution" "$version"; then
    print_green "[Ready]" nskip
  else
    print_yellow "[Not-Ready]" nskip
  fi
}

# Status will be computed after version selection in interactive mode
# For now, these are placeholders

fn_select_os_distro() {
  local action_title="$1"
  local version="${2:-latest}"
  
  # Define distro list with keys and display names
  local -a distro_keys=("almalinux" "rocky" "oraclelinux" "centos-stream" "rhel" "ubuntu-lts" "opensuse-leap")
  local -a distro_names=("AlmaLinux" "Rocky Linux" "OracleLinux" "CentOS Stream" "Red Hat Enterprise Linux" "Ubuntu Server LTS" "openSUSE Leap")
  
  # Build menu
  local menu="Please select the OS distribution to ${action_title}:\n"
  for i in "${!distro_keys[@]}"; do
    local key="${distro_keys[$i]}"
    local name="${distro_names[$i]}"
    local ver=$(fn_get_version_number "$key" "$version")
    local status=$(fn_get_distro_status_display "$key" "$version")
    printf -v line "  %d)  %-32s %s\n" $((i+1)) "${name} ${ver}" "${status}"
    menu+="${line}"
  done
  menu+="  q)  Quit"
  
  print_notify "$menu"
  read -p "Enter option number (default: AlmaLinux): " os_distribution
  case "$os_distribution" in
    1 | "" ) DISTRO="almalinux" ;;
    2 ) DISTRO="rocky" ;;
    3 ) DISTRO="oraclelinux" ;;
    4 ) DISTRO="centos-stream" ;;
    5 ) DISTRO="rhel" ;;
    6 ) DISTRO="ubuntu-lts" ;;
    7 ) DISTRO="opensuse-leap" ;;
    q | Q ) print_notify "Exiting the utility $(basename $0) !\n"; exit 0 ;;
    * ) print_error "Invalid option! Please try again."; fn_select_os_distro "$action_title" ;;
  esac
}

prepare_iso() {
  local distro="$1" iso_file="$2" iso_url="$3"
  local mount_dir="/${dnsbinder_server_fqdn}/${distro}-${VERSION_VARIANT}"
  local iso_path="${ISO_DIR}/${iso_file}"

  print_info "Ensuring ISO directory exists..."
  sudo mkdir -p "$ISO_DIR"
  sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$ISO_DIR"

  if [[ -f "$iso_path" ]]; then
    print_info "ISO already exists: $iso_path\n"
  else
    print_info "Downloading ISO from $iso_url\n"
    if ! wget --continue --output-document="$iso_path" "$iso_url"; then
      print_error "Failed to download ISO from $iso_url"
      print_info "Cleaning up partial download..."
      sudo rm -f "$iso_path"
      exit 1
    fi
    sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$iso_path"
    print_success "Download complete and ownership set.\n"
  fi

  print_info "Preparing mount point: $mount_dir"
  sudo mkdir -p "$mount_dir"
  sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$mount_dir"
  local fstab_entry="$iso_path $mount_dir iso9660 uid=${mgmt_super_user},gid=${mgmt_super_user} 0 0"
  if ! grep -qF "$fstab_entry" "$FSTAB"; then
    print_info "Adding mount entry to /etc/fstab\n"
    if ! echo "$fstab_entry" | sudo tee -a "$FSTAB" > /dev/null; then
      print_error "Failed to add fstab entry"
      print_info "Cleaning up ISO file..."
      sudo rm -f "$iso_path"
      exit 1
    fi
    sudo systemctl daemon-reload
  else
    print_info "fstab already contains ISO mount entry.\n"
  fi

  if ! mountpoint -q "$mount_dir"; then
    print_info "Mounting ISO to $mount_dir\n"
    if ! sudo mount "$mount_dir"; then
      print_error "Failed to mount ISO at $mount_dir"
      print_info "Cleaning up..."
      sudo sed -i "\|${mount_dir}|d" "$FSTAB"
      sudo systemctl daemon-reload
      sudo rm -f "$iso_path"
      sudo rm -rf "$mount_dir"
      exit 1
    fi
    print_success "ISO mounted.\n"
  else
    print_info "ISO already mounted.\n"
  fi

  print_success "All done for $distro.\n"
}

prepare_rhel() {
  local distro="rhel"
  local rhel_version="10"
  if [[ "${VERSION_VARIANT}" == "previous" ]]; then
    rhel_version="9"
  fi
  
  print_info "Login from a browser with your Red Hat Developer Subscription!"
  read -rp "Enter the link to download RHEL ${rhel_version} ISO : " iso_url

  prepare_iso "$distro" "${ISO_FILENAMES[rhel]}" "$iso_url"
}

prepare_ubuntu() {
  local distro="ubuntu-lts"
  prepare_iso "$distro" "${ISO_FILENAMES[ubuntu-lts]}" "${ISO_URLS[ubuntu-lts]}"
}

prepare_oraclelinux() {
  local distro="oraclelinux"
  prepare_iso "$distro" "${ISO_FILENAMES[oraclelinux]}" "${ISO_URLS[oraclelinux]}"
}

cleanup_distro() {
  local distro="$1"
  local iso_file="$2"
  local iso_path="${ISO_DIR}/${iso_file}"
  local mount_dir="/${dnsbinder_server_fqdn}/${distro}-${VERSION_VARIANT}"

  print_warning "This will delete ISO and mount point for $distro."
  read -p "Are you sure you want to continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    print_error "Cleanup aborted."
    exit 1
  fi

  sudo rm -f $iso_path

  if [[ -n "$mount_dir" && -d "$mount_dir" ]]; then
    if mountpoint -q "$mount_dir"; then
      print_task "Unmounting $mount_dir..."
      if sudo umount "$mount_dir"; then
        print_task_done
      else
        print_task_fail
        print_error "Failed to unmount $mount_dir. Please check if it's in use."
        exit 1
      fi
    fi
    sudo rm -rf "$mount_dir"
  fi

  print_info "Cleaning up /etc/fstab entries containing '${distro}-${VERSION_VARIANT}'"
  sudo sed -i "/${distro}-${VERSION_VARIANT}/d" "$FSTAB"
  sudo systemctl daemon-reexec

  print_success "Cleanup completed for $distro.\n"
}

# Menu mode when no args
if [[ $# -lt 1 ]]; then
  print_info "No arguments provided. Launching interactive mode.
What would you like to do?
  1) Setup Distro
  2) Cleanup Distro
  q) Quit"
  read -p "Enter option (default: 1): " action
  case "$action" in
    1 | "" ) MODE="--setup" ; MENU_TITLE="setup" ;;
    2 ) MODE="--cleanup" ; MENU_TITLE="cleanup" ;;
    q | Q ) print_notify "Exiting the utility $(basename $0) !\n"; exit 0 ;;
    * ) print_error "Invalid choice. Exiting."; exit 1 ;;
  esac
  
  # Ask for version FIRST in interactive mode
  print_info "Which version do you want to ${MENU_TITLE}?
  1) Latest (default)
  2) Previous"
  read -p "Enter option: " version_choice
  case "$version_choice" in
    1 | "" ) VERSION_VARIANT="latest" ;;
    2 ) VERSION_VARIANT="previous" ;;
    * ) print_error "Invalid choice. Using 'latest'."; VERSION_VARIANT="latest" ;;
  esac
  
  # Select version-aware arrays based on VERSION_VARIANT before displaying menu
  if [[ "${VERSION_VARIANT}" == "previous" ]]; then
    declare -n ISO_FILENAMES=ISO_FILENAMES_PREVIOUS
    declare -n ISO_URLS=ISO_URLS_PREVIOUS
  else
    declare -n ISO_FILENAMES=ISO_FILENAMES_LATEST
    declare -n ISO_URLS=ISO_URLS_LATEST
  fi
  
  fn_select_os_distro "$MENU_TITLE" "$VERSION_VARIANT"
else
  MODE="$1"
  DISTRO="${2:-}"

  if [[ "$MODE" == "-h" || "$MODE" == "--help" ]]; then
    print_usage
    exit 0
  fi

  if [[ "$MODE" != "--setup" && "$MODE" != "--cleanup" ]]; then
    print_error "Invalid mode: $MODE"
    print_usage
    exit 1
  fi

  if [[ -z "$DISTRO" ]]; then
    print_error "Missing distro argument for $MODE."
    print_usage
    exit 1
  fi

  # Parse --version parameter (optional, defaults to 'latest')
  VERSION_VARIANT="latest"
  if [[ $# -ge 3 ]]; then
    if [[ "$3" == "--version" && -n "${4:-}" ]]; then
      if [[ "$4" == "latest" || "$4" == "previous" ]]; then
        VERSION_VARIANT="$4"
      else
        print_error "Invalid version: $4. Must be 'latest' or 'previous'."
        print_usage
        exit 1
      fi
    else
      print_error "Invalid parameter: $3"
      print_usage
      exit 1
    fi
  fi
fi

# Select version-aware arrays based on VERSION_VARIANT (for CLI mode)
if [[ "${VERSION_VARIANT}" == "previous" ]]; then
  declare -n ISO_FILENAMES=ISO_FILENAMES_PREVIOUS
  declare -n ISO_URLS=ISO_URLS_PREVIOUS
else
  declare -n ISO_FILENAMES=ISO_FILENAMES_LATEST
  declare -n ISO_URLS=ISO_URLS_LATEST
fi

# Main logic
case "$MODE" in
  --setup)
    # Check if distro is already prepared (DRY - check once)
    if fn_is_distro_ready "$DISTRO" "$VERSION_VARIANT"; then
      print_warning "Distro '${DISTRO}' already appears to be prepared."
      print_info "Please cleanup first using: $(basename $0) --cleanup ${DISTRO}"
      exit 1
    fi

    case "$DISTRO" in
      almalinux)
        prepare_iso "almalinux" "${ISO_FILENAMES[almalinux]}" \
          "${ISO_URLS[almalinux]}"
        ;;
      rocky)
        prepare_iso "rocky" "${ISO_FILENAMES[rocky]}" \
          "${ISO_URLS[rocky]}"
        ;;
      oraclelinux)
        prepare_iso "oraclelinux" "${ISO_FILENAMES[oraclelinux]}" \
          "${ISO_URLS[oraclelinux]}"
        ;;
      centos-stream)
        prepare_iso "centos-stream" "${ISO_FILENAMES[centos-stream]}" \
          "${ISO_URLS[centos-stream]}"
        ;;
      rhel)
        prepare_rhel
        ;;
      ubuntu-lts)
        prepare_iso "ubuntu-lts" "${ISO_FILENAMES[ubuntu-lts]}" \
          "${ISO_URLS[ubuntu-lts]}"
        ;;
      opensuse-leap)
        prepare_iso "opensuse-leap" "${ISO_FILENAMES[opensuse-leap]}" \
          "${ISO_URLS[opensuse-leap]}"
        ;;
      *)
        print_error "Unknown distro: $DISTRO"
        exit 1
        ;;
    esac
    ;;
  --cleanup)
    case "$DISTRO" in
      almalinux)       cleanup_distro "almalinux" "${ISO_FILENAMES[almalinux]}" ;;
      rocky)           cleanup_distro "rocky" "${ISO_FILENAMES[rocky]}" ;;
      oraclelinux)     cleanup_distro "oraclelinux" "${ISO_FILENAMES[oraclelinux]}" ;;
      centos-stream)   cleanup_distro "centos-stream" "${ISO_FILENAMES[centos-stream]}" ;;
      rhel)            cleanup_distro "rhel" "${ISO_FILENAMES[rhel]}" ;;
      ubuntu-lts)      cleanup_distro "ubuntu-lts" "${ISO_FILENAMES[ubuntu-lts]}" ;;
      opensuse-leap)   cleanup_distro "opensuse-leap" "${ISO_FILENAMES[opensuse-leap]}" ;;
      *)
        print_error "Unknown distro: $DISTRO"
        exit 1
        ;;
    esac
    ;;
  *)
    print_usage
    exit 1
    ;;
esac
