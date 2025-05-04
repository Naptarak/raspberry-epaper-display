#!/bin/bash

# =====================================================
# WAVESHARE E-PAPER HTML RENDERER ELTÁVOLÍTÓ
# A teljes telepítés törlése
# =====================================================

# Kilépés hiba esetén
set -e

echo "======================================================"
echo "  WAVESHARE E-PAPER HTML RENDERER ELTÁVOLÍTÓ"
echo "======================================================"

# Aktuális felhasználó és könyvtárak beállítása
CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo ~$CURRENT_USER)
INSTALL_DIR="$HOME_DIR/e-paper-display"

echo "Eltávolítás a következő felhasználótól: $CURRENT_USER"
echo "Eltávolítandó könyvtár: $INSTALL_DIR"

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop epaper-display.service 2>/dev/null || true
sudo systemctl disable epaper-display.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/epaper-display.service
sudo systemctl daemon-reload

# Crontab bejegyzés eltávolítása
echo "Crontab bejegyzés eltávolítása..."
(crontab -l 2>/dev/null | grep -v "e-paper-display") | crontab - || true

# Telepítési könyvtár törlése
echo "Telepítési könyvtár törlése..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "Könyvtár törölve: $INSTALL_DIR"
else
    echo "A könyvtár nem létezik: $INSTALL_DIR"
fi

# Opcionális csomagok eltávolítása
echo "Telepített csomagok eltávolítása nem javasolt, mert más"
echo "programok is használhatják őket. Ha biztosan szeretnéd eltávolítani,"
echo "használd a következő parancsot:"
echo "sudo apt-get remove python3-selenium python3-bs4 firefox-esr xvfb python3-venv"
echo ""

# SPI interfész kikapcsolásának lehetősége
echo "Az SPI interfész továbbra is engedélyezve van."
echo "Szeretnéd kikapcsolni az SPI interfészt? (i/n)"
read disable_spi

if [ "$disable_spi" = "i" ]; then
    echo "SPI interfész kikapcsolása..."
    if grep -q "^dtparam=spi=on" /boot/config.txt; then
        sudo sed -i '/^dtparam=spi=on/s/^/#/' /boot/config.txt
        echo "SPI interfész kikapcsolva. A változtatások érvényesítéséhez"
        echo "újra kell indítani a Raspberry Pi-t."
        REBOOT_NEEDED=true
    else
        echo "Az SPI interfész már ki van kapcsolva vagy nincs beállítva."
    fi
else
    echo "Az SPI interfész továbbra is engedélyezve marad."
fi

# Telepítés befejezve
echo ""
echo "======================================================"
echo "  ELTÁVOLÍTÁS SIKERESEN BEFEJEZVE!"
echo "======================================================"
echo ""

# Újraindítás, ha szükséges
if [ "$REBOOT_NEEDED" = "true" ]; then
    echo "FONTOS: Az SPI interfész kikapcsolásához újra kell indítani"
    echo "a Raspberry Pi-t. Szeretnéd most újraindítani? (i/n)"
    read restart_now
    
    if [ "$restart_now" = "i" ]; then
        echo "Újraindítás 5 másodperc múlva..."
        sleep 5
        sudo reboot
    else
        echo "Ne felejtsd el később újraindítani a rendszert:"
        echo "sudo reboot"
    fi
fi

echo "Az eltávolítás befejeződött."
echo ""
