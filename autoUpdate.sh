#!/bin/bash
# autoUpdate.sh — watches ~/network-backups for changes and auto-commits to Gitea
# Runs as a systemd service (netconfig-watcher.service), not from cron.

MONITOR_DIR="$HOME/network-backups"

echo "Watcher started on $MONITOR_DIR at $(date)..."

inotifywait -m -e close_write --format '%f' "$MONITOR_DIR" | while read FILE; do
    # Ignore git internals
    [[ "$FILE" == .git* ]] && continue

    echo "Change detected: $FILE — committing to Gitea..."
    cd "$MONITOR_DIR"

    git pull origin master --quiet
    git add "$FILE"
    git commit -m "Auto backup: $FILE ($(date +'%Y-%m-%d %H:%M'))"
    git push origin master

    if [[ $? -eq 0 ]]; then
        echo "  Pushed: $FILE"
    else
        echo "  Push failed for $FILE — check Gitea connectivity"
    fi
done
