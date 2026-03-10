#!/bin/bash
# autoUpdate.sh — watches ~/network-backups for changes and auto-commits to Gitea
# Runs as a systemd service (netconfig-watcher.service), not from cron.

MONITOR_DIR="$HOME/network-backups"
GITEA_URL="http://localhost:3000"
GITEA_USER="$(whoami)"

# ─── Ensure backup dir is a valid git repo linked to Gitea ───────────────────
mkdir -p "$MONITOR_DIR"
cd "$MONITOR_DIR"

if [[ ! -d ".git" ]]; then
    echo "No git repo found — initialising and linking to Gitea..."
    git init
    git remote add origin "$GITEA_URL/$GITEA_USER/network-backups.git"
fi

# Ensure remote is set in case it was init'd bare
if ! git remote get-url origin &>/dev/null; then
    git remote add origin "$GITEA_URL/$GITEA_USER/network-backups.git"
fi

# Pull latest from Gitea if remote has commits
if git fetch origin 2>/dev/null; then
    if git ls-remote --exit-code origin main &>/dev/null; then
        git checkout -b main --track origin/main 2>/dev/null || \
        git branch --set-upstream-to=origin/main main 2>/dev/null || true
        git pull origin main --quiet 2>/dev/null || true
        echo "Repo synced with Gitea."
    fi
fi
# ─────────────────────────────────────────────────────────────────────────────

echo "Watcher started on $MONITOR_DIR at $(date)..."

inotifywait -m -e close_write --format '%f' "$MONITOR_DIR" | while read FILE; do
    # Ignore git internals
    [[ "$FILE" == .git* ]] && continue

    echo "Change detected: $FILE — committing to Gitea..."
    cd "$MONITOR_DIR"

    git pull origin main --quiet
    git add "$FILE"
    git commit -m "Auto backup: $FILE ($(date +'%Y-%m-%d %H:%M'))"
    git push origin main

    if [[ $? -eq 0 ]]; then
        echo "  Pushed: $FILE"
    else
        echo "  Push failed for $FILE — check Gitea connectivity"
    fi
done
