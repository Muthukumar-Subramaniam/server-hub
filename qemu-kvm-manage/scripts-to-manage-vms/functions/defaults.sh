source /server-hub/common-utils/color-functions.sh

if [[ "$EUID" -eq 0 ]]; then
    print_error "[ERROR] Running as root user is not allowed."
    print_info "[INFO] This script should be run as a user with sudo privileges, not as root."
    exit 1
fi

# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    print_error "[ERROR] This script cannot be executed inside a QEMU guest VM."
    print_info "[INFO] This script must be run on the host system managing QEMU/KVM virtual machines."
    print_info "[INFO] Current environment is a QEMU guest, which is not supported."
    exit 1
fi

LAB_ENV_VARS_FILE="/kvm-hub/lab_environment_vars"
if [ -f "$LAB_ENV_VARS_FILE" ]; then
    source "$LAB_ENV_VARS_FILE"
else
    print_error "[ERROR] Lab environment variables file not found at $LAB_ENV_VARS_FILE"
    exit 1
fi
