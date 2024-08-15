# OpenVPN Installation and Uninstallation Scripts

This repository provides a set of scripts to install and configure OpenVPN on your server, as well as a script to completely remove OpenVPN and its associated configurations.

## Introduction

OpenVPN is a powerful, open-source VPN solution that allows you to secure your network communications. The provided scripts automate the process of setting up OpenVPN on a server and configuring it according to best practices. Additionally, an uninstallation script is included to completely remove OpenVPN and all related configurations from the server.

## Prerequisites

Before running the scripts, ensure that you have:

- A server running a Debian-based Linux distribution (e.g., Ubuntu).
- Root or sudo access to the server.
- An active internet connection on the server.

## Installation Script

### Usage

To install and configure OpenVPN using the provided installation script, follow these steps:

1. Clone the repository to your server:
   
   ```bash
   git clone https://github.com/jonasonline/setup-openvpn.git
   ```

2. Navigate to the cloned directory:
   
   ```bash
   cd setup-openvpn
   ```

3. Run the installation script:
   
   ```bash
   ./setup_openvpn.sh
   ```

The script will:

- Update the package list and install necessary packages (`openvpn`, `easy-rsa`).
- Set up the necessary directories and files for Easy-RSA.
- Generate the Certificate Authority (CA) and server keys.
- Configure OpenVPN with best practices.
- Set up UFW rules for OpenVPN.
- Enable IP forwarding for VPN traffic.
- Create client configuration files.

### Customization

- The script allows you to configure the OpenVPN server based on your own needs, such as changing the encryption algorithm or specifying different DNS servers.
- Make sure to update the network interface name (`eth0`) in the UFW rules if your server uses a different interface.

## Uninstallation Script

### Usage

To completely remove OpenVPN and its associated configurations from your server, follow these steps:

1. Navigate to the cloned directory (if not already there):
   
   ```bash
   cd setup-openvpn
   ```

2. Run the uninstallation script:
   
   ```bash
   ./uninstall_openvpn.sh
   ```

The script will:

- Stop and disable the OpenVPN service.
- Uninstall the `openvpn` and `easy-rsa` packages.
- Remove all directories and files created during the installation process.
- Revert changes made to UFW and `sysctl.conf`.
- Optionally, remove any OpenVPN logs.

### Important Notes

- Ensure that no critical data is stored in the directories that will be deleted by the uninstallation script (`~/easy-rsa`, `~/client-configs`, etc.).
- After running the uninstallation script, the server will no longer function as an OpenVPN server.

## Troubleshooting

- If you encounter any issues during installation or uninstallation, please verify that you have the correct permissions and that your server meets the prerequisites.
- For network-related issues, ensure that UFW or any other firewall is configured correctly to allow OpenVPN traffic.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
