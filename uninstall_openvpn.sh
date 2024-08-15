#!/bin/bash

# Stop and disable the OpenVPN service
sudo systemctl stop openvpn-server@server.service
sudo systemctl disable openvpn-server@server.service

# Remove OpenVPN and easy-rsa packages
sudo apt remove --purge openvpn easy-rsa -y
sudo apt autoremove -y
sudo apt autoclean

# Remove the directories and files created by the script
rm -rf ~/easy-rsa
rm -rf ~/client-configs
rm ~/server.conf

# Remove OpenVPN configuration files
sudo rm -rf /etc/openvpn/server

# Remove the OpenVPN rules from UFW
sudo sed -i '/# START OPENVPN RULES/,/# END OPENVPN RULES/d' /etc/ufw/before.rules

# Restore DEFAULT_FORWARD_POLICY to DROP if it was changed
sudo sed -i 's/DEFAULT_FORWARD_POLICY="ACCEPT"/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw

# Disable IP forwarding if it was enabled
sudo sed -i '/net.ipv4.ip_forward = 1/d' /etc/sysctl.conf
sudo sysctl -p

# Revert UFW rules
sudo ufw delete allow 1194/udp
sudo ufw delete allow OpenSSH

# Reload UFW
sudo ufw disable
sudo ufw enable

# Optionally, remove any OpenVPN logs
sudo rm -rf /var/log/openvpn

echo "OpenVPN and associated configurations have been removed."
