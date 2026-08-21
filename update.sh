#!/bin/bash
# update.sh — pull the latest NetConfig scripts without touching your
# local device list (devices.yml) or secrets (secrets.yml).
#
# Usage: bash update.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; C='\033[0;36m'; N='\033[0m'

echo ""
echo -e "${C}  NetConfig — Update${N}"
echo ""

if ! git rev-parse --git-dir &>/dev/null; then
    echo -e "  ${R}✗ $SCRIPT_DIR is not a git repo.${N}"
    exit 1
fi

# Older installs may still have devices.yml tracked from before it became
# gitignored local config — untrack it (working copy is untouched) so the
# pull below can't conflict with or overwrite your real devices.
if git ls-files --error-unmatch devices.yml &>/dev/null 2>&1; then
    echo -e "  ${Y}Found a tracked devices.yml from an older install — untracking it (your devices stay put).${N}"
    git rm --cached -q devices.yml
fi

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo -e "  ${R}✗ Local changes to tracked NetConfig files — commit or stash them first:${N}"
    git status --short
    exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "  Pulling latest changes ($BRANCH)..."
git pull origin "$BRANCH"
echo ""

if [[ ! -f devices.yml ]]; then
    cp devices.yml.example devices.yml
    echo -e "  ${G}✓${N} Created devices.yml from template — edit it or run add-device.sh"
fi

chmod +x GetConfigs.sh autoUpdate.sh add-device.sh update.sh install.sh 2>/dev/null || true

if [[ -f 99-netconfig ]]; then
    if sudo cp 99-netconfig /etc/update-motd.d/99-netconfig 2>/dev/null && sudo chmod +x /etc/update-motd.d/99-netconfig; then
        echo -e "  ${G}✓${N} MOTD updated"
    else
        echo -e "  ${Y}!${N} Could not update MOTD — run manually: sudo cp 99-netconfig /etc/update-motd.d/99-netconfig"
    fi
fi

WATCHER="netconfig-watcher@$(whoami)"
if systemctl list-unit-files "netconfig-watcher@.service" &>/dev/null && systemctl is-enabled "$WATCHER" &>/dev/null; then
    sudo systemctl restart "$WATCHER" && echo -e "  ${G}✓${N} Restarted $WATCHER"
fi

echo ""
echo -e "  ${G}✓ Update complete.${N}"
echo -e "  ${C}Note:${N} if compose.yml or the systemd/cron setup changed upstream, re-run: sudo bash install.sh"
echo ""
