#!/bin/bash

# E-Paper Website Display Eltávolító
# Készítette: Claude

echo "=================================================="
echo "  E-Paper Website Display Eltávolító"
echo "=================================================="
echo ""
echo "Ez a script eltávolítja az E-Paper Website Display alkalmazást."
echo "Figyelem: Ez a művelet nem távolítja el a telepített függőségeket."
echo ""
echo -n "Biztosan el szeretnéd távolítani az alkalmazást? (i/n): "
read confirm

if [ "$confirm" != "i" ]; then
    echo "Eltávolítás megszakítva."
    exit 0
fi

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop epaper-display.service
sudo systemctl disable epaper-display.service
sudo rm /etc/systemd/system/epaper-display.service
sudo systemctl daemon-reload

# Autostart beállítás eltávolítása
echo "Automatikus indítás eltávolítása..."
rm -f /home/pi/.config/autostart/browser.desktop

# Telepítési könyvtár eltávolítása
echo "Telepítési könyvtár eltávolítása..."
rm -rf /home/pi/e-paper-display

echo ""
echo "==================================================="
echo "  Eltávolítás befejezve!"
echo "==================================================="
echo ""
echo "Az E-Paper Website Display alkalmazás sikeresen el lett távolítva."
echo ""