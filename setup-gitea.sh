#!/bin/bash
# setup-gitea.sh — Run this AFTER completing the Gitea first-run wizard.
# Creates the network-backups repo, initialises the local git repo,
# and starts the autoUpdate watcher service.
#
# Usage: bash setup-gitea.sh
# (run as your normal user, NOT sudo)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="$(whoami)"
BACKUP_DIR="$HOME/network-backups"
GITEA_URL="http://localhost:3000"

echo ""
echo "======================================"
echo "  NetConfig — Gitea Setup"
echo "======================================"
echo ""

# ─── Ask for Gitea credentials ────────────────────────────────────────────────
read -p "  Gitea username: " GITEA_USER
read -s -p "  Gitea password: " GITEA_PASS
echo ""

# ─── Create the network-backups repo via Gitea API ────────────────────────────
echo ""
echo "[1/3] Creating 'network-backups' repo in Gitea..."
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
    echo "  Repo created OK"
elif [[ "$HTTP_STATUS" == "409" ]]; then
    echo "  Repo already exists — skipping"
else
    echo "  ERROR: Gitea returned HTTP $HTTP_STATUS"
    echo "  Check your credentials and that Gitea is running at $GITEA_URL"
    exit 1
fi

# ─── Init local backup dir and link to Gitea ──────────────────────────────────
echo "[2/3] Initialising local backup repo..."
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

if [[ ! -d ".git" ]]; then
    git init
    git remote add origin "$GITEA_URL/$GITEA_USER/network-backups.git"
    # Store credentials so push doesn't prompt
    git config credential.helper store
    echo "$GITEA_URL" | git -c credential.helper="store --file $HOME/.git-credentials" \
        credential approve <<< "protocol=http
host=localhost:3000
username=$GITEA_USER
password=$GITEA_PASS" 2>/dev/null || true
    printf "protocol=http\nhost=localhost:3000\nusername=%s\npassword=%s\n" \
        "$GITEA_USER" "$GITEA_PASS" > "$HOME/.git-credentials"
    chmod 600 "$HOME/.git-credentials"

    # Pull the auto-init commit from Gitea
    git fetch origin
    git checkout -b main --track origin/main 2>/dev/null || \
        git branch --set-upstream-to=origin/main main 2>/dev/null || true
    echo "  Local repo linked to Gitea"
else
    echo "  Git repo already initialised — skipping"
fi

# ─── Start the watcher service ────────────────────────────────────────────────
echo "[3/3] Starting autoUpdate watcher service..."
sudo systemctl enable "netconfig-watcher@$TARGET_USER"
sudo systemctl start "netconfig-watcher@$TARGET_USER"

STATUS=$(sudo systemctl is-active "netconfig-watcher@$TARGET_USER")
if [[ "$STATUS" == "active" ]]; then
    echo "  Watcher is running"
else
    echo "  WARNING: Watcher may not have started — check: sudo systemctl status netconfig-watcher@$TARGET_USER"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "======================================"
echo "  All done! System is fully live."
echo "======================================"
echo ""
echo "  Gitea          : http://$SERVER_IP:3000"
echo "  Backup repo    : $GITEA_URL/$GITEA_USER/network-backups"
echo "  Backup dir     : $BACKUP_DIR"
echo "  Config backups : every night at 02:00"
echo "  Auto-push      : on every file change (watcher running)"
echo ""
echo "  Test it now:"
echo "    touch $BACKUP_DIR/test.conf"
echo "    # Wait a moment, then check Gitea for the commit"
echo ""
