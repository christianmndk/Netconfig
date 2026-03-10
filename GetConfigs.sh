#!/bin/bash
# GetConfigs.sh — pulls running configs from all devices defined in devices.yml
# Runs via cron at 02:00. Triggered backups handled by autoUpdate.sh (systemd).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES_FILE="$SCRIPT_DIR/devices.yml"
BACKUP_DIR="$HOME/network-backups"

mkdir -p "$BACKUP_DIR"

echo "--- Starting network backup: $(date) ---"

# Parse devices.yml with awk (no python/yq dependency needed)
# Reads name, ip, type, filename fields
while IFS= read -r line; do
    # Extract fields
    [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+) ]] && NAME="${BASH_REMATCH[1]}"
    [[ "$line" =~ ^[[:space:]]*ip:[[:space:]]*(.+) ]]                && IP="${BASH_REMATCH[1]}"
    [[ "$line" =~ ^[[:space:]]*type:[[:space:]]*(.+) ]]              && TYPE="${BASH_REMATCH[1]}"
    [[ "$line" =~ ^[[:space:]]*filename:[[:space:]]*(.+) ]]          && FILENAME="${BASH_REMATCH[1]}"

    # Once we have all 4 fields, process the device
    if [[ -n "$NAME" && -n "$IP" && -n "$TYPE" && -n "$FILENAME" ]]; then
        echo "Fetching $NAME ($IP) -> $FILENAME..."

        if [[ "$TYPE" == "pfsense" ]]; then
            scp "admin@$IP:/conf/config.xml" "$BACKUP_DIR/$FILENAME"
        else
            # Cisco and generic SSH devices
            scp -O "admin@$IP:running-config" "$BACKUP_DIR/$FILENAME"
        fi

        if [[ $? -eq 0 ]]; then
            echo "  OK: $NAME"
        else
            echo "  FAILED: $NAME ($IP) — check SSH key / connectivity"
        fi

        # Reset for next device
        NAME="" IP="" TYPE="" FILENAME=""
    fi
done < "$DEVICES_FILE"

echo "--- Backup complete: $(date) ---"
