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

Redigér `devices.yml`. Filen er gitignored og lokal for din installation — den bliver oprettet fra `devices.yml.example` under installation, og en fremtidig `update.sh` / `git pull` rører aldrig den, så dine enheder er trygge ved opdatering.

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

  - name: RT03
    ip: 192.168.99.11
    type: cisco
    username: svc-netconfig  # dedikeret AD-konto
    auth: password            # RADIUS/AD-login — kan ikke bruge SSH-nøgle
    filename: rt03.conf

  - name: SW02
    ip: 192.168.99.4
    type: cisco
    enabled: false            # udgået/utilgængelig — springes over af GetConfigs.sh
    filename: sw02.conf
```

Felter:

| Felt | Påkrævet | Beskrivelse |
|---|---|---|
| `name` | Ja | Visningsnavn (bruges i logs og commit-beskeder) |
| `ip` | Ja | IP-adresse på enheden |
| `type` | Ja | Enhedstype — `cisco` (running-config) eller `pfsense` (`/cf/conf/config.xml`) |
| `username` | Nej | SSH-brugernavn — default: `admin` |
| `auth` | Nej | `key` (default) eller `password` — se afsnittet om `secrets.yml` nedenfor |
| `enabled` | Nej | `true` (default) eller `false` — sæt `false` for at beholde enheden i listen men springe den over ved backup |
| `filename` | Ja | Filnavn config gemmes som i backup-mappen |

**pfSense:** Sørg for at SSH-nøglen er lagt ind under **System → User Manager → brugerens Authorized keys**, og at brugeren har shell-adgang. Så henter `GetConfigs.sh` config-XML'en automatisk sammen med resten. Det separate `pfsense/pfsense_backup.sh` er stadig med til manuel/standalone brug.

Ændringer træder i kraft næste gang `GetConfigs.sh` kører (kl. 02:00), eller du kører den manuelt.

---

## Enheder med password-login (fx RADIUS/AD)

De fleste enheder bør bruge SSH-nøgle (`auth: key`, default). Men nogle enheder — typisk switches/routere hvor login går gennem RADIUS mod AD med en dedikeret service-konto — understøtter ikke pubkey-auth og skal bruge et rigtigt password.

For de enheder: sæt `auth: password` på enheden i `devices.yml`, og læg selve passwordet i en separat `secrets.yml` ved siden af — **aldrig i `devices.yml`, og aldrig i git**.

```bash
cp secrets.yml.example secrets.yml
chmod 600 secrets.yml
```

```yaml
# secrets.yml
secrets:
  RT03: det-rigtige-password
```

`secrets.yml` er tilføjet til `.gitignore` og bliver aldrig committet. `GetConfigs.sh` slår password op i den (via `sshpass`) ved kørsel og advarer i loggen hvis filen mangler rettigheder `600`, eller hvis der er en `auth: password`-enhed uden matchende entry.

Denne løsning beskytter passwordet mod at ligge i klartekst i git-repoet eller devices.yml — den beskytter ikke mod nogen med root-adgang til selve boksen, da cron-jobbet skal kunne læse passwordet uden interaktion. Brug SSH-nøgle hvor det overhovedet er muligt.

---

## Tilføj en enhed

Kør `add-device.sh` — den guider dig igennem hele processen:

```bash
bash ~/NetConfig/add-device.sh
```

Den genererer automatisk en SSH-nøgle hvis der ikke er en, pinger enheden, og udskriver de IOS-kommandoer du skal paste ind i Cisco-konsollen. Enheden tilføjes kommenteret ud i `devices.yml` — fjern `#` foran linjerne når nøglen er sat op.

---

## Opdatering

Kør `update.sh` for at hente de nyeste scripts:

```bash
bash ~/NetConfig/update.sh
```

Den henter ændringer via `git pull`, men rører aldrig `devices.yml` eller `secrets.yml` — de er gitignored lokal config, ikke en del af repoet. Scriptet opdaterer også MOTD og genstarter watcher-servicen hvis nødvendigt.

Hvis `compose.yml` eller systemd/cron-opsætningen i `install.sh` er ændret upstream, kør `sudo bash install.sh` igen (det er idempotent — se afsnittet nedenfor).

> Opgraderer du fra en ældre installation hvor `devices.yml` stadig var sporet i git? `update.sh` opdager det automatisk, untracker filen (uden at røre indholdet) og fortsætter.

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
├── update.sh               Opdater scripts sikkert uden at røre devices.yml/secrets.yml
├── add-device.sh           Tilføj en Cisco-enhed (SSH-nøgle + devices.yml)
├── GetConfigs.sh           Henter configs fra alle enheder i devices.yml
├── autoUpdate.sh           Polling-loop — committer ændringer til Gitea
├── compose.yml             Docker Compose — Gitea + Postgres
├── devices.yml.example     Template til devices.yml (kopieres automatisk af install.sh)
├── devices.yml             Enhedsliste (gitignored, lokal) — redigér denne for at tilføje/fjerne enheder
├── secrets.yml.example     Template til secrets.yml (kopiér, udfyld, chmod 600)
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
