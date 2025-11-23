#!/bin/bash
#
# BACKUP SCRIPT WITH LVM SNAPSHOT (PULL)
# Guarantees data consistency (Atomic Backup).
#

set -o pipefail

# --- CONFIGURATION ---
SSH_USER="root"

# Remote LVM Data (YOU MUST EDIT THIS ACCORDING TO YOUR SERVER)
# Run 'lsblk' or 'lvdisplay' on the remote to know these names.
REMOTE_VG="ubuntu-vg"     # Volume Group name (e.g.: ubuntu-vg, centos)
REMOTE_LV="ubuntu-lv"     # Logical Volume name where the data is (e.g.: root, data)
SNAPSHOT_SIZE="512M"      # Size reserved for changes during backup (reduced to 512MB)

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 <ip> \"<relative_path_inside_snapshot>\" <destination_dir>"
    echo "Example: $0 192.168.1.50 var/www /backups"
    exit 1
fi

TARGET_IP="$1"
# Note: When mounting the snapshot, the path is no longer /var/www, but /mnt/backup_snap/var/www
# That's why we ask for the relative path (without the leading /)
SOURCE_REL_PATH="$2" 
LOCAL_BACKUP_DIR="$3"

mkdir -p "$LOCAL_BACKUP_DIR"

# Connection verification
if ! ssh -o ConnectTimeout=5 "${SSH_USER}@${TARGET_IP}" "echo ok" >/dev/null 2>&1; then
    echo "ERROR: Could not connect to $TARGET_IP."
    exit 1
fi

TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
REMOTE_SNAP_NAME="snap_backup_${TIMESTAMP}"
REMOTE_MOUNT_POINT="/mnt/backup_temp_${TIMESTAMP}"
REMOTE_TEMP_FILE="/tmp/backup-${TARGET_IP}.tar.gz"
LOCAL_FILE="$LOCAL_BACKUP_DIR/backup-${TARGET_IP}-${TIMESTAMP}.tar.gz"

echo "--------------------------------------------------"
echo "Starting Consistent LVM Backup of $TARGET_IP"
echo "--------------------------------------------------"

# 1. CREATE SNAPSHOT, MOUNT, COMPRESS AND CLEAN (All in one SSH block for safety)
# We use 'trap' inside the remote to ensure the snapshot is removed even if tar fails.

echo "[1/3] Generating Snapshot and packaging on remote..."

ssh "${SSH_USER}@${TARGET_IP}" "
    set -e # If something fails, stop
    
    # 1. Create Snapshot
    echo '>>> Creating LVM Snapshot...'
    lvcreate -L $SNAPSHOT_SIZE -s -n $REMOTE_SNAP_NAME /dev/$REMOTE_VG/$REMOTE_LV >/dev/null
    
    # Safe cleanup function (executes at the end, whether it fails or not)
    cleanup() {
        echo '>>> Cleaning up Snapshot...'
        umount $REMOTE_MOUNT_POINT 2>/dev/null || true
        lvremove -f /dev/$REMOTE_VG/$REMOTE_SNAP_NAME >/dev/null || true
        rmdir $REMOTE_MOUNT_POINT 2>/dev/null || true
    }
    trap cleanup EXIT

    # 2. Mount Snapshot
    mkdir -p $REMOTE_MOUNT_POINT
    mount /dev/$REMOTE_VG/$REMOTE_SNAP_NAME $REMOTE_MOUNT_POINT
    
    # 3. Create TAR from mount point (Frozen Data)
    # Here's the magic: Consistent backup
    echo '>>> Compressing data...'
    # Enter the mounted directory so that paths in the tar are clean
    cd $REMOTE_MOUNT_POINT
    tar -czf \"$REMOTE_TEMP_FILE\" $SOURCE_REL_PATH
" 2>&1

if [ $? -ne 0 ]; then
    echo "CRITICAL ERROR: Remote snapshot/compression process failed."
    exit 1
fi

echo "[2/3] Downloading file..."
rsync --progress -e ssh "${SSH_USER}@${TARGET_IP}:${REMOTE_TEMP_FILE}" "$LOCAL_FILE"

if [ $? -eq 0 ]; then
    echo "[3/3] Removing remote temporary file..."
    ssh "${SSH_USER}@${TARGET_IP}" "rm -f \"$REMOTE_TEMP_FILE\""
    
    echo "--------------------------------------------------"
    echo "BACKUP COMPLETED SUCCESSFULLY"
    echo "File: $LOCAL_FILE"
    echo "--------------------------------------------------"
else
    echo "ERROR: Download failed."
    exit 1
fi
