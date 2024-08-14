# OpenVPN Server Setup Script

This script automates the process of setting up an OpenVPN server on Ubuntu using Easy-RSA for certificate management. It also includes steps for configuring client connections.

## Prerequisites

- Ubuntu Server (Tested on Ubuntu 20.04 and newer)
- Sudo privileges

## What the Script Does

1. Installs necessary packages: `openvpn` and `easy-rsa`.
2. Initializes the Public Key Infrastructure (PKI) using Easy-RSA.
3. Generates the Certificate Authority (CA) and server certificates.
4. Creates Diffie-Hellman parameters and a TLS-auth key for added security.
5. Configures the OpenVPN server.
6. Sets up firewall rules using UFW to allow VPN traffic.
7. Starts and enables the OpenVPN service.
8. Prepares a script to generate client configuration files.

## Usage

### 1. Download and Run the Script

Clone this repository or download the script file to your server.

```bash
git clone https://github.com/jonasonline/openvpn-setup.git
cd openvpn-setup
chmod +x SetupOpenVPNServer.sh
sudo ./SetupOpenVPNServer.sh
```

### 2. Verify OpenVPN Service

After the script completes, verify that the OpenVPN server is running:

```bash
sudo systemctl status openvpn@server
```

You can also check logs if you encounter issues:

```bash
sudo journalctl -u openvpn@server
```

### 3. Generate Client Configuration

To create a client configuration file, use the helper script `make_config.sh`:

```bash
cd ~/client-configs
./make_config.sh client1
```

This will generate a `client1.ovpn` file in the `~/client-configs/files/` directory.

### 4. Configure and Connect the Client

#### On a Linux Client:

1. Install OpenVPN:

    ```bash
    sudo apt-get install openvpn
    ```

2. Copy the `client1.ovpn` file from the server to your client machine.

3. Connect to the VPN:

    ```bash
    sudo openvpn --config /path/to/client1.ovpn
    ```

#### On a Windows or macOS Client:

1. Download and install the [OpenVPN client](https://openvpn.net/community-downloads/).

2. Transfer the `client1.ovpn` file to your computer.

3. Open the OpenVPN client, import the `.ovpn` file, and connect.

## Notes

- The script configures OpenVPN to use port `1194` with UDP protocol by default. This can be changed in the `/etc/openvpn/server.conf` file if needed.
- The default encryption settings include `AES-256-GCM` for the cipher and `SHA256` for HMAC authentication.

## Troubleshooting

- **Firewall Issues:** If clients cannot connect, ensure that UFW or any other firewall is properly configured to allow traffic on port `1194/udp`.
- **Client Configuration:** Make sure the client `.ovpn` file is correctly configured with the server's public IP address or domain name.

## Contributing

Contributions are welcome! Please fork this repository and submit a pull request.
