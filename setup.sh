#!/bin/bash
# setup.sh — One-shot VM/CT setup for NetConfig server
# Run as root on a fresh Debian/Ubuntu/CT install.
#
# On a VM with a normal user:   sudo ./setup.sh YOUR_USERNAME
# On a root-only CT:            ./setup.sh root

set -e

# Resolve the real directory of this script regardless of how it was called
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Config ───────────────────────────────────────────────────────────────────
# If no argument given, use SUDO_USER (VM) or fall back to root (CT)
TARGET_USER="${1:-${SUDO_USER:-root}}"
NETCONFIG_REPO="https://github.com/YOU/NetConfig.git"  # <-- update this
BACKUP_DIR="/home/$TARGET_USER/network-backups"
[[ "$TARGET_USER" == "root" ]] && BACKUP_DIR="/root/network-backups"
# ──────────────────────────────────────────────────────────────────────────────

# Helper: run a command as TARGET_USER without requiring sudo
# On a normal system uses sudo -u, on root-only CT uses su -c or runs directly
run_as_user() {
    if [[ "$TARGET_USER" == "root" ]] || [[ "$(whoami)" == "$TARGET_USER" ]]; then
        bash -c "$*"
    elif command -v sudo &>/dev/null; then
        sudo -u "$TARGET_USER" bash -c "$*"
    else
        su -l "$TARGET_USER" -c "$*"
    fi
}

echo ""
echo "======================================"
echo "  NetConfig VM Setup"
echo "  User: $TARGET_USER"
echo "======================================"
echo ""

# ─── 1. System update ─────────────────────────────────────────────────────────
echo "[1/8] Updating system..."
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq \
    curl git ufw fail2ban \
    inotify-tools openssh-client \
    ca-certificates gnupg lsb-release

# ─── 2. SSH hardening ─────────────────────────────────────────────────────────
echo "[2/8] Hardening SSH..."
if [[ "$TARGET_USER" == "root" ]]; then
    # Root-only CT — keep root login but enforce key-only
    cat > /etc/ssh/sshd_config.d/99-netconfig.conf <<EOF
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
EOF
else
    cat > /etc/ssh/sshd_config.d/99-netconfig.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
EOF
fi
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

# ─── 3. Firewall ──────────────────────────────────────────────────────────────
echo "[3/8] Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 3000/tcp  # Gitea web UI
ufw allow 2222/tcp  # Gitea SSH
ufw --force enable

# ─── 4. Docker ────────────────────────────────────────────────────────────────
echo "[4/8] Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
    | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
$(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
[[ "$TARGET_USER" != "root" ]] && usermod -aG docker "$TARGET_USER" || true

# ─── 5. Start Gitea + Postgres ────────────────────────────────────────────────
echo "[5/8] Starting Gitea + Postgres..."
mkdir -p /opt/netconfig-docker
cp "$SCRIPT_DIR/compose.yml" /opt/netconfig-docker/compose.yml
docker compose -f /opt/netconfig-docker/compose.yml up -d
echo "  Waiting for Gitea to be ready..."
sleep 15

# ─── 6. Create backup dir + set git identity ──────────────────────────────────
echo "[6/8] Preparing backup directory..."
mkdir -p "$BACKUP_DIR"
[[ "$TARGET_USER" != "root" ]] && chown -R "$TARGET_USER:$TARGET_USER" "$BACKUP_DIR" || true

# Set git identity so commits don't fail
run_as_user "git config --global user.name '$TARGET_USER'"
run_as_user "git config --global user.email '$TARGET_USER@netconfig.local'"

# Make all scripts executable
chmod +x "$SCRIPT_DIR/"*.sh

# ─── 7. systemd watcher + cron (disabled until Gitea is ready) ───────────────
echo "[7/8] Installing systemd watcher and cron job..."

cp "$SCRIPT_DIR/netconfig-watcher@.service" /etc/systemd/system/
systemctl daemon-reload
# NOTE: watcher is installed but NOT started yet — run setup-gitea.sh after
# configuring Gitea to start it properly.

# Install cron job (runs GetConfigs.sh at 02:00 nightly)
CRON_JOB="0 2 * * * $SCRIPT_DIR/GetConfigs.sh >> $BACKUP_DIR/cron.log 2>&1"
run_as_user "(crontab -l 2>/dev/null; echo '$CRON_JOB') | crontab -"

# ─── 8. MOTD ──────────────────────────────────────────────────────────────────
echo "[8/8] Installing MOTD..."

# Disable noisy default motd parts
chmod -x /etc/update-motd.d/10-uname 2>/dev/null || true
chmod -x /etc/update-motd.d/50-motd-news 2>/dev/null || true
chmod -x /etc/update-motd.d/80-esm 2>/dev/null || true
chmod -x /etc/update-motd.d/91-release-upgrade 2>/dev/null || true

# Install ours
cp "$SCRIPT_DIR/99-netconfig" /etc/update-motd.d/99-netconfig
chmod +x /etc/update-motd.d/99-netconfig

# ─── Done ─────────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "======================================"
echo "  Step 1 complete!"
echo "======================================"
echo ""
echo "  Gitea web UI : http://$SERVER_IP:3000"
echo ""
echo "  ┌─ NEXT STEPS ──────────────────────────────────────────────┐"
echo "  │                                                           │"
echo "  │  1. Go to http://$SERVER_IP:3000                         │"
echo "  │  2. Complete the Gitea first-run wizard                  │"
echo "  │     - Use these DB settings (already running):           │"
echo "  │       Type: PostgreSQL                                    │"
echo "  │       Host: postgres:5432                                 │"
echo "  │       User: gitea  Password: gitea  DB: gitea            │"
echo "  │  3. Create your admin account (use username: $TARGET_USER) │"
echo "  │  4. Then run: bash $SCRIPT_DIR/setup-gitea.sh            │"
echo "  │                                                           │"
echo "  └───────────────────────────────────────────────────────────┘"
echo ""