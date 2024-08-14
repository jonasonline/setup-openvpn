#!/bin/bash

# Update and install necessary packages
apt-get update -y
apt-get install -y openvpn easy-rsa curl

# Fetch the external IP address of the server
EXTERNAL_IP=$(curl -s ifconfig.me)

# Set up the Easy-RSA environment in the user's home directory
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# Customize the vars file
cat << EOF > vars
export EASYRSA_REQ_COUNTRY="US"
export EASYRSA_REQ_PROVINCE="CA"
export EASYRSA_REQ_CITY="San Francisco"
export EASYRSA_REQ_ORG="MyCompany"
export EASYRSA_REQ_EMAIL="admin@example.com"
export EASYRSA_REQ_OU="MyOrganizationalUnit"
EOF

# Build the certificate authority
source vars
./easyrsa init-pki
./easyrsa build-ca nopass

# Generate a server certificate and key
./easyrsa gen-req server nopass
./easyrsa sign-req server server

# Generate Diffie-Hellman key exchange
./easyrsa gen-dh

# Generate a client certificate and key
./easyrsa gen-req client1 nopass
./easyrsa sign-req client client1

# Generate a shared HMAC key for extra security
openvpn --genkey --secret ta.key

# Copy certificates and keys to the OpenVPN directory
sudo cp pki/ca.crt pki/private/server.key pki/issued/server.crt pki/dh.pem ta.key /etc/openvpn/

# Create the OpenVPN server configuration with port 1194
cat << EOF > /etc/openvpn/server.conf
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA256
tls-auth ta.key 0
topology subnet
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
keepalive 10 120
cipher AES-256-GCM
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
verb 3
EOF

# Enable packet forwarding
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

# Set up firewall rules for port 1194
sudo ufw allow 1194/udp
sudo ufw allow OpenSSH
sudo ufw disable
sudo ufw enable

# Start and enable OpenVPN
sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server

# Client configuration file generation
mkdir -p ~/client-configs/keys
chmod -R 700 ~/client-configs
cp ~/openvpn-ca/pki/private/client1.key ~/client-configs/keys/
cp ~/openvpn-ca/pki/issued/client1.crt ~/client-configs/keys/
cp ~/openvpn-ca/pki/ca.crt ~/client-configs/keys/
cp /etc/openvpn/ta.key ~/client-configs/keys/

# Create base client config using external IP and port 1194
cat << EOF > ~/client-configs/base.conf
client
dev tun
proto udp
remote $EXTERNAL_IP 1194
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
ca ca.crt
cert client1.crt
key client1.key
tls-auth ta.key 1
cipher AES-256-GCM
verb 3
EOF

# Create a script to package the client configuration
cat << EOF > ~/client-configs/make_config.sh
#!/bin/bash

KEY_DIR=~/client-configs/keys
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/client-configs/base.conf

mkdir -p \${OUTPUT_DIR}

cat \${BASE_CONFIG} \\
    <(echo -e '<ca>') \\
    \${KEY_DIR}/ca.crt \\
    <(echo -e '</ca>\n<cert>') \\
    \${KEY_DIR}/client1.crt \\
    <(echo -e '</cert>\n<key>') \\
    \${KEY_DIR}/client1.key \\
    <(echo -e '</key>\n<tls-auth>') \\
    \${KEY_DIR}/ta.key \\
    <(echo -e '</tls-auth>') \\
    > \${OUTPUT_DIR}/client1.ovpn
EOF

chmod 700 ~/client-configs/make_config.sh

echo "OpenVPN server setup is complete. Use ~/client-configs/make_config.sh to generate client configuration."
