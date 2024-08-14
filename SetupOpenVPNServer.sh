#!/bin/bash

# Update package list and install OpenVPN and Easy-RSA
sudo apt-get update
sudo apt-get install openvpn easy-rsa -y

# Create the .rnd file to avoid RNG errors and place it in the home directory
openssl rand -writerand ~/.rnd

# Create a directory for Easy-RSA and move into it
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# Initialize the Public Key Infrastructure (PKI)
./easyrsa init-pki

# Build the Certificate Authority (CA)
./easyrsa build-ca nopass

# Generate the server certificate and key
./easyrsa gen-req server nopass
./easyrsa sign-req server server

# Generate Diffie-Hellman parameters
./easyrsa gen-dh

# Generate a HMAC signature key for TLS-auth
openvpn --genkey --secret ~/openvpn-ca/pki/ta.key

# Generate client certificate and key
./easyrsa gen-req client1 nopass
./easyrsa sign-req client client1

# Copy necessary files to the OpenVPN configuration directory
sudo cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/ta.key pki/dh.pem /etc/openvpn

# Create and configure the OpenVPN server configuration file
sudo bash -c 'cat > /etc/openvpn/server.conf << EOF
port 443
proto tcp
dev tun
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh.pem
tls-auth /etc/openvpn/ta.key 0
cipher AES-128-CBC
auth SHA256
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /etc/openvpn/ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 208.67.222.222"
push "dhcp-option DNS 208.67.220.220"
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup
log-append /var/log/openvpn.log
status /var/log/openvpn-status.log
verb 3
duplicate-cn
EOF'

# Enable IP forwarding
sudo sed -i -e 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sudo sysctl -p

# UFW configuration for OpenVPN
cd /tmp
DEFAULT_NIC=$(ip route | grep default | grep -oP "(?<=dev )[^ ]+")
echo "
#

# START OPENVPN RULES
# NAT table rules
*nat
:POSTROUTING ACCEPT [0:0] 
# Allow traffic from OpenVPN client to $DEFAULT_NIC
-A POSTROUTING -s 10.8.0.0/8 -o $DEFAULT_NIC -j MASQUERADE
COMMIT
# END OPENVPN RULES

" > UFWSettingsForOpenVPN
sudo sed -i -E '/#   ufw-before-forward/r UFWSettingsForOpenVPN' /etc/ufw/before.rules
rm UFWSettingsForOpenVPN
sudo sed -i -e 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
sudo ufw allow 443/tcp
sudo ufw allow OpenSSH
sudo ufw disable
sudo ufw --force enable

# Start and enable the OpenVPN server
sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server

# Create client configuration directory
mkdir -p ~/client-configs/files
chmod 700 ~/client-configs/files
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/client-configs/base.conf

# Customize the client configuration
IP=$(curl -s https://api.ipify.org)
sed -i -e "s/remote my-server-1 1194/remote $IP 443/g" ~/client-configs/base.conf
sed -i -e 's/;proto tcp/proto tcp/g' ~/client-configs/base.conf
sed -i -e 's/proto udp/;proto udp/g' ~/client-configs/base.conf
sed -i -e 's/;user nobody/user nobody/g' ~/client-configs/base.conf
sed -i -e 's/;group nogroup/group nogroup/g' ~/client-configs/base.conf
sed -i -e 's/ca ca.crt/#ca ca.crt/g' ~/client-configs/base.conf
sed -i -e 's/cert client.crt/#cert client.crt/g' ~/client-configs/base.conf
sed -i -e 's/key client.key/#key client.key/g' ~/client-configs/base.conf
sed -i -e 's/;cipher x/cipher AES-128-CBC/g' ~/client-configs/base.conf
sed -i '/cipher AES-128-CBC/a auth SHA256' ~/client-configs/base.conf
sed -i '/auth SHA256/a key-direction 1' ~/client-configs/base.conf
echo "" >> ~/client-configs/base.conf
echo "# script-security 2" >> ~/client-configs/base.conf
echo "# up /etc/openvpn/update-resolv-conf" >> ~/client-configs/base.conf
echo "# down /etc/openvpn/update-resolv-conf" >> ~/client-configs/base.conf

# Create make_config.sh script to generate .ovpn files
cat <<'EOF' > ~/client-configs/make_config.sh
#!/bin/bash

# First argument: Client identifier
KEY_DIR=~/openvpn-ca/pki
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/client-configs/base.conf

cat ${BASE_CONFIG} \
    <(echo -e '<ca>') \
    ${KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    ${KEY_DIR}/issued/${1}.crt \
    <(echo -e '</cert>\n<key>') \
    ${KEY_DIR}/private/${1}.key \
    <(echo -e '</key>\n<tls-auth>') \
    ${KEY_DIR}/ta.key \
    <(echo -e '</tls-auth>') \
    > ${OUTPUT_DIR}/${1}.ovpn
EOF

# Make the script executable
chmod +x ~/client-configs/make_config.sh

# Generate the .ovpn file for the client
cd ~/client-configs
./make_config.sh client1

echo "Client configuration file created at: ~/client-configs/files/client1.ovpn"
