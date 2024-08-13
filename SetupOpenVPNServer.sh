# Update package list and install OpenVPN and Easy-RSA
sudo apt-get update
sudo apt-get install openvpn easy-rsa -y

# Create a directory for Easy-RSA and copy the script there
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# Initialize PKI (Public Key Infrastructure)
./easyrsa init-pki

# Build the Certificate Authority (CA)
./easyrsa build-ca nopass

# Generate server certificate
./easyrsa gen-req server nopass
./easyrsa sign-req server server

# Generate Diffie-Hellman parameters
./easyrsa gen-dh

# Generate a HMAC signature key for TLS-auth
openvpn --genkey --secret ta.key

# Generate client certificate
./easyrsa gen-req client1 nopass
./easyrsa sign-req client client1

# Create the .rnd file to avoid RNG errors
openssl rand -writerand ~/.rnd

# Copy necessary files to the OpenVPN configuration directory
sudo cp pki/ca.crt pki/issued/server.crt pki/private/server.key ta.key pki/dh.pem /etc/openvpn

# Configure the OpenVPN server
sudo sed -i -e 's/;tls-auth/tls-auth/g' /etc/openvpn/server.conf
sudo sed -i '/tls-auth ta.key 0 # This file is secret/a key-direction 0' /etc/openvpn/server.conf
sudo sed -i -e 's/;cipher AES-128-CBC/cipher AES-128-CBC/g' /etc/openvpn/server.conf
sudo sed -i '/cipher AES-128-CBC/a auth SHA256' /etc/openvpn/server.conf
sudo sed -i -e 's/;user nobody/user nobody/g' /etc/openvpn/server.conf
sudo sed -i -e 's/;group nogroup/group nogroup/g' /etc/openvpn/server.conf
sudo sed -i -e 's/;push "redirect-gateway def1 bypass-dhcp"/push "redirect-gateway def1 bypass-dhcp"/g' /etc/openvpn/server.conf
sudo sed -i -e 's/;push "dhcp-option DNS 208.67.222.222"/push "dhcp-option DNS 208.67.222.222"/g' /etc/openvpn/server.conf
sudo sed -i -e 's/;push "dhcp-option DNS 208.67.220.220"/push "dhcp-option DNS 208.67.220.220"/g' /etc/openvpn/server.conf
sudo sed -i -e 's/port 1194/port 443/g' /etc/openvpn/server.conf
sudo sed -i -e 's/;proto tcp/proto tcp/g' /etc/openvpn/server.conf
sudo sed -i -e 's/proto udp/;proto udp/g' /etc/openvpn/server.conf
sudo echo "duplicate-cn" >> /etc/openvpn/server.conf
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

" >> UFWSettingsForOpenVPN
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
IP=$(curl 'https://api.ipify.org')
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

# Download script to create client configuration files
wget -O ~/client-configs/make_config.sh https://git.io/vxyc7
chmod 700 ~/client-configs/make_config.sh
