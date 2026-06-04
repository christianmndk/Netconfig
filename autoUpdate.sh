#!/bin/bash
# autoUpdate.sh — polls ~/network-backups every 30s and auto-commits changes to Gitea
# Runs as a systemd service (netconfig-watcher@.service).

MONITOR_DIR="$HOME/network-backups"
POLL_INTERVAL=30

mkdir -p "$MONITOR_DIR"
cd "$MONITOR_DIR"

if ! git -C "$MONITOR_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') ERROR: $MONITOR_DIR is not a git repo — run install.sh first"
    exit 1
fi

git pull origin main --quiet 2>/dev/null || true

echo "$(date +'%Y-%m-%d %H:%M:%S') Watcher started on $MONITOR_DIR (polling every ${POLL_INTERVAL}s)"

while true; do
    if [[ -n "$(git -C "$MONITOR_DIR" status --porcelain 2>/dev/null)" ]]; then
        git -C "$MONITOR_DIR" pull origin main --quiet 2>/dev/null || true
        git -C "$MONITOR_DIR" add -A

        CHANGED=$(git -C "$MONITOR_DIR" diff --cached --name-only | tr '\n' ' ')
        git -C "$MONITOR_DIR" commit -m "Auto backup: $(date +'%Y-%m-%d %H:%M') — ${CHANGED%% }"

        if git -C "$MONITOR_DIR" push origin main 2>/dev/null; then
            echo "$(date +'%Y-%m-%d %H:%M:%S') Pushed: $CHANGED"
        else
            echo "$(date +'%Y-%m-%d %H:%M:%S') Push failed — check Gitea connectivity"
        fi
    fi

    sleep $POLL_INTERVAL
done
