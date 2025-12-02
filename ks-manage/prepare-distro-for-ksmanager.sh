#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#

source /server-hub/common-utils/color-functions.sh

if [[ "$USER" != "$mgmt_super_user" ]]; then
	print_error "Access denied. Only infra management super user '${mgmt_super_user}' is authorized to run this tool."
	print_error "Also if the user itself is ${mgmt_super_user}, Please do not elevate access again with sudo.\n"
    	exit 1
fi

set -euo pipefail

: "${dnsbinder_server_fqdn:?Must set dnsbinder_server_fqdn}"
: "${mgmt_super_user:?Must set mgmt_super_user}"

ISO_DIR="/iso-files"
FSTAB="/etc/fstab"

print_usage() {
  print_info "[INFO] Usage:
    $(basename $0) --setup <distro>
    $(basename $0) --cleanup <distro>

Supported distros:
    almalinux, rocky, oraclelinux, centos-stream, rhel, ubuntu-lts, opensuse-leap"
}

fn_is_distro_ready() {
  local os_distribution="$1"
  if [[ "$os_distribution" == "opensuse-leap" ]]; then
    kernel_file_name="linux"
  else
    kernel_file_name="vmlinuz"
  fi
  if [[ -f "/${dnsbinder_server_fqdn}/ipxe/images/${os_distribution}-latest/${kernel_file_name}" ]]; then
    return 0  # Ready
  else
    return 1  # Not Ready
  fi
}

fn_get_distro_status_display() {
  local os_distribution="$1"
  if fn_is_distro_ready "$os_distribution"; then
    print_success "[Ready]" nskip
  else
    print_warning "[Not-Ready]" nskip
  fi
}

almalinux_os_availability=$(fn_get_distro_status_display "almalinux")
rocky_os_availability=$(fn_get_distro_status_display "rocky")
oraclelinux_os_availability=$(fn_get_distro_status_display "oraclelinux")
centos_stream_os_availability=$(fn_get_distro_status_display "centos-stream")
rhel_os_availability=$(fn_get_distro_status_display "rhel")
fedora_os_availability=$(fn_get_distro_status_display "fedora")
ubuntu_lts_os_availability=$(fn_get_distro_status_display "ubuntu-lts")
opensuse_leap_os_availability=$(fn_get_distro_status_display "opensuse-leap")

fn_select_os_distro() {
  local action_title="$1"
  print_notify "Please select the OS distribution to ${action_title}:
  1)  AlmaLinux                ${almalinux_os_availability}
  2)  Rocky Linux              ${rocky_os_availability}
  3)  OracleLinux              ${oraclelinux_os_availability}
  4)  CentOS Stream            ${centos_stream_os_availability}
  5)  Red Hat Enterprise Linux ${rhel_os_availability}
  6)  Fedora Linux             ${fedora_os_availability}
  7)  Ubuntu Server LTS        ${ubuntu_lts_os_availability}
  8)  openSUSE Leap Latest     ${opensuse_leap_os_availability}
  q)  Quit"
  read -p "Enter option number (default: AlmaLinux): " os_distribution
  case "$os_distribution" in
    1 | "" ) DISTRO="almalinux" ;;
    2 ) DISTRO="rocky" ;;
    3 ) DISTRO="oraclelinux" ;;
    4 ) DISTRO="centos-stream" ;;
    5 ) DISTRO="rhel" ;;
    6 ) DISTRO="fedora" ;;
    7 ) DISTRO="ubuntu-lts" ;;
    8 ) DISTRO="opensuse-leap" ;;
    q | Q ) print_notify "[NOTIFY] Exiting the utility $(basename $0) ! \n"; exit 0 ;;
    * ) print_error "[ERROR] Invalid option! Please try again."; fn_select_os_distro "$action_title" ;;
  esac
}

prepare_iso() {
  local distro="$1" iso_file="$2" iso_url="$3" kernel_path="$4" initrd_path="$5"
  local mount_dir="/${dnsbinder_server_fqdn}/${distro}-latest"
  local web_image_dir="/${dnsbinder_server_fqdn}/ipxe/images/${distro}-latest"
  local iso_path="${ISO_DIR}/${iso_file}"

  print_info "[INFO] Ensuring ISO directory exists..."
  sudo mkdir -p "$ISO_DIR"
  sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$ISO_DIR"

  if [[ -f "$iso_path" ]]; then
    print_info "[INFO] ISO already exists: $iso_path\n"
  else
    print_info "[INFO] Downloading ISO from $iso_url\n"
    wget --continue --output-document="$iso_path" "$iso_url"
    sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$iso_path"
    print_success "[SUCCESS] Download complete and ownership set.\n"
  fi

  print_info "[INFO] Preparing mount point: $mount_dir"
  sudo mkdir -p "$mount_dir"
  sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$mount_dir"
  local fstab_entry="$iso_path $mount_dir iso9660 uid=${mgmt_super_user},gid=${mgmt_super_user} 0 0"
  if ! grep -qF "$fstab_entry" "$FSTAB"; then
    print_info "[INFO] Adding mount entry to /etc/fstab\n"
    echo "$fstab_entry" | sudo tee -a "$FSTAB" > /dev/null
    sudo systemctl daemon-reload
  else
    print_info "[INFO] fstab already contains ISO mount entry.\n"
  fi

  if ! mountpoint -q "$mount_dir"; then
    print_info "[INFO] Mounting ISO to $mount_dir\n"
    sudo mount "$mount_dir"
    print_success "[SUCCESS] ISO mounted.\n"
  else
    print_info "[INFO] ISO already mounted.\n"
  fi

  print_info "[INFO] Syncing kernel and initrd to $web_image_dir\n"
  sudo mkdir -p "$web_image_dir"
  sudo chown "${mgmt_super_user}:${mgmt_super_user}" "$web_image_dir"

  rsync -avPh "$mount_dir/$kernel_path" "$web_image_dir/"
  rsync -avPh "$mount_dir/$initrd_path" "$web_image_dir/"

  print_success "[SUCCESS] All done for $distro.\n"
}

prepare_rhel() {
  local distro="rhel"
  if fn_is_distro_ready "$distro"; then
    print_warning "[WARNING] Distro '$distro' already appears to be prepared."
    print_info "[INFO] Please cleanup first using: $(basename $0) --cleanup $distro"
    exit 1
  fi
  local iso_file="rhel-10.0-x86_64-dvd.iso"
  local mount_dir="/${dnsbinder_server_fqdn}/${distro}"
  local web_image_dir="/${dnsbinder_server_fqdn}/ipxe/images/${distro}-latest"
  local iso_path="${ISO_DIR}/${iso_file}"

  print_info "[INFO] Login from a browser with your Red Hat Developer Subscription!"
  read -rp "Enter the link to download RHEL 10 ISO : " iso_url

  prepare_iso "$distro" "$iso_file" "$iso_url" "images/pxeboot/vmlinuz" "images/pxeboot/initrd.img"
}

prepare_ubuntu() {
  local distro="ubuntu-lts"
  if fn_is_distro_ready "$distro"; then
    print_warning "[WARNING] Distro '$distro' already appears to be prepared."
    print_info "[INFO] Please cleanup first using: $(basename $0) --cleanup $distro"
    exit 1
  fi
  local latest_lts=$(curl -s https://cdimage.ubuntu.com/releases/ | sed -n 's/.*href="\([0-9][0-9]\.04\(\.[0-9][0-9]*\)\?\)\/".*/\1/p' | awk -F. '$1 % 2 == 0 { print }' | sort -V | tail -n1)
  local iso_file="ubuntu-${latest_lts}-live-server-amd64.iso"
  local iso_url="https://releases.ubuntu.com/${latest_lts}/${iso_file}"
  prepare_iso "$distro" "$iso_file" "$iso_url" "casper/vmlinuz" "casper/initrd"
}

cleanup_distro() {
  local distro="$1"
  local iso_file="$2"
  local iso_path="${ISO_DIR}/${iso_file}"
  local mount_dir="/${dnsbinder_server_fqdn}/${distro}-latest"
  local web_image_dir="/${dnsbinder_server_fqdn}/ipxe/images/${distro}-latest"

  print_warning "[WARNING] This will delete ISO, mount point and boot image files for $distro."
  read -p "Are you sure you want to continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    print_error "[ERROR] Cleanup aborted."
    exit 1
  fi

  sudo rm -f $iso_path

  if [[ -n "$mount_dir" && -d "$mount_dir" ]]; then
    sudo umount -l "$mount_dir" || true
    sudo rm -rf "$mount_dir"
  fi

  if [[ -n "$web_image_dir" && -d "$web_image_dir" ]]; then
    sudo rm -rf "$web_image_dir"
  fi

  print_info "[INFO] Cleaning up /etc/fstab entries containing '${distro}-latest'"
  sudo sed -i "/${distro}-latest/d" "$FSTAB"
  sudo systemctl daemon-reexec

  print_success "[SUCCESS] Cleanup completed for $distro.\n"
}

# Menu mode when no args
if [[ $# -lt 1 ]]; then
  print_info "[INFO] No arguments provided. Launching interactive mode.
What would you like to do?
  1) Setup Distro
  2) Cleanup Distro
  q) Quit"
  read -p "Enter option (default: 1): " action
  case "$action" in
    1 | "" ) MODE="--setup" ; MENU_TITLE="setup" ;;
    2 ) MODE="--cleanup" ; MENU_TITLE="cleanup" ;;
    q | Q ) print_notify "[NOTIFY] Exiting the utility $(basename $0) ! \n"; exit 0 ;;
    * ) print_error "[ERROR] Invalid choice. Exiting."; exit 1 ;;
  esac
  fn_select_os_distro "$MENU_TITLE"
else
  MODE="$1"
  DISTRO="${2:-}"

  if [[ "$MODE" == "-h" || "$MODE" == "--help" ]]; then
    print_usage
    exit 0
  fi

  if [[ "$MODE" != "--setup" && "$MODE" != "--cleanup" ]]; then
    print_error "[ERROR] Invalid mode: $MODE"
    print_usage
    exit 1
  fi

  if [[ -z "$DISTRO" ]]; then
    print_error "[ERROR] Missing distro argument for $MODE."
    print_usage
    exit 1
  fi
fi

# Main logic
case "$MODE" in
  --setup)
    case "$DISTRO" in
      almalinux)
        if fn_is_distro_ready "almalinux"; then
          print_warning "[WARNING] Distro 'almalinux' already appears to be prepared."
          print_info "[INFO] Please cleanup first using: $(basename $0) --cleanup almalinux"
          exit 1
        fi
        prepare_iso "almalinux" "AlmaLinux-10-latest-x86_64-dvd.iso" \
          "https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10-latest-x86_64-dvd.iso" \
          "images/pxeboot/vmlinuz" "images/pxeboot/initrd.img"
        ;;
      rocky)
        if fn_is_distro_ready "rocky"; then
          print_warning "[WARNING] Distro 'rocky' already appears to be prepared."
          print_info "[INFO] Please cleanup first using: $(basename $0) --cleanup rocky"
          exit 1
        fi
        prepare_iso "rocky" "Rocky-10-latest-x86_64-dvd.iso" \
          "https://dl.rockylinux.org/pub/rocky/10/isos/x86_64/Rocky-10-latest-x86_64-dvd.iso" \
          "images/pxeboot/vmlinuz" "images/pxeboot/initrd.img"
        ;;
      fedora)
        if fn_is_distro_ready "fedora"; then
          print_warning "[WARNING] Distro 'fedora' already appears to be prepared."
          print_info "[INFO] Please cleanup first using: $(basename $0) --cleanup rocky"
          exit 1
        fi
        prepare_iso "fedora" "Fedora-Server-dvd-x86_64-42-1.1.iso" \
          "https://download.fedoraproject.org/pub/fedora/linux/releases/42/Server/x86_64/iso/Fedora-Server-dvd-x86_64-42-1.1.iso" \
          "images/pxeboot/vmlinuz" "images/pxeboot/initrd.img"
        ;;
      oraclelinux)
        if fn_is_distro_ready "oraclelinux"; then
          print_warning "[WARNING] Distro 'oraclelinux' already appears to be prepared."
          print_info "[INFO] Please cleanup first using: $(basename $0) --cleanup oraclelinux"
          exit 1
        fi
        prepare_iso "oraclelinux" "OracleLinux-R10-U0-x86_64-dvd.iso" \
          "https://yum.oracle.com/ISOS/OracleLinux/OL10/u0/x86_64/OracleLinux-R10-U0-x86_64-dvd.iso" \
          "images/pxeboot/vmlinuz" "images/pxeboot/initrd.img"
        ;;
      centos-stream)
        if fn_is_distro_ready "centos-stream"; then
          print_warning "[WARNING] Distro 'centos-stream' already appears to be prepared."
          print_info "[INFO] Please cleanup first using: $(basename $0) --cleanup centos-stream"
          exit 1
        fi
        prepare_iso "centos-stream" "CentOS-Stream-10-latest-x86_64-dvd.iso" \
          "https://mirrors.centos.org/mirrorlist?path=/10-stream/BaseOS/x86_64/iso/CentOS-Stream-10-latest-x86_64-dvd1.iso&redirect=1&protocol=https" \
          "images/pxeboot/vmlinuz" "images/pxeboot/initrd.img"
        ;;
      rhel)
        prepare_rhel
        ;;
      ubuntu-lts)
        prepare_ubuntu
        ;;
      opensuse-leap)
        if fn_is_distro_ready "opensuse-leap"; then
          print_warning "[WARNING] Distro 'opensuse-leap' already appears to be prepared."
          print_info "[INFO] Please cleanup first using: $(basename $0) --cleanup opensuse-leap"
          exit 1
        fi
        prepare_iso "opensuse-leap" "openSUSE-Leap-15.6-DVD-x86_64-Media.iso" \
          "https://download.opensuse.org/distribution/leap/15.6/iso/openSUSE-Leap-15.6-DVD-x86_64-Media.iso" \
          "boot/x86_64/loader/linux" "boot/x86_64/loader/initrd"
        ;;
      *)
        print_error "[ERROR] Unknown distro: $DISTRO"
        exit 1
        ;;
    esac
    ;;
  --cleanup)
    case "$DISTRO" in
      almalinux)       cleanup_distro "almalinux" "AlmaLinux-10-latest-x86_64-dvd.iso" ;;
      rocky)           cleanup_distro "rocky" "Rocky-10-latest-x86_64-dvd.iso" ;;
      oraclelinux)     cleanup_distro "oraclelinux" "OracleLinux-*-x86_64-dvd.iso" ;;
      centos-stream)   cleanup_distro "centos-stream" "CentOS-Stream-10-latest-x86_64-dvd.iso" ;;
      rhel)            cleanup_distro "rhel" "rhel-*-x86_64-dvd.iso" ;;
      fedora)          cleanup_distro "fedora" "Fedora-Server-dvd-x86_64*.iso" ;;
      ubuntu-lts)      cleanup_distro "ubuntu-lts" "ubuntu-*-live-server-amd64.iso" ;;
      opensuse-leap)   cleanup_distro "opensuse-leap" "openSUSE-Leap-*-DVD-x86_64-Media.iso" ;;
      *)
        print_error "[ERROR] Unknown distro: $DISTRO"
        exit 1
        ;;
    esac
    ;;
  *)
    print_usage
    exit 1
    ;;
esac
