#!/bin/bash
# GetConfigs.sh — pulls running configs from all Cisco devices in devices.yml
# Runs via cron at 02:00. Logs to ~/network-backups/cron.log.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES_FILE="$SCRIPT_DIR/devices.yml"
BACKUP_DIR="$HOME/network-backups"

mkdir -p "$BACKUP_DIR"

echo "--- Starting network backup: $(date) ---"

NAME="" IP="" TYPE="" FILENAME="" USERNAME=""

fetch_device() {
    [[ -z "$NAME" || -z "$IP" || -z "$FILENAME" ]] && return

    local user="${USERNAME:-admin}"
    echo "Fetching $NAME ($IP) as $user..."

    if scp -O "$user@$IP:running-config" "$BACKUP_DIR/$FILENAME" 2>/dev/null; then
        echo "  OK: $NAME"
    else
        echo "  FAILED: $NAME ($IP) — check SSH key / connectivity"
    fi

    NAME="" IP="" TYPE="" FILENAME="" USERNAME=""
}

while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+) ]]; then
        fetch_device
        NAME="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*ip:[[:space:]]*(.+) ]]; then
        IP="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]*(.+) ]]; then
        TYPE="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*filename:[[:space:]]*(.+) ]]; then
        FILENAME="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*username:[[:space:]]*(.+) ]]; then
        USERNAME="${BASH_REMATCH[1]}"
    fi
done < "$DEVICES_FILE"

fetch_device  # process last device

echo "--- Backup complete: $(date) ---"
