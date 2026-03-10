# NetConfig

Network configuration backup and automation server.

## What this is

A self-hosted VM running:
- **Gitea** — git server storing all device configs and scripts
- **Postgres** — database backend for Gitea
- **GetConfigs.sh** — pulls running configs from all network devices nightly at 02:00
- **autoUpdate.sh** — watches the backup folder and auto-commits any changes to Gitea

## Fresh install (one command)

On a clean Debian/Ubuntu server:

```bash
git clone https://github.com/YOU/NetConfig.git
cd NetConfig
sudo ./setup.sh YOUR_USERNAME
```

That's it. The script sets up everything and prints next steps when done.

## Repo structure

```
NetConfig/
├── setup.sh                        ← run this once on a fresh VM
├── docker/
│   └── compose.yml                 ← Gitea + Postgres
└── VELO_TOOLS/
    ├── devices.yml                 ← device inventory (edit this)
    ├── GetConfigs.sh               ← pulls configs from all devices
    ├── autoUpdate.sh               ← watches backup dir, pushes to Gitea
    ├── netconfig-watcher@.service  ← systemd unit for autoUpdate
    └── cron_config                 ← reference for the cron entry
```

## Adding / changing devices

Edit `VELO_TOOLS/devices.yml`:

```yaml
devices:
  - name: SW04
    ip: 192.168.99.7
    type: cisco
    filename: sw04.conf
```

Types: `cisco`, `pfsense`, `generic`

## Useful commands

```bash
# Check watcher is running
systemctl status netconfig-watcher@YOUR_USER

# Manually trigger a backup run
~/NetConfig/VELO_TOOLS/GetConfigs.sh

# View last cron log
tail -f ~/network-backups/cron.log

# Restart Gitea
docker compose -f /opt/netconfig-docker/compose.yml restart
```
