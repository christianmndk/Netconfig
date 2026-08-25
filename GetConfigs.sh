#!/bin/bash
# GetConfigs.sh — pulls running configs from all Cisco devices in devices.yml
# Runs via cron at 02:00. Logs to ~/network-backups/cron.log.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES_FILE="$SCRIPT_DIR/devices.yml"
SECRETS_FILE="$SCRIPT_DIR/secrets.yml"
BACKUP_DIR="$HOME/network-backups"

mkdir -p "$BACKUP_DIR"

echo "--- Starting network backup: $(date) ---"

# ── Load secrets.yml (passwords for devices with auth: password) ─────────────
declare -A SECRETS
if [[ -f "$SECRETS_FILE" ]]; then
    perms=$(stat -c '%a' "$SECRETS_FILE" 2>/dev/null)
    if [[ -n "$perms" && "$perms" != "600" ]]; then
        echo "  WARNING: $SECRETS_FILE has mode $perms, expected 600 — run: chmod 600 $SECRETS_FILE"
    fi
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+([A-Za-z0-9_.-]+):[[:space:]]*(.+)$ ]]; then
            SECRETS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        fi
    done < "$SECRETS_FILE"
fi
if ! command -v sshpass &>/dev/null && grep -q '^\s*auth:\s*password' "$DEVICES_FILE"; then
    echo "  WARNING: devices.yml has auth: password entries but 'sshpass' is not installed (apt install sshpass)"
fi

# Old Cisco IOS SSH stacks only speak legacy algorithms that modern OpenSSH
# disables by default; re-enable them (append with '+', don't replace) so the
# client still prefers modern algorithms where devices support them. pfSense
# runs a modern OpenSSH, so the appended legacy algorithms are simply ignored
# there and the modern ones are used instead.
#
# These apply to BOTH auth paths: algorithm negotiation happens before
# authentication, so a device that only speaks legacy KEX drops the connection
# long before the password or key is ever offered.
LEGACY_SSH_OPTS=(
    -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1,diffie-hellman-group1-sha1
    -o HostKeyAlgorithms=+ssh-rsa
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
    -o Ciphers=+aes128-cbc,aes192-cbc,aes256-cbc,3des-cbc
)

NAME="" IP="" TYPE="" FILENAME="" USERNAME="" AUTH=""

fetch_device() {
    [[ -z "$NAME" || -z "$IP" || -z "$FILENAME" ]] && return

    local user="${USERNAME:-admin}"
    local type="${TYPE:-cisco}"
    local auth="${AUTH:-key}"

    # Each device type exposes its config at a different remote path.
    local remote
    case "$type" in
        cisco)
            remote="running-config"
            ;;
        pfsense)
            # pfSense keeps its full configuration as one XML file.
            # /conf is a symlink to /cf/conf, so /cf/conf/config.xml is the
            # canonical location on the underlying FreeBSD filesystem.
            remote="/cf/conf/config.xml"
            ;;
        *)
            echo "  SKIPPED: $NAME ($IP) — unknown type '$type'"
            NAME="" IP="" TYPE="" FILENAME="" USERNAME="" AUTH=""
            return
            ;;
    esac

    echo "Fetching $NAME ($IP) as $user [$type/$auth]..."

    local err
    if [[ "$auth" == "password" ]]; then
        local pass="${SECRETS[$NAME]}"
        if [[ -z "$pass" ]]; then
            echo "  FAILED: $NAME ($IP) — auth: password but no entry for '$NAME' in secrets.yml"
            NAME="" IP="" TYPE="" FILENAME="" USERNAME="" AUTH=""
            return
        fi
        # Password goes through the SSHPASS env var (sshpass -e), never -p,
        # so it doesn't show up in the process list (ps aux).
        if err=$(SSHPASS="$pass" sshpass -e scp -O -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
            -o PreferredAuthentications=keyboard-interactive,password -o PubkeyAuthentication=no \
            "${LEGACY_SSH_OPTS[@]}" \
            "$user@$IP:$remote" "$BACKUP_DIR/$FILENAME" 2>&1); then
            echo "  OK: $NAME"
        else
            echo "  FAILED: $NAME ($IP) — ${err:-unknown error}"
        fi
    else
        if err=$(scp -O -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
            "${LEGACY_SSH_OPTS[@]}" \
            "$user@$IP:$remote" "$BACKUP_DIR/$FILENAME" 2>&1); then
            echo "  OK: $NAME"
        else
            echo "  FAILED: $NAME ($IP) — ${err:-unknown error}"
        fi
    fi

    NAME="" IP="" TYPE="" FILENAME="" USERNAME="" AUTH=""
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
    elif [[ "$line" =~ ^[[:space:]]*auth:[[:space:]]*(.+) ]]; then
        AUTH="${BASH_REMATCH[1]}"
    fi
done < "$DEVICES_FILE"

fetch_device  # process last device

echo "--- Backup complete: $(date) ---"
