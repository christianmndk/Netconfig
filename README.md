# NetConfig

Selvhostet backup-system til netværksudstyr. Henter running-config fra Cisco switches og routere hver nat, committer ændringer automatisk til en lokal Gitea-instans, og holder styr på historikken i git.

Designet til at køre på Debian 12/13 eller Ubuntu 21+ — VM eller LXC container (Proxmox, ESXi, Hyper-V).

---

## Hvad kører der

| Komponent | Hvad den gør |
|---|---|
| **Gitea** | Selvhostet git-server — gemmer alle device-configs |
| **Postgres** | Database-backend til Gitea (sættes op automatisk) |
| **GetConfigs.sh** | Henter running-config fra alle enheder kl. 02:00 |
| **autoUpdate.sh** | Poller backup-mappen hvert 30. sekund og committer ændringer |

Gitea kører på port **80** (web UI) og **2222** (git SSH).

---

## Installation

### Krav
- Frisk Debian 12/13 eller Ubuntu 21+ (kun terminal)
- SSH-nøgle på maskinen (password-login deaktiveres under setup)
- Internetadgang (til apt og Docker-images)

> **LXC på Proxmox:** Containeren skal være privilegeret og have _Nesting_ aktiveret for at Docker virker.

---

### Klon og kør

```bash
git clone https://github.com/christianmndk/Netconfig.git
cd NetConfig
bash install.sh
```

Scriptet håndterer `sudo` selv — kør det bare som din normale bruger.

Du bliver bedt om at vælge et **Gitea-brugernavn og password** i starten. Så klarer det resten:

1. Opdaterer systemet og installerer afhængigheder
2. Hærder SSH (kun nøgle, ingen root-login)
3. Konfigurerer firewall (port 22, 80, 2222)
4. Installerer Docker
5. Starter Gitea og Postgres via Docker Compose
6. Opretter Gitea-admin-kontoen automatisk (ingen browser-wizard)
7. Opretter `network-backups`-repo i Gitea
8. Initialiserer lokalt git-repo og linker det til Gitea
9. Installerer systemd-watcher-service og nightly cron-job
10. Installerer MOTD

Når det er færdigt er systemet live. Ingen ekstra trin.

---

## Verificer at det virker

```bash
# Tjek at watcher-servicen kører
sudo systemctl status netconfig-watcher@DIT_BRUGERNAVN

# Test commit (vises i Gitea inden for ~30 sekunder)
touch ~/network-backups/test.conf

# Tjek at cron-job er registreret
crontab -l

# Tjek at Gitea kører
docker ps
```

---

## Tilføj eller ændr enheder

Redigér `devices.yml`:

```yaml
devices:
  - name: SW04
    ip: 192.168.99.7
    type: cisco
    filename: sw04.conf

  - name: RT03
    ip: 192.168.99.10
    type: cisco
    username: cisco        # valgfrit — default er "admin"
    filename: rt03.conf

  - name: FW01
    ip: 192.168.99.1
    type: pfsense          # henter /cf/conf/config.xml
    username: admin
    filename: fw01.xml
```

Felter:

| Felt | Påkrævet | Beskrivelse |
|---|---|---|
| `name` | Ja | Visningsnavn (bruges i logs og commit-beskeder) |
| `ip` | Ja | IP-adresse på enheden |
| `type` | Ja | Enhedstype — `cisco` (running-config) eller `pfsense` (`/cf/conf/config.xml`) |
| `username` | Nej | SSH-brugernavn — default: `admin` |
| `filename` | Ja | Filnavn config gemmes som i backup-mappen |

**pfSense:** Sørg for at SSH-nøglen er lagt ind under **System → User Manager → brugerens Authorized keys**, og at brugeren har shell-adgang. Så henter `GetConfigs.sh` config-XML'en automatisk sammen med resten. Det separate `pfsense/pfsense_backup.sh` er stadig med til manuel/standalone brug.

Ændringer træder i kraft næste gang `GetConfigs.sh` kører (kl. 02:00), eller du kører den manuelt.

---

## Tilføj en enhed

Kør `add-device.sh` — den guider dig igennem hele processen:

```bash
bash ~/NetConfig/add-device.sh
```

Den genererer automatisk en SSH-nøgle hvis der ikke er en, pinger enheden, og udskriver de IOS-kommandoer du skal paste ind i Cisco-konsollen. Enheden tilføjes kommenteret ud i `devices.yml` — fjern `#` foran linjerne når nøglen er sat op.

---

## Nyttige kommandoer

```bash
# Manuel backup-kørsel
~/NetConfig/GetConfigs.sh

# Følg backup-loggen
tail -f ~/network-backups/cron.log

# Genstart watcher (f.eks. efter ændringer i autoUpdate.sh)
sudo systemctl restart netconfig-watcher@DIT_BRUGERNAVN

# Genstart Gitea og Postgres
docker compose -f /opt/netconfig-docker/compose.yml restart

# Se Docker-container-status
docker ps

# Se Gitea-logs
docker logs gitea
```

---

## Mappestruktur

```
NetConfig/
├── install.sh              Fuld installation — ét script, ingen ekstra trin
├── add-device.sh           Tilføj en Cisco-enhed (SSH-nøgle + devices.yml)
├── GetConfigs.sh           Henter configs fra alle enheder i devices.yml
├── autoUpdate.sh           Polling-loop — committer ændringer til Gitea
├── compose.yml             Docker Compose — Gitea + Postgres
├── devices.yml             Enhedsliste — redigér denne for at tilføje/fjerne enheder
├── 99-netconfig            MOTD — vises ved SSH-login
└── pfsense/
    └── pfsense_backup.sh   Standalone pfSense-backup (ikke del af hovedflowet)
```

---

## Geninstallation

`install.sh` er idempotent — du kan køre det igen uden at det ødelægger noget:
- Eksisterende Docker-containers springes ikke over (de genstartes ikke unødigt)
- Gitea-admin-konto og repo springes over hvis de allerede eksisterer
- Git-repo'et i `~/network-backups` springes over hvis det allerede er initialiseret
- Cron-job de-duplikeres automatisk
