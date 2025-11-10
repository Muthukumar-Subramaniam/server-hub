if [[ "$EUID" -eq 0 ]]; then
    echo -e "\n⛔ Running as root user is not allowed."
    echo -e "\n🔐 This script should be run as a user who has sudo privileges, but *not* using sudo.\n"
    exit 1
fi

# Check if we're inside a QEMU guest
if sudo dmidecode -s system-manufacturer | grep -qi 'QEMU'; then
    echo "❌❌❌  FATAL: WRONG PLACE, BUDDY! ❌❌❌"
    echo -e "\n⚠️ Note:"
    echo -e "  🔹 This script is meant to be run on the *host* system managing QEMU/KVM VMs."
    echo -e "  🔹 You’re currently inside a QEMU guest VM, which makes absolutely no sense.\n"
    echo "💥 ABORTING EXECUTION 💥"
    exit 1
fi

LAB_ENV_VARS_FILE="/kvm-hub/lab_environment_vars"
if [ -f "$LAB_ENV_VARS_FILE" ]; then
    source "$LAB_ENV_VARS_FILE"
else
    echo -e "\n❌ Lab environment variables file not found at $LAB_ENV_VARS_FILE\n"
    exit 1
fi