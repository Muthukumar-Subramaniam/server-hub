#!/bin/bash

source /etc/os-release
almalinux_major_version="${VERSION_ID%%.*}"

if [ -z "${dnsbinder_domain}"  ]; then
	echo -e "\nSeems like your local server is not yet built ! \n" 
	exit 1
fi

if [[ "${UID}" -ne 0 ]]
then
    echo -e "\nRun with sudo or run from root account ! \n"
    exit 1
fi

if ! ping -c 1 google.com &>/dev/null; then
	echo "Your internet connection is down! "
	exit 1
fi

# Define paths
LOCAL_REPO_DIR="/var/www/${dnsbinder_server_fqdn}.${dnsbinder_domain}/almalinux-local-repo"
REMOTE_BASEOS="https://repo.almalinux.org/almalinux/${almalinux_major_version}/BaseOS/x86_64/os/repodata/repomd.xml"
REMOTE_APPSTREAM="https://repo.almalinux.org/almalinux/${almalinux_major_version}/AppStream/x86_64/os/repodata/repomd.xml"
LOCK_FILE="/var/lock/almalinux-repo-sync.lock"
LOG_FILE="/var/log/almalinux-repo-sync.log"

# Acquire lock to prevent multiple simultaneous runs
exec 200>$LOCK_FILE
flock -n 200 || { echo "[$(date)] Another process is running. Exiting." | tee -a $LOG_FILE; exit 1; }

mkdir -p $LOCAL_REPO_DIR

echo "[$(date)] Checking for repository updates..." | tee -a $LOG_FILE

# Function to check and sync repo
sync_repo() {
    local repo_name="$1"
    local local_dir="$2"
    local remote_metadata_url="$3"

    local remote_checksum=$(curl -s "$remote_metadata_url" | grep "revision" | awk -F '[<>]' '{print $3}')
    local local_checksum=$(grep "revision" "$local_dir/$repo_name/repodata/repomd.xml" 2>/dev/null | awk -F '[<>]' '{print $3}')

    if [[ "$remote_checksum" != "$local_checksum" ]]; then
        echo "[$(date)] $repo_name has updates. Syncing..." | tee -a $LOG_FILE
        reposync --download-path="$local_dir" --repo="$repo_name" --arch=x86_64,noarch --download-metadata --newest-only
	echo "[$(date)] Removing old packages if any ..." | tee -a $LOG_FILE
	repomanage --keep=1 --old "$local_dir/$repo_name" | xargs rm -f
        log_sync_status "$repo_name" "updated"
    else
        log_sync_status "$repo_name" "no update"
    fi
}

# Function to log sync status separately for each repo
log_sync_status() {
    local repo_name="$1"
    local status="$2"

    if [[ "$status" == "updated" ]]; then
        echo "[$(date)] $repo_name sync completed successfully." | tee -a $LOG_FILE
    else
        echo "[$(date)] No updates detected for $repo_name." | tee -a $LOG_FILE
    fi
}

# Perform sync for both repos
sync_repo "baseos" "$LOCAL_REPO_DIR" "$REMOTE_BASEOS"
sync_repo "appstream" "$LOCAL_REPO_DIR" "$REMOTE_APPSTREAM"

rm -f $LOCK_FILE  # Delete the lock file
