#!/bin/bash
# setup.sh — One-shot VM setup for NetConfig server
# Run as root on a fresh Debian/Ubuntu terminal install.
# Usage: sudo ./setup.sh YOUR_USERNAME
# Example: sudo ./setup.sh admin

set -e  # Exit on any error

# ─── Config ───────────────────────────────────────────────────────────────────
TARGET_USER="${1:-$SUDO_USER}"
NETCONFIG_REPO="https://github.com/YOU/NetConfig.git"  # <-- update this
BACKUP_DIR="/home/$TARGET_USER/network-backups"
NETCONFIG_DIR="/home/$TARGET_USER/NetConfig"
# ──────────────────────────────────────────────────────────────────────────────

if [[ -z "$TARGET_USER" ]]; then
    echo "Usage: sudo ./setup.sh YOUR_USERNAME"
    exit 1
fi

echo ""
echo "======================================"
echo "  NetConfig VM Setup"
echo "  User: $TARGET_USER"
echo "======================================"
echo ""

# ─── 1. System update ─────────────────────────────────────────────────────────
echo "[1/7] Updating system..."
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq \
    curl git ufw fail2ban \
    inotify-tools openssh-client \
    ca-certificates gnupg lsb-release

# ─── 2. SSH hardening ─────────────────────────────────────────────────────────
echo "[2/7] Hardening SSH..."
cat > /etc/ssh/sshd_config.d/99-netconfig.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
EOF
systemctl reload ssh

# ─── 3. Firewall ──────────────────────────────────────────────────────────────
echo "[3/7] Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 3000/tcp  # Gitea web UI
ufw allow 2222/tcp  # Gitea SSH
ufw --force enable

# ─── 4. Docker ────────────────────────────────────────────────────────────────
echo "[4/7] Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
$(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker "$TARGET_USER"

# ─── 5. Start Gitea + Postgres ────────────────────────────────────────────────
echo "[5/7] Starting Gitea + Postgres..."
mkdir -p /opt/netconfig-docker
cp "$(dirname "$0")/docker/compose.yml" /opt/netconfig-docker/compose.yml
docker compose -f /opt/netconfig-docker/compose.yml up -d
echo "  Waiting for Gitea to be ready..."
sleep 15

# ─── 6. Clone NetConfig repo + set up backup dir ──────────────────────────────
echo "[6/7] Setting up NetConfig repo and backup directory..."
mkdir -p "$BACKUP_DIR"

# Init backup dir as a git repo pointing at Gitea
# (After setup, create the repo in Gitea UI at http://YOUR_IP:3000 first)
cd "$BACKUP_DIR"
git init
git remote add origin "http://localhost:3000/$TARGET_USER/network-backups.git" || true

# Clone the NetConfig scripts repo
if [[ ! -d "$NETCONFIG_DIR" ]]; then
    sudo -u "$TARGET_USER" git clone "$NETCONFIG_REPO" "$NETCONFIG_DIR"
fi

# Make scripts executable
chmod +x "$NETCONFIG_DIR/VELO_TOOLS/"*.sh

# Fix ownership
chown -R "$TARGET_USER:$TARGET_USER" "$BACKUP_DIR" "$NETCONFIG_DIR"

# ─── 7. systemd watcher service + cron ───────────────────────────────────────
echo "[7/7] Installing systemd watcher and cron job..."

# Install systemd service
cp "$NETCONFIG_DIR/VELO_TOOLS/netconfig-watcher@.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable "netconfig-watcher@$TARGET_USER"
systemctl start "netconfig-watcher@$TARGET_USER"

# Install cron job (runs GetConfigs.sh at 02:00 nightly)
CRON_JOB="0 2 * * * $NETCONFIG_DIR/VELO_TOOLS/GetConfigs.sh >> $BACKUP_DIR/cron.log 2>&1"
(crontab -u "$TARGET_USER" -l 2>/dev/null; echo "$CRON_JOB") | crontab -u "$TARGET_USER" -

# ─── Done ─────────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "======================================"
echo "  Setup complete!"
echo "======================================"
echo ""
echo "  Gitea web UI : http://$SERVER_IP:3000"
echo "  Gitea SSH    : ssh://git@$SERVER_IP:2222"
echo "  Backup dir   : $BACKUP_DIR"
echo "  Scripts      : $NETCONFIG_DIR/VELO_TOOLS/"
echo ""
echo "  Next steps:"
echo "  1. Go to http://$SERVER_IP:3000 and complete Gitea setup"
echo "  2. Create a repo called 'network-backups' in Gitea"
echo "  3. Add your SSH key to each network device"
echo "  4. Update NETCONFIG_REPO in setup.sh to point at your Gitea"
echo "  5. Edit devices.yml with your actual device IPs"
echo ""
echo "  Watcher service: systemctl status netconfig-watcher@$TARGET_USER"
echo "  Cron job added for user: $TARGET_USER"
echo ""
