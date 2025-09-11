#!/usr/bin/env bash
# rootfs-extender.sh
# Usage:
#   ./rootfs-extender.sh [remote-host]
# If remote-host != localhost the script rsync/ssh's itself and runs under sudo remotely.

# --- Config ---
SSH_OPTS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
TMP_SCRIPT="/tmp/rootfs-extender.sh"
SCRIPT_LOCATION="/server-hub/common-utils/rootfs-extender.sh"

# ----------------------
# Prompt for hostname if not passed
# ----------------------
REMOTE_HOST="${1:-}"

if [[ -z "$REMOTE_HOST" ]]; then
    read -rp "Enter remote hostname [default: localhost]: " REMOTE_HOST
    REMOTE_HOST=${REMOTE_HOST:-localhost}
fi

# ----------------------
# Remote execution logic
# ----------------------
if [[ "$REMOTE_HOST" != "localhost" ]]; then
    echo -n "[INFO] Checking SSH connectivity to $REMOTE_HOST . . . "
    if ! ssh $SSH_OPTS "$REMOTE_HOST" "true" >/dev/null 2>&1; then
        echo -e "\n[ERROR] SSH connection to $REMOTE_HOST failed. Ensure SSH access works."
        exit 1
    fi
    echo "[ok]"

    echo "[INFO] Copying script to remote host and executing..."
    rsync -az -e "ssh $SSH_OPTS" "$SCRIPT_LOCATION" "$REMOTE_HOST:$TMP_SCRIPT"
    ssh $SSH_OPTS -t "$REMOTE_HOST" "sudo bash $TMP_SCRIPT localhost && sudo rm -f $TMP_SCRIPT"

    echo "[INFO] Remote execution completed on $REMOTE_HOST."
    exit 0
fi

# ----------------------
# Local execution logic
# ----------------------
FS_BEFORE=$(df -h / | awk 'NR==2{print $2}')
echo "[INFO] Root filesystem size BEFORE expansion: $FS_BEFORE"

# Ensure growpart is installed
if ! command -v growpart >/dev/null 2>&1; then
    echo -n "[INFO] 'growpart' not found. Installing . . . "
    sudo curl -fsSL -o /usr/bin/growpart https://raw.githubusercontent.com/canonical/cloud-utils/main/bin/growpart && sudo chmod +x /usr/bin/growpart
    echo "[ok]"
fi

ROOT_DEV=$(findmnt -n -o SOURCE /)
echo "[INFO] Root device: $ROOT_DEV"

# Only XFS supported
FS_TYPE=$(findmnt -n -o FSTYPE /)
if [[ "$FS_TYPE" != "xfs" ]]; then
    echo "[ERROR] Unsupported filesystem type: $FS_TYPE. This script only supports XFS."
    exit 1
fi

if [[ "$ROOT_DEV" =~ ^/dev/mapper/ ]]; then
    echo "[INFO] Detected LVM-based root filesystem."

    # Get VG name from LV path
    VG_NAME=$(sudo lvs --noheadings -o vg_name "$ROOT_DEV" | awk '{$1=$1};1')
    echo "[INFO] Volume Group: $VG_NAME"

    # Get PV (first if multiple)
    PV_PATH=$(sudo pvs --noheadings -o pv_name --select vg_name="$VG_NAME" | awk '{$1=$1};1' | head -n1)
    echo "[INFO] Physical Volume: $PV_PATH"

    # Get disk and partition number from lsblk
    DISK="/dev/$(lsblk -no pkname "$PV_PATH" | sort | head -n1 | tr -d '[:space:]')"
    PART_NUM=$(lsblk -no partn "$PV_PATH" | tr -d '[:space:]')

    echo -n "[STEP] Growing partition $PV_PATH ... "
    sudo growpart "$DISK" "$PART_NUM" >/dev/null 2>&1
    echo "[ok]"

    echo -n "[STEP] Resizing PV $PV_PATH ... "
    sudo pvresize "$PV_PATH" >/dev/null 2>&1
    echo "[ok]"

    echo -n "[STEP] Extending LV $ROOT_DEV ... "
    sudo lvextend -l +100%FREE "$ROOT_DEV" >/dev/null 2>&1
    echo "[ok]"

    echo -n "[STEP] Extending XFS filesystem on / ... "
    sudo xfs_growfs / >/dev/null 2>&1
    echo "[ok]"

else
    echo "[INFO] Detected non-LVM root filesystem (plain partition)."

    # Get disk and partition number from lsblk
    DISK="/dev/$(lsblk -no pkname "$ROOT_DEV" | sort | head -n1 | tr -d '[:space:]')"
    PART_NUM=$(lsblk -no partn "$ROOT_DEV" | tr -d '[:space:]')

    echo "[INFO] Disk: $DISK, Partition: $PART_NUM"

    echo -n "[STEP] Growing partition ${DISK}${PART_NUM} ... "
    sudo growpart "$DISK" "$PART_NUM" >/dev/null 2>&1
    echo "[ok]"

    echo -n "[STEP] Extending XFS filesystem on / ... "
    sudo xfs_growfs / >/dev/null 2>&1
    echo "[ok]"
fi

FS_AFTER=$(df -h / | awk 'NR==2{print $2}')

if [[ "$FS_BEFORE" == "$FS_AFTER" ]]; then
    echo "[INFO] No change in root filesystem size."
else
    echo "[INFO] Root filesystem size AFTER expansion: $FS_AFTER"
    echo "[SUCCESS] Root filesystem successfully expanded!"
fi
