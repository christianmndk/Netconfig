#!/bin/bash
# setup-gitea.sh — Run this AFTER completing the Gitea first-run wizard.
# Creates the network-backups repo, initialises the local git repo,
# and starts the autoUpdate watcher service.
#
# Usage: bash setup-gitea.sh
# (run as your normal user, NOT sudo)

set -e

# Block sudo but allow direct root login
if [[ "$EUID" -eq 0 && -n "$SUDO_USER" ]]; then
    echo ""
    echo "  ERROR: Do not run this script with sudo."
    echo "  Run it as your normal user: bash setup-gitea.sh"
    echo ""
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="$(whoami)"
BACKUP_DIR="$HOME/network-backups"
GITEA_URL="http://localhost:3000"
SERVER_IP=$(hostname -I | awk '{print $1}')

# ─── Colours ──────────────────────────────────────────────────────────────────
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
C='\033[0;36m'
W='\033[1;37m'
D='\033[2;37m'
N='\033[0m'

echo ""
echo -e "${W}  ╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${W}  ║              NetConfig — Gitea Setup                     ║${N}"
echo -e "${W}  ╚══════════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "${D}  Running as: $TARGET_USER${N}"
echo ""

# ─── Ask for Gitea credentials ────────────────────────────────────────────────
echo -e "${C}  Gitea credentials${N}"
read -p "  Username: " GITEA_USER
read -s -p "  Password: " GITEA_PASS
echo ""
echo ""

# ─── Create the network-backups repo via Gitea API ────────────────────────────
echo -e "${C}  [1/3] Creating 'network-backups' repo in Gitea...${N}"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$GITEA_URL/api/v1/user/repos" \
    -u "$GITEA_USER:$GITEA_PASS" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "network-backups",
        "description": "Automated network device config backups",
        "private": true,
        "auto_init": true,
        "default_branch": "main"
    }')

if [[ "$HTTP_STATUS" == "201" ]]; then
    echo -e "  ${G}✓${N} Repo created"
elif [[ "$HTTP_STATUS" == "409" ]]; then
    echo -e "  ${Y}~${N} Repo already exists — skipping"
else
    echo -e "  ${R}✗ ERROR: Gitea returned HTTP $HTTP_STATUS${N}"
    echo -e "  ${D}Check your credentials and that Gitea is running at $GITEA_URL${N}"
    exit 1
fi

# ─── Init local backup dir and link to Gitea ──────────────────────────────────
echo -e "${C}  [2/3] Initialising local backup repo...${N}"
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

if [[ ! -d ".git" ]]; then
    git init -q
    git remote add origin "$GITEA_URL/$GITEA_USER/network-backups.git"
    git config credential.helper store
    printf "protocol=http\nhost=localhost:3000\nusername=%s\npassword=%s\n" \
        "$GITEA_USER" "$GITEA_PASS" > "$HOME/.git-credentials"
    chmod 600 "$HOME/.git-credentials"
    git fetch origin -q
    git checkout -b main --track origin/main 2>/dev/null || \
        git branch --set-upstream-to=origin/main main 2>/dev/null || true
    echo -e "  ${G}✓${N} Local repo linked to Gitea"
else
    echo -e "  ${Y}~${N} Git repo already initialised — skipping"
fi

# ─── Start the watcher service ────────────────────────────────────────────────
echo -e "${C}  [3/3] Starting autoUpdate watcher service...${N}"
sudo systemctl enable "netconfig-watcher@$TARGET_USER" -q
sudo systemctl start "netconfig-watcher@$TARGET_USER"

STATUS=$(sudo systemctl is-active "netconfig-watcher@$TARGET_USER")
if [[ "$STATUS" == "active" ]]; then
    echo -e "  ${G}✓${N} Watcher is running"
else
    echo -e "  ${R}✗ Watcher did not start${N}"
    echo -e "  ${D}Check: sudo systemctl status netconfig-watcher@$TARGET_USER${N}"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${W}  ╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${W}  ║  All done! System is fully live.                         ║${N}"
echo -e "${W}  ╠══════════════════════════════════════════════════════════╣${N}"
echo -e "${W}  ║${N}  ${C}Gitea${N}        http://$SERVER_IP:3000                      ${W}║${N}"
echo -e "${W}  ║${N}  ${C}Backup repo${N}  $GITEA_URL/$GITEA_USER/network-backups  ${W}║${N}"
echo -e "${W}  ║${N}  ${C}Backup dir${N}   $BACKUP_DIR                      ${W}║${N}"
echo -e "${W}  ║${N}  ${C}Schedule${N}     every night at 02:00                       ${W}║${N}"
echo -e "${W}  ║${N}  ${C}Auto-push${N}    on every file change                       ${W}║${N}"
echo -e "${W}  ╠══════════════════════════════════════════════════════════╣${N}"
echo -e "${W}  ║${N}  ${D}Test it:${N}                                                 ${W}║${N}"
echo -e "${W}  ║${N}  touch ~/network-backups/test.conf                    ${W}║${N}"
echo -e "${W}  ║${N}  Then check http://$SERVER_IP:3000 for the commit     ${W}║${N}"
echo -e "${W}  ╚══════════════════════════════════════════════════════════╝${N}"
echo ""