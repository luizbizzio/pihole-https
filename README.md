
# Pi-hole HTTPS Setup 🔒

This repository automates the setup of a secure HTTPS connection for your Pi-hole server, including automatic detection and support for Tailscale.

## Features 🌟
- Automatically generates SSL certificates and configures your Pi-hole for HTTPS.
- Detects Tailscale setup and includes it in the SSL configuration.
- Works seamlessly with Windows, Linux, MacOS, and Android.
- Simplifies the process with a single command.

---

## Quick Start 🚀

### Step 1: Run the Script
Copy and paste the following command into your terminal to run the script:
```bash
curl -fsSL https://raw.githubusercontent.com/luizbizzio/pihole-https/refs/heads/main/pihole-https.sh | sudo bash
```

That's it! The script will handle everything automatically, including certificate generation, configuration, and applying HTTPS settings.

---

## How It Works 🛠️
1. **Hostname and IP Detection**:
   - Detects your Pi-hole's hostname and IP addresses automatically.
   - If Tailscale is installed, it also includes the Tailscale DNS in the SSL configuration.

2. **SSL Certificate Generation**:
   - Creates an SSL certificate for your Pi-hole server, valid for 10 years.

3. **Lighttpd Configuration**:
   - Configures Lighttpd to serve HTTPS using the generated SSL certificate.

4. **Certificate Accessibility**:
   - The certificate is saved locally and ready for use on all major platforms.

---

## Installing the Certificate on Devices 📱💻

Once the script completes, you'll need to install the certificate on your devices for secure access.

### Windows 🪟
1. Download the certificate file.
2. Open the certificate by double-clicking it.
3. Click **Install Certificate**, choose **Local Machine**, and proceed.
4. Select **Trusted Root Certification Authorities** and complete the wizard.

### MacOS 🍏
1. Download the certificate file.
2. Open **Keychain Access**.
3. Drag the certificate into the **System** keychain.
4. Right-click the certificate, select **Get Info**, and set **Trust** to **Always Trust**.

### Linux 🐧
1. Copy the certificate to `/usr/local/share/ca-certificates/`.
2. Rename the file with a `.crt` extension if necessary.
3. Run:
   ```bash
   sudo update-ca-certificates
   ```

### Android 📱
1. Download the certificate file to your device.
2. Go to **Settings** > **Security** > **Install Certificate**.
3. Select the file and follow the instructions.

---

## Notes 📝
- This script assumes your Pi-hole is running on a system with Lighttpd.
- The script skips Tailscale detection if it is not installed.
- Compatible with most major browsers and operating systems.

---

## License 📄
This repository is licensed under the [MIT License](./LICENSE).

Enjoy secure Pi-hole browsing! 🔒
