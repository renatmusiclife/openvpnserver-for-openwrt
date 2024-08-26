#!/bin/sh

# Configuration parameters
VPN_DIR="/etc/openvpn"
VPN_PKI="/etc/easy-rsa/pki-ovpn"
VPN_PORT="1194"
VPN_PROTO="udp"
VPN_POOL="192.168.9.0 255.255.255.0"
VPN_DNS="${VPN_POOL%.* *}.1"
VPN_DN="$(uci -q get dhcp.@dnsmasq[0].domain)"
USERS_FILE="/etc/openvpn/users.txt"
SERVER_CONF="/etc/openvpn/server.conf"

alias easyrsa="/root/EasyRSA-3.1.7/easyrsa"
# Fetch server address
NET_FQDN="$(uci -q get ddns.@service[0].lookup_host)"
. /lib/functions/network.sh
network_flush_cache
network_find_wan NET_IF
network_get_ipaddr NET_ADDR "${NET_IF}"
if [ -n "${NET_FQDN}" ]; then
    VPN_SERV="${NET_FQDN}"
else
    VPN_SERV="${NET_ADDR}"
fi

echo "Server address is set to ${VPN_SERV}"

# Function to install and configure DDNS
configure_ddns() {
    echo "Installing DDNS..."
    opkg update
    opkg install ddns-scripts

    echo "Configuring DDNS service..."

    echo -n "Enter your DuckDNS username: "
    read DDNS_USERNAME
    echo -n "Enter your DuckDNS token: "
    read -s DDNS_PASSWORD
    echo 
    # Remove existing DDNS configuration if it exists
    uci delete ddns.duckdns 2>/dev/null
    uci commit ddns

    # Add new DDNS configuration
    uci set ddns.duckdns=service
    uci set ddns.duckdns.enabled="1"
    uci set ddns.duckdns.domain="${DDNS_USERNAME}.duckdns.org"
    uci set ddns.duckdns.username="${DDNS_USERNAME}"
    uci set ddns.duckdns.password="${DDNS_PASSWORD}"
    uci set ddns.duckdns.ip_source="network"
    uci set ddns.duckdns.ip_network="wan"
    uci set ddns.duckdns.force_interval="72"
    uci set ddns.duckdns.force_unit="hours"
    uci set ddns.duckdns.check_interval="10"
    uci set ddns.duckdns.check_unit="minutes"
    uci set ddns.duckdns.update_url="http://www.duckdns.org/update?domains=[USERNAME]&token=[PASSWORD]&ip=[IP]"
    # Commit and restart the DDNS service
    uci commit ddns
    /etc/init.d/ddns restart

    echo "DDNS configuration complete."
}


# Function to install OpenVPN and EasyRSA
install_openvpn() {
    echo "Updating package list and installing required packages..."
    opkg update
    opkg install openvpn-openssl openvpn-easy-rsa

    # Key management
    if [ ! -d "/root/EasyRSA-3.1.7" ]; then
        echo "Downloading and extracting EasyRSA..."
        wget -U "" -O /tmp/easyrsa.tar.gz https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.7/EasyRSA-3.1.7.tgz
        tar -z -x -f /tmp/easyrsa.tar.gz -C /root/
    fi

# Configuration parameters
    cat << EOF > /etc/profile.d/easy-rsa.sh
export EASYRSA_PKI="${VPN_PKI}"
export EASYRSA_TEMP_DIR="/tmp"
export EASYRSA_CERT_EXPIRE="3650"
export EASYRSA_BATCH="1"
alias easyrsa="/root/EasyRSA-3.1.7/easyrsa"
EOF
    . /etc/profile.d/easy-rsa.sh
    if [ ! -d "${VPN_PKI}" ]; then
        echo "Initializing PKI directory..."
        easyrsa init-pki
        easyrsa gen-dh
        easyrsa build-ca nopass
        easyrsa build-server-full server nopass
        openvpn --genkey tls-crypt-v2-server ${VPN_PKI}/private/server.pem
    fi

    # Ensure the users file exists
    if [ ! -f "${USERS_FILE}" ]; then
        touch "${USERS_FILE}"
    fi

    # Create server configuration file
    VPN_DH="$(cat ${VPN_PKI}/dh.pem)"
    VPN_TC=$(cat "${VPN_PKI}/private/server.pem")
    VPN_KEY=$(cat "${VPN_PKI}/private/server.key")
    VPN_CERT=$(openssl x509 -in "${VPN_PKI}/issued/server.crt")
    VPN_CA=$(openssl x509 -in "${VPN_PKI}/ca.crt")
    VPN_CONF="${VPN_DIR}/server.conf"
    cat << EOF > ${VPN_CONF}
user nobody
group nogroup
dev tun
port ${VPN_PORT}
proto ${VPN_PROTO}
server ${VPN_POOL}
topology subnet
client-to-client
keepalive 10 60
persist-tun
persist-key
push "dhcp-option DNS ${VPN_DNS}"
push "dhcp-option DOMAIN ${VPN_DN}"
push "redirect-gateway def1"
push "persist-tun"
push "persist-key"
<dh>
${VPN_DH}
</dh>
<tls-crypt-v2>
${VPN_TC}
</tls-crypt-v2>
<key>
${VPN_KEY}
</key>
<cert>
${VPN_CERT}
</cert>
<ca>
${VPN_CA}
</ca>
EOF

    echo "Server configuration file created at ${VPN_CONF}"

    # Firewall configuration
    echo "Configuring VPN firewall settings..."

    # Remove existing VPN-related firewall rules and zones
    uci delete firewall.Allow_OpenVPN_Inbound 2>/dev/null
    uci delete firewall.vpn 2>/dev/null
    uci delete firewall.vpn_forwarding_lan_in 2>/dev/null
    uci delete firewall.vpn_forwarding_lan_out 2>/dev/null
    uci delete firewall.vpn_forwarding_wan 2>/dev/null
    # Remove aditional
    # uci delete firewall.mark_domains_vpn 2>/dev/null
    # uci delete firewall.vpn_forwarding_awg 2>/dev/null

    # Create new rules and zones
    # Create interface
    uci set network.vpn0=interface
    uci set network.vpn0.ifname=tun0
    uci set network.vpn0.proto=none
    uci set network.vpn0.auto=1

    # Allow input for port 
    uci set firewall.Allow_OpenVPN_Inbound=rule
    uci set firewall.Allow_OpenVPN_Inbound.target=ACCEPT
    uci set firewall.Allow_OpenVPN_Inbound.src=*
    uci set firewall.Allow_OpenVPN_Inbound.proto=udp
    uci set firewall.Allow_OpenVPN_Inbound.dest_port=${VPN_PORT}

    # Create new zone vpn
    uci set firewall.vpn=zone
    uci set firewall.vpn.name=vpn
    uci set firewall.vpn.network=vpn0
    uci set firewall.vpn.input=ACCEPT
    uci set firewall.vpn.forward=REJECT
    uci set firewall.vpn.output=ACCEPT
    uci set firewall.vpn.masq=1

    # Allow from vpn to lan
    uci set firewall.vpn_forwarding_lan_in=forwarding
    uci set firewall.vpn_forwarding_lan_in.src=vpn
    uci set firewall.vpn_forwarding_lan_in.dest=lan

    # Allow from lan to vpn
    uci set firewall.vpn_forwarding_lan_out=forwarding
    uci set firewall.vpn_forwarding_lan_out.src=lan
    uci set firewall.vpn_forwarding_lan_out.dest=vpn

    # Allow from lan to wan
    uci set firewall.vpn_forwarding_wan=forwarding
    uci set firewall.vpn_forwarding_wan.src=vpn
    uci set firewall.vpn_forwarding_wan.dest=wan

    # Adittional firewall rules
    # uci set firewall.mark_domains=rule
    # uci set firewall.mark_domains.name='mark_domains_vpn'
    # uci set firewall.mark_domains.src='vpn'
    # uci set firewall.mark_domains.dest='*'
    # uci set firewall.mark_domains.proto='all'
    # uci set firewall.mark_domains.ipset='vpn_domains'
    # uci set firewall.mark_domains.set_mark='0x1'
    # uci set firewall.mark_domains.target='MARK'
    # uci set firewall.mark_domains.family='ipv4'

    # uci set firewall.vpn_forwarding_awg=forwarding
    # uci set firewall.vpn_forwarding_awg.src='vpn'
    # uci set firewall.vpn_forwarding_awg.dest='awg'

    # Apply network and firewall changes
    uci commit network
    /etc/init.d/network reload
    uci commit firewall
    /etc/init.d/firewall reload
    /etc/init.d/openvpn restart
    echo "OpenVPN server setup is complete."
}



# Function to update the CRL in the configuration file
update_crl_in_config() {
    VPN_CRL=$(cat "${VPN_PKI}/crl.pem")
    
    # Remove existing crl-verify block
    sed -i '/<crl-verify>/,/<\/crl-verify>/d' "${SERVER_CONF}"
    
    # Add new CRL block
    {
        echo "<crl-verify>"
        echo "$VPN_CRL"
        echo "</crl-verify>"
    } >> "${SERVER_CONF}"
    
    echo "CRL updated in ${SERVER_CONF}"
}

# Function to list existing users
list_users() {
    cat "${USERS_FILE}"
}

# Function to add a user
add_user() {
    . /etc/profile.d/easy-rsa.sh
    echo -n "Enter username: "
    read USERNAME
    if grep -qx "$USERNAME" "${USERS_FILE}"; then
        echo "User $USERNAME already exists."
    else
        echo -n "Do you want to set a password for the certificate? (y/n, default is no): "
        read PASSWORD_CHOICE
        if [ "$PASSWORD_CHOICE" = "y" ] || [ "$PASSWORD_CHOICE" = "yes" ]; then
            easyrsa build-client-full "$USERNAME"
        else
            easyrsa build-client-full "$USERNAME" nopass
        fi 
        openvpn --tls-crypt-v2 "${VPN_PKI}/private/server.pem" --genkey tls-crypt-v2-client "${VPN_PKI}/private/${USERNAME}.pem"
        echo "$USERNAME" >> "${USERS_FILE}"
        echo "User $USERNAME added."

        # Create the client configuration file
        VPN_CONF="${VPN_DIR}/clients/${USERNAME}.ovpn"
        mkdir -p "${VPN_DIR}/clients"

        # Read the necessary files into variables
        VPN_TC=$(cat "${VPN_PKI}/private/${USERNAME}.pem")
        VPN_KEY=$(cat "${VPN_PKI}/private/${USERNAME}.key")
        VPN_CERT=$(openssl x509 -in "${VPN_PKI}/issued/${USERNAME}.crt")
        VPN_CA=$(openssl x509 -in "${VPN_PKI}/ca.crt")

        cat << EOF > "${VPN_CONF}"
client
dev tun
proto ${VPN_PROTO}
remote ${VPN_SERV} ${VPN_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth-nocache

<tls-crypt-v2>
${VPN_TC}
</tls-crypt-v2>
<key>
${VPN_KEY}
</key>
<cert>
${VPN_CERT}
</cert>
<ca>
${VPN_CA}
</ca>
EOF

        echo "Configuration file created at ${VPN_CONF}"
    fi
}


# Function to delete a user
delete_user() {
    . /etc/profile.d/easy-rsa.sh
    USERS=$(list_users)
    if [ -z "$USERS" ]; then
        echo "No users found."
        return
    fi

    echo "Existing users:"
    
    i=1
    for USERNAME in $USERS; do
        echo "$i) $USERNAME"
        i=$((i + 1))
    done
    read -p "Enter the number corresponding to the user you want to delete: " user_num

    i=1
    for USERNAME in $USERS; do
        if [ "$i" -eq "$user_num" ]; then
            easyrsa revoke "$USERNAME"
            easyrsa gen-crl
            update_crl_in_config
            rm -f "${VPN_PKI}/private/${USERNAME}.pem"
            sed -i "/^${USERNAME}$/d" "${USERS_FILE}"
            rm -f "${VPN_DIR}/clients/${USERNAME}.ovpn"
            echo "User $USERNAME deleted."
            /etc/init.d/openvpn restart            
            return
        fi
        i=$((i + 1))
    done

    echo "Invalid selection."
}

# Function to uninstall and clean up OpenVPN and DDNS
uninstall_openvpn_ddns() {
    echo "Stopping OpenVPN service..."
    /etc/init.d/openvpn stop

    echo "Removing OpenVPN-related firewall rules and zones..."
    uci delete firewall.Allow_OpenVPN_Inbound 2>/dev/null
    uci delete firewall.vpn 2>/dev/null
    uci delete firewall.vpn_forwarding_lan_in 2>/dev/null
    uci delete firewall.vpn_forwarding_lan_out 2>/dev/null
    uci delete firewall.vpn_forwarding_wan 2>/dev/null
    uci delete firewall.mark_domains_vpn 2>/dev/null
    uci delete firewall.vpn_forwarding_awg 2>/dev/null
    uci commit firewall
    /etc/init.d/firewall reload

    echo "Removing OpenVPN configuration and keys..."
    rm -rf ${VPN_DIR}/*
    rm -rf ${VPN_PKI}/*

    echo "Removing DDNS configuration..."
    uci delete ddns.duckdns 2>/dev/null
    uci commit ddns
    /etc/init.d/ddns stop

    echo "Uninstalling OpenVPN and DDNS packages..."
    opkg remove openvpn-openssl openvpn-easy-rsa ddns-scripts

    echo "Removing EasyRSA files and environment setup..."
    rm -rf /root/EasyRSA-3.1.7
    rm -f /etc/profile.d/easy-rsa.sh

    echo "Cleanup complete. OpenVPN, DDNS, and EasyRSA have been uninstalled."
}

# Main script
echo "What would you like to do?"
echo "1) Install OpenVPN"
echo "2) Add User"
echo "3) Delete User"
echo "4) Configure DDNS"
echo "5) Uninstall OpenVPN and DDNS"
echo "6) Quit"

while true; do
    read -p "Select an option [1-6]: " opt
    case $opt in
        1)
            install_openvpn
            break
            ;;
        2)
            add_user
            break
            ;;
        3)
            delete_user
            break
            ;;
        4)
            configure_ddns
            break
            ;;
        5)
            uninstall_openvpn_ddns
            break
            ;;
        6)
            break
            ;;
        *)
            echo "Invalid option. Please enter a number between 1 and 6."
            ;;
    esac
done

echo "Script finished."


