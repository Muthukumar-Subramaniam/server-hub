#!/bin/bash

# --- Config ---
SSH_OPTS="-o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
TMP_SCRIPT="/tmp/rootfs-extender.sh"
SCRIPT_LOCATION="/server-hub/common-utils/rootfs-extender.sh"

# ----------------------
# Prompt for hostname if not passed
# ----------------------
REMOTE_HOST="$1"

if [[ -z "$REMOTE_HOST" ]]; then
    read -rp "Enter remote hostname [default: localhost]: " REMOTE_HOST
    REMOTE_HOST=${REMOTE_HOST:-localhost}
fi

# ----------------------
# Remote execution logic
# ----------------------
if [[ "$REMOTE_HOST" != "localhost" ]]; then
    echo -n "[INFO] Checking SSH connectivity to $REMOTE_HOST . . . "
    if ! ssh $SSH_OPTS "$REMOTE_HOST" '[ OK ]' >/dev/null 2>&1; then
        echo -e "\n[ERROR] SSH connection to $REMOTE_HOST failed. Ensure SSH access works."
        exit 1
    fi

    rsync -az -e "ssh $SSH_OPTS" "$SCRIPT_LOCATION" "$REMOTE_HOST:$TMP_SCRIPT"
    ssh $SSH_OPTS -t "$REMOTE_HOST" "sudo bash $TMP_SCRIPT localhost && rm -f $TMP_SCRIPT"

    echo "[INFO] Remote execution completed on $REMOTE_HOST."
    exit 0
fi

# ----------------------
# Local execution logic
# ----------------------
echo "[INFO] Starting root filesystem expansion for XFS + LVM setup..."

# Show root FS size before
echo "[INFO] Root filesystem BEFORE expansion:"
df -Th /

# Ensure growpart is installed
if ! command -v growpart >/dev/null 2>&1; then
    echo "[INFO] 'growpart' not found. Installing..."

    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y cloud-utils-growpart
    elif command -v apt >/dev/null 2>&1; then
        sudo apt update -y && sudo apt install -y cloud-guest-utils
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y cloud-utils-growpart
    else
        echo "[ERROR] No supported package manager (dnf, apt, zypper) found."
        exit 1
    fi
else
    echo "[INFO] 'growpart' is already installed."
fi

# Step 1: Find the root LV device
ROOT_LV=$(findmnt -n -o SOURCE /)
echo "[INFO] Root Logical Volume: $ROOT_LV"

# Step 2: Get the Volume Group name
VG_NAME=$(sudo lvs --noheadings -o vg_name "$ROOT_LV" | awk '{$1=$1};1')
echo "[INFO] Volume Group: $VG_NAME"

# Step 3: Get the Physical Volume path
PV_PATH=$(sudo pvs --noheadings -o pv_name --select vg_name="$VG_NAME" | awk '{$1=$1};1')
echo "[INFO] Physical Volume: $PV_PATH"

# Step 4: Get disk and partition number
DISK=$(lsblk -no pkname "$PV_PATH" | grep -Ev '^\s*$' | head -n1)
PART_NUM=$(echo "$PV_PATH" | grep -o '[0-9]*$')

echo "[INFO] Disk: /dev/$DISK"
echo "[INFO] Partition Number: $PART_NUM"

# Step 5: Grow the partition
echo "[STEP] Growing partition /dev/${DISK}${PART_NUM}"
sudo growpart "/dev/$DISK" "$PART_NUM"

# Step 6: Resize PV
echo "[STEP] Resizing PV: $PV_PATH"
sudo pvresize "$PV_PATH"

# Step 7: Extend LV
echo "[STEP] Extending LV: $ROOT_LV"
sudo lvextend -l +100%FREE "$ROOT_LV"

# Step 8: Resize XFS filesystem
echo "[STEP] Extending XFS filesystem on /"
sudo xfs_growfs /

# Show root FS size after
echo "[INFO] Root filesystem AFTER expansion:"
df -Th /

echo "[SUCCESS] Root XFS filesystem successfully expanded ! "
