#!/bin/bash
# PC Plus Computing - VPN Customer Onboarding Script
# Usage: ./onboard-customer.sh <customer-name> <device-name>
# Example: ./onboard-customer.sh "John Smith" "johns-laptop"
#
# This script:
# 1. Creates a WireGuard config for the customer device
# 2. Generates a QR code for mobile setup
# 3. Outputs the config file path and QR code path

set -e

CUSTOMER_NAME="${1:?Usage: $0 <customer-name> <device-name>}"
DEVICE_NAME="${2:?Usage: $0 <customer-name> <device-name>}"
API_URL="https://api.vpn.pcpluscomputing.com"
MASTER_KEY="PCplus-Netmaker-2026-Key!"
NETWORK="pcplus-vpn"
OUTPUT_DIR="/opt/netmaker/customer-configs"

mkdir -p "$OUTPUT_DIR"

SAFE_NAME=$(echo "$CUSTOMER_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
CONFIG_DIR="$OUTPUT_DIR/$SAFE_NAME"
mkdir -p "$CONFIG_DIR"

echo "================================================"
echo "  PC Plus Computing - VPN Customer Onboarding"
echo "================================================"
echo ""
echo "Customer: $CUSTOMER_NAME"
echo "Device:   $DEVICE_NAME"
echo "Network:  $NETWORK"
echo ""

# Step 1: Generate WireGuard keypair
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

# Step 2: Get next available IP from Netmaker
echo "[1/4] Registering device with Netmaker..."

# Create external client via API
RESPONSE=$(curl -s -X POST "$API_URL/api/extclients/$NETWORK" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -d "{
    \"clientid\": \"$DEVICE_NAME\",
    \"publickey\": \"$PUBLIC_KEY\",
    \"enabled\": true,
    \"dns\": \"1.1.1.1,8.8.8.8\"
  }" 2>&1)

if echo "$RESPONSE" | grep -q "error\|Error"; then
    echo "Error creating client: $RESPONSE"
    echo ""
    echo "If external clients API is not available, use the Netmaker dashboard:"
    echo "  1. Go to https://dashboard.vpn.pcpluscomputing.com"
    echo "  2. Login as admin"
    echo "  3. Navigate to Network > pcplus-vpn > Remote Access"
    echo "  4. Create a new client for: $CUSTOMER_NAME ($DEVICE_NAME)"
    echo "  5. Download the WireGuard config file"
    echo ""
    echo "The config file can then be shared with the customer."
    exit 0
fi

echo "[2/4] Fetching client configuration..."

# Get the client config
CONFIG=$(curl -s "$API_URL/api/extclients/$NETWORK/$DEVICE_NAME" \
  -H "Authorization: Bearer $MASTER_KEY" 2>&1)

CLIENT_IP=$(echo "$CONFIG" | jq -r '.address // empty')
if [ -z "$CLIENT_IP" ]; then
    echo "Note: Could not auto-fetch IP. Check Netmaker dashboard for the config."
    CLIENT_IP="<check-dashboard>"
fi

# Step 3: Generate WireGuard config file
echo "[3/4] Generating config file..."

CONFIG_FILE="$CONFIG_DIR/${DEVICE_NAME}.conf"
cat > "$CONFIG_FILE" << WGCONF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $CLIENT_IP/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = <server-public-key>
AllowedIPs = 10.100.0.0/16
Endpoint = 65.7.31.125:51821
PersistentKeepalive = 20
WGCONF

echo "  Config saved: $CONFIG_FILE"

# Step 4: Generate QR code
echo "[4/4] Generating QR code..."

if command -v qrencode &>/dev/null; then
    QR_FILE="$CONFIG_DIR/${DEVICE_NAME}-qr.png"
    qrencode -t PNG -o "$QR_FILE" -r "$CONFIG_FILE" -s 6
    echo "  QR code saved: $QR_FILE"
else
    echo "  qrencode not installed. Install with: apt install qrencode"
    echo "  Then run: qrencode -t PNG -o $CONFIG_DIR/${DEVICE_NAME}-qr.png -r $CONFIG_FILE"
fi

echo ""
echo "================================================"
echo "  Onboarding Complete!"
echo "================================================"
echo ""
echo "Files created:"
echo "  Config: $CONFIG_FILE"
[ -f "$CONFIG_DIR/${DEVICE_NAME}-qr.png" ] && echo "  QR Code: $CONFIG_DIR/${DEVICE_NAME}-qr.png"
echo ""
echo "Next steps:"
echo "  1. Download the config from Netmaker dashboard (more reliable)"
echo "     https://dashboard.vpn.pcpluscomputing.com"
echo "  2. Send config file + QR code to customer"
echo "  3. Direct customer to https://vpn.pcpluscomputing.com for setup guide"
echo ""
echo "Customer portal: https://vpn.pcpluscomputing.com"
echo "Support portal:  https://support.pcpluscomputing.com"
echo ""
