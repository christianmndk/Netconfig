#!/bin/bash
# pfsense_backup.sh — standalone pfSense config backup
# Preserved from GetConfigs.sh when pfSense support was removed from the main script.
#
# pfSense exposes its config at /conf/config.xml over SCP.
# Usage: bash pfsense_backup.sh <ip> <output_file>
#   e.g. bash pfsense_backup.sh 10.10.10.2 firewall.xml
#
# Requires SSH key auth to be set up on the pfSense box first.

set -e

IP="${1:?Usage: pfsense_backup.sh <ip> <output_file>}"
OUTPUT="${2:?Usage: pfsense_backup.sh <ip> <output_file>}"
BACKUP_DIR="$HOME/network-backups"

mkdir -p "$BACKUP_DIR"

echo "Fetching pfSense config from $IP..."
scp "admin@$IP:/conf/config.xml" "$BACKUP_DIR/$OUTPUT"

if [[ $? -eq 0 ]]; then
    echo "  OK: saved to $BACKUP_DIR/$OUTPUT"
else
    echo "  FAILED: could not reach $IP — check SSH key / connectivity"
    exit 1
fi
