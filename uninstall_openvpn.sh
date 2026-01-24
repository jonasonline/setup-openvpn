#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -euo pipefail

log(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*" >&2; }

if [[ "$(id -u)" -ne 0 ]]; then
  echo "[ERROR] Run as root: sudo ./uninstall_openvpn.sh" >&2
  exit 1
fi

VPN_PORT="443"

# Detect original user home (where setup created easy-rsa and client-configs)
VPN_USER="${SUDO_USER:-root}"
VPN_HOME="$(getent passwd "$VPN_USER" | cut -d: -f6 || true)"
if [[ -z "${VPN_HOME}" ]]; then VPN_HOME="/root"; fi

EASYRSA_DIR="${VPN_HOME}/easy-rsa"
CLIENT_DIR="${VPN_HOME}/client-configs"

SERVER_DIR="/etc/openvpn/server"
SYSCTL_DROPIN="/etc/sysctl.d/99-openvpn.conf"
UFW_BEFORE="/etc/ufw/before.rules"

log "Stopping and disabling OpenVPN services..."
systemctl stop openvpn-server@server.service 2>/dev/null || true
systemctl stop openvpn-server@server-tcp.service 2>/dev/null || true
systemctl disable openvpn-server@server.service 2>/dev/null || true
systemctl disable openvpn-server@server-tcp.service 2>/dev/null || true

log "Removing OpenVPN server configuration..."
rm -rf "${SERVER_DIR}" || true

log "Removing local PKI and client configs for user home..."
rm -rf "${EASYRSA_DIR}" "${CLIENT_DIR}" || true

# Optional: if root also has these (common if script was run directly as root)
if [[ "${VPN_HOME}" != "/root" ]]; then
  rm -rf "/root/easy-rsa" "/root/client-configs" 2>/dev/null || true
fi

log "Removing sysctl configuration for IP forwarding..."
rm -f "${SYSCTL_DROPIN}" || true
sysctl --system >/dev/null 2>&1 || true

log "Removing OpenVPN NAT block from UFW (if present)..."
if [[ -f "${UFW_BEFORE}" ]]; then
  sed -i '/^# START OPENVPN RULES$/,/^# END OPENVPN RULES$/d' "${UFW_BEFORE}" || true
fi

log "Restoring DEFAULT_FORWARD_POLICY to DROP (if modified)..."
sed -i 's/^DEFAULT_FORWARD_POLICY="ACCEPT"/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw || true

log "Removing UFW rules for OpenVPN ports (if present)..."
ufw delete allow "${VPN_PORT}/udp" >/dev/null 2>&1 || true
ufw delete allow "${VPN_PORT}/tcp" >/dev/null 2>&1 || true

# Setup script added OpenSSH; only remove it if it exists as a simple allow rule
ufw delete allow OpenSSH >/dev/null 2>&1 || true

log "Reloading UFW..."
ufw reload >/dev/null 2>&1 || true

log "Optionally removing OpenVPN logs..."
rm -rf /var/log/openvpn 2>/dev/null || true

log "Removing packages..."
export DEBIAN_FRONTEND=noninteractive
apt remove --purge -y openvpn easy-rsa || true
apt autoremove -y || true
apt autoclean || true

log "DONE: OpenVPN and associated configuration have been removed."
