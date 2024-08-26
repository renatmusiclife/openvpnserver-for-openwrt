# OpenVPN Setup Script

This script automates the installation and configuration of an OpenVPN server on an OpenWRT router, including the setup of EasyRSA for managing SSL/TLS certificates. Additionally, it provides functionality for configuring a DDNS service using DuckDNS.

## Features

- Installs OpenVPN and EasyRSA.
- Initializes PKI (Public Key Infrastructure) and generates necessary keys and certificates.
- Configures OpenVPN server with appropriate firewall rules.
- Configures DDNS service with DuckDNS.
- Supports adding and deleting users.
- Provides the ability to regenerate the server configuration.

## Prerequisites

- OpenWRT router with internet access.
- Basic knowledge of OpenWRT and SSH.

## Usage

### 1. Installation

To install and configure the OpenVPN server along with EasyRSA:

1. **SSH into your OpenWRT router**:
    ```sh
    ssh root@your-router-ip
    ```

2. **Run the script**:
    - Download and execute the script directly from GitHub:
    ```sh
    wget -O - https://raw.githubusercontent.com/renatmusiclife/openvpnserver-for-openwrt/main/openvpn.sh | sh
    ```

3. **Select "Install OpenVPN"**:
    - Follow the prompts to install OpenVPN, generate keys, and configure the server.

### 2. Adding and Managing Users

The script allows you to add and manage VPN users:

- **Add User**:
    - Select "Add User" from the script menu. You will be prompted to enter a username and decide whether to set a password for the certificate.
    - A configuration file (`.ovpn`) will be generated for the user.

- **Delete User**:
    - Select "Delete User" to revoke the user's certificate and update crl.

### 3. Configuring DDNS

The script includes an option to configure DDNS with DuckDNS:

- **Configure DDNS**:
    - Enter your DuckDNS username and token when prompted.
    - The script will automatically configure the DDNS service.

## Customization

You can customize the script by modifying the following variables at the beginning of the script:

- **VPN_PORT**: The port on which OpenVPN will listen.
- **VPN_PROTO**: The protocol used by OpenVPN (e.g., UDP or TCP).
- **VPN_POOL**: The IP pool for the VPN network.

## License

This script is provided as-is, without any warranty. Use it at your own risk.
