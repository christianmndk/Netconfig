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

    # Old Cisco IOS SSH stacks only speak legacy algorithms that modern
    # OpenSSH disables by default; re-enable them (append, don't replace)
    # so the client still prefers modern algorithms where devices support them.
    local err
    if err=$(scp -O -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1,diffie-hellman-group1-sha1 \
        -o HostKeyAlgorithms=+ssh-rsa \
        -o PubkeyAcceptedAlgorithms=+ssh-rsa \
        -o Ciphers=+aes128-cbc,aes192-cbc,aes256-cbc,3des-cbc \
        "$user@$IP:running-config" "$BACKUP_DIR/$FILENAME" 2>&1); then
        echo "  OK: $NAME"
    else
        echo "  FAILED: $NAME ($IP) — ${err:-unknown error}"
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
