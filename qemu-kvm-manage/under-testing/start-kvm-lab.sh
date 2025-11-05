#!/bin/bash
# Purpose: Bring up virbr0 and dependent lab services cleanly

set -euo pipefail

# ====== CONFIGURATION ======
DUMMY_IF="dummy-vnet"
BRIDGE_IF="virbr0"
LAB_SERVICES=("kea-dhcp4" "nfs-server" "nginx" "tftp.socket")
DNS_ADDR="${dnsbinder_server_ipv4_address}"
DNS_DOMAIN="${dnsbinder_domain}"
LAB_CIDR="${dnsbinder_cidr_prefix}"

# ====== COLOR OUTPUT ======
green() { echo -e "\e[32m$1\e[0m"; }
yellow() { echo -e "\e[33m$1\e[0m"; }
red() { echo -e "\e[31m$1\e[0m"; }

# ====== CLEANUP ON EXIT ======
trap 'red "⚠️  Script interrupted or failed!"' ERR SIGINT

# ====== STEP 1: Restart libvirtd ======
yellow "🔁 Restarting libvirtd..."
sudo systemctl restart libvirtd

# ====== STEP 2: Wait for virbr0 ======
yellow "⏳ Waiting for $BRIDGE_IF to be created..."
until ip link show "$BRIDGE_IF" &>/dev/null; do
    printf "."
    sleep 1
done
echo
green "✅ $BRIDGE_IF detected!"

# ====== STEP 3: Create dummy link if missing ======
if ! ip link show "$DUMMY_IF" &>/dev/null; then
    yellow "🧱 Creating dummy interface $DUMMY_IF to keep $BRIDGE_IF always up..."
    sudo ip link add name "$DUMMY_IF" type dummy
    sudo ip link set "$DUMMY_IF" master "$BRIDGE_IF"
    sudo ip link set "$DUMMY_IF" up
else
    yellow "ℹ️ Dummy interface $DUMMY_IF already exists."
fi

# ====== STEP 4: Wait for virbr0 to come up ======
yellow "⏳ Waiting for $BRIDGE_IF to come UP..."
while [[ "$(cat /sys/class/net/$BRIDGE_IF/operstate 2>/dev/null)" != "up" ]]; do
    printf "."
    sleep 1
done
echo
green "✅ $BRIDGE_IF is UP and running!"

yellow "🌐 Assign IP "$DNS_ADDR" on $BRIDGE_IF for lab infra services..."
sudo ip addr add "${DNS_ADDR}/${LAB_CIDR}" dev "$BRIDGE_IF"

# ====== STEP 5: Configure DNS for virbr0 ======
yellow "🌐 Configuring DNS for $BRIDGE_IF..."
sudo systemctl restart named
sudo resolvectl dns "$BRIDGE_IF" "$DNS_ADDR"
sudo resolvectl domain "$BRIDGE_IF" "$DNS_DOMAIN"

# ====== STEP 6: Restart dependent services ======
yellow "🔁 Restarting dependent lab services..."
for svc in "${LAB_SERVICES[@]}"; do
    sudo systemctl restart "$svc"
done
green "✅ All lab services restarted."

# ====== STEP 7: Show service status ======
yellow "📋 Checking service statuses..."
sudo systemctl status libvirtd named "${LAB_SERVICES[@]}" --no-pager -l || true

green "🎉 Setup complete! virbr0 is up and all services are live."
