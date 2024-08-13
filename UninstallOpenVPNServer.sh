#!/bin/bash

# Stop the OpenVPN service
sudo systemctl stop openvpn@server
sudo systemctl disable openvpn@server

# Remove OpenVPN and Easy-RSA packages
sudo apt-get remove --purge -y openvpn easy-rsa
sudo apt-get autoremove -y
sudo apt-get autoclean

# Remove OpenVPN configuration and certificates
sudo rm -rf /etc/openvpn
sudo rm -rf ~/openvpn-ca
sudo rm -rf ~/client-configs

# Revert UFW settings
sudo sed -i '/# START OPENVPN RULES/,/# END OPENVPN RULES/d' /etc/ufw/before.rules
sudo sed -i -e 's/DEFAULT_FORWARD_POLICY="ACCEPT"/DEFAULT_FORWARD_POLICY="DROP"/g' /etc/default/ufw

# Reload UFW to apply changes
sudo ufw disable
sudo ufw --force enable

# Revert sysctl IP forwarding setting
sudo sed -i -e 's/net.ipv4.ip_forward=1/#net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sudo sysctl -p

# Remove the client configuration script
rm -f ~/client-configs/make_config.sh

# Remove OpenVPN log file
sudo rm -f /var/log/openvpn.log

echo "OpenVPN and associated files have been removed."
