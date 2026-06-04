#!/bin/bash
# add-device.sh — Tilføj en Cisco-enhed til NetConfig
#
# Genererer færdige IOS-kommandoer til SSH-nøgle-opsætning,
# og tilføjer enheden kommenteret ud i devices.yml.
#
# Usage: bash add-device.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES_FILE="$SCRIPT_DIR/devices.yml"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[2;37m'; N='\033[0m'

# ── Find eller generer SSH-nøgle ──────────────────────────────────────────────
KEY_FILE=""
for candidate in ~/.ssh/id_rsa.pub ~/.ssh/id_ed25519.pub ~/.ssh/id_ecdsa.pub; do
    [[ -f "$candidate" ]] && KEY_FILE="$candidate" && break
done

if [[ -z "$KEY_FILE" ]]; then
    echo -e "  ${Y}Ingen SSH-nøgle fundet — genererer RSA 2048 (ingen passphrase)...${N}"
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N "" -q
    KEY_FILE="$HOME/.ssh/id_rsa.pub"
    echo -e "  ${G}✓${N} Nøgle genereret: $KEY_FILE"
fi

KEY_TYPE=$(awk '{print $1}' "$KEY_FILE")
KEY_BODY=$(awk '{print $2}' "$KEY_FILE")

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${W}  ╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${W}  ║           NetConfig — Tilføj Cisco-enhed                 ║${N}"
echo -e "${W}  ╚══════════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${D}SSH-nøgle: $KEY_FILE ($KEY_TYPE)${N}"

if [[ "$KEY_TYPE" != "ssh-rsa" ]]; then
    echo -e "  ${Y}Advarsel: Ældre Cisco IOS understøtter kun ssh-rsa.${N}"
    echo -e "  ${Y}Hvis enheden afviser nøglen: ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa${N}"
fi
echo ""

# ── Enhedsoplysninger ─────────────────────────────────────────────────────────
echo -e "${C}  Enhedsoplysninger${N}"
read -p "  Navn        (f.eks. SW04):       " DEVICE_NAME
read -p "  IP-adresse:                      " DEVICE_IP
read -p "  Brugernavn  [admin]:             " DEVICE_USER
DEVICE_USER="${DEVICE_USER:-admin}"

DEFAULT_FILE="${DEVICE_NAME,,}.conf"
read -p "  Filnavn     [$DEFAULT_FILE]: " DEVICE_FILE
DEVICE_FILE="${DEVICE_FILE:-$DEFAULT_FILE}"
echo ""

# ── Ping-tjek ─────────────────────────────────────────────────────────────────
echo -ne "  Pinger $DEVICE_IP... "
if ping -c 3 -W 1 "$DEVICE_IP" > /dev/null 2>&1; then
    echo -e "${G}udstyr svarer :)${N}"
else
    echo -e "${Y}svarer ikke — fortsætter alligevel${N}"
fi
echo ""

# ── Generer Cisco IOS-kommandoer ──────────────────────────────────────────────
WRAPPED=$(echo "$KEY_BODY" | fold -w 70)

echo -e "${W}  Paste disse kommandoer ind i Cisco-konsollen:${N}"
echo ""
echo    "  ─────────────────────────────────────────────────────────"
echo    "  conf t"
echo    "  ip ssh version 2"
echo    "  ip ssh pubkey-chain"
echo    "   username $DEVICE_USER"
echo    "    key-string"
while IFS= read -r chunk; do
    echo "     $chunk"
done <<< "$WRAPPED"
echo    "    exit"
echo    "   exit"
echo    "  exit"
echo    "  wr"
echo    "  ─────────────────────────────────────────────────────────"
echo ""
echo -e "  ${D}Verificer bagefter med: show run | section pubkey${N}"
echo ""

# ── Skriv til devices.yml (kommenteret ud) ────────────────────────────────────
DATE=$(date +'%Y-%m-%d')

cat >> "$DEVICES_FILE" <<EOF

  # $DEVICE_NAME — tilføjet $DATE (fjern # på linjerne nedenfor når SSH-nøglen er pastet ind)
  # - name: $DEVICE_NAME
  #   ip: $DEVICE_IP
  #   type: cisco
  #   username: $DEVICE_USER
  #   filename: $DEVICE_FILE
EOF

echo -e "  ${G}✓${N} $DEVICE_NAME tilføjet i devices.yml (kommenteret ud)"
echo -e "  ${D}Fil: $DEVICES_FILE${N}"
echo -e "  ${D}Fjern # foran de 5 linjer når du har pastet nøglen ind.${N}"
echo ""
