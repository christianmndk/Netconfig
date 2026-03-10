#!/bin/bash
# cisco-ssh-key.sh — Formats your SSH public key for Cisco IOS
#
# Cisco IOS requires the public key to be entered line by line,
# max ~70 characters per line, wrapped in a specific command block.
#
# Usage: bash cisco-ssh-key.sh [USERNAME] [HOSTNAME/IP]
# Example: bash cisco-ssh-key.sh admin SW01

TARGET_USER="${1:-admin}"
TARGET_HOST="${2:-DEVICE}"
KEY_FILE="$HOME/.ssh/id_rsa.pub"

# Check for key file
if [[ ! -f "$KEY_FILE" ]]; then
    # Try ed25519 as fallback
    KEY_FILE="$HOME/.ssh/id_ed25519.pub"
    if [[ ! -f "$KEY_FILE" ]]; then
        echo "ERROR: No public key found at ~/.ssh/id_rsa.pub or ~/.ssh/id_ed25519.pub"
        echo "Generate one with: ssh-keygen -t rsa -b 2048"
        echo "(Note: Cisco IOS works best with RSA 2048 — ed25519 is not supported on older IOS)"
        exit 1
    fi
fi

# Extract just the base64 key body (strip the 'ssh-rsa ' prefix and comment)
KEY_BODY=$(awk '{print $2}' "$KEY_FILE")
KEY_TYPE=$(awk '{print $1}' "$KEY_FILE")

if [[ "$KEY_TYPE" != "ssh-rsa" ]]; then
    echo "WARNING: Key type is '$KEY_TYPE' — older Cisco IOS only supports ssh-rsa."
    echo "         If the device rejects it, generate an RSA key with:"
    echo "         ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa"
    echo ""
fi

# Split key body into 70-char chunks
WRAPPED=$(echo "$KEY_BODY" | fold -w 70)
LINE_COUNT=$(echo "$WRAPPED" | wc -l)
KEY_BITS=$(echo "$KEY_BODY" | base64 -d 2>/dev/null | wc -c)
KEY_BITS=$(( KEY_BITS * 8 / 128 * 128 ))  # rough bit estimate

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║         Cisco IOS — SSH Public Key Import Commands                  ║"
echo "║  Device: $TARGET_HOST  |  User: $TARGET_USER"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Paste the following into the Cisco CLI (in enable + config mode):"
echo ""
echo "─────────────────────────────────────────────────────────────────────"
echo "ip ssh pubkey-chain"
echo "  username $TARGET_USER"
echo "    key-string"

echo "$WRAPPED" | while IFS= read -r chunk; do
    echo "      $chunk"
done

echo "    exit"
echo "  exit"
echo "exit"
echo "─────────────────────────────────────────────────────────────────────"
echo ""
echo "Key file : $KEY_FILE"
echo "Key type : $KEY_TYPE"
echo "Lines    : $LINE_COUNT (70 chars each)"
echo ""
echo "After pasting, verify with:"
echo "  show ip ssh"
echo "  show running-config | section pubkey"
echo ""
