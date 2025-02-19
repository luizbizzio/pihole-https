#!/bin/bash
################################################################################
# Pi-hole SSL Setup Script
# Compatible with both Lighttpd and Pi-hole FTL webserver (6.0).
# Run as root: sudo ./setup_pihole_ssl.sh
################################################################################

# 1) Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[31m[ERROR] This script must be run as root (sudo).\033[0m"
  exit 1
fi

echo -e "\033[32m[OK] Running with administrative privileges.\033[0m"

################################################################################
# 2) Gather system info (HOSTNAME, IPs, Tailscale)
################################################################################

# Get dynamic hostname
HOSTNAME=$(hostname)
echo -e "\033[34m[INFO] Detected hostname: $HOSTNAME\033[0m"

# Retrieve all IP addresses
ALL_IPS=$(hostname -I)
echo -e "\033[34m[INFO] Detected IP addresses: $ALL_IPS\033[0m"

# Attempt to retrieve Tailscale DNS if installed
TAILSCALE_DNS=""
if command -v tailscale &>/dev/null; then
    echo -e "\033[34m[INFO] Tailscale detected, attempting to retrieve DNS...\033[0m"
    TAILSCALE_DNS=$(tailscale status -json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//')
    if [ -n "$TAILSCALE_DNS" ]; then
        echo -e "\033[32m[OK] Tailscale DNS retrieved: $TAILSCALE_DNS\033[0m"
    else
        echo -e "\033[33m[WARN] Tailscale found, but no DNS info available.\033[0m"
    fi
else
    echo -e "\033[31m[INFO] Tailscale is not installed or not configured. Skipping Tailscale DNS.\033[0m"
fi

################################################################################
# 3) Create certificates and keys in /etc/ssl/mycerts
################################################################################

SSL_DIR="/etc/ssl/mycerts"
mkdir -p "$SSL_DIR"
echo -e "\033[32m[OK] Created certificate directory at: $SSL_DIR\033[0m"
cd "$SSL_DIR"

# Create a dynamic openssl.cnf file
cat << EOF > openssl.cnf
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
DNS.2 = pi.hole
EOF

# Add Tailscale DNS if available
if [ -n "$TAILSCALE_DNS" ]; then
    echo "DNS.3 = $TAILSCALE_DNS" >> openssl.cnf
fi

# Add each IP to the [alt_names] section
IP_INDEX=1
for IP in $ALL_IPS; do
    echo "IP.$IP_INDEX = $IP" >> openssl.cnf
    IP_INDEX=$((IP_INDEX + 1))
done

echo -e "\033[32m[OK] openssl.cnf file created in $SSL_DIR.\033[0m"

# Generate private key
openssl genpkey -algorithm RSA -out "$HOSTNAME.key" -pkeyopt rsa_keygen_bits:2048
echo -e "\033[32m[OK] Private key generated: $HOSTNAME.key\033[0m"

# Generate X.509 certificate
openssl req -new -x509 -key "$HOSTNAME.key" -out "$HOSTNAME.crt" -config ./openssl.cnf -extensions v3_req -nodes -days 3650
echo -e "\033[32m[OK] Certificate created: $HOSTNAME.crt\033[0m"

# Combine key + certificate into a single PEM file
cat "$HOSTNAME.key" "$HOSTNAME.crt" > "$HOSTNAME.pem"
echo -e "\033[32m[OK] PEM file created: $HOSTNAME.pem\033[0m"

################################################################################
# 4) Adjust ownership and permissions for user 'pihole'
################################################################################
chown pihole:pihole "$HOSTNAME."*
chmod 640 "$HOSTNAME."*
echo -e "\033[32m[OK] Ownership set to pihole:pihole, permissions set to 640.\033[0m"

################################################################################
# 5) Detect if Lighttpd is active
################################################################################

LIGHTTPD_ACTIVE=false
if systemctl is-active --quiet lighttpd; then
    LIGHTTPD_ACTIVE=true
fi

################################################################################
# 6) If Lighttpd is active, configure Lighttpd
################################################################################
if [ "$LIGHTTPD_ACTIVE" = true ]; then
    echo -e "\033[32m[OK] Lighttpd detected and running. Configuring SSL...\033[0m"

    # Install openssl module if needed
    apt-get update
    apt-get install -y lighttpd-mod-openssl
    echo -e "\033[32m[OK] lighttpd-mod-openssl installed.\033[0m"

    CONFIG_FILE="/etc/lighttpd/lighttpd.conf"
    PEM_PATH="$SSL_DIR/$HOSTNAME.pem"

    # Add "mod_openssl" if not present
    if ! grep -q '"mod_openssl"' "$CONFIG_FILE"; then
        sed -i '/server.modules = (/a\        "mod_openssl",' "$CONFIG_FILE"
        echo -e "\033[32m[OK] 'mod_openssl' added to $CONFIG_FILE.\033[0m"
    else
        echo -e "\033[33m[WARN] 'mod_openssl' is already present in $CONFIG_FILE.\033[0m"
    fi

    # Add SSL block if not present
    if ! grep -q 'ssl.engine = "enable"' "$CONFIG_FILE"; then
        cat << EOF >> "$CONFIG_FILE"

# SSL
\$SERVER["socket"] == ":443" {
    ssl.engine = "enable"
    ssl.pemfile = "$PEM_PATH"
}

# Redirect /admin to HTTPS
\$SERVER["socket"] == ":80" {
    url.redirect = ( "^/admin(.*)" => "https://$HOSTNAME/admin\$1" )
}
EOF
        echo -e "\033[32m[OK] SSL block appended to $CONFIG_FILE.\033[0m"
    else
        echo -e "\033[33m[WARN] SSL configuration already exists in $CONFIG_FILE.\033[0m"
    fi

    systemctl restart lighttpd
    if [ $? -eq 0 ]; then
        echo -e "\033[32m[OK] Lighttpd successfully restarted.\033[0m"
    else
        echo -e "\033[31m[ERROR] Failed to restart Lighttpd. Check logs.\033[0m"
    fi

################################################################################
# 7) Otherwise, assume Pi-hole 6.0 with built-in FTL webserver
################################################################################
else
    echo -e "\033[32m[OK] Lighttpd is not active. Assuming Pi-hole 6.0 FTL webserver.\033[0m"
    TOML_FILE="/etc/pihole/pihole.toml"
    PEM_PATH="$SSL_DIR/$HOSTNAME.pem"

    if [ ! -f "$TOML_FILE" ]; then
        touch "$TOML_FILE"
    fi

    cat << EOF > "$TOML_FILE"
[webserver]
portssl = 443

[webserver.tls]
cert = "$PEM_PATH"
EOF

    chown pihole:pihole "$TOML_FILE"
    chmod 644 "$TOML_FILE"
    echo -e "\033[32m[OK] Wrote TLS config to $TOML_FILE.\033[0m"

    pihole restartdns
    echo -e "\033[32m[OK] pihole-FTL restarted.\033[0m"
fi

################################################################################
# 8) Copy the .crt file to /var/www/html for easy download (if directory exists)
################################################################################
WEB_DIR="/var/www/html"
CRT_FILE="$SSL_DIR/$HOSTNAME.crt"

if [ -d "$WEB_DIR" ]; then
    cp "$CRT_FILE" "$WEB_DIR/"
    chmod 644 "$WEB_DIR/$HOSTNAME.crt"
    echo -e "\033[32m[OK] Certificate copied to $WEB_DIR. Accessible via URL.\033[0m"

    if command -v hostname -I &>/dev/null; then
        IP_ADDRESS=$(hostname -I | awk '{print $1}')
        CERT_URL="http://$IP_ADDRESS/$HOSTNAME.crt"
        echo -e "\033[34m[INFO] Download the certificate at:\033[0m"
        echo -e "\033[4;32m$CERT_URL\033[0m"
    else
        echo -e "\033[33m[WARN] Could not detect IP automatically.\033[0m"
        echo -e "\033[34mPlease manually retrieve $HOSTNAME.crt if needed.\033[0m"
    fi
else
    echo -e "\033[33m[WARN] $WEB_DIR does not exist. Certificate is not available via URL.\033[0m"
    echo -e "\033[34m[INFO] Certificate content (copy into a file named $HOSTNAME.crt):\033[0m"
    cat "$CRT_FILE"
fi

################################################################################
# 9) Final instructions
################################################################################
echo -e "\033[34m[INFO] Install this certificate as a Trusted Root CA on your devices.\033[0m"
echo -e "\033[34mSteps:\033[0m"
echo -e "\033[34m1. Download or copy the .crt file.\033[0m"
echo -e "\033[34m2. Open your OS certificate manager (Windows, Linux, Android, macOS, etc.).\033[0m"
echo -e "\033[34m3. Import it into 'Trusted Root Certification Authorities'.\033[0m"
echo -e "\033[34m4. Restart your browser or device if necessary.\033[0m"
echo -e "\033[32m[OK] Script completed!\033[0m"
