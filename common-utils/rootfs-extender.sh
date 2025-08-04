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
    if ! ssh $SSH_OPTS "$REMOTE_HOST" "true" >/dev/null 2>&1; then
    	echo -e "\n[ERROR] SSH connection to $REMOTE_HOST failed. Ensure SSH access works."
     	exit 1
    fi
    echo "[ok]"
    rsync -az -e "ssh $SSH_OPTS" "$SCRIPT_LOCATION" $REMOTE_HOST:$TMP_SCRIPT"
    ssh $SSH_OPTS -t $REMOTE_HOST" "sudo bash $TMP_SCRIPT localhost && rm -f $TMP_SCRIPT"

    echo "[INFO] Remote execution of rootfs-extender utility completed on $REMOTE_HOST."
    exit 0
fi

# ----------------------
# Local execution logic
# ----------------------

# Show root FS size before
echo "[INFO] Root filesystem size BEFORE expansion: $(df -h / | awk 'NR==2 {print $2}')"

# Ensure growpart is installed
if ! command -v growpart >/dev/null 2>&1; then
    echo -n "[INFO] 'growpart' not found. Installing . . . "
    sudo curl -fsSL -o /usr/bin/growpart https://raw.githubusercontent.com/canonical/cloud-utils/main/bin/growpart && sudo chmod +x /usr/bin/growpart
    echo "[ok]"
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
DISK=$(lsblk -no pkname "$PV_PATH" | grep -Ev '^\s*$' | sort -u | head -n1)
PART_NUM=$(echo "$PV_PATH" | grep -o '[0-9]*$')

echo "[INFO] Disk: /dev/$DISK"
echo "[INFO] Partition Number: $PART_NUM"

# Step 5: Grow the partition
echo -n  "[STEP] Growing partition /dev/${DISK}${PART_NUM} . . . "
sudo growpart "/dev/$DISK" "$PART_NUM" >/dev/null 2>&1
echo "[ok]"

# Step 6: Resize PV
echo -n "[STEP] Resizing PV: $PV_PATH . . . "
sudo pvresize "$PV_PATH" >/dev/null 2>&1
echo "[ok]"

# Step 7: Extend LV
echo -n "[STEP] Extending LV: $ROOT_LV . . . "
sudo lvextend -l +100%FREE "$ROOT_LV" >/dev/null 2>&1
echo "[ok]"

# Step 8: Resize XFS filesystem
echo -n "[STEP] Extending XFS filesystem on / . . . "
sudo xfs_growfs / >/dev/null 2>&1
echo "[ok]"

# Show root FS size after
echo "[INFO] Root filesystem size AFTER expansion: $(df -h / | awk 'NR==2 {print $2}')"

echo "[SUCCESS] Root filesystem successfully expanded ! "
