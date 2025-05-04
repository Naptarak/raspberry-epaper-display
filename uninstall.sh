#!/bin/bash

# =====================================================
# E-PAPER KIJELZŐ ELTÁVOLÍTÓ SCRIPT
# =====================================================

echo "======================================================"
echo "  WAVESHARE E-PAPER KIJELZŐ ELTÁVOLÍTÓ"
echo "======================================================"

# Aktuális felhasználó és könyvtárak beállítása
CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo ~$CURRENT_USER)
INSTALL_DIR="$HOME_DIR/e-paper-display"

echo "Eltávolítás a következő felhasználótól: $CURRENT_USER"
echo "Eltávolítandó könyvtár: $INSTALL_DIR"

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop epaper-display.service
sudo systemctl disable epaper-display.service
sudo rm -f /etc/systemd/system/epaper-display.service
sudo systemctl daemon-reload

# Telepítési könyvtár törlése
echo "Telepítési könyvtár törlése..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "Könyvtár törölve: $INSTALL_DIR"
else
    echo "A könyvtár nem létezik: $INSTALL_DIR"
fi

echo ""
echo "======================================================"
echo "  ELTÁVOLÍTÁS SIKERESEN BEFEJEZVE!"
echo "======================================================"
echo ""
echo "Megjegyzés: Az SPI interfész továbbra is engedélyezve van."
echo "Ha más projektek nem használják, manuálisan kikapcsolhatod a /boot/config.txt fájlban."
echo ""
