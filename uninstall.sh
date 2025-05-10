#!/bin/bash

# uninstall.sh - Eltávolító script a Waveshare 4.01 HAT (F) e-paper kijelző alkalmazáshoz

echo "Waveshare 4.01 HAT (F) E-paper kijelző eltávolító script"
echo "======================================================"

# Ellenőrizzük, hogy root jogosultsággal fut-e a script
if [ "$(id -u)" -ne 0 ]; then
    echo "Hiba: Az eltávolítót root jogosultsággal kell futtatni!" >&2
    echo "Használja a 'sudo bash uninstall.sh' parancsot." >&2
    exit 1
fi

# Systemd service leállítása és eltávolítása
echo "Systemd service leállítása és eltávolítása..."
systemctl stop e-paper-display.service
systemctl disable e-paper-display.service
rm -f /etc/systemd/system/e-paper-display.service
systemctl daemon-reload

# Telepítési könyvtár eltávolítása
INSTALL_DIR="/opt/e-paper-display"
echo "Telepítési könyvtár eltávolítása: $INSTALL_DIR"
rm -rf "$INSTALL_DIR"

# Logfájl eltávolítása
echo "Naplófájl eltávolítása..."
rm -f /var/log/e-paper-display.log

# Ideiglenes fájlok eltávolítása
echo "Ideiglenes fájlok eltávolítása..."
rm -f /tmp/screenshot.png
rm -f /tmp/temp_page.html
rm -f /tmp/image.png

echo ""
echo "Eltávolítás befejezve!"
echo "Az e-paper kijelző alkalmazás eltávolításra került."
echo ""
