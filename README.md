# NetConfig

Self-hosted network configuration backup and automation server.

Runs on a fresh Debian/Ubuntu VM. Backs up running configs from all network
devices every night, auto-commits changes to a local Gitea instance, and
watches for file changes in real time.

## What's running

| Component | What it does |
|---|---|
| **Gitea** | Self-hosted git server — stores all device configs |
| **Postgres** | Database backend for Gitea (no manual setup needed) |
| **GetConfigs.sh** | Pulls running configs from all devices nightly at 02:00 |
| **autoUpdate.sh** | Watches backup folder, auto-commits any changes to Gitea |

---

## Setup — fresh VM

### Prerequisites
- Fresh Debian or Ubuntu install (terminal only)
- You are logged in as your normal user (e.g. `feet`)
- SSH key already on the VM

---

### Step 1 — Run the main setup script

Clone this repo and run `setup.sh` as root:

```bash
git clone https://github.com/YOU/NetConfig.git
cd NetConfig
sudo ./setup.sh YOUR_USERNAME
```

Replace `YOUR_USERNAME` with your actual login name (e.g. `feet`).

This will:
- Update the system and install dependencies
- Harden SSH (key-only, no root login)
- Configure the firewall (ports 22, 3000, 2222)
- Install Docker
- Start Gitea and Postgres via Docker Compose
- Set up the backup directory
- Install the systemd watcher service and nightly cron job

When it finishes it will print the IP and tell you to continue to Step 2.

---

### Step 2 — Configure Gitea

Open a browser and go to:

```
http://YOUR_VM_IP:3000
```

Fill in the first-run wizard with these settings:

| Field | Value |
|---|---|
| Database type | PostgreSQL |
| Host | `postgres:5432` |
| Database name | `gitea` |
| Username | `gitea` |
| Password | `gitea` |

Scroll down to **Administrator account** and create your admin user.
Use the same username as your Linux user (e.g. `feet`) to keep things simple.

Click **Install Gitea** and wait for it to finish.

---

### Step 3 — Run the Gitea setup script

Back on the VM, run the second script **as your normal user — not sudo**:

```bash
bash ~/NetConfig/setup-gitea.sh
```

It will ask for your Gitea username and password, then:
- Create the `network-backups` repo in Gitea automatically
- Initialise the local backup directory as a git repo
- Store credentials so pushes never prompt
- Start the autoUpdate watcher service

When it finishes the system is fully live.

---

## Verifying everything works

Check the watcher is running:
```bash
sudo systemctl status netconfig-watcher@YOUR_USERNAME
```

Trigger a test commit:
```bash
touch ~/network-backups/test.conf
# Wait a few seconds, then check http://YOUR_VM_IP:3000
```

Check the nightly cron is registered:
```bash
crontab -l
```

---

## Adding or changing devices

Edit `devices.yml`:

```yaml
devices:
  - name: SW04
    ip: 192.168.99.7
    type: cisco
    filename: sw04.conf
```

Supported types: `cisco`, `pfsense`, `generic`

---

## Useful commands

```bash
# Check watcher status
sudo systemctl status netconfig-watcher@YOUR_USERNAME

# Restart watcher after config changes
sudo systemctl restart netconfig-watcher@YOUR_USERNAME

# Manually trigger a backup run
~/NetConfig/GetConfigs.sh

# View last cron log
tail -f ~/network-backups/cron.log

# Restart Gitea and Postgres
docker compose -f /opt/netconfig-docker/compose.yml restart
```

---

## Known limitations / future improvements

- Gitea admin user still needs to be created manually via the web UI
- `setup-gitea.sh` will exit with an error if accidentally run with `sudo` — always run it as your normal user