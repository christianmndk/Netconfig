#!/bin/bash
# install.sh — NetConfig full installation (single script, no steps)
#
# Usage:
#   bash install.sh          (re-execs with sudo automatically)
#   sudo bash install.sh     (or run as root directly)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Auto-escalate to root ─────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "  NetConfig needs root for system setup — re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

TARGET_USER="${1:-${SUDO_USER:-root}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
BACKUP_DIR="$TARGET_HOME/network-backups"
GITEA_URL="http://localhost"
SERVER_IP=$(hostname -I | awk '{print $1}')

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[2;37m'; N='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
run_as_user() {
    if [[ "$TARGET_USER" == "root" ]] || [[ "$(whoami)" == "$TARGET_USER" ]]; then
        bash -c "$*"
    elif command -v sudo &>/dev/null; then
        sudo -u "$TARGET_USER" -H bash -c "$*"
    else
        su -l "$TARGET_USER" -c "$*"
    fi
}

wait_for_gitea() {
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if curl -sf "$GITEA_URL/api/v1/settings/api" > /dev/null 2>&1; then
            echo -e "  ${G}✓${N} Gitea is ready"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    echo -e "  ${R}✗ Gitea did not start in time. Check: docker logs gitea${N}"
    exit 1
}

# ── Header + credentials prompt ───────────────────────────────────────────────
echo ""
echo -e "${W}  ╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${W}  ║              NetConfig — Full Installation               ║${N}"
echo -e "${W}  ╚══════════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "${D}  Installing for user: $TARGET_USER${N}"
echo ""

echo -e "${C}  Choose a Gitea admin username and password.${N}"
echo -e "${D}  These are used to log in to the Gitea web UI.${N}"
echo ""
read -p "  Gitea username: " GITEA_USER
while true; do
    read -s -p "  Gitea password (min 8 chars): " GITEA_PASS
    echo ""
    [[ ${#GITEA_PASS} -ge 8 ]] && break
    echo -e "  ${Y}Password must be at least 8 characters.${N}"
done
echo ""

# ── [1/7] System packages ─────────────────────────────────────────────────────
echo -e "${C}  [1/7] Updating system and installing dependencies...${N}"
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq \
    curl git ufw fail2ban \
    openssh-client \
    ca-certificates gnupg lsb-release
echo -e "  ${G}✓${N} Done"

# ── [2/7] SSH hardening ───────────────────────────────────────────────────────
echo -e "${C}  [2/7] SSH hardening...${N}"
AUTH_KEYS="$TARGET_HOME/.ssh/authorized_keys"
if [[ -s "$AUTH_KEYS" ]]; then
    if [[ "$TARGET_USER" == "root" ]]; then
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
    echo -e "  ${G}✓${N} SSH hærdet (kun nøgle)"
else
    echo -e "  ${Y}~${N} Ingen authorized_keys fundet — springer SSH hardening over"
    echo -e "  ${D}  Tilføj din nøgle til $AUTH_KEYS og kør:${N}"
    echo -e "  ${D}  sudo bash $SCRIPT_DIR/install.sh${N}"
fi

# ── [3/7] Firewall ────────────────────────────────────────────────────────────
echo -e "${C}  [3/7] Configuring firewall...${N}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp     # SSH
ufw allow 80/tcp     # Gitea web UI
ufw allow 2222/tcp   # Gitea SSH
ufw --force enable
echo -e "  ${G}✓${N} Done"

# ── [4/7] Docker ─────────────────────────────────────────────────────────────
echo -e "${C}  [4/7] Installing Docker...${N}"
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" \
        | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
$(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    echo -e "  ${G}✓${N} Docker installed"
else
    echo -e "  ${Y}~${N} Docker already installed — skipping"
fi
[[ "$TARGET_USER" != "root" ]] && usermod -aG docker "$TARGET_USER" || true

# ── [5/7] Start Gitea + create admin account ─────────────────────────────────
echo -e "${C}  [5/7] Starting Gitea + Postgres...${N}"
mkdir -p /opt/netconfig-docker
cp "$SCRIPT_DIR/compose.yml" /opt/netconfig-docker/compose.yml
docker compose -f /opt/netconfig-docker/compose.yml up -d

wait_for_gitea

echo -e "  Creating Gitea admin account '${GITEA_USER}'..."
CREATE_OUTPUT=$(docker exec -u git gitea gitea admin user create \
    --username "$GITEA_USER" \
    --password "$GITEA_PASS" \
    --email "$GITEA_USER@netconfig.local" \
    --admin 2>&1) && CREATE_OK=true || CREATE_OK=false

if $CREATE_OK; then
    echo -e "  ${G}✓${N} Admin account created"
elif echo "$CREATE_OUTPUT" | grep -q "user already exists"; then
    echo -e "  ${Y}~${N} Account already exists — continuing"
else
    echo -e "  ${R}✗ Kunne ikke oprette Gitea-konto:${N}"
    echo "  $CREATE_OUTPUT"
    exit 1
fi

# ── [6/7] network-backups repo + local git ────────────────────────────────────
echo -e "${C}  [6/7] Setting up network-backups repo...${N}"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$GITEA_URL/api/v1/user/repos" \
    -u "$GITEA_USER:$GITEA_PASS" \
    -H "Content-Type: application/json" \
    -d '{"name":"network-backups","description":"Automated network device config backups","private":true,"auto_init":true,"default_branch":"main"}')

if [[ "$HTTP_STATUS" == "201" ]]; then
    echo -e "  ${G}✓${N} Repo created in Gitea"
elif [[ "$HTTP_STATUS" == "409" ]]; then
    echo -e "  ${Y}~${N} Repo already exists — skipping"
else
    echo -e "  ${R}✗ Gitea API returned HTTP $HTTP_STATUS — check credentials${N}"
    exit 1
fi

mkdir -p "$BACKUP_DIR"
[[ "$TARGET_USER" != "root" ]] && chown -R "$TARGET_USER:$TARGET_USER" "$BACKUP_DIR" || true

run_as_user "git config --global user.name '$TARGET_USER'"
run_as_user "git config --global user.email '$TARGET_USER@netconfig.local'"
run_as_user "git config --global credential.helper store"

if [[ ! -d "$BACKUP_DIR/.git" ]]; then
    run_as_user "git -C '$BACKUP_DIR' init -q"
    run_as_user "git -C '$BACKUP_DIR' remote add origin '$GITEA_URL/$GITEA_USER/network-backups.git'"
    printf "http://%s:%s@localhost\n" "$GITEA_USER" "$GITEA_PASS" > "$TARGET_HOME/.git-credentials"
    chmod 600 "$TARGET_HOME/.git-credentials"
    [[ "$TARGET_USER" != "root" ]] && chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.git-credentials" || true
    run_as_user "git -C '$BACKUP_DIR' fetch origin -q"
    run_as_user "git -C '$BACKUP_DIR' checkout -b main --track origin/main 2>/dev/null || \
        git -C '$BACKUP_DIR' branch --set-upstream-to=origin/main main 2>/dev/null || true"
    echo -e "  ${G}✓${N} Local repo linked to Gitea"
else
    echo -e "  ${Y}~${N} Git repo already initialised — skipping"
fi

# ── [7/7] Watcher service + cron + MOTD ──────────────────────────────────────
echo -e "${C}  [7/7] Installing watcher, cron job, and MOTD...${N}"

chmod +x "$SCRIPT_DIR/"*.sh

# Write config file so MOTD and other tools can find the right user/paths
cat > /etc/netconfig.conf <<EOF
NETCONFIG_USER=$TARGET_USER
NETCONFIG_HOME=$TARGET_HOME
NETCONFIG_BACKUP_DIR=$BACKUP_DIR
NETCONFIG_SCRIPT_DIR=$SCRIPT_DIR
EOF

# Generate service file with the actual script path
cat > /etc/systemd/system/netconfig-watcher@.service <<EOF
[Unit]
Description=NetConfig — auto-commit watcher for network-backups
After=network.target

[Service]
Type=simple
User=%i
ExecStart=$SCRIPT_DIR/autoUpdate.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "netconfig-watcher@$TARGET_USER" -q
systemctl start "netconfig-watcher@$TARGET_USER"

if [[ "$(systemctl is-active "netconfig-watcher@$TARGET_USER")" == "active" ]]; then
    echo -e "  ${G}✓${N} Watcher service running"
else
    echo -e "  ${R}✗ Watcher did not start — check: systemctl status netconfig-watcher@$TARGET_USER${N}"
fi

# Cron job (de-duplicate if re-running install)
CRON_JOB="0 2 * * * $SCRIPT_DIR/GetConfigs.sh >> $BACKUP_DIR/cron.log 2>&1"
run_as_user "(crontab -l 2>/dev/null | grep -v 'GetConfigs.sh'; echo '$CRON_JOB') | crontab -"
echo -e "  ${G}✓${N} Cron job installed (02:00 nightly)"

# MOTD
chmod -x /etc/update-motd.d/10-uname 2>/dev/null || true
chmod -x /etc/update-motd.d/50-motd-news 2>/dev/null || true
chmod -x /etc/update-motd.d/80-esm 2>/dev/null || true
chmod -x /etc/update-motd.d/91-release-upgrade 2>/dev/null || true
cp "$SCRIPT_DIR/99-netconfig" /etc/update-motd.d/99-netconfig
chmod +x /etc/update-motd.d/99-netconfig
echo -e "  ${G}✓${N} MOTD installed"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${W}  ╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${W}  ║  NetConfig is live!                                      ║${N}"
echo -e "${W}  ╠══════════════════════════════════════════════════════════╣${N}"
echo -e "${W}  ║${N}  ${C}Gitea${N}         http://$SERVER_IP                          ${W}║${N}"
echo -e "${W}  ║${N}  ${C}Backup repo${N}   $GITEA_URL/$GITEA_USER/network-backups  ${W}║${N}"
echo -e "${W}  ║${N}  ${C}Backup dir${N}    $BACKUP_DIR                     ${W}║${N}"
echo -e "${W}  ║${N}  ${C}Schedule${N}      nightly at 02:00                          ${W}║${N}"
echo -e "${W}  ║${N}  ${C}Auto-push${N}     every 30 seconds (polling)                ${W}║${N}"
echo -e "${W}  ╠══════════════════════════════════════════════════════════╣${N}"
echo -e "${W}  ║${N}  ${D}Test it:${N}                                                 ${W}║${N}"
echo -e "${W}  ║${N}  touch ~/network-backups/test.conf                    ${W}║${N}"
echo -e "${W}  ║${N}  Then check http://$SERVER_IP for the commit          ${W}║${N}"
echo -e "${W}  ╚══════════════════════════════════════════════════════════╝${N}"
echo ""
