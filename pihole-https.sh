#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[31mThis script must be run as root. Please use sudo.\033[0m"
  exit 1
fi

echo -e "\033[32mRunning script with admin privileges ✅\033[0m"

# Get the hostname dynamically
HOSTNAME=$(hostname)
echo -e "\033[34mHostname detected: $HOSTNAME\033[0m"

# Get all IPs dynamically
ALL_IPS=$(hostname -I)
echo -e "\033[34mAll IP addresses detected: $ALL_IPS\033[0m"

# Attempt to get the Tailscale DNS dynamically
if command -v tailscale &>/dev/null; then
    echo -e "\033[34mTailscale detected. Attempting to retrieve DNS configuration...\033[0m"
    TAILSCALE_DNS=$(tailscale status -json | jq -r '.Self.DNSName' 2>/dev/null | sed 's/\.$//')
    
    if [ -n "$TAILSCALE_DNS" ]; then
        echo -e "\033[32mTailscale DNS successfully retrieved: $TAILSCALE_DNS\033[0m"
    else
        echo -e "\033[33mTailscale detected, but no DNS information could be retrieved.\033[0m"
        TAILSCALE_DNS=""
    fi
else
    echo -e "\033[31mTailscale is not installed or not configured. Skipping Tailscale DNS.\033[0m"
    TAILSCALE_DNS=""
fi

# Create the directory to store certificates
sudo mkdir -p /etc/ssl/mycerts
echo -e "\033[32mCreated folder 'mycerts' at /etc/ssl.\033[0m"
cd /etc/ssl/mycerts

# Create the OpenSSL configuration file dynamically
sudo bash -c "cat << EOF > openssl.cnf
[ req ]
default_bits        = 2048
default_keyfile     = $HOSTNAME.key
distinguished_name  = req_distinguished_name
req_extensions      = v3_req
prompt = no

[ req_distinguished_name ]
CN = $HOSTNAME

[ v3_req ]
subjectAltName = @alt_names
basicConstraints = CA:TRUE
keyUsage = digitalSignature, keyEncipherment, keyCertSign
extendedKeyUsage = serverAuth, clientAuth

[ alt_names ]
DNS.1 = $HOSTNAME
EOF"

# Add Tailscale DNS if available
if [ -n "$TAILSCALE_DNS" ]; then
    sudo bash -c "echo DNS.2 = $TAILSCALE_DNS >> openssl.cnf"
fi

# Add each IP to the [alt_names] section
IP_INDEX=1
for IP in $ALL_IPS; do
    sudo bash -c "echo IP.$IP_INDEX = $IP >> openssl.cnf"
    IP_INDEX=$((IP_INDEX + 1))
done

echo -e "\033[32mOpenSSL configuration file created at /etc/ssl/mycerts/openssl.cnf.\033[0m"

# Generate the private key
sudo openssl genpkey -algorithm RSA -out $HOSTNAME.key -pkeyopt rsa_keygen_bits:2048
echo -e "\033[32mGenerated private key: $HOSTNAME.key.\033[0m"

# Create the x509 certificate
sudo openssl req -new -x509 -key $HOSTNAME.key -out $HOSTNAME.crt -config ./openssl.cnf -extensions v3_req -nodes -days 3650
echo -e "\033[32mGenerated certificate: $HOSTNAME.crt.\033[0m"

# Combine the key and certificate into a single PEM file
sudo cat $HOSTNAME.key $HOSTNAME.crt | sudo tee $HOSTNAME.pem > /dev/null
echo -e "\033[32mGenerated PEM file: $HOSTNAME.pem.\033[0m"

sudo chmod 640 ./$HOSTNAME.*
echo -e "\033[32mPermissions set for $HOSTNAME.*.\033[0m"

# Install the OpenSSL module for Lighttpd
sudo apt install -y lighttpd-mod-openssl
echo -e "\033[32mLighttpd OpenSSL module installed.\033[0m"

# Add SSL and redirect configuration
CONFIG_FILE="/etc/lighttpd/lighttpd.conf"

# Check if the .pem file exists
if [ ! -f "/etc/ssl/mycerts/$HOSTNAME.pem" ]; then
    echo -e "\033[31mError: File /etc/ssl/mycerts/$HOSTNAME.pem does not exist. Cannot configure SSL.\033[0m"
    exit 1
fi

echo "Starting SSL and redirect configuration for Lighttpd..."

# Add mod_openssl module
if ! grep -q '"mod_openssl"' "$CONFIG_FILE"; then
    sudo sed -i '/server.modules = (/a\        "mod_openssl",' "$CONFIG_FILE"
    echo -e "\033[32mAdded 'mod_openssl' to Lighttpd modules.\033[0m"
else
    echo -e "\033[33m'mod_openssl' is already present in Lighttpd modules.\033[0m"
fi

# Add SSL block
if ! grep -q 'ssl.engine = "enable"' "$CONFIG_FILE"; then
    sudo bash -c "cat << 'EOF' >> $CONFIG_FILE

# SSL
\$SERVER[\"socket\"] == \":443\" {
    ssl.engine = \"enable\"
    ssl.pemfile = \"/etc/ssl/mycerts/$HOSTNAME.pem\"
}

# Redirect /admin to HTTPS
\$SERVER[\"socket\"] == \":80\" {
    url.redirect = ( \"^/admin(.*)\" => \"https://$HOSTNAME/admin\$1\" )
}
EOF"
    echo -e "\033[32mSSL and redirect configuration added to Lighttpd.\033[0m"
else
    echo -e "\033[33mSSL configuration is already present in Lighttpd.\033[0m"
fi

# Restart Lighttpd service
sudo systemctl restart lighttpd
if [ $? -eq 0 ]; then
    echo -e "\033[32mLighttpd service restarted successfully.\033[0m"
else
    echo -e "\033[31mFailed to restart Lighttpd service. Please check the configuration.\033[0m"
fi


echo -e "\033[34mConfiguration completed! Certificates are stored in /etc/ssl/mycerts/.\033[0m"
echo -e "\033[34mTo install the certificate on your device, copy and use the following certificate:\033[0m"
sudo cat /etc/ssl/mycerts/$HOSTNAME.crt
