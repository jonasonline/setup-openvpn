# OpenVPN Installation and Uninstallation Scripts

This repository provides scripts to **install, configure, repair, and remove OpenVPN** on a Debian-based server.
The installation script is **fully automated, idempotent**, and uses **modern OpenVPN best practices**, including **tls-crypt-v2** and per-client certificates.

## Overview

- `setup_openvpn.sh`  
  Installs and configures OpenVPN using Easy-RSA and tls-crypt-v2.  
  Safe to run multiple times to **repair or re-apply** the configuration.

- `uninstall_openvpn.sh`  
  Completely removes OpenVPN and all related configuration (to be reviewed/updated separately).

---

## Features

- Fully automated (no interactive prompts)
- Idempotent (safe to re-run)
- One certificate per client
- `tls-crypt-v2` for hardened control channel
- Client-to-client communication enabled
- Modern crypto defaults (AES-GCM / ChaCha20)
- Automatic firewall (UFW) and IP forwarding setup
- Generates ready-to-use `.ovpn` client files

---

## Prerequisites

Before running the scripts, ensure that you have:

- A server running a Debian-based Linux distribution (Ubuntu 20.04+ recommended)
- Root or sudo access
- Internet connectivity
- `bash` available (default on Ubuntu)

---

## Installation Script (`setup_openvpn.sh`)

### Usage

1. Clone the repository:

```bash
git clone https://github.com/jonasonline/setup-openvpn.git
```

2. Enter the directory:

```bash
cd setup-openvpn
```

3. Make the script executable (only needed once):

```bash
chmod +x setup_openvpn.sh
```

4. Run the installer:

```bash
sudo ./setup_openvpn.sh
```

---

### What the script does

The script will:

- Install required packages (`openvpn`, `easy-rsa`, `ufw`, `curl`)
- Create and maintain a local Easy-RSA PKI
- Generate:
  - Certificate Authority (CA)
  - Server certificate
  - One certificate per client
  - tls-crypt-v2 server key
  - tls-crypt-v2 client keys
- Configure OpenVPN with:
  - `tls-crypt-v2`
  - Modern cipher negotiation
  - Client-to-client communication
- Enable IP forwarding
- Configure UFW firewall rules (including NAT)
- Generate client `.ovpn` configuration files

You can safely **run the script again** to:
- Repair a broken configuration
- Reapply firewall rules
- Add missing keys or client files

Existing keys and certificates are **not overwritten**.

---

## Client Configuration Files

### Location on the server

After a successful run, client files are created here:

```text
~/client-configs/files/
```

---

## Downloading client files

### Using scp

```bash
scp user@your-server-ip:~/client-configs/files/client1.ovpn .
```

### Download all client files

```bash
scp user@your-server-ip:~/client-configs/files/*.ovpn .
```

### Using rsync

```bash
rsync -av user@your-server-ip:~/client-configs/files/ .
```

---

## License

This project is licensed under the MIT License.
