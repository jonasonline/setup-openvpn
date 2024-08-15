#!/bin/bash

sudo apt update
sudo apt install openvpn easy-rsa -y

# Get the current user's home directory and username
USER_HOME=$(eval echo ~$SUDO_USER)
USERNAME=$SUDO_USER

# Fetch the external IP address of the server
EXTERNAL_IP=$(curl -s ifconfig.me)

mkdir ~/easy-rsa
ln -s /usr/share/easy-rsa/* ~/easy-rsa/

#sudo chown "$USER" ~/easy-rsa
chmod 700 ~/easy-rsa

# Customize the vars file
cat << EOF > ~/easy-rsa/vars
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "NewYork"
set_var EASYRSA_REQ_CITY       "New York City"
set_var EASYRSA_REQ_ORG        "DigitalOcean"
set_var EASYRSA_REQ_EMAIL      "admin@example.com"
set_var EASYRSA_REQ_OU         "Community"
set_var EASYRSA_ALGO           "ec"
set_var EASYRSA_DIGEST         "sha512"
EOF

cd ~/easy-rsa
./easyrsa init-pki
./easyrsa build-ca nopass

./easyrsa gen-req server nopass

sudo cp /home/$USER/easy-rsa/pki/private/server.key /etc/openvpn/server/

./easyrsa sign-req server server

sudo cp /home/$USER/easy-rsa/pki/ca.crt /etc/openvpn/server
sudo cp /home/$USER/easy-rsa/pki/issued/server.crt /etc/openvpn/server

openvpn --genkey --secret ta.key
sudo cp ta.key /etc/openvpn/server

mkdir -p ~/client-configs/keys
chmod -R 700 ~/client-configs

./easyrsa gen-req client1 nopass
cp pki/private/client1.key ~/client-configs/keys/
./easyrsa sign-req client client1
cp /home/$USER/easy-rsa/pki/issued/client1.crt ~/client-configs/keys/

cp ~/easy-rsa/ta.key ~/client-configs/keys/
sudo cp /etc/openvpn/server/ca.crt ~/client-configs/keys/

sudo chown $USER.$USER ~/client-configs/keys/*

cd ~/
cat << EOF > ~/server.conf
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh none
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 208.67.222.222"
push "dhcp-option DNS 208.67.220.220"
ifconfig-pool-persist /var/log/openvpn/ipp.txt
keepalive 10 120
tls-crypt ta.key
cipher AES-256-GCM
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
verb 3
explicit-exit-notify 1
EOF
sudo cp server.conf /etc/openvpn/server/

echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p

sudo sed -i '/#   ufw-before-forward/a # START OPENVPN RULES\n# NAT table rules\n*nat\n:POSTROUTING ACCEPT [0:0]\n# Allow traffic from OpenVPN client to eth0 (change to the interface you discovered!)\n-A POSTROUTING -s 10.8.0.0/8 -o eth0 -j MASQUERADE\nCOMMIT\n# END OPENVPN RULES' /etc/ufw/before.rules
sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

sudo ufw allow 1194/udp
sudo ufw allow OpenSSH
sudo ufw disable
sudo ufw enable

sudo systemctl -f enable openvpn-server@server.service
sudo systemctl start openvpn-server@server.service

mkdir -p ~/client-configs/files
#cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/client-configs/base.conf

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
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
verb 3
key-direction 1
; script-security 2
; up /etc/openvpn/update-resolv-conf
; down /etc/openvpn/update-resolv-conf
; script-security 2
; up /etc/openvpn/update-systemd-resolved
; down /etc/openvpn/update-systemd-resolved
; down-pre
; dhcp-option DOMAIN-ROUTE .
EOF

cat << EOF > ~/client-configs/make_config.sh
#!/bin/bash
 
# First argument: Client identifier
 
KEY_DIR=~/client-configs/keys
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/client-configs/base.conf
 
cat \${BASE_CONFIG} \\
    <(echo -e '<ca>') \\
    \${KEY_DIR}/ca.crt \\
    <(echo -e '</ca>\n<cert>') \\
    \${KEY_DIR}/\${1}.crt \\
    <(echo -e '</cert>\n<key>') \\
    \${KEY_DIR}/\${1}.key \\
    <(echo -e '</key>\n<tls-crypt>') \\
    \${KEY_DIR}/ta.key \\
    <(echo -e '</tls-crypt>') \\
    > \${OUTPUT_DIR}/\${1}.ovpn
EOF

chmod 700 ~/client-configs/make_config.sh
cd ~/client-configs
./make_config.sh client1