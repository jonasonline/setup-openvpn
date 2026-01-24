#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

VPN_PORT="443"

VPN_NET="10.8.0.0"
VPN_MASK="255.255.255.0"
VPN_CIDR="10.8.0.0/24"

DNS1="9.9.9.9"
DNS2="149.112.112.112"

CLIENTS=("client1" "client2" "client3")

REQ_COUNTRY="SE"
REQ_PROVINCE="VastraGotaland"
REQ_CITY="Gothenburg"
REQ_ORG="Example"
REQ_EMAIL="admin@example.com"
REQ_OU="VPN"

IP_CHECK_URL="https://api.ipify.org"

log(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERROR] $*" >&2; }

if [[ "$(id -u)" -ne 0 ]]; then
  err "Run as root: sudo ./setup_openvpn.sh"
  exit 1
fi

VPN_USER="${SUDO_USER:-root}"
VPN_HOME="$(getent passwd "$VPN_USER" | cut -d: -f6 || true)"
if [[ -z "${VPN_HOME}" ]]; then VPN_HOME="/root"; fi

EASYRSA_DIR="${VPN_HOME}/easy-rsa"
CLIENT_DIR="${VPN_HOME}/client-configs"

SERVER_DIR="/etc/openvpn/server"
SERVER_CONF_UDP="${SERVER_DIR}/server.conf"
SERVER_CONF_TCP="${SERVER_DIR}/server-tcp.conf"
TLSV2_SERVER_KEY="${SERVER_DIR}/tls-crypt-v2-server.key"

EXTERNAL_IP="$(curl -fsS "${IP_CHECK_URL}" 2>/dev/null || true)"
WAN_IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}' || true)"
if [[ -z "${WAN_IFACE}" ]]; then
  err "Could not detect WAN interface."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y openvpn easy-rsa curl ufw

mkdir -p "${EASYRSA_DIR}"
if [[ ! -f "${EASYRSA_DIR}/easyrsa" ]]; then
  cp -a /usr/share/easy-rsa/* "${EASYRSA_DIR}/"
fi
chown -R "${VPN_USER}:${VPN_USER}" "${EASYRSA_DIR}"
chmod 700 "${EASYRSA_DIR}"

cat > "${EASYRSA_DIR}/vars" <<EOF
set_var EASYRSA_REQ_COUNTRY "${REQ_COUNTRY}"
set_var EASYRSA_REQ_PROVINCE "${REQ_PROVINCE}"
set_var EASYRSA_REQ_CITY "${REQ_CITY}"
set_var EASYRSA_REQ_ORG "${REQ_ORG}"
set_var EASYRSA_REQ_EMAIL "${REQ_EMAIL}"
set_var EASYRSA_REQ_OU "${REQ_OU}"
set_var EASYRSA_ALGO ec
set_var EASYRSA_DIGEST sha512
EOF
chown "${VPN_USER}:${VPN_USER}" "${EASYRSA_DIR}/vars"

sudo -u "${VPN_USER}" /usr/bin/env bash -c "
set -euo pipefail
cd '${EASYRSA_DIR}'

if [[ ! -d pki ]]; then
  ./easyrsa init-pki
fi

if [[ ! -f pki/ca.crt ]]; then
  ./easyrsa --batch build-ca nopass
fi

if [[ ! -f pki/issued/server.crt || ! -f pki/private/server.key ]]; then
  ./easyrsa --batch gen-req server nopass
  ./easyrsa --batch sign-req server server
fi

for c in ${CLIENTS[*]}; do
  if [[ ! -f pki/issued/\$c.crt || ! -f pki/private/\$c.key ]]; then
    ./easyrsa --batch gen-req \"\$c\" nopass
    ./easyrsa --batch sign-req client \"\$c\"
  fi
done
"

install -d -m 750 "${SERVER_DIR}"
install -m 600 "${EASYRSA_DIR}/pki/private/server.key" "${SERVER_DIR}/server.key"
install -m 644 "${EASYRSA_DIR}/pki/issued/server.crt" "${SERVER_DIR}/server.crt"
install -m 644 "${EASYRSA_DIR}/pki/ca.crt" "${SERVER_DIR}/ca.crt"

if [[ ! -f "${TLSV2_SERVER_KEY}" ]]; then
  openvpn --genkey tls-crypt-v2-server "${TLSV2_SERVER_KEY}"
fi
chmod 600 "${TLSV2_SERVER_KEY}"

cat > "${SERVER_CONF_UDP}" <<EOF
port ${VPN_PORT}
proto udp
dev tun
topology subnet

ca ca.crt
cert server.crt
key server.key
dh none

server ${VPN_NET} ${VPN_MASK}
ifconfig-pool-persist /var/log/openvpn/ipp-udp.txt

client-to-client

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${DNS1}"
push "dhcp-option DNS ${DNS2}"

keepalive 10 120
explicit-exit-notify 1

tls-crypt-v2 tls-crypt-v2-server.key
tls-version-min 1.2

data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM
auth SHA256

user nobody
group nogroup
persist-key
persist-tun
verb 3

status /var/log/openvpn/openvpn-status-udp.log
EOF

cat > "${SERVER_CONF_TCP}" <<EOF
port ${VPN_PORT}
proto tcp-server
dev tun
topology subnet

ca ca.crt
cert server.crt
key server.key
dh none

server ${VPN_NET} ${VPN_MASK}
ifconfig-pool-persist /var/log/openvpn/ipp-tcp.txt

client-to-client

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${DNS1}"
push "dhcp-option DNS ${DNS2}"

keepalive 10 120
explicit-exit-notify 0

tls-crypt-v2 tls-crypt-v2-server.key
tls-version-min 1.2

data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM
auth SHA256

user nobody
group nogroup
persist-key
persist-tun
verb 3

status /var/log/openvpn/openvpn-status-tcp.log
EOF

echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
sysctl --system >/dev/null 2>&1 || true

UFW_BEFORE="/etc/ufw/before.rules"
if ! grep -q "^# START OPENVPN RULES" "${UFW_BEFORE}"; then
  sed -i "/^*filter/i # START OPENVPN RULES\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s ${VPN_CIDR} -o ${WAN_IFACE} -j MASQUERADE\nCOMMIT\n# END OPENVPN RULES\n" "${UFW_BEFORE}"
else
  sed -i "/^# START OPENVPN RULES/,/^# END OPENVPN RULES/ s|^-A POSTROUTING -s .* -o .* -j MASQUERADE$|-A POSTROUTING -s ${VPN_CIDR} -o ${WAN_IFACE} -j MASQUERADE|" "${UFW_BEFORE}" || true
fi

sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

ufw allow "${VPN_PORT}/udp" >/dev/null 2>&1 || true
ufw allow "${VPN_PORT}/tcp" >/dev/null 2>&1 || true
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw route allow in on tun0 out on "${WAN_IFACE}" >/dev/null 2>&1 || true
ufw route allow in on tun0 out on tun0 >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

systemctl enable openvpn-server@server.service >/dev/null 2>&1 || true
systemctl enable openvpn-server@server-tcp.service >/dev/null 2>&1 || true
systemctl restart openvpn-server@server.service >/dev/null 2>&1 || true
systemctl restart openvpn-server@server-tcp.service >/dev/null 2>&1 || true

mkdir -p "${CLIENT_DIR}/keys" "${CLIENT_DIR}/files"
chmod 700 "${CLIENT_DIR}" "${CLIENT_DIR}/keys"

install -m 644 "${EASYRSA_DIR}/pki/ca.crt" "${CLIENT_DIR}/keys/ca.crt"

for c in "${CLIENTS[@]}"; do
  install -m 600 "${EASYRSA_DIR}/pki/private/${c}.key" "${CLIENT_DIR}/keys/${c}.key"
  install -m 644 "${EASYRSA_DIR}/pki/issued/${c}.crt" "${CLIENT_DIR}/keys/${c}.crt"

  if [[ ! -f "${CLIENT_DIR}/keys/${c}.tlsv2.key" ]]; then
    openvpn --tls-crypt-v2 "${TLSV2_SERVER_KEY}" --genkey tls-crypt-v2-client "${CLIENT_DIR}/keys/${c}.tlsv2.key"
  fi
  chmod 600 "${CLIENT_DIR}/keys/${c}.tlsv2.key"
done

cat > "${CLIENT_DIR}/base.conf" <<EOF
client
dev tun

remote ${EXTERNAL_IP:-0.0.0.0} ${VPN_PORT} udp
remote ${EXTERNAL_IP:-0.0.0.0} ${VPN_PORT} tcp-client

resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth-nocache

data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM
auth SHA256

verb 3
EOF

for c in "${CLIENTS[@]}"; do
  ovpn="${CLIENT_DIR}/files/${c}.ovpn"
  : > "${ovpn}"
  cat "${CLIENT_DIR}/base.conf" >> "${ovpn}"
  printf "%s\n" "<ca>" >> "${ovpn}"
  cat "${CLIENT_DIR}/keys/ca.crt" >> "${ovpn}"
  printf "%s\n" "</ca>" >> "${ovpn}"
  printf "%s\n" "<cert>" >> "${ovpn}"
  cat "${CLIENT_DIR}/keys/${c}.crt" >> "${ovpn}"
  printf "%s\n" "</cert>" >> "${ovpn}"
  printf "%s\n" "<key>" >> "${ovpn}"
  cat "${CLIENT_DIR}/keys/${c}.key" >> "${ovpn}"
  printf "%s\n" "</key>" >> "${ovpn}"
  printf "%s\n" "<tls-crypt-v2>" >> "${ovpn}"
  cat "${CLIENT_DIR}/keys/${c}.tlsv2.key" >> "${ovpn}"
  printf "%s\n" "</tls-crypt-v2>" >> "${ovpn}"
done

chown -R "${VPN_USER}:${VPN_USER}" "${CLIENT_DIR}" || true

log "DONE"
echo "WAN interface: ${WAN_IFACE}"
echo "Server: ${EXTERNAL_IP:-unknown}:${VPN_PORT} (UDP primary, TCP fallback)"
for c in "${CLIENTS[@]}"; do
  echo "Client: ${CLIENT_DIR}/files/${c}.ovpn"
done

if [[ -z "${EXTERNAL_IP}" ]]; then
  warn "External IP could not be detected. Update the 'remote' lines in client configs."
fi
